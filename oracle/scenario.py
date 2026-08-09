# oracle/scenario.py
"""
scenario.py — deterministic battles as data.

A scenario is a seed, a battlefield, two sides, and a command list. Running it
produces a LOG: an ordered list of plain strings. That log is the artifact —
committed, diffed, and compared between the Python oracle and the GDScript port.

WHY A LOG AND NOT A FINAL STATE. A final state can match while the route to it
differs: two implementations that disagree about pathfinding tie-breaks, or
about when stamina is charged, can still land the same unit on the same hex with
the same HP. The log catches the divergence at the step where it happens, which
is the difference between a five-minute fix and an afternoon of bisection.

THIS IS THE INTEGRATION POINT. Everything the project has built meets here:
battlefield pathfinding updates live capacity and command-entry coordinates;
the composed profile rule resolves primary-melee charge; stamina scales the
ordinary attack; the RNG rolls it; defence reduces it; then charge is added.
A scenario that reproduces exactly is evidence the whole chain agrees — far stronger than any
subsystem test.

Command set, deliberately small:

    move        <unit> to <col,row>       explicit movement
    attack      <unit> -> <target>        AUTO-PATHS into contact first
    shoot       <unit> -> <target>        range-checked, no movement
    rest        <unit>
    extra_turn  <unit>                    what a spell would grant
    end_phase                             hand control to the other side
"""

from __future__ import annotations

import copy
import json
import re

import battlefield as bfmod
import auras
import charge
import combat
import content
import handlers
import identity
import counterattack as ca
import statuses as st
import actions as actionsmod
import turn
from battlefield import Battlefield
from modifier import Hook, Modifier, Pipeline
from combat import AttackKind, Combatant, Rng


PROFILE_GENESIS = "genesis"
PROFILE_NEW_HORIZONS = "new_horizons"
PROFILE_NATIVE = "native"
_PROFILE_NAMES = {PROFILE_GENESIS, PROFILE_NEW_HORIZONS, PROFILE_NATIVE}
_PROFILE_REQUIRED = (
    'scenario configuration requires explicit "profile"; '
    'the omitted-profile native fallback was removed'
)
_RNG_REMOVED = (
    'scenario configuration key "rng" was removed; use explicit "profile" '
    '("genesis" for LegacyRng or "native" for named streams)'
)
_NEW_HORIZONS_INCOMPLETE = (
    'scenario profile "new_horizons" is incomplete: '
    'minimum rules assignment is not defined'
)
_ORDERING_TRACE_SOURCES = {
    "conditional attack contribution",
    "attack randomisation",
    "ranged early provider total",
    "defence provider total",
    "zero-stamina defence halving",
    "final defence clamp",
    "defence subtraction",
    "command-entry charge consumption",
    "live-capacity stamina discriminator",
    "attack stamina mutation",
    "modifier 0x12 stamina mutation suppression",
    "ranged activation capacity clear",
}

# Canonical units deliberately have a closed envelope.  Sibling fields are not
# silently interpreted as overrides, and override keys must map to construction
# fields rather than battle identity, placement or provenance.
_CANONICAL_UNIT_KEYS = {"id", "def", "at", "overrides"}
_SPECIAL_UNIT_FIELDS = {"name", "flags", "subtypes", "modifiers", "auras", "statuses"}
_SETTABLE_UNIT_FIELDS = (
    set(Combatant.__dataclass_fields__) | _SPECIAL_UNIT_FIELDS
) - {"instance_id", "content_id", "statuses"}
_RESOLVED_CONTENT_ID = "__scenario_resolved_content_id"
_SERIALIZED_IDENTITY_FIELDS = {"content_id", "instance_id", _RESOLVED_CONTENT_ID}
_FORBIDDEN_OVERRIDE_FIELDS = {
    "id", "def", "at", "overrides", "instance_id", "content_id",
    _RESOLVED_CONTENT_ID,
    "content", "pack", "version", "build", "fingerprint", "provenance",
}
_FINGERPRINT_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


