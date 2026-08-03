# oracle/auras.py
"""
auras.py — continuous area effects.

SCOPING THIS RIGHT MATTERED MORE THAN BUILDING IT. Sixty-six abilities use radius
or area language, which looks like a large aura system. It is not: 264 of them
are `Заклятье "X"` spells applying an effect once when cast, 5 are ranged attacks
that spread damage around their target, and only **10 are persistent auras**.
Those three mechanisms share the word "radius" and nothing else, so building one
"area effects" module would have produced an abstraction that fitted none of
them. Spell AoE belongs to casting; attack spread belongs to the attack path;
this file is the ten.

AURAS ARE DERIVED, NEVER APPLIED. An aura depends on where units are standing
and on its source still being alive, both of which change constantly. Applying
one as a status on entry would need removal on every move, death and expiry —
the bookkeeping that flags avoided by deriving. So `modifiers_for` recomputes
from the battlefield each time it is asked, exactly as Combatant.has_flag walks
its sources.

WHAT THE TEN ABILITIES DECLARE THEMSELVES:

    scope       «все союзники НА ПОЛЕ БОЯ» (Вдохновляющее присутствие,
                Гнетущее присутствие) versus «ВОКРУГ воина» / «РЯДОМ с воином»
                (Аура доблести, Аура жизни, Аура смерти, Аура бодрости,
                Аура увядания). Battlefield-wide and adjacent-only, no radii
                between.

    stacking    «эффекты всех лидеров СКЛАДЫВАЮТСЯ» versus «действует только
                САМАЯ СИЛЬНАЯ аура». Stated per-ability, and the same
                cumulative-versus-maximum split the status effects showed.

    side        Аура жизни helps «союзные войска»; Аура увядания drains
                «вражеские войска»; but Аура смерти drains ALL «живые войска»
                regardless of side — an aura is not necessarily friendly to its
                own army.

    subtypes    Аура жизни reaches «смертные, демоны и герои», i.e. not undead.
                Аура смерти spares «Привратников Смерти». Filters are per-aura.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

import battlefield as bfmod
from combat import Trace


class Scope(Enum):
    ADJACENT = "adjacent"       ## «вокруг воина» / «рядом с воином»
    BATTLEFIELD = "battlefield"  ## «все союзники на поле боя»
    SELF = "self"


class Side(Enum):
    ALLY = "ally"
    ENEMY = "enemy"
    ALL = "all"                  ## Аура смерти — «все живые войска»


class Stacking(Enum):
    CUMULATIVE = "cumulative"   ## «эффекты всех лидеров складываются»
    MAXIMUM = "maximum"         ## «действует только самая сильная аура»


@dataclass
class Aura:
    id: str
    name: str = ""
    scope: Scope = Scope.ADJACENT
    affects: Side = Side.ALLY
    stacking: Stacking = Stacking.MAXIMUM
    power: int = 0

    ## Modifiers granted to each affected unit. Built with the aura's power, and
    ## carrying its source so the Trace can attribute them.
    modifiers: list = field(default_factory=list)

    ## Per-round deltas: {"life": 2} for Аура жизни, {"stamina": -1} for
    ## Аура увядания. Applied by the round machinery, not here.
    tick: dict = field(default_factory=dict)

    ## Only these subtypes are affected, if given.
    only_subtypes: tuple = ()
    ## These subtypes are spared even if otherwise eligible.
    except_subtypes: tuple = ()

    ## The unit projecting it. An aura with a dead source projects nothing.
    source: object = None

    def reaches(self, target, source_hex, target_hex, field) -> bool:
        if self.source is not None and not self.source.alive:
            return False
        if target is self.source and self.scope is not Scope.SELF:
            # «все дружественные воины ВОКРУГ» — the projector is not in its own
            # adjacency. Whether it benefits from its own battlefield-wide aura
            # is not stated; excluded for consistency. OPEN_QUESTIONS item 19.
            return False
        if self.only_subtypes and not any(
                target.has_subtype(s) for s in self.only_subtypes):
            return False
        if any(target.has_subtype(s) for s in self.except_subtypes):
            return False
        if self.scope is Scope.BATTLEFIELD:
            return True
        if self.scope is Scope.SELF:
            return target is self.source
        if source_hex is None or target_hex is None:
            return False
        return source_hex.distance(target_hex) == 1


def _side_matches(aura: Aura, source_side, target_side) -> bool:
    if aura.affects is Side.ALL:
        return True
    same = source_side is not None and source_side is target_side
    return same if aura.affects is Side.ALLY else not same


def collect(unit, auras_by_source, field, side_of) -> list:
    """Every aura reaching `unit` right now.

    `auras_by_source` maps a projecting unit to its auras; `side_of` answers
    which side a unit belongs to. Both are passed in rather than looked up so
    this module needs no knowledge of BattleState.
    """
    target_hex = field.find(unit) if field is not None else None
    out = []
    for source, auras in auras_by_source.items():
        source_hex = field.find(source) if field is not None else None
        for aura in auras:
            if aura.source is None:
                aura.source = source
            if not _side_matches(aura, side_of(source), side_of(unit)):
                continue
            if aura.reaches(unit, source_hex, target_hex, field):
                out.append(aura)
    return out


def _resolve_stacking(auras: list) -> list:
    """«действует только самая сильная аура» versus «складываются».

    Grouped by aura id, because the rule is a property of the ability: two
    Аура доблести sources give the stronger one only, while two
    Вдохновляющее присутствие sources add up.
    """
    by_id: dict = {}
    for a in auras:
        by_id.setdefault(a.id, []).append(a)
    out = []
    for group in by_id.values():
        if group[0].stacking is Stacking.CUMULATIVE:
            out.extend(group)
        else:
            out.append(max(group, key=lambda a: a.power))
    return out


def active_for(unit, auras_by_source, field, side_of) -> list:
    """The auras actually in effect on `unit`, after stacking is resolved."""
    return _resolve_stacking(collect(unit, auras_by_source, field, side_of))


def modifiers_for(unit, auras_by_source, field, side_of) -> list:
    """Modifiers to hand the Pipeline. Recomputed on every call by design."""
    out = []
    for aura in active_for(unit, auras_by_source, field, side_of):
        out.extend(aura.modifiers)
    return out


def tick_for(unit, auras_by_source, field, side_of) -> tuple[dict, Trace]:
    """Per-round deltas from every aura reaching this unit.

    Аура жизни and Аура смерти can both reach the same unit — one restoring and
    one draining — so the deltas are SUMMED rather than resolved by precedence.
    Nothing in the documentation suggests one wins.
    """
    t = Trace("%s: auras" % unit.name)
    totals: dict = {}
    for aura in active_for(unit, auras_by_source, field, side_of):
        for stat, delta in aura.tick.items():
            before = totals.get(stat, 0)
            totals[stat] = before + delta
            t.step("%s: %s" % (aura.name or aura.id, stat), before, totals[stat])
    t.result = sum(totals.values())
    return totals, t


def apply_tick(unit, totals: dict) -> Trace:
    """Apply summed aura deltas, respecting the unit's caps."""
    t = Trace("%s: aura tick" % unit.name)
    for stat, delta in sorted(totals.items()):
        if not delta:
            continue
        before = getattr(unit, stat, 0)
        after = before + delta
        cap = {"life": unit.life_base, "stamina": unit.stamina_base,
               "morale": unit.morale_base}.get(stat)
        if cap is not None:
            after = min(after, cap)
        if stat in ("stamina", "morale"):
            after = max(0, after)
        setattr(unit, stat, after)
        t.step(stat, before, after)
    if unit.life <= 0 and unit.alive:
        unit.alive = False
        t.step("died", 0, 0, "killed by an aura")
    return t
