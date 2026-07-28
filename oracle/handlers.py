"""
handlers.py — the engine side of the opcode bindings.

Handlers are named, never numbered. A pack maps opcode 30 to "magic_immunity"
or to "armor_pierce"; the rules layer calls whichever name came back and
contains no conditional about which pack is loaded. That indirection is the
whole reason the vanilla/NH opcode reassignment is a data problem rather than a
code problem.

Signature is uniform: (ctx, value, params) -> value.

    ctx     what is being computed and for whom — "stat", "unit", "target",
            "kind". Handlers read it; they never write to it.
    value   the running value at this point in the pipeline.
    params  from the pack binding, plus "power" injected from the modifier.

Registering a handler is what moves an opcode from `unbound` to `usable` in the
load report, so this file IS the progress meter's denominator.
"""

from __future__ import annotations


# ---------------------------------------------------------------------------
# Stat deltas — the largest unambiguous family.
#
# 15-16 opcodes per pack collapse to this single handler because the stat is a
# parameter rather than part of the opcode. The `stat` guard matters: a
# modifier granting +2 Attack must not also raise Defence when the pipeline
# happens to be resolving Defence.
# ---------------------------------------------------------------------------

def stat_delta(ctx, value, params):
    if params.get("stat") != ctx.get("stat"):
        return value
    return value + int(params.get("power", 0))


def stat_scale(ctx, value, params):
    """Percentage modifiers. `power` is a percentage: 50 means +50%.

    Kept separate from stat_delta because they must not interleave — additive
    before multiplicative is documented and not negotiable, and giving them
    different hooks is how that is enforced structurally rather than by
    convention.
    """
    if params.get("stat") != ctx.get("stat"):
        return value
    return value * (1.0 + int(params.get("power", 0)) / 100.0)


# ---------------------------------------------------------------------------
# Defence modification
# ---------------------------------------------------------------------------

def armor_pierce(ctx, value, params):
    """«дистанционная защита ... её значение считается в 2 раза меньшим» —
    the documented form is a HALVING, not a flat subtraction. Recorded here
    rather than as a constant so the distinction survives.
    """
    return value * 0.5


def defence_ignore(ctx, value, params):
    """Flat bypass, for abilities whose text says a number rather than a
    fraction. Floors at 0 — negative defence would turn a bypass into a bonus.
    """
    return max(0, value - int(params.get("power", 0)))


# ---------------------------------------------------------------------------
# Conditional damage — the family that sits OUTSIDE the multiplier chain.
# ---------------------------------------------------------------------------

def bonus_vs_subtype(ctx, value, params):
    """`Охотник на X`, `Сокрушение зла` and similar. Applies only when the
    target carries the named subtype.

    Morale does not multiply these; the modifier carrying this handler should
    be built with outside_multipliers=True.
    """
    target = ctx.get("target")
    wanted = params.get("subtype")
    if target is None or wanted is None:
        return value
    if not target.has_subtype(wanted):
        return value
    return value + int(params.get("power", 0))


# ---------------------------------------------------------------------------
# Yes/no answers. These run through Pipeline.flag(), where `value` arrives as
# False and any handler asserting True short-circuits.
# ---------------------------------------------------------------------------

def immunity(ctx, value, params):
    return params.get("against") == ctx.get("against")


def resistance(ctx, value, params):
    """Partial resistance: reduces rather than nullifies. Returns a value, so
    it is used through resolve() and not through flag()."""
    if params.get("against") != ctx.get("against"):
        return value
    return value * max(0.0, 1.0 - int(params.get("power", 0)) / 100.0)


def magic_immunity(ctx, value, params):
    return ctx.get("school") is not None


# ---------------------------------------------------------------------------
# Spell grants — 276 of 598 NH opcodes, one handler.
#
# Granting a spell changes no number, so it returns `value` untouched. It exists
# to be enumerable: asking a unit which spells it knows means walking its
# modifiers for this handler.
# ---------------------------------------------------------------------------

def grant_spell(ctx, value, params):
    known = ctx.get("known_spells")
    if known is not None and params.get("spell"):
        known.add(params["spell"])
    return value


def spells_granted(mods) -> set:
    return {m.params["spell"] for m in mods
            if m.handler == "grant_spell" and m.params.get("spell")}


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

ALL = {
    "stat_delta": stat_delta,
    "stat_scale": stat_scale,
    "armor_pierce": armor_pierce,
    "defence_ignore": defence_ignore,
    "bonus_vs_subtype": bonus_vs_subtype,
    "immunity": immunity,
    "resistance": resistance,
    "magic_immunity": magic_immunity,
    "grant_spell": grant_spell,
}


def register_all(registry) -> None:
    for name, fn in ALL.items():
        if not registry.has(name):
            registry.register(name, fn)