class Scenario:
    def __init__(self, spec: dict, rng=None, content_provider=None):
        self.spec = spec
        self.name = spec.get("name", "unnamed")
        self.seed = int(spec.get("seed", 0))
        self.profile = self.normalize_profile(spec)
        # Resolve and verify all canonical dependencies before constructing a
        # battlefield or a Combatant. Inline scenarios never touch the provider.
        self._side_specs = self.prepare_content(spec, content_provider)
        self.log: list[str] = []
        # THE randomness boundary. Rules never choose a generator and never
        # branch on profile — they receive whatever is injected here and call
        # roll(x, stream). Genesis compatibility needs ONE shared LegacyRng
        # because the original advances a single CRT state across every
        # consumer; native keeps per-subsystem streams so that adding a roll in
        # one place does not invalidate every stored replay. Those two
        # requirements are irreconcilable, which is why this composition-root
        # seam exists and why it is the only general seam in the engine.
        self.rng = (rng if rng is not None
                    else self._make_rng(self.profile, self.seed, self.name))
        # The second profile seam. Battle commands ask one injected callable for
        # a resolved primary-melee charge; ordinary damage arithmetic never
        # branches on profile. Native injects no R3 consumer so its established
        # zero-charge/overkill behaviour remains untouched; New Horizons has
        # already been rejected above.
        self._attack_command_charge = (
            self._genesis_attack_command_charge
            if self.profile == PROFILE_GENESIS else self._no_attack_command_charge
        )
        # Actions available in this battle. A scenario may declare its own so
        # the file is self-contained and the GDScript port can build the same
        # catalogue from the same source — the port loads its catalogue from
        # data rather than hardcoding it, and a committed scenario must not
        # depend on a fixture only one side reads.
        self.catalogue = dict(actionsmod.CATALOGUE)
        for entry in spec.get("actions", []) or []:
            action = actionsmod.action_from_dict(entry)
            self.catalogue[action.id] = action
        self.field = self._build_field(spec.get("battlefield", {}))
        self.units: dict[str, Combatant] = {}
        self.sides = self._build_sides(self._side_specs)
        self.state = turn.BattleState(sides=self.sides)
        ## unit -> its projected auras. Passive, so it is built once; which units
        ## an aura REACHES is recomputed on every query.
        self.auras_by_source = self._build_auras(self._side_specs)

    # -- construction -------------------------------------------------------

    @staticmethod
    def prepare_content(spec: dict, provider=None) -> list:
        """Validate provenance and return side specs with definitions merged."""
        sides = spec.get("sides", [])
        references = []
        for side in sides:
            for unit in side.get("units", []):
                if "def" in unit:
                    references.append(unit)
                    continue
                spoofed = sorted(set(unit) & _SERIALIZED_IDENTITY_FIELDS)
                if spoofed:
                    raise ValueError(
                        "inline unit %r cannot contain serialized identity fields: %s"
                        % (unit.get("id", unit.get("name", "?")),
                           ", ".join(spoofed)))
        if not references:
            return sides

        declaration = spec.get("content")
        if not isinstance(declaration, dict):
            raise ValueError('scenario units using "def" require a scenario-level "content" object')
        allowed_provenance = {"pack", "version", "build", "fingerprint"}
        unknown_provenance = sorted(set(declaration) - allowed_provenance)
        if unknown_provenance:
            raise ValueError("unknown scenario content provenance fields: %s"
                             % ", ".join(unknown_provenance))
        pack = declaration.get("pack")
        if not isinstance(pack, str) or not pack:
            raise ValueError('scenario content provenance requires non-empty "pack"')
        discriminators = [key for key in ("version", "build", "fingerprint")
                          if declaration.get(key) not in (None, "")]
        if not discriminators:
            raise ValueError("scenario content provenance requires version, build, and/or fingerprint")
        for key in discriminators:
            if not isinstance(declaration[key], str):
                raise ValueError('scenario content provenance field "%s" must be a string' % key)
        if "fingerprint" in discriminators and not _FINGERPRINT_RE.match(declaration["fingerprint"]):
            raise ValueError('scenario content fingerprint must use "sha256:" plus 64 lowercase hex digits')
        if provider is None:
            raise ValueError("scenario canonical definitions require an injected content provider")
        provenance_fn = getattr(provider, "content_provenance", None)
        resolve_fn = getattr(provider, "resolve_definition", None)
        if not callable(provenance_fn) or not callable(resolve_fn):
            raise ValueError("content provider must report provenance and resolve canonical definitions")
        observed = provenance_fn()
        if not isinstance(observed, dict):
            raise ValueError("content provider returned malformed provenance")
        if observed.get("error"):
            raise ValueError("content provider provenance error: %s"
                             % observed["error"])
        for key in ("pack", *discriminators):
            expected = str(declaration.get(key, ""))
            actual = str(observed.get(key, ""))
            if actual != expected:
                raise ValueError("content provenance mismatch for %s: expected %r, observed %r"
                                 % (key, expected, actual or "<missing>"))

        prepared = copy.deepcopy(sides)
        seen_instance_ids = set()
        for side in prepared:
            for index, unit in enumerate(side.get("units", [])):
                if "def" not in unit:
                    inline_id = str(unit.get("id") or unit.get("name", ""))
                    if inline_id in seen_instance_ids:
                        raise ValueError("duplicate unit instance id %r" % inline_id)
                    seen_instance_ids.add(inline_id)
                    continue
                extra = sorted(set(unit) - _CANONICAL_UNIT_KEYS)
                if extra:
                    raise ValueError("canonical unit %r mixes undeclared inline fields: %s; use overrides"
                                     % (unit.get("id", "?"), ", ".join(extra)))
                instance_id = unit.get("id")
                if not isinstance(instance_id, str) or not instance_id:
                    raise ValueError('canonical unit requires a non-empty battle-instance "id"')
                if instance_id in seen_instance_ids:
                    raise ValueError("duplicate unit instance id %r" % instance_id)
                seen_instance_ids.add(instance_id)
                content_id = unit.get("def")
                cid = identity.ContentId.parse(content_id) if isinstance(content_id, str) else None
                if cid is None or cid.kind != "unit":
                    raise ValueError("canonical unit definition id is malformed: %r" % content_id)
                if cid.pack != pack:
                    raise ValueError("canonical definition namespace mismatch: %r uses pack %r, scenario declares %r"
                                     % (content_id, cid.pack, pack))
                at = unit.get("at")
                if not isinstance(at, list) or len(at) != 2:
                    raise ValueError('canonical unit %r requires battle placement \"at\"' % instance_id)
                overrides = unit.get("overrides", {})
                if not isinstance(overrides, dict):
                    raise ValueError("canonical unit %r overrides must be an object" % instance_id)
                forbidden = sorted(set(overrides) & _FORBIDDEN_OVERRIDE_FIELDS)
                if forbidden:
                    raise ValueError("canonical unit %r overrides forbidden fields: %s"
                                     % (instance_id, ", ".join(forbidden)))
                unknown = sorted(set(overrides) - _SETTABLE_UNIT_FIELDS)
                if unknown:
                    raise ValueError("canonical unit %r overrides unknown or non-settable fields: %s"
                                     % (instance_id, ", ".join(unknown)))
                definition = resolve_fn(content_id)
                if definition is None:
                    raise ValueError("canonical definition %r was not found in content pack %r"
                                     % (content_id, pack))
                if not isinstance(definition, dict):
                    raise ValueError("canonical definition %r did not resolve to an object" % content_id)
                definition = copy.deepcopy(definition)
                reserved = sorted(set(definition) & _FORBIDDEN_OVERRIDE_FIELDS)
                if reserved:
                    raise ValueError("canonical definition %r contains scenario-owned fields: %s"
                                     % (content_id, ", ".join(reserved)))
                unknown_definition = sorted(set(definition) - _SETTABLE_UNIT_FIELDS)
                if unknown_definition:
                    raise ValueError("canonical definition %r contains unknown construction fields: %s"
                                     % (content_id, ", ".join(unknown_definition)))
                merged = definition
                for key, value in overrides.items():
                    merged[key] = copy.deepcopy(value)
                if not isinstance(merged.get("name"), str) or not merged["name"]:
                    raise ValueError("canonical definition %r has no display name" % content_id)
                merged["id"] = instance_id
                merged["at"] = copy.deepcopy(at)
                merged[_RESOLVED_CONTENT_ID] = content_id
                side["units"][index] = merged
        return prepared

    @staticmethod
    def _profile_configuration(spec: dict) -> tuple[str, str]:
        """Return the normalized profile and any configuration error.

        Serialized scenario configuration is strict: profile identity is
        explicit, and the removed ``rng`` selector is never interpreted as a
        rules axis. Direct ``Scenario(..., rng=obj)`` dependency injection is a
        constructor concern and remains independent of this parser.
        """
        if "rng" in spec:
            return "", _RNG_REMOVED
        if "profile" not in spec:
            return "", _PROFILE_REQUIRED

        profile = str(spec["profile"]).strip().lower()
        if profile not in _PROFILE_NAMES:
            return "", 'unknown scenario profile "%s"' % profile

        if profile == PROFILE_NEW_HORIZONS:
            return profile, _NEW_HORIZONS_INCOMPLETE
        return profile, ""

    @classmethod
    def normalize_profile(cls, spec: dict) -> str:
        profile, error = cls._profile_configuration(spec)
        if error:
            raise ValueError(error)
        return profile

    @staticmethod
    def _make_rng(profile: str, seed: int, name: str):
        """Composition root: derive the generator from normalized identity."""
        if profile == PROFILE_GENESIS:
            from legacy_rng import LegacyRng
            r = LegacyRng(seed)
            r.epoch = "scenario/%s" % name
            return r
        if profile == PROFILE_NATIVE:
            return Rng(seed)
        raise AssertionError("profile was not validated: %s" % profile)

    def _build_field(self, spec: dict) -> Battlefield:
        field = Battlefield(int(spec.get("width", 7)), int(spec.get("height", 7)))
        for t in spec.get("tiles", []):
            h = bfmod.offset_to_axial(int(t["col"]), int(t["row"]))
            tile = field.tile(h)
            if tile is None:
                continue
            if "bf_object" in t:
                tile.bf_object = int(t["bf_object"])
            if "move_cost" in t:
                tile.move_cost = int(t["move_cost"])
            if "stam_cost" in t:
                tile.stam_cost = int(t["stam_cost"])
        return field

    def _build_sides(self, specs: list) -> list:
        sides = []
        for s in specs:
            side = turn.Side(
                id=int(s["id"]), name=s.get("name", str(s["id"])),
                leader_initiative=int(s.get("leader_initiative", 0)),
                is_attacker=bool(s.get("is_attacker", False)),
            )
            for u in s.get("units", []):
                unit = Combatant(name=u["name"])
                # Battle-instance identity, distinct from the display name. An
                # army may field several units of one type; they share a name and
                # must still be addressable individually. Defaults to the name,
                # so existing scenarios are unaffected.
                unit.instance_id = str(u.get("id") or u["name"])
                for key, value in u.items():
                    if key in ("name", "id", "at", "flags", "subtypes",
                               "modifiers", "auras", "statuses", "content_id",
                               "instance_id", _RESOLVED_CONTENT_ID):
                        continue
                    setattr(unit, key, value)
                unit.content_id = str(u.get(_RESOLVED_CONTENT_ID, ""))
                unit.flags = set(u.get("flags", []))
                for m in u.get("modifiers", []) or []:
                    unit.modifiers.append(Modifier(
                        ability=int(m.get("ability", 0)), handler=m["handler"],
                        hook=getattr(Hook, m.get("hook", "STAT_PASSIVE")),
                        power=int(m.get("power", 0)),
                        params=m.get("params", {}),
                        source=m.get("source", m["handler"])))
                for status_spec in u.get("statuses", []) or []:
                    st.apply(unit, self._build_status(status_spec))
                unit.subtypes = set(u.get("subtypes", []))
                # Base values default to the CURRENT value, because the .var
                # tables carry only one figure per stat. A unit declared with
                # `stamina: 4` therefore has a CAP of 4 and cannot be restored
                # above it — describing a tired unit needs both `stamina` and
                # `stamina_base`. Easy to trip over, so stated here.
                unit.life_base = u.get("life_base", unit.life)
                unit.stamina_base = u.get("stamina_base", unit.stamina)
                unit.morale_base = u.get("morale_base", unit.morale)
                col, row = u["at"]
                if not self.field.place(unit, bfmod.offset_to_axial(col, row)):
                    raise ValueError("cannot place %s at %s" % (unit.name, u["at"]))
                if unit.instance_id in self.units:
                    raise ValueError(
                        "duplicate unit instance id %r — give each unit an "
                        "explicit \"id\" when several share a display name"
                        % unit.instance_id)
                self.units[unit.instance_id] = unit
                side.units.append(unit)
            sides.append(side)
        return sides

    @staticmethod
    def _build_status(specification: dict) -> st.StatusEffect:
        status = st.StatusEffect(
            id=str(specification["id"]),
            name=str(specification.get("name", "")),
            source=str(specification.get("source", "")),
            duration=int(specification.get("duration", st.PERMANENT)),
            power=int(specification.get("power", 0)),
            tick=copy.deepcopy(specification.get("tick", {})),
            decay_per=(tuple(specification["decay_per"])
                       if specification.get("decay_per") else None),
            stacking=st.Stacking[specification.get("stacking", "REFRESH")],
            prevents_action=bool(specification.get("prevents_action", False)),
            hostile=bool(specification.get("hostile", False)),
            tags=tuple(specification.get("tags", [])),
        )
        for modifier_spec in specification.get("modifiers", []):
            status.modifiers.append(Modifier(
                ability=int(modifier_spec.get("ability", 0)),
                handler=modifier_spec["handler"],
                hook=getattr(Hook, modifier_spec.get("hook", "STAT_PASSIVE")),
                power=int(modifier_spec.get("power", 0)),
                params=copy.deepcopy(modifier_spec.get("params", {})),
                source=modifier_spec.get("source", status.name),
            ))
        return status

    def _build_auras(self, specs: list) -> dict:
        out = {}
        for side_spec in specs:
            for u in side_spec.get("units", []):
                declared = u.get("auras") or []
                if not declared:
                    continue
                unit = self.units[str(u.get("id") or u["name"])]
                built = []
                for a in declared:
                    aura = auras.Aura(
                        id=a["id"], name=a.get("name", a["id"]),
                        scope=auras.Scope[a.get("scope", "ADJACENT")],
                        affects=auras.Side[a.get("affects", "ALLY")],
                        stacking=auras.Stacking[a.get("stacking", "MAXIMUM")],
                        power=int(a.get("power", 0)),
                        tick=a.get("tick", {}),
                        only_subtypes=tuple(a.get("only_subtypes", [])),
                        except_subtypes=tuple(a.get("except_subtypes", [])),
                        source=unit)
                    for m in a.get("modifiers", []):
                        aura.modifiers.append(Modifier(
                            ability=int(m.get("ability", 0)),
                            handler=m["handler"],
                            hook=getattr(Hook, m.get("hook", "STAT_PASSIVE")),
                            power=int(m.get("power", a.get("power", 0))),
                            params=m.get("params", {}),
                            source=aura.name))
                    built.append(aura)
                out[unit] = built
        return out

    def side_of(self, unit):
        return self._side_of(unit)

    def environment(self, unit) -> list:
        """Modifiers from the unit's surroundings — the auras reaching it now."""
        return auras.modifiers_for(unit, self.auras_by_source, self.field,
                                   self.side_of)

    # -- helpers ------------------------------------------------------------

    def _at(self, unit: Combatant) -> str:
        h = self.field.find(unit)
        if h is None:
            return "-"
        col, row = bfmod.axial_to_offset(h)
        return "%d,%d" % (col, row)

    def emit(self, line: str) -> None:
        self.log.append(line)

    def _emit_ordering_traces(self, traces: list) -> None:
        for trace in traces:
            if trace is None:
                continue
            for source, before, after, note in trace.steps:
                if source not in _ORDERING_TRACE_SOURCES:
                    continue
                tail = " # " + note if note else ""
                self.emit("  [trace] %s | %s: %s -> %s%s" % (
                    trace.label, source, combat._fmt(before), combat._fmt(after),
                    tail))

    def _side_of(self, unit: Combatant):
        for s in self.sides:
            if unit in s.units:
                return s
        return None

    # -- profile-composed primary-melee charge --------------------------------

    @staticmethod
    def _no_attack_command_charge(unit: Combatant, attacker_xy: tuple[int, int],
                                  target_xy: tuple[int, int],
                                  movement_requested: bool) -> None:
        return None

    @staticmethod
    def _genesis_attack_command_charge(unit: Combatant,
                                      attacker_xy: tuple[int, int],
                                      target_xy: tuple[int, int],
                                      movement_requested: bool) -> dict:
        # Applicability and coordinates are resolved together at command entry.
        applicable = combat.has_effective_modifier(unit, 0x25)
        value = (charge.command_entry_charge(
            attacker_xy, target_xy, movement_requested) if applicable else 0)
        return {"applicable": applicable, "value": value}

    # -- commands -----------------------------------------------------------

    def cmd_move(self, unit: Combatant, col: int, row: int) -> None:
        start = self.field.find(unit)
        goal = bfmod.offset_to_axial(col, row)
        path = (None if unit.action_spent else
                self.field.path(start, goal, max_cost=unit.movement_remaining))
        if not path:
            self.emit("%s cannot reach %d,%d" % (unit.label(), col, row))
            return
        cost = sum(self.field.tile(h).move_cost for h in path)
        if cost > unit.movement_remaining:
            self.emit("%s lacks movement for %d,%d" % (unit.label(), col, row))
            return
        stam = sum(self.field.tile(h).stam_cost for h in path)
        self.field.remove(start)
        self.field.place(unit, goal)
        move_trace = turn.spend_move(
            unit, cost, stamina_cost=stam,
            modifier_0x12_effective=combat.has_effective_modifier(unit, 0x12))
        self._emit_ordering_traces([move_trace])
        self.emit("%s moves to %s (%d steps, %d total this round)"
                  % (unit.label(), self._at(unit), len(path), unit.steps_this_round))

    def _approach(self, unit: Combatant, target: Combatant) -> bool:
        """Attack commands carry an implicit move: issuing an attack against a
        reachable target auto-paths the unit into contact, drawing from the same
        action-point pool."""
        here = self.field.find(unit)
        there = self.field.find(target)
        if here.distance(there) == 1:
            return True
        best = None
        for h in self.field.neighbours(there):
            if not self.field.tile(h).free:
                continue
            p = self.field.path(here, h, max_cost=unit.movement_remaining)
            if p is None:
                continue
            cost = sum(self.field.tile(x).move_cost for x in p)
            if cost > unit.movement_remaining:
                continue
            if best is None or cost < best[0]:
                best = (cost, h, p)
        if best is None:
            return False
        cost, dest, path = best
        stam = sum(self.field.tile(x).stam_cost for x in path)
        self.field.remove(here)
        self.field.place(unit, dest)
        move_trace = turn.spend_move(
            unit, cost, stamina_cost=stam,
            modifier_0x12_effective=combat.has_effective_modifier(unit, 0x12))
        self._emit_ordering_traces([move_trace])
        self.emit("%s closes to %s (%d steps)" % (unit.label(), self._at(unit), len(path)))
        return True

    def _fell(self, unit: Combatant) -> None:
        h = self.field.find(unit)
        if h is not None:
            self.field.remove(h)
        self.emit("%s falls" % unit.label())

    def _strike(self, unit: Combatant, target: Combatant, kind: AttackKind,
                action=None, primary_melee_charge: int | None = None) -> None:
        """One exchange: the attack and any retaliation, in the right order.

        Melee is answered; a shot is not. `Первый удар` moves the retaliation
        ahead of the blow that caused it, so a defender can kill an attacker
        before the attack lands.
        """
        ex = ca.resolve(unit, target, self.rng, kind, action,
                        primary_melee_charge=primary_melee_charge)
        modifier_0x12 = combat.has_effective_modifier(unit, 0x12)
        if kind is AttackKind.RANGED:
            cost_trace = turn.spend_ranged_attack(
                unit, modifier_0x12_effective=modifier_0x12)
        else:
            # R8 is not generalized here: non-ranged callers retain their
            # established cost boundary; only ranged clears live capacity.
            cost_trace = turn.spend_attack(
                unit, modifier_0x12_effective=modifier_0x12)
        self._emit_ordering_traces(ex.traces)
        self._emit_ordering_traces([cost_trace])

        for what, damage in ex.order:
            if what == "attack":
                self.emit("%s hits %s for %d (%s at %d/%d, stamina %d)"
                          % (unit.label(), target.label(), damage, target.label(),
                             max(0, target.life), target.life_base, unit.stamina))
            else:
                self.emit("%s counters%s for %d (%s at %d/%d)"
                          % (target.label(),
                             " first" if ex.counter_first else "",
                             damage, unit.label(),
                             max(0, unit.life), unit.life_base))
        if ex.defender_died:
            self._fell(target)
        if ex.attacker_died:
            self._fell(unit)
        if not ex.countered and ex.reason not in (ca.NoCounter.RANGED,
                                                  ca.NoCounter.DEAD):
            self.emit("  (%s does not counter: %s)"
                      % (target.label(), ex.reason.value))

    def cmd_attack(self, unit: Combatant, target: Combatant) -> None:
        if not target.alive:
            self.emit("%s has no target: %s is down" % (unit.label(), target.label()))
            return
        if unit.action_spent:
            self.emit("%s has already acted" % unit.label())
            return
        # Resolve both R3 applicability and distance before automatic approach
        # mutates battlefield occupancy or the environment-derived modifier set.
        attacker_entry_h = self.field.find(unit)
        target_entry_h = self.field.find(target)
        attacker_entry = bfmod.axial_to_offset(attacker_entry_h)
        target_entry = bfmod.axial_to_offset(target_entry_h)
        movement_requested = attacker_entry_h.distance(target_entry_h) != 1
        charge_decision = self._attack_command_charge(
            unit, attacker_entry, target_entry, movement_requested)
        primary_melee_charge = None
        if charge_decision is not None:
            applicable = bool(charge_decision["applicable"])
            charge_value = int(charge_decision["value"])
            self.emit(
                "  [trace] command-entry charge | modifier 0x25 applicable %s; "
                "movement requested %s; attacker %d,%d; target %d,%d; value %d"
                % (str(applicable).lower(), str(movement_requested).lower(),
                   attacker_entry[0], attacker_entry[1],
                   target_entry[0], target_entry[1], charge_value))
            if applicable:
                primary_melee_charge = charge_value
        if not self._approach(unit, target):
            self.emit("%s cannot reach %s" % (unit.label(), target.label()))
            return
        self._strike(unit, target, AttackKind.MELEE,
                     primary_melee_charge=primary_melee_charge)

    def cmd_shoot(self, unit: Combatant, target: Combatant) -> None:
        if not target.alive:
            self.emit("%s has no target: %s is down" % (unit.label(), target.label()))
            return
        if unit.action_spent:
            self.emit("%s has already acted" % unit.label())
            return
        if unit.ammo <= 0:
            self.emit("%s is out of ammunition" % unit.label())
            return
        dist = self.field.find(unit).distance(self.field.find(target))
        if dist > unit.shooting_range:
            self.emit("%s is out of range of %s (%d > %d)"
                      % (target.label(), unit.label(), dist, unit.shooting_range))
            return
        unit.ammo -= 1
        self._strike(unit, target, AttackKind.RANGED)

    def cmd_rest(self, unit: Combatant) -> None:
        if unit.action_spent:
            self.emit("%s has already acted" % unit.label())
            return
        turn.rest(unit)
        self.emit("%s rests (stamina %d)" % (unit.label(), unit.stamina))

    def cmd_extra_turn(self, unit: Combatant, spec: dict) -> None:
        granted, _ = turn.grant_extra_turn(
            unit, source=spec.get("source", ""),
            once_per_round=bool(spec.get("once_per_round", False)),
            fire_round_start=bool(spec.get("fire_round_start", False)),
        )
        self.emit("%s %s an extra turn (movement %d, steps %d)"
                  % (unit.label(), "receives" if granted else "is refused",
                     unit.movement_remaining, unit.steps_this_round))

    def _round_upkeep(self) -> None:
        """Existing aura upkeep; automatic status lifecycle is unresolved."""
        for side in self.sides:
            for unit in list(side.units):
                if not unit.alive:
                    continue
                totals, _ = auras.tick_for(unit, self.auras_by_source,
                                           self.field, self.side_of)
                if totals:
                    before = unit.life
                    auras.apply_tick(unit, totals)
                    parts = ", ".join("%s %+d" % (k, v)
                                      for k, v in sorted(totals.items()))
                    self.emit("  %s: auras (%s)" % (unit.label(), parts))
                    if not unit.alive:
                        self._fell(unit)
                        continue

    def _auto_end_phase(self) -> None:
        """R7: the side toggles on exhaustion as well as on an explicit pass.

        Checked after every unit command, which is where the original scans the
        roster and finds nothing selectable.
        """
        while (not turn.battle_over(self.state)
               and turn.phase_done(self.state, self.state.active_side)):
            before = self.state.round_number
            new_round = turn.end_phase(self.state)
            if new_round:
                self.emit("-- round %d, side %d first (both sides exhausted) --"
                          % (self.state.round_number, self.state.active_side))
                self._round_upkeep()
            else:
                self.emit("-- side %d takes over (no units left to act) --"
                          % self.state.active_side)
            if self.state.round_number == before and not new_round:
                # handed over to the other side; if it can act, stop here
                if not turn.phase_done(self.state, self.state.active_side):
                    break

    def cmd_action(self, unit: Combatant, action_id: str,
                   target: Combatant | None = None) -> None:
        """Invoke a catalogued action.

        Before this, `oracle/actions.py` defined fourteen actions with costs,
        availability and refusal reasons — and the battle layer had no command
        that could invoke any of them. The whole catalogue was reachable only
        from its own unit tests: tested, and inert.

        What executes here is the part the Action model actually declares:
        `grants`, applied as timed statuses through the normal status machinery.
        Everything else is REFUSED EXPLICITLY rather than silently doing
        nothing, because an action that appears to succeed and changes nothing is
        worse than one that reports it cannot run yet:

          - `is_attack` actions need the attack pipeline plus `damage_scale`,
            whose insertion point is an open question (§1.1);
          - target-consuming effects (healing, ammo transfer) need magnitudes
            from `unit_upg.Quantity`, which are not yet carried into Action
            instances — every catalogue magnitude is currently 0.
        """
        action = self.catalogue.get(action_id)
        if action is None:
            self.emit("unknown action %r" % action_id)
            return

        modifier_0x12 = combat.has_effective_modifier(unit, 0x12)
        refusal = action.availability(unit, modifier_0x12)
        if refusal is not actionsmod.Refusal.OK:
            self.emit("%s cannot use %s: %s"
                      % (unit.label(), action.name, refusal.value))
            return

        if action.is_attack:
            self.emit("%s: %s is an attack-replacing action and is not "
                      "executable yet" % (unit.label(), action.name))
            return
        if not action.grants:
            self.emit("%s: %s has no executable effect yet (magnitudes are not "
                      "loaded from unit_upg)" % (unit.label(), action.name))
            return

        action_cost_trace = action.pay(unit, modifier_0x12)
        self._emit_ordering_traces([action_cost_trace])
        applied = []
        for ability, magnitude, duration in action.grants:
            effect = st.StatusEffect(
                id="%s:%s" % (action.id, ability),
                name=ability, source=action.name,
                duration=int(duration) if duration is not None else st.PERMANENT,
                power=int(magnitude or 0),
            )
            st.apply(unit, effect)
            applied.append(ability)
        self.emit("%s uses %s (%s; stamina %d)"
                  % (unit.label(), action.name, ", ".join(applied), unit.stamina))

    def cmd_end_phase(self) -> None:
        new_round = turn.end_phase(self.state)
        if new_round:
            self.emit("-- round %d, side %d first --"
                      % (self.state.round_number, self.state.active_side))
            self._round_upkeep()
        else:
            self.emit("-- side %d --" % self.state.active_side)

    # -- run ----------------------------------------------------------------

    def run(self) -> dict:
        """Install the pipeline AND the environment, then run.

        Both are needed and forgetting either is silent. Without a pipeline,
        combat._run_hook returns immediately and NO modifier applies — innate
        abilities, statuses and auras alike. Without an environment, auras alone
        vanish. The first version of this method bound only the environment,
        which meant a scenario ran with every modifier inert while looking
        entirely healthy.
        """
        registry = content.AbilityRegistry()
        handlers.register_all(registry)
        combat.bind_pipeline(Pipeline(registry))
        combat.bind_environment(self.environment)
        try:
            return self._run()
        finally:
            combat.bind_environment(None)
            combat.bind_pipeline(None)

    def _run(self) -> dict:
        turn.begin_battle(self.state)
        self.emit("== %s (seed %d) ==" % (self.name, self.seed))
        self.emit("-- round %d, side %d first --"
                  % (self.state.round_number, self.state.active_side))
        for unit_id in sorted(self.units):
            unit = self.units[unit_id]
            if unit.statuses:
                descriptions = ", ".join(status.describe()
                                         for status in unit.statuses)
                self.emit("  %s: statuses [%s]" % (unit.label(), descriptions))

        for c in self.spec.get("commands", []):
            op = c["op"]
            if op == "end_phase":
                self.cmd_end_phase()
                continue
            unit = self.units.get(c.get("unit", ""))
            if unit is None:
                self.emit("unknown unit %r" % c.get("unit"))
                continue
            if not unit.alive:
                self.emit("%s is down and cannot act" % unit.label())
                continue
            side = self._side_of(unit)
            if side is not None and side.id != self.state.active_side:
                self.emit("%s is not in the active side's phase" % unit.label())
                continue
            if op == "move":
                self.cmd_move(unit, int(c["to"][0]), int(c["to"][1]))
            elif op == "attack":
                self.cmd_attack(unit, self.units[c["target"]])
            elif op == "shoot":
                self.cmd_shoot(unit, self.units[c["target"]])
            elif op == "rest":
                self.cmd_rest(unit)
            elif op == "action":
                self.cmd_action(unit, str(c.get("action", "")),
                                self.units.get(c["target"]) if c.get("target") else None)
            elif op == "extra_turn":
                self.cmd_extra_turn(unit, c)
            else:
                self.emit("unknown command %r" % op)
            if turn.battle_over(self.state):
                self.emit("== battle over ==")
                break
            # R7: the side may also toggle because nothing is left to act.
            self._auto_end_phase()

        return {"name": self.name, "seed": self.seed,
                "log": self.log, "final": self.final_state()}

    def final_state(self) -> dict:
        out = {}
        for name, u in sorted(self.units.items()):
            unit_state = {
                "alive": u.alive, "life": max(0, u.life), "stamina": u.stamina,
                "at": self._at(u), "steps_this_round": u.steps_this_round,
                "action_spent": u.action_spent, "movement_remaining": u.movement_remaining,
            }
            if u.statuses:
                unit_state["statuses"] = [status.to_dict() for status in u.statuses]
            out[name] = unit_state
        return out


def run_file(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return Scenario(json.load(fh)).run()
