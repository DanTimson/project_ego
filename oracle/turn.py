"""
turn.py — action points and the round loop.

The activation model is free and re-entrant: within its side's phase the player
(or AI) picks any unit with resources left, spends some of them, and may yield
and come back to the same unit later in the same round. There is no initiative
queue within a side and no per-unit turn boundary.

That single property drives everything here:

  * Per-round state lives on the Combatant and resets once, at ROUND_START.
    Anything reset per activation could be farmed by yielding and reselecting.
  * `steps_this_round` is cumulative PATH LENGTH, not displacement. One counter
    feeds Атака с разгона directly and, via `> 0`, the stamina -2/-1 attack
    discriminator.
  * An attack command carries an implicit move: issuing an attack against a
    reachable target auto-paths the unit into position out of the same pool.
    The `Удар и возврат` anchor is therefore captured on the COMMAND.

ASSUMPTION, NOT ESTABLISHED (OPEN_QUESTIONS item 16): sides alternate in whole
PHASES — one side activates all the units it wants to, then the other. The
alternative is unit-by-unit alternation between sides. The documented initiative
rule («первый ход в бою получает отряд, у лидера которого выше инициатива»)
speaks of a side moving first, which fits phases, but does not exclude
alternation. Settled by watching one battle.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from combat import Combatant, Trace


# ---------------------------------------------------------------------------
# Action points
# ---------------------------------------------------------------------------

class Refusal(Enum):
    OK = "ok"
    NO_MOVEMENT = "not enough movement"
    ACTION_SPENT = "already acted this round"
    EXHAUSTED = "forced to rest at 0 stamina"
    NOT_YOUR_PHASE = "not this side's phase"


def effective_speed(u: Combatant) -> tuple[int, Trace]:
    """Speed after the documented stamina penalty. Floors at 1.

        stamina 3-4  ->  -1
        stamina <= 2 ->  -2

    `Неутомимый` never loses stamina, so it never reaches the penalty band.
    """
    t = Trace(f"{u.name}.speed")
    t.base = u.speed
    value = u.speed
    if not u.has_flag("Неутомимый") and u.stamina <= 4:
        penalty = -1 if u.stamina >= 3 else -2
        t.step(f"stamina {u.stamina}", value, value + penalty)
        value += penalty
    if value < 1:
        t.step("floor", value, 1, "speed never drops below 1")
        value = 1
    t.result = value
    return value, t


def begin_round(u: Combatant) -> None:
    """Reset per-round state. The ONLY place these are cleared."""
    u.movement_remaining = effective_speed(u)[0]
    u.steps_this_round = 0
    u.action_spent = False
    # «в свой следующий ход принудительно выполняет команду Отдых» — a unit that
    # ended the previous round at zero stamina spends this one resting.
    if u.forced_rest:
        rest(u)
        u.forced_rest = False
        u.movement_remaining = 0
        u.action_spent = True


def can_move(u: Combatant, tiles: int = 1) -> Refusal:
    if u.movement_remaining < tiles:
        return Refusal.NO_MOVEMENT
    return Refusal.OK


def spend_move(u: Combatant, tiles: int = 1, stamina_cost: int = 0) -> Trace:
    """Move `tiles` steps. `stamina_cost` is the terrain drain the caller has
    already resolved from bf_object (hills and swamp cost 1 unless the unit has
    the matching Знание; flyers pay nothing).

    Steps ACCUMULATE. A unit pacing back and forth to its starting tile has
    still moved, for both charge distance and the attack stamina discriminator.
    """
    t = Trace(f"{u.name}.move")
    t.base = u.movement_remaining
    u.movement_remaining -= tiles
    t.step(f"-{tiles} tiles", t.base, u.movement_remaining)

    before_steps = u.steps_this_round
    u.steps_this_round += tiles
    t.step("steps_this_round", before_steps, u.steps_this_round, "cumulative path length")

    # Speed reduced to <= 0 costs an extra point per tile.
    extra = tiles if effective_speed(u)[0] <= 0 else 0
    total_stamina = stamina_cost + extra
    if total_stamina and not u.has_flag("Неутомимый"):
        before = u.stamina
        u.stamina = max(0, u.stamina - total_stamina)
        t.step("stamina", before, u.stamina, "terrain")
    t.result = u.movement_remaining
    return t


def attack_stamina_cost(u: Combatant) -> int:
    """-2 if the unit moved at any point this round, -1 otherwise.

    The discriminator is `steps_this_round > 0`, NOT a position comparison: a
    unit that moved out and back to its starting tile has moved.
    """
    return 2 if u.moved_this_round() else 1


def spend_attack(u: Combatant) -> Trace:
    t = Trace(f"{u.name}.attack_cost")
    cost = attack_stamina_cost(u)
    t.base = u.stamina
    if not u.has_flag("Неутомимый"):
        u.stamina = max(0, u.stamina - cost)
        t.step(f"-{cost} stamina", t.base, u.stamina,
               "moved this round" if u.moved_this_round() else "attacked in place")
    u.action_spent = True
    if u.stamina <= 0 and not u.has_flag("Неутомимый"):
        u.forced_rest = True
        t.step("exhausted", u.stamina, u.stamina, "forced Rest next round")
    t.result = u.stamina
    return t


def rest(u: Combatant) -> Trace:
    """Rest or skip: +(2 + Восстановление сил).

    Under the Зуд effect the recovery bonus is 0 regardless of its value.
    Resting also forgoes counterattacks for the round.
    """
    t = Trace(f"{u.name}.rest")
    t.base = u.stamina
    if u.has_flag("Зуд"):
        gain = 2
        note = "Зуд suppresses the recovery bonus"
    else:
        gain = 2 + u.stamina_recovery
        note = f"2 + {u.stamina_recovery} recovery"
    u.stamina = min(u.stamina_base, u.stamina + gain)
    t.step(f"+{gain}", t.base, u.stamina, note)
    u.resting = True
    u.action_spent = True
    u.movement_remaining = 0
    t.result = u.stamina
    return t


def has_resources(u: Combatant) -> bool:
    """Can this unit still do anything at all this round?"""
    if not u.alive:
        return False
    return u.movement_remaining > 0 or not u.action_spent


# ---------------------------------------------------------------------------
# Round loop
# ---------------------------------------------------------------------------

@dataclass
class Side:
    id: int
    name: str
    units: list = field(default_factory=list)
    leader_initiative: int = 0
    is_attacker: bool = False

    def living(self) -> list:
        return [u for u in self.units if u.alive]


@dataclass
class BattleState:
    sides: list
    round_number: int = 0
    active_side: int = 0
    log: list = field(default_factory=list)

    def side(self, sid: int) -> Side:
        return next(s for s in self.sides if s.id == sid)

    def other(self, sid: int) -> Side:
        return next(s for s in self.sides if s.id != sid)


def first_side(sides: list) -> int:
    """«Первый ход в бою получает отряд, у лидера которого выше инициатива.
    Если инициатива равна, первым ходит атакующий.»

    Army-level, one comparison at battle start. Not a per-unit stat.
    """
    a, b = sides[0], sides[1]
    if a.leader_initiative != b.leader_initiative:
        return a.id if a.leader_initiative > b.leader_initiative else b.id
    return a.id if a.is_attacker else b.id


def begin_battle(state: BattleState) -> None:
    state.round_number = 0
    state.active_side = first_side(state.sides)
    begin_new_round(state)


def begin_new_round(state: BattleState) -> None:
    state.round_number += 1
    for s in state.sides:
        for u in s.units:
            if u.alive:
                begin_round(u)
                u.resting = False
    state.active_side = first_side(state.sides)
    state.log.append(f"round {state.round_number} begins, side {state.active_side} first")


def activatable(state: BattleState, side_id: int) -> list:
    """Units the player may select right now. Free choice among them, and a
    unit may be selected again later in the round while it still has
    resources — that re-entry is the whole point of the model."""
    return [u for u in state.side(side_id).living() if has_resources(u)]


def phase_done(state: BattleState, side_id: int) -> bool:
    return not activatable(state, side_id)


def end_phase(state: BattleState) -> bool:
    """Hand control to the other side. Returns True if a new round started.

    ASSUMPTION: whole-phase alternation, not unit-by-unit. See module docstring.
    """
    other = state.other(state.active_side)
    if phase_done(state, other.id):
        begin_new_round(state)
        return True
    state.active_side = other.id
    state.log.append(f"side {state.active_side} takes over")
    return False


def battle_over(state: BattleState) -> bool:
    return any(not s.living() for s in state.sides)
