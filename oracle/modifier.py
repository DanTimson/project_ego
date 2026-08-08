"""
modifier.py — the atomic value type and the resolution pipeline.

Until now the damage pipeline hardcoded its three multipliers and read two
scalar `attack_bonus` / `defence_bonus` fields. Those fields were always a
placeholder for "the sum of every additive modifier", and this module is what
they were standing in for. Content loading resolves an opcode to a handler name;
this is what finally calls it.

THE HOOK ORDER IS THE ARCHITECTURE. Hook is an IntEnum and modifiers resolve in
hook order, so the declaration order below decides rounding, clamping, and
whether percentage modifiers compound. Reordering it changes every battle
outcome, which is why it is written once, in one place, with the reasoning
attached.

ONE VALUE TYPE. Innate ability, level-up perk, item enchant, spell buff,
terrain, medal, aura — all of them are a Modifier. One type, one resolution
path, one place to debug.

THE MULTIPLIERS ARE NOT MODIFIERS. StaminaMod, MoraleMod and WoundMod are
intrinsic pipeline stages, not things content can add or remove. They sit
between the additive hooks by construction, which is what makes
`(base + additive) * multipliers` the documented order rather than an emergent
one.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import IntEnum

from combat import Trace


class Hook(IntEnum):
    """Resolution order. Lower runs first.

    Only the hooks the engine actually reaches today are listed. The full
    33-hook taxonomy lives in tools/var/hooks.py; adding one here means the
    pipeline can dispatch it, and the gap between the two lists is honest
    about what is implemented.
    """

    # --- attack, attacker side ---
    STAT_PASSIVE = 10        # flat deltas to a base stat, inside the multipliers
    DAMAGE_BASE = 20         # reshapes the damage figure itself
    DAMAGE_VS_TARGET = 30    # conditional bonuses, OUTSIDE the multipliers

    # --- attack, defender side ---
    EVASION = 40             # avoid the strike entirely
    DEFENCE_APPLY = 50       # defence subtracted, bypassed or scaled
    DAMAGE_TAKEN = 60        # final modification of incoming damage

    # --- riders ---
    ON_HIT = 70
    ON_DAMAGED = 80
    COUNTERATTACK = 90
    ON_KILL = 100
    ON_DEATH = 110

    # --- resources and state ---
    STAMINA = 120
    MORALE = 130
    AMMO = 140
    STATUS_RESIST = 150

    # --- passive, no value to resolve ---
    AURA = 160


@dataclass(frozen=True)
class Modifier:
    """One thing that changes one number.

    `ability` is the opcode — opaque, meaningful only against its pack.
    `handler` is the engine function name the pack's bindings resolved it to.
    Both are kept: the opcode identifies WHAT, the handler identifies HOW, and
    they differ per pack.
    """

    ability: int
    handler: str
    hook: Hook
    power: int = 0
    params: dict = field(default_factory=dict)
    source: str = ""
    duration: int = -1          # -1 = permanent

    ## Already-applicable conditional attack contributions marked here resolve
    ## after effective-stat multipliers. Modifier 0x3D placement is frozen by
    ## R10; target applicability remains outside the numeric stage.
    outside_multipliers: bool = False

    def describe(self) -> str:
        return "%s%s" % (self.source or self.handler,
                         "" if self.power == 0 else " %+d" % self.power)


class Pipeline:
    """Runs modifiers at a hook, in order, through the registry."""

    def __init__(self, registry):
        self.registry = registry

    def at(self, mods, hook: Hook):
        """Modifiers for one hook, in a STABLE order.

        Sorted by (ability, source) rather than left in list order: two
        implementations that build the list differently would otherwise apply
        the same set in a different sequence.

        This ordering is for DETERMINISM ONLY and carries no semantics — it is
        alphabetical by ability name, which means nothing mechanically. Handlers
        that are non-commutative with each other must therefore live at
        DIFFERENT hooks; that is what the hook order is for. A halving belongs
        at DEFENCE_APPLY, downstream of the additive STAT_PASSIVE stage, so the
        two can never interleave by accident.
        """
        return sorted((m for m in mods if m.hook == hook),
                      key=lambda m: (m.ability, m.source, m.handler))

    def resolve(self, base, mods, hook: Hook, ctx: dict, label: str = ""):
        """Returns (value, Trace). Unknown handlers are skipped and recorded —
        an unbound opcode must not silently behave as if it did nothing, and
        must not crash the battle either."""
        t = Trace(label or ("hook:%s" % hook.name))
        t.base = base
        value = base
        for m in self.at(mods, hook):
            if not self.registry.has(m.handler):
                t.step(m.describe(), value, value, "no handler %r — skipped" % m.handler)
                continue
            params = dict(m.params)
            params["power"] = m.power
            before = value
            value = self.registry.call(m.handler, ctx, value, params)
            t.step(m.describe(), before, value, m.handler)
        t.result = value
        return value, t

    def flag(self, mods, hook: Hook, ctx: dict) -> bool:
        """True if any modifier at this hook asserts. For immunities and other
        yes/no questions, where a numeric value would be meaningless."""
        for m in self.at(mods, hook):
            if not self.registry.has(m.handler):
                continue
            params = dict(m.params)
            params["power"] = m.power
            if self.registry.call(m.handler, ctx, False, params):
                return True
        return False


def from_binding(opcode: int, handler: str, params: dict, power: int,
                 hook: Hook, source: str = "") -> Modifier:
    """Build a Modifier from what ContentDb.resolve() returns."""
    return Modifier(ability=opcode, handler=handler, hook=hook, power=power,
                    params=dict(params or {}), source=source)
