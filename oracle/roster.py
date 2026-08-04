"""
roster.py — turn a unit.var record into a live Combatant.

This closes the last link in the chain. Everything before it was engine
machinery with hand-written test units; this is where the 290-unit corpus
becomes something the battle loop can fight with.

THE RESOLUTION CHAIN, and every hop can fail independently:

    unit.var "Abilityes"  ->  unit_upg INDEX          (a curried modifier)
    unit_upg "Upg Type"   ->  ability_num Number      (the opcode)
    unit_upg "Quantity"   ->  the modifier's power    (the magnitude)
    bindings[opcode]      ->  handler name + params   (per content pack)
    registry[handler]     ->  the engine function

Recall the trap from the format work: unit.var's `Abilityes` block references
unit_upg by INDEX, while item/spell/medal `Effects` reference ability_num by
NUMBER. Both are dense integer spaces, so resolving against the wrong table
succeeds about 97% of the time and returns silent nonsense. This module only
ever walks the unit path, and says so at every hop.

WHAT IT REFUSES TO DO. A unit whose abilities are unbound still builds, with
those abilities recorded as unresolved rather than dropped. Silently building a
Мечник without his Парирование would produce a unit that fights wrong and looks
fine — the exact failure mode the load report exists to prevent.
"""

from __future__ import annotations

import identity
from dataclasses import dataclass, field

from combat import Combatant
from modifier import Hook, Modifier

## unit.var column -> Combatant attribute. Only the combat-relevant ones; the
## economic (GoldPrice, GemPayment) and presentation (SoundHit, Missile) columns
## are deliberately not carried into the battle model.
STAT_COLUMNS = {
    "Life": "life",
    "Attack": "attack",
    "CounterAttack": "counter_attack",
    "Defence": "defence",
    "RangedDefence": "ranged_defence",
    "Resist": "resist",
    "Speed": "speed",
    "RangedAttack": "ranged_attack",
    "ShootingRange": "shooting_range",
    "Ammo": "ammo",
    "Stamina": "stamina",
    "Morale": "morale",
}

## Hook names in the bindings file -> the Hook enum. A binding naming a hook the
## engine does not implement resolves to STAT_PASSIVE and is reported, rather
## than silently landing somewhere arbitrary.
DEFAULT_HOOK = Hook.STAT_PASSIVE


@dataclass
class UnresolvedAbility:
    """One ability that could not be turned into a Modifier, and where it broke."""
    upgrade_index: int
    upgrade_name: str = ""
    opcode: int | None = None
    ability_name: str = ""
    reason: str = ""

    def __str__(self) -> str:
        head = "upg/%d %s" % (self.upgrade_index, self.upgrade_name or "?")
        if self.opcode is not None:
            head += " -> opcode %d %s" % (self.opcode, self.ability_name)
        return "%s: %s" % (head, self.reason)


@dataclass
class BuiltUnit:
    unit: Combatant
    resolved: list = field(default_factory=list)      # (opcode, name)
    unresolved: list = field(default_factory=list)    # UnresolvedAbility
    content_id: str = ""                              # canonical, pack-qualified
    provenance: dict = field(default_factory=dict)

    @property
    def complete(self) -> bool:
        return not self.unresolved

    def summary(self) -> str:
        return "%s: %d abilities resolved, %d unresolved" % (
            self.unit.name, len(self.resolved), len(self.unresolved))


