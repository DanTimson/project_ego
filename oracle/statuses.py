"""
statuses.py — timed effects.

Thirty-six abilities carry duration or stacking language, and between them they
settle four things that could not be guessed:

    DURATION IS REDUCED BY THE TARGET'S RESIST
        «Сопротивление противника снижает время действия» — Сглаз, Окаменение,
        Насылает гниение. The arithmetic is the documented spell formula:
        base + concentration*DurationMod/100 - effective_resist*ResistDuration/100

    STACKING IS PER-EFFECT, NOT GLOBAL
        «кумулятивному воздействию» (Всплеск Тьмы, Шторм Тьмы) stacks, while
        «Способности нескольких Оруженосцев НЕ СКЛАДЫВАЮТСЯ между собой, вместо
        этого выбирается» the maximum. Both idioms appear, so the policy is a
        property of the effect.

    DURATION IS REDUCIBLE FROM OUTSIDE
        Разрушение заклинаний shortens enemy enchantments by N; Исцеление and
        Излечение shorten hostile ones; Опытный лекарь shortens poison and
        bleeding specifically. So durations are not merely counted down — they
        are a target other effects act on.

    SOME EFFECTS DECAY AGAINST THE TARGET'S OWN STATS
        Паутина: «каждые 10 единиц атаки, контратаки или магической
        дистанционной атаки цели снижает длительность опутывания на 1». A
        per-effect rule, not a general one — hence `decay_per` rather than a
        hardcoded formula.

Effects carry Modifiers, so a status changing a number does it through the same
pipeline as everything else. Nothing here recomputes damage.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum

from combat import Trace


class Stacking(Enum):
    """What happens when an effect is applied to a unit that already has it."""

    CUMULATIVE = "cumulative"   ## a separate instance each time — Всплеск Тьмы
    MAXIMUM = "maximum"         ## only the strongest applies — Оруженосец, Мощь племени
    REFRESH = "refresh"         ## reapplying resets the duration
    UNIQUE = "unique"           ## ignored entirely if already present


## Duration values with a meaning other than "this many rounds".
PERMANENT = -1
UNTIL_NEXT_TURN = 0   ## expires at the owner's next round start — Бдительность


@dataclass
class StatusEffect:
    id: str
    name: str = ""
    source: str = ""
    duration: int = PERMANENT
    power: int = 0

    ## Modifiers this effect contributes while active. They go through the
    ## normal Pipeline; a status never computes a number itself.
    modifiers: list = field(default_factory=list)

    ## Per-round deltas, applied at round start: {"life": -4, "stamina": -2}.
    ## Всплеск Тьмы is exactly this shape.
    tick: dict = field(default_factory=dict)

    stacking: Stacking = Stacking.REFRESH

    ## «не может действовать» — Окаменение, Паутина.
    prevents_action: bool = False

    ## Hostile effects are what Разрушение заклинаний and the healing spells
    ## shorten; friendly buffs are not.
    hostile: bool = False

    ## Tags for targeted removal: Опытный лекарь shortens "poison" and
    ## "bleeding" specifically rather than everything hostile.
    tags: tuple = ()

    ## «каждые 10 единиц атаки ... снижает длительность на 1» — Паутина.
    ## (stat_name, units_per_point) or None.
    decay_per: tuple | None = None

    def expired(self) -> bool:
        return self.duration == 0

    def describe(self) -> str:
        if self.duration == PERMANENT:
            return self.name or self.id
        return "%s (%d)" % (self.name or self.id, self.duration)


# ---------------------------------------------------------------------------
# Duration arithmetic
# ---------------------------------------------------------------------------

def effective_duration(base: int, concentration: int = 0, duration_mod: int = 0,
                       target_resist: int = 0, resist_duration: int = 0,
                       thaumaturgy: int = 0) -> int:
    """«Сила и длительность заклинаний», the documented form.

    DurationMod and ResistDuration are percentages PER POINT: 100 means one
    round per point of concentration, 200 two, 50 one per two points.
    Thaumaturgy subtracts from the target's resist before it counts.

    The page's worked example: concentration 3, thaumaturgy 2, target resist 7
    -> effective resist 5; base 6 with both mods at 100 -> 6 + 3 - 5 = 4.
    """
    effective_resist = max(0, target_resist - thaumaturgy)
    gain = concentration * duration_mod // 100
    loss = effective_resist * resist_duration // 100
    return max(0, base + gain - loss)


def decay_from_stats(effect: StatusEffect, unit) -> int:
    """Паутина's rule: the target's own numbers erode the effect.

    Per-effect rather than general — nothing else in the documentation works
    this way, so it lives on the effect that needs it.
    """
    if effect.decay_per is None:
        return 0
    stat_name, per = effect.decay_per
    if stat_name == "attack_group":
        # «атаки, контратаки или магической дистанционной атаки» — the best of
        # the three, not their sum.
        value = max(unit.attack, unit.counter_attack, unit.ranged_attack)
    else:
        value = getattr(unit, stat_name, 0)
    return value // per if per else 0


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

def find(unit, effect_id: str):
    return [e for e in unit.statuses if e.id == effect_id]


def apply(unit, effect: StatusEffect) -> Trace:
    """Add an effect, honouring its stacking policy."""
    t = Trace("%s <- %s" % (unit.name, effect.describe()))
    existing = find(unit, effect.id)

    if not existing:
        unit.statuses.append(effect)
        t.step("applied", 0, effect.duration, effect.stacking.value)
        return t

    if effect.stacking is Stacking.CUMULATIVE:
        unit.statuses.append(effect)
        t.step("stacked", len(existing), len(existing) + 1, "cumulative")
    elif effect.stacking is Stacking.MAXIMUM:
        strongest = max(existing, key=lambda e: e.power)
        if effect.power > strongest.power:
            unit.statuses.remove(strongest)
            unit.statuses.append(effect)
            t.step("replaced", strongest.power, effect.power, "stronger")
        else:
            t.step("ignored", strongest.power, strongest.power,
                   "«не складываются, вместо этого выбирается» the maximum")
    elif effect.stacking is Stacking.REFRESH:
        current = existing[0]
        before = current.duration
        current.duration = max(current.duration, effect.duration)
        current.power = max(current.power, effect.power)
        t.step("refreshed", before, current.duration)
    else:  # UNIQUE
        t.step("ignored", 1, 1, "already present")
    return t


def remove(unit, effect_id: str) -> int:
    before = len(unit.statuses)
    unit.statuses = [e for e in unit.statuses if e.id != effect_id]
    return before - len(unit.statuses)


def reduce_duration(unit, amount: int, *, hostile_only: bool = True,
                    tags: tuple = ()) -> Trace:
    """Разрушение заклинаний, Исцеление, Излечение, Опытный лекарь.

    `tags` narrows it: Опытный лекарь shortens poison and bleeding, not every
    hostile effect.
    """
    t = Trace("%s: shorten effects" % unit.name)
    shortened = 0
    for e in list(unit.statuses):
        if hostile_only and not e.hostile:
            continue
        if tags and not any(tag in e.tags for tag in tags):
            continue
        if e.duration == PERMANENT:
            continue
        before = e.duration
        e.duration = max(0, e.duration - amount)
        t.step(e.name or e.id, before, e.duration)
        shortened += 1
        if e.duration == 0:
            unit.statuses.remove(e)
            t.step(e.name or e.id, 0, 0, "expired")
    if not shortened:
        t.step("nothing to shorten", 0, 0)
    return t


# ---------------------------------------------------------------------------
# The round tick
# ---------------------------------------------------------------------------

def tick_round(unit) -> Trace:
    """Apply per-round deltas, then age every effect by one round.

    Order matters and is not arbitrary: an effect that deals damage on the turn
    it expires should still deal it. Ageing first would silently drop the last
    tick of every damage-over-time effect.
    """
    t = Trace("%s: statuses" % unit.name)

    for e in list(unit.statuses):
        for stat, delta in e.tick.items():
            before = getattr(unit, stat, 0)
            after = before + delta
            if stat == "life":
                after = min(after, unit.life_base)
            elif stat == "stamina":
                after = max(0, min(after, unit.stamina_base))
            elif stat == "morale":
                after = max(0, min(after, unit.morale_base))
            setattr(unit, stat, after)
            t.step("%s: %s" % (e.name or e.id, stat), before, after)
        if unit.life <= 0 and unit.alive:
            unit.alive = False
            t.step("died", 0, 0, "killed by %s" % (e.name or e.id))

    for e in list(unit.statuses):
        if e.duration == PERMANENT:
            continue
        before = e.duration
        e.duration -= 1 + decay_from_stats(e, unit)
        if e.duration != before - 1:
            t.step("%s decays faster" % (e.name or e.id), before, max(0, e.duration),
                   "eroded by the target's own stats")
        if e.duration <= 0:
            unit.statuses.remove(e)
            t.step(e.name or e.id, before, 0, "expired")
    return t


def active_modifiers(unit) -> list:
    """Every Modifier contributed by active effects, for the Pipeline."""
    out = []
    for e in unit.statuses:
        out.extend(e.modifiers)
    return out


def can_act(unit) -> tuple[bool, str]:
    """«не может действовать» — Окаменение, Паутина."""
    for e in unit.statuses:
        if e.prevents_action:
            return False, e.name or e.id
    return True, ""
