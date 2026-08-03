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
# Presence-only abilities
#
# The single highest-leverage handler in the file. A large family of abilities
# compute nothing — they are simply TRUE or FALSE about a unit, and the rules
# modules already ask:
#
#     wounds.py         "Не чувствует боли", "Боевое безумие"
#     stamina.py        "Неутомимый"
#     counterattack.py  "Ловкость", "Первый удар", "Не сражается",
#                       "Касание вампира"
#
# Those checks were written against flags that nothing set. Binding an opcode to
# `grant_flag` sets the flag at build time and the existing rule lights up with
# no further work — which is why one handler closes so many blockers at once.
#
# The flag NAME comes from the binding params, not from the handler, because the
# same behaviour has different names in different packs.
# ---------------------------------------------------------------------------

def grant_flag(ctx, value, params):
    """A no-op by design.

    Flags are DERIVED from the modifier list rather than written into the unit:
    Combatant.has_flag walks modifiers and statuses as well as the explicit set.
    That is what makes a temporary flag work — a spell granting Неутомимый for
    three rounds needs no separate bookkeeping, because the modifier appears and
    vanishes with the status carrying it.

    Mutating the unit here would work for innate abilities and silently fail for
    every temporary one, which is the worse failure: it looks correct in tests
    built from unit.var and breaks the first time a buff is cast.
    """
    return value


def flags_granted(mods) -> set:
    return {m.params["flag"] for m in mods
            if m.handler == "grant_flag" and m.params.get("flag")}


# ---------------------------------------------------------------------------
# Terrain knowledge
#
# «Он тратит только единицу скорости на преодоление [тайла] и не тратит
# выносливость. Кроме того, каждый пункт знания выше первого увеличивает защиту
# и контратаку воина на 1.»
#
# Two effects from one ability, and the second is conditional on the FIRST point
# being exceeded — a rank-1 Знание леса gives movement relief only, rank 3 gives
# +2 defence and counterattack on top.
# ---------------------------------------------------------------------------

def terrain_knowledge(ctx, value, params):
    if ctx.get("stat") not in ("defence", "counter_attack"):
        return value
    rank = int(params.get("power", 0))
    return value + max(0, rank - 1)


def knows_terrain(mods, terrain: str) -> int:
    """Rank held for a terrain, or 0. Movement code asks this rather than
    walking the modifier list itself."""
    for m in mods:
        if m.handler == "terrain_knowledge" and m.params.get("terrain") == terrain:
            return m.power
    return 0


# ---------------------------------------------------------------------------
# Damage typing
#
# «наносит магический урон, и от неё спасает не защита, а сопротивление» —
# magical attacks are reduced by Resist instead of Defence. That is a change of
# WHICH STAT the defender applies, not a change to any number, so the handler
# only records the type and the damage path reads it.
# ---------------------------------------------------------------------------

def damage_type(ctx, value, params):
    return value


def defence_stat_for(mods, kind_is_ranged: bool) -> str:
    """Which defender stat this attacker's damage resolves against."""
    want = "ranged" if kind_is_ranged else "melee"
    for m in mods:
        if m.handler == "damage_type" and m.params.get("applies_to") == want:
            if m.params.get("type") == "magic":
                return "resist"
    return "ranged_defence" if kind_is_ranged else "defence"


# ---------------------------------------------------------------------------
# Province-layer abilities
#
# Осада, Мародер, Грабитель, Трудоголик and friends do nothing in a battle. They
# are bound to an explicit no-op rather than left unbound, because "implemented,
# and it does nothing here" and "not implemented yet" are different facts and the
# load report must not conflate them.
# ---------------------------------------------------------------------------

def strategic_only(ctx, value, params):
    return value


# ---------------------------------------------------------------------------
# Regeneration
#
# «восстанавливает %d жизни каждый ход» — a per-round tick, so it is applied by
# the status/round machinery rather than computed here. This handler exists to
# make the ability enumerable and to carry its magnitude.
# ---------------------------------------------------------------------------

def regeneration(ctx, value, params):
    return value


def regeneration_rate(mods) -> int:
    return sum(m.power for m in mods if m.handler == "regeneration")


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
    "grant_flag": grant_flag,
    "terrain_knowledge": terrain_knowledge,
    "damage_type": damage_type,
    "strategic_only": strategic_only,
    "regeneration": regeneration,
}


def register_all(registry) -> None:
    for name, fn in ALL.items():
        if not registry.has(name):
            registry.register(name, fn)
