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


# ---------------------------------------------------------------------------
# Round start vs. extra turns
#
# Eleven documented effects grant a unit a SECOND TURN inside the same round:
#
#   single target   Рывок, Всплеск Хаоса (demon), Стрекало (animal),
#                   Руна обновления (mechanism)
#   filtered group  Искажение Хаоса (all friendly demons),
#                   Клич некроманта (all friendly undead, EXCEPT слуги Смерти),
#                   Стимул (several kobold slaves, +1 speed until end of turn)
#   with a rider    Слово вождя (5 damage to the target, then a second turn),
#                   Ментальный резонанс (magic boost, then a second turn)
#   self, on kill   Кровавое безумие (melee kill: -2 stamina, act again),
#                   Азарт Охотника (ranged kill: act again)
#
# So refreshing a unit and starting a round are DIFFERENT operations, and both
# are needed. `begin_round` is the true round boundary. `refresh_for_extra_turn`
# hands back resources without it.
#
# THE LIMITER MATTERS MOST. Кровавое безумие and Азарт Охотника are both
# «только один раз за ход». If an extra turn reset that counter, they would
# chain without bound: kill -> extra action -> kill -> extra action. So
# `once_per_round` is cleared by begin_round and by NOTHING else.
# ---------------------------------------------------------------------------

def begin_round(u: Combatant) -> Trace:
    """True round boundary. The ONLY place once-per-round limiters are cleared."""
    t = Trace(f"{u.name}.begin_round")
    u.movement_remaining = effective_speed(u)[0]
    u.steps_this_round = 0
    u.action_spent = False
    u.resting = False
    u.once_per_round.clear()
    t.step("refresh", 0, u.movement_remaining, "movement, steps, action, limiters")
    # «в свой следующий ход принудительно выполняет команду Отдых» — a unit that
    # ended the previous round at zero stamina spends this one resting.
    if u.forced_rest:
        rest(u)
        u.forced_rest = False
        u.movement_remaining = 0
        u.action_spent = True
        t.step("forced rest", 0, u.stamina, "round consumed")
    t.result = u.movement_remaining
    return t


def refresh_for_extra_turn(u: Combatant, *, fire_round_start: bool = False,
                           reset_steps: bool = False) -> Trace:
    """Hand a unit its movement and action back inside the current round.

    `fire_round_start` — whether the grant also triggers "в начале хода"
    effects. Both variants exist among the spells, so it is a parameter rather
    than a decision. When True this also serves a pending forced rest, which
    means such a spell can rescue an exhausted unit.

    `reset_steps` — UNKNOWN (OPEN_QUESTIONS item 17). Left False so that
    `Атака с разгона` keeps accumulating across both turns of the same round,
    consistent with charge counting cumulative movement rather than
    displacement. Resetting would silently nerf cavalry given an extra turn.

    Never clears `once_per_round`, and never clears `resting`: a rest already
    taken is not undone by being handed another turn.
    """
    t = Trace(f"{u.name}.extra_turn")
    t.base = u.movement_remaining
    u.movement_remaining = effective_speed(u)[0]
    u.action_spent = False
    if reset_steps:
        t.step("steps reset", u.steps_this_round, 0)
        u.steps_this_round = 0
    t.step("refresh", t.base, u.movement_remaining,
           "movement and action only" if not fire_round_start else "with round-start effects")
    if fire_round_start and u.forced_rest:
        rest(u)
        u.forced_rest = False
        u.movement_remaining = 0
        u.action_spent = True
        t.step("forced rest served", 0, u.stamina, "round-start effects fired")
    t.result = u.movement_remaining
    return t


def may_trigger_once(u: Combatant, source: str) -> bool:
    """For «только один раз за ход» effects. Survives extra turns by design."""
    return source not in u.once_per_round


def mark_triggered(u: Combatant, source: str) -> None:
    u.once_per_round.add(source)


def grant_extra_turn(u: Combatant, *, source: str = "", once_per_round: bool = False,
                     fire_round_start: bool = False,
                     reset_steps: bool = False) -> tuple[bool, Trace]:
    """Returns (granted, trace). Refused if the unit is dead or the source has
    already fired this round."""
    if not u.alive:
        return False, Trace(f"{u.name}.extra_turn refused: dead")
    if once_per_round and not may_trigger_once(u, source):
        t = Trace(f"{u.name}.extra_turn")
        t.step("refused", 0, 0, f"{source} already triggered this round")
        return False, t
    if once_per_round:
        mark_triggered(u, source)
    return True, refresh_for_extra_turn(u, fire_round_start=fire_round_start,
                                        reset_steps=reset_steps)


def grant_extra_turn_to(units, *, exclude=(), predicate=None, **kw) -> list:
    """Group grants: Искажение Хаоса (all friendly demons), Клич некроманта
    (all friendly undead EXCEPT слуги Смерти), Стимул (several kobold slaves).

    `exclude` covers both the documented content exclusion and the common
    caster-excluded pattern; `predicate` covers the subtype filter. Rider
    effects (Стимул's +1 speed, Слово вождя's 5 damage) are applied by the
    CALLER — they belong to the spell, not to the turn system.
    """
    traces = []
    for u in units:
        if u in exclude or (predicate is not None and not predicate(u)):
            continue
        granted, t = grant_extra_turn(u, **kw)
        if granted:
            traces.append(t)
    return traces


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
    ## The side has declared itself finished for this round. Needed because a
    ## phase does NOT end when resources run out: with free re-entry a unit
    ## almost always has leftover movement, so without a voluntary "done" the
    ## two sides hand control back and forth forever and no round ever ends.
    ## This is the model's equivalent of clicking End Turn.
    passed: bool = False

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
        s.passed = False
        for u in s.units:
            if u.alive:
                begin_round(u)
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
    """The active side declares itself finished. Returns True if a new round
    started.

    A new round begins once BOTH sides are finished — each having either passed
    voluntarily or run out of resources. Waiting for resources alone would never
    trigger: with free re-entry a unit almost always has leftover movement, so
    the sides would trade control indefinitely.

    Whole-phase alternation, not unit-by-unit (user-confirmed).
    """
    current = state.side(state.active_side)
    current.passed = True
    other = state.other(state.active_side)
    if other.passed or phase_done(state, other.id):
        begin_new_round(state)
        return True
    state.active_side = other.id
    state.log.append(f"side {state.active_side} takes over")
    return False


def battle_over(state: BattleState) -> bool:
    return any(not s.living() for s in state.sides)
