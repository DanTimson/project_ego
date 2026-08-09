"""Stable runtime status containers and explicit status policy.

Automatic duration ticking, expiry edges, and UNTIL_NEXT_TURN are intentionally
absent. Those lifecycle boundaries remain observation-first work under R13.
"""

from __future__ import annotations

import copy
from dataclasses import dataclass, field
from enum import Enum

from combat import Trace


class Stacking(Enum):
    """What happens when a status with the same project-local identity exists."""

    CUMULATIVE = "cumulative"
    MAXIMUM = "maximum"
    REFRESH = "refresh"
    UNIQUE = "unique"


PERMANENT = -1


@dataclass
class StatusEffect:
    """Address-free mutable battle-time status instance."""

    id: str
    name: str = ""
    source: str = ""
    duration: int = PERMANENT
    power: int = 0
    modifiers: list = field(default_factory=list)
    # Retained for the pre-existing explicit lifecycle-step reference helper.
    # No battle event invokes it in the stable tranche.
    tick: dict = field(default_factory=dict)
    decay_per: tuple | None = None
    stacking: Stacking = Stacking.REFRESH
    prevents_action: bool = False
    hostile: bool = False
    remove_on_damage: bool = False
    tags: tuple = ()

    def describe(self) -> str:
        if self.duration == PERMANENT:
            return self.name or self.id
        return "%s (%d)" % (self.name or self.id, self.duration)

    def copy(self) -> "StatusEffect":
        return copy.deepcopy(self)

    def to_dict(self) -> dict:
        out = {
            "id": self.id,
            "name": self.name,
            "source": self.source,
            "duration": self.duration,
            "power": self.power,
            "tick": copy.deepcopy(self.tick),
            "decay_per": list(self.decay_per) if self.decay_per else [],
            "stacking": self.stacking.name,
            "prevents_action": self.prevents_action,
            "hostile": self.hostile,
            "tags": list(self.tags),
            "modifiers": [
                {
                    "ability": modifier.ability,
                    "handler": modifier.handler,
                    "hook": modifier.hook.name,
                    "power": modifier.power,
                    "params": copy.deepcopy(modifier.params),
                    "source": modifier.source,
                }
                for modifier in self.modifiers
            ],
        }
        if self.remove_on_damage:
            out["remove_on_damage"] = True
        return out


def effective_duration(base: int, concentration: int = 0, duration_mod: int = 0,
                       target_resist: int = 0, resist_duration: int = 0,
                       thaumaturgy: int = 0) -> int:
    """Documented spell-duration arithmetic.

    A zero result is a fully resisted/rejected ordinary application. It is not an
    UNTIL_NEXT_TURN lifecycle sentinel.
    """
    effective_resist = max(0, target_resist - thaumaturgy)
    gain = concentration * duration_mod // 100
    loss = effective_resist * resist_duration // 100
    return max(0, base + gain - loss)


def find(unit, effect_id: str) -> list[StatusEffect]:
    return [effect for effect in unit.statuses if effect.id == effect_id]


def apply(unit, effect: StatusEffect) -> Trace:
    """Add one runtime instance according to its per-effect stacking policy."""
    trace = Trace("%s <- %s" % (unit.name, effect.describe()))
    if effect.duration == 0:
        trace.step("resisted", 0, 0, "effective duration is zero")
        return trace

    existing = find(unit, effect.id)
    if not existing:
        unit.statuses.append(effect)
        trace.step("applied", 0, effect.duration, effect.stacking.value)
        return trace

    if effect.stacking is Stacking.CUMULATIVE:
        unit.statuses.append(effect)
        trace.step("stacked", len(existing), len(existing) + 1, "cumulative")
    elif effect.stacking is Stacking.MAXIMUM:
        strongest = max(existing, key=lambda current: current.power)
        if effect.power > strongest.power:
            unit.statuses.remove(strongest)
            unit.statuses.append(effect)
            trace.step("replaced", strongest.power, effect.power, "stronger")
        else:
            trace.step("ignored", strongest.power, strongest.power,
                       "maximum already active")
    elif effect.stacking is Stacking.REFRESH:
        current = existing[0]
        before = current.duration
        current.duration = max(current.duration, effect.duration)
        current.power = max(current.power, effect.power)
        trace.step("refreshed", before, current.duration)
    else:
        trace.step("ignored", 1, 1, "already present")
    return trace