class Roster:
    """Builds Combatants from a ContentDb's tables."""

    def __init__(self, db):
        self.db = db
        self.index = db.index
        self.units = db.pack.tables.get("unit", {})
        self.upgrades = db.pack.tables.get("unit_upg", {})
        self.abilities = db.pack.tables.get("ability_num", {})
        # ability_num is indexed by record, but bindings are keyed by the
        # `Number` column — the same distinction that makes the two-namespace
        # trap possible.
        self.by_number = {
            r.get("Number"): r for r in self.abilities.values()
            if isinstance(r.get("Number"), int)
        }

    # -- lookup -------------------------------------------------------------

    def find(self, name: str):
        """Transitional pack-scoped name lookup. Prefer canonical IDs.

        Raises identity.AmbiguousName rather than returning the first match, so
        an ambiguous name fails loudly instead of resolving to a plausible wrong
        record. Cross-pack ambiguity cannot occur here — a Roster wraps exactly
        one pack — but the same name can repeat inside one table.
        """
        return self.index.resolve(name, "unit")

    def names(self) -> list:
        return sorted(r.get("Name", "") for r in self.units.values()
                      if r.get("Name") and r.get("Name") != "Пусто")

    def ids(self) -> list:
        """Canonical unit IDs. This is the addressing mode callers should use."""
        return self.index.ids("unit")

    def id_for_name(self, name: str) -> str | None:
        return self.index.id_for_name(name, "unit")

    # -- building -----------------------------------------------------------

    def build(self, reference, *, hook_for=None) -> BuiltUnit | None:
        """Build by canonical ID, by raw record index, or by display name.

        Canonical ID is the supported form; the other two are transitional.
        """
        if isinstance(reference, int):
            record = self.units.get(reference)
        else:
            record = self.index.resolve(reference, "unit")
        if record is None:
            return None

        record_index_early = record.get("index", -1)
        unit = Combatant(
            name=record.get("Name", "?"),
            content_id=identity.make_id(self.db.pack.id, "unit", record_index_early)
            if isinstance(record_index_early, int) and record_index_early >= 0 else "",
        )
        for column, attr in STAT_COLUMNS.items():
            value = record.get(column)
            if isinstance(value, int):
                setattr(unit, attr, value)
        # Base values are what the multipliers and caps measure against, and the
        # .var tables carry only the current figure.
        unit.life_base = unit.life
        unit.stamina_base = unit.stamina
        unit.morale_base = unit.morale

        subtypes = record.get("Subtype")
        if isinstance(subtypes, list):
            unit.subtypes = {str(s) for s in subtypes if s}
        elif isinstance(subtypes, int) and subtypes:
            unit.subtypes = {str(subtypes)}

        record_index = record.get("index", -1)
        built = BuiltUnit(
            unit=unit,
            content_id=identity.make_id(self.db.pack.id, "unit", record_index)
            if isinstance(record_index, int) and record_index >= 0 else "",
            provenance=identity.Provenance(
                pack=self.db.pack.id,
                source_kind="var",
                source_file="unit.var",
                source_record_index=record_index
                if isinstance(record_index, int) else -1,
            ).as_dict(),
        )
        for entry in record.get("Abilityes", []) or []:
            self._resolve_ability(entry, built, hook_for)
        return built

    def _resolve_ability(self, entry, built: BuiltUnit, hook_for) -> None:
        ref = entry.get("ref") if isinstance(entry, dict) else entry
        if not isinstance(ref, int) or ref == 0:
            return   # /0 is the reserved empty entry, not a real ability

        upgrade = self.upgrades.get(ref)
        if upgrade is None:
            built.unresolved.append(UnresolvedAbility(
                upgrade_index=ref,
                reason="no unit_upg record — the reference is dangling"))
            return

        upgrade_name = upgrade.get("Name", "")

        # COMPOUND ROWS. `Upg Type` and `Quantity` are PARALLEL LISTS when one
        # upgrade grants several abilities at once — `Здоровье +1` is
        # [1, 11] / [1, 1] (Life and Stamina together), `Младшая нежить` is
        # [13, 19, 18, 42] / [1, 1, 1, 1]. 10 of 153 vanilla rows and 212 of 868
        # NH rows are like this, and lengths always match in both corpora.
        #
        # Treating Upg Type as a scalar silently drops every ability after the
        # first, which would build a unit that fights wrong and looks fine.
        opcodes = upgrade.get("Upg Type")
        powers = upgrade.get("Quantity", 0)
        if isinstance(opcodes, list):
            if not isinstance(powers, list):
                powers = [powers] * len(opcodes)
            if len(powers) != len(opcodes):
                built.unresolved.append(UnresolvedAbility(
                    upgrade_index=ref, upgrade_name=upgrade_name,
                    reason="Upg Type and Quantity lists differ in length "
                           "(%d vs %d)" % (len(opcodes), len(powers))))
                return
            for opcode, power in zip(opcodes, powers):
                self._resolve_one(ref, upgrade_name, opcode, power, built, hook_for)
            return
        self._resolve_one(ref, upgrade_name, opcodes, powers, built, hook_for)

    def _resolve_one(self, ref: int, upgrade_name: str, opcode, power,
                     built: BuiltUnit, hook_for) -> None:
        if not isinstance(opcode, int):
            built.unresolved.append(UnresolvedAbility(
                upgrade_index=ref, upgrade_name=upgrade_name,
                reason="unit_upg row has no usable Upg Type"))
            return

        ability = self.by_number.get(opcode)
        ability_name = ability.get("Name", "") if ability else ""

        handler, params = self.db.resolve(opcode)
        if not handler:
            binding = self.db.pack.binding(opcode)
            if binding is None:
                reason = "opcode is in no binding table"
            elif not binding.is_bound:
                reason = "unbound in %s" % self.db.pack.id
            else:
                reason = "handler %r is not implemented" % binding.handler
            built.unresolved.append(UnresolvedAbility(
                upgrade_index=ref, upgrade_name=upgrade_name, opcode=opcode,
                ability_name=ability_name, reason=reason))
            return

        binding = self.db.pack.binding(opcode)
        hook = DEFAULT_HOOK
        if hook_for is not None:
            hook = hook_for(binding.hook if binding else "", opcode)
        elif binding is not None:
            hook = getattr(Hook, binding.hook, DEFAULT_HOOK)

        built.unit.modifiers.append(Modifier(
            ability=opcode, handler=handler, hook=hook,
            power=power if isinstance(power, int) else 0,
            params=dict(params),
            source=upgrade_name or ability_name or ("opcode %d" % opcode)))
        built.resolved.append((opcode, upgrade_name or ability_name))

    # -- reporting ----------------------------------------------------------

    def coverage(self, limit: int = 0) -> dict:
        """How much of the roster builds cleanly.

        This is the content-side counterpart to the load report: that one counts
        opcodes, this one counts UNITS, which is what a player would notice.
        A pack can bind most of its opcodes and still have most of its units
        incomplete, because the unbound ones cluster on interesting abilities.
        """
        # Iterate canonical IDs, not display names. NH uses 11 names for more
        # than one record — «Паладин» is 22/55 at index 57 and 6/22 at index 265
        # — so a name-driven sweep both mis-attributes and under-counts.
        # /0 is the reserved empty record in every .var table, not a unit.
        ids = [cid for cid in self.ids()
               if (self.index.get(cid) or {}).get("Name") not in (None, "", "Пусто")]
        if limit:
            ids = ids[:limit]
        complete, partial = [], []
        missing = {}
        for cid in ids:
            built = self.build(cid)
            if built is None:
                continue
            if built.complete:
                complete.append(cid)
            else:
                partial.append(cid)
            for u in built.unresolved:
                key = (u.opcode, u.ability_name or u.upgrade_name)
                missing[key] = missing.get(key, 0) + 1
        return {
            "units": len(ids),
            "complete": len(complete),
            "partial": len(partial),
            "blockers": sorted(missing.items(), key=lambda kv: -kv[1]),
        }