def remove_on_damage(unit) -> list[StatusEffect]:
    """Explicit damage-boundary removal; no duration clock is involved."""
    removed = [effect for effect in unit.statuses if effect.remove_on_damage]
    unit.statuses[:] = [effect for effect in unit.statuses
                        if not effect.remove_on_damage]
    return removed


def remove(unit, effect_id: str) -> int:
    """Remove every instance sharing the established effect identity/group."""
    before = len(unit.statuses)
    unit.statuses = [effect for effect in unit.statuses if effect.id != effect_id]
    return before - len(unit.statuses)


def reduce_duration(unit, amount: int, *, hostile_only: bool = True,
                    tags: tuple = ()) -> Trace:
    """Explicitly shorten matching statuses; this is not a lifecycle clock."""
    trace = Trace("%s: shorten effects" % unit.name)
    shortened = 0
    reduction = max(0, amount)
    for effect in list(unit.statuses):
        if hostile_only and not effect.hostile:
            continue
        if tags and not any(tag in effect.tags for tag in tags):
            continue
        if effect.duration == PERMANENT:
            continue
        before = effect.duration
        effect.duration = max(0, effect.duration - reduction)
        trace.step(effect.name or effect.id, before, effect.duration)
        shortened += 1
        if effect.duration == 0:
            unit.statuses.remove(effect)
            trace.step(effect.name or effect.id, 0, 0, "removed")
    if not shortened:
        trace.step("nothing to shorten", 0, 0)
    return trace


def tick_round(unit) -> Trace:
    """Run the pre-existing explicit provisional lifecycle step.

    Scenario/turn/selection/activation/extra-turn code deliberately never calls
    this helper. Its event boundary and internal tick/expiry order remain a
    reference-model assumption pending R13, not compatibility truth.
    """
    trace = Trace("%s: statuses" % unit.name)
    for effect in list(unit.statuses):
        for stat, delta in effect.tick.items():
            before = getattr(unit, stat, 0)
            after = before + delta
            if stat == "life":
                after = min(after, unit.life_base)
            elif stat == "stamina":
                after = max(0, min(after, unit.stamina_base))
            elif stat == "morale":
                after = max(0, min(after, unit.morale_base))
            setattr(unit, stat, after)
            trace.step("%s: %s" % (effect.name or effect.id, stat), before, after)
        if unit.life <= 0 and unit.alive:
            unit.alive = False
            trace.step("died", 0, 0, "killed by %s" % (effect.name or effect.id))

    for effect in list(unit.statuses):
        if effect.duration == PERMANENT:
            continue
        before = effect.duration
        effect.duration -= 1 + decay_from_stats(effect, unit)
        if effect.duration != before - 1:
            trace.step("%s decays faster" % (effect.name or effect.id),
                       before, max(0, effect.duration),
                       "eroded by the target's own stats")
        if effect.duration <= 0:
            unit.statuses.remove(effect)
            trace.step(effect.name or effect.id, before, 0,
                       "expired in provisional explicit step")
    return trace


def decay_from_stats(effect: StatusEffect, unit) -> int:
    if effect.decay_per is None:
        return 0
    stat_name, per = effect.decay_per
    if stat_name == "attack_group":
        value = max(unit.attack, unit.counter_attack, unit.ranged_attack)
    else:
        value = getattr(unit, stat_name, 0)
    return value // per if per else 0


def active_modifiers(unit) -> list:
    """Every modifier contributed by active statuses."""
    return [modifier for effect in unit.statuses for modifier in effect.modifiers]


def can_act(unit) -> tuple[bool, str]:
    """Existing stable status-state query; not an action executor."""
    for effect in unit.statuses:
        if effect.prevents_action:
            return False, effect.name or effect.id
    return True, ""
