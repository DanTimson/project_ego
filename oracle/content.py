"""
content.py — content packs, the ability registry, and the unbound report.

A ContentPack is data tables plus an opcode->handler bindings manifest. The
manifest exists because the opcode table is NOT stable between builds: opcode 30
is magic immunity in Genesis and armour-piercing strike in New Horizons. The
mapping is therefore content, and each pack carries its own.

Handlers are ENGINE code, named not numbered. The rules layer never branches on
which pack is loaded — it asks the registry for a handler name and calls it.

LOADING MUST FAIL LOUDLY. `report()` lists every opcode the pack references that
has no working handler, split by cause:

    unbound    the pack's bindings leave the handler empty
    missing    the pack names a handler the registry does not implement
    orphaned   the registry implements a handler no opcode binds to

That list is the implementation progress meter. It is only useful if nothing
quietly papers over a gap, so a pack with holes loads in a degraded state and
says so, rather than either crashing or pretending.
"""

from __future__ import annotations

import copy
import hashlib
import json
import os

import identity
from dataclasses import dataclass, field


def _canonical_json_value(value):
    """Normalize JSON values shared with Godot before hashing.

    Godot's JSON parser represents every number as a float, while Python keeps
    integral JSON numbers as ``int``.  Treat mathematically integral floats as
    integers so both loaders fingerprint the same serialized pack snapshot.
    """
    if isinstance(value, dict):
        return {str(key): _canonical_json_value(item)
                for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_canonical_json_value(item) for item in value]
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def canonical_fingerprint(value) -> str:
    """Return a deterministic identity for JSON-compatible content.

    The digest identifies a local snapshot only.  It does not establish legal
    transferability or rules compatibility.
    """
    payload = json.dumps(_canonical_json_value(value), ensure_ascii=False,
                         sort_keys=True, separators=(",", ":"), allow_nan=False)
    return "sha256:" + hashlib.sha256(payload.encode("utf-8")).hexdigest()


class ScenarioContentProvider:
    """Small in-memory provider for portable synthetic tests and callers.

    ``ContentDb`` implements the same two-method seam for locally loaded packs;
    this container is not a second pack parser or registry.  A caller-supplied
    fingerprint is an assertion, never a substitute for observing the current
    canonical snapshot.
    """

    def __init__(self, pack: str, definitions: dict, *, version: str = "",
                 build: str = "", fingerprint: str = ""):
        self.pack_id = str(pack)
        self.version = str(version)
        self.build = str(build)
        self._definitions = copy.deepcopy(definitions)
        self.asserted_fingerprint = str(fingerprint)

    def snapshot_payload(self) -> dict:
        return {
            "pack": self.pack_id,
            "version": self.version,
            "build": self.build,
            "definitions": self._definitions,
        }

    @property
    def fingerprint(self) -> str:
        return canonical_fingerprint(self.snapshot_payload())

    def content_provenance(self) -> dict:
        observed = self.fingerprint
        if (self.asserted_fingerprint
                and self.asserted_fingerprint != observed):
            raise ValueError(
                "content fingerprint assertion mismatch: expected %r, observed %r"
                % (self.asserted_fingerprint, observed))
        out = {"pack": self.pack_id, "fingerprint": observed}
        if self.version:
            out["version"] = self.version
        if self.build:
            out["build"] = self.build
        return out

    def resolve_definition(self, content_id: str):
        definition = self._definitions.get(content_id)
        return copy.deepcopy(definition) if definition is not None else None


class AbilityRegistry:
    """Handler name -> implementation. Populated by engine code at startup."""

    def __init__(self):
        self._handlers: dict = {}

    def register(self, name: str, fn) -> None:
        if name in self._handlers:
            raise ValueError(f"handler {name!r} registered twice")
        self._handlers[name] = fn

    def has(self, name: str) -> bool:
        return name in self._handlers

    def get(self, name: str):
        return self._handlers.get(name)

    def names(self) -> set:
        return set(self._handlers)

    def call(self, name: str, ctx: dict, value, params: dict):
        return self._handlers[name](ctx, value, params)


@dataclass
class Binding:
    opcode: int
    name: str
    hook: str
    handler: str
    params: dict = field(default_factory=dict)
    uses: int = 0

    @property
    def is_bound(self) -> bool:
        return bool(self.handler)


@dataclass
class LoadReport:
    pack_id: str
    total: int = 0
    bound: int = 0
    unbound: list = field(default_factory=list)     # (opcode, name, uses)
    missing: list = field(default_factory=list)     # (opcode, name, handler)
    orphaned: list = field(default_factory=list)    # handler names
    errors: list = field(default_factory=list)

    @property
    def usable(self) -> int:
        return self.bound - len(self.missing)

    @property
    def ok(self) -> bool:
        return not self.errors and not self.unbound and not self.missing

    def summary(self) -> str:
        return (
            "%s: %d opcodes, %d usable, %d unbound, %d missing handlers, %d orphaned"
            % (self.pack_id, self.total, self.usable, len(self.unbound),
               len(self.missing), len(self.orphaned))
        )

    def detail(self, limit: int = 20) -> str:
        out = [self.summary()]
        if self.errors:
            out.append("  errors:")
            out.extend("    %s" % e for e in self.errors)
        if self.missing:
            out.append("  handlers named by the pack but not implemented:")
            for opcode, name, handler in self.missing[:limit]:
                out.append("    %5d  %-28s -> %s" % (opcode, name, handler))
        if self.unbound:
            out.append("  unbound, most-used first:")
            for opcode, name, uses in sorted(self.unbound, key=lambda r: -r[2])[:limit]:
                out.append("    %5d  %-28s  %d options" % (opcode, name, uses))
            if len(self.unbound) > limit:
                out.append("    ... and %d more" % (len(self.unbound) - limit))
        if self.orphaned:
            out.append("  implemented but bound to nothing: %s"
                       % ", ".join(sorted(self.orphaned)[:limit]))
        return "\n".join(out)


class ContentPack:
    """Data tables plus bindings for one game build."""

    def __init__(self, pack_id: str):
        self.id = pack_id
        self.bindings: dict = {}      # opcode -> Binding
        self.tables: dict = {}        # table name -> {index: record}
        self.loaded_from: str = ""
        # Optional source metadata carried by a local pack manifest.  A missing
        # version/build is not guessed; the deterministic snapshot fingerprint
        # remains available as the reproducibility discriminator.
        self.version: str = ""
        self.build: str = ""
        self.declared_fingerprint: str = ""

    # -- loading ------------------------------------------------------------

    def load_bindings(self, path: str) -> list:
        """Returns a list of error strings; empty means clean."""
        errors = []
        if not os.path.exists(path):
            return ["bindings file not found: %s" % path]
        try:
            with open(path, encoding="utf-8") as fh:
                payload = json.load(fh)
        except (OSError, json.JSONDecodeError) as exc:
            return ["bindings unreadable: %s" % exc]

        if payload.get("pack") != self.id:
            errors.append("bindings declare pack %r, loaded as %r"
                          % (payload.get("pack"), self.id))
        self.version = str(payload.get("version", "") or "")
        self.build = str(payload.get("build", "") or "")
        self.declared_fingerprint = str(payload.get("fingerprint", "") or "")

        for key, entry in (payload.get("abilities") or {}).items():
            try:
                opcode = int(key)
            except ValueError:
                errors.append("non-numeric opcode key %r" % key)
                continue
            self.bindings[opcode] = Binding(
                opcode=opcode,
                name=entry.get("name", ""),
                hook=entry.get("hook", "UNCLASSIFIED"),
                handler=entry.get("handler", "") or "",
                params=entry.get("params") or {},
                uses=int(entry.get("uses", 0)),
            )
        self.loaded_from = path
        return errors

    def load_table(self, name: str, path: str) -> list:
        """Load one converted .var table (the JSON eador_var.py emits)."""
        if not os.path.exists(path):
            return ["table %s not found: %s" % (name, path)]
        try:
            with open(path, encoding="utf-8") as fh:
                payload = json.load(fh)
        except (OSError, json.JSONDecodeError) as exc:
            return ["table %s unreadable: %s" % (name, exc)]
        self.tables[name] = {int(r["index"]): r for r in payload.get("records", [])}
        return []

    # -- verification -------------------------------------------------------

    def report(self, registry: AbilityRegistry, errors: list = ()) -> LoadReport:
        rep = LoadReport(pack_id=self.id, errors=list(errors))
        used_handlers = set()
        for opcode, b in sorted(self.bindings.items()):
            rep.total += 1
            if not b.is_bound:
                rep.unbound.append((opcode, b.name, b.uses))
                continue
            rep.bound += 1
            used_handlers.add(b.handler)
            if not registry.has(b.handler):
                rep.missing.append((opcode, b.name, b.handler))
        rep.orphaned = sorted(registry.names() - used_handlers)
        return rep

    def snapshot_payload(self) -> dict:
        """Canonical, machine-independent inputs to the local snapshot hash."""
        bindings = {}
        for opcode, binding in self.bindings.items():
            bindings[str(opcode)] = {
                "name": binding.name,
                "hook": binding.hook,
                "handler": binding.handler,
                "params": binding.params,
                "uses": binding.uses,
            }
        return {
            "pack": self.id,
            "version": self.version,
            "build": self.build,
            "bindings": bindings,
            "tables": self.tables,
        }

    def provenance(self) -> dict:
        observed = canonical_fingerprint(self.snapshot_payload())
        if (self.declared_fingerprint
                and self.declared_fingerprint != observed):
            raise ValueError(
                "content pack fingerprint assertion mismatch: expected %r, observed %r"
                % (self.declared_fingerprint, observed))
        out = {"pack": self.id, "fingerprint": observed}
        if self.version:
            out["version"] = self.version
        if self.build:
            out["build"] = self.build
        return out

    # -- lookup -------------------------------------------------------------

    def binding(self, opcode: int) -> Binding | None:
        return self.bindings.get(opcode)

    def record(self, table: str, index: int):
        return self.tables.get(table, {}).get(index)


class ContentDb:
    """A constructed instance, never a singleton. The simulation takes one as an
    argument; the UI layer may hold the currently active one, and that is all an
    autoload is for."""

    def __init__(self, pack: ContentPack, registry: AbilityRegistry, report: LoadReport):
        self.pack = pack
        self.registry = registry
        self.report = report
        # Canonical, pack-qualified identity over the loaded tables. Display
        # names are localization only. See oracle/identity.py.
        self.index = identity.Index(pack=pack.id)
        for table_name, records in pack.tables.items():
            self.index.add_table(table_name, records)

    @classmethod
    def load(cls, pack_id: str, pack_dir: str, registry: AbilityRegistry,
             tables: dict | None = None) -> "ContentDb":
        pack = ContentPack(pack_id)
        errors = pack.load_bindings(os.path.join(pack_dir, "bindings.json"))
        for name, filename in (tables or {}).items():
            errors += pack.load_table(name, os.path.join(pack_dir, "data", filename))
        return cls(pack, registry, pack.report(registry, errors))

    def resolve(self, opcode: int):
        """Returns (handler_name, params) or (None, {}) when unusable."""
        b = self.pack.binding(opcode)
        if b is None or not b.is_bound or not self.registry.has(b.handler):
            return None, {}
        return b.handler, b.params

    # Scenario composition seam.  Keeping this on the constructed ContentDb
    # reuses the existing pack/roster loader instead of creating a parallel pack
    # model for scenarios.
    def content_provenance(self) -> dict:
        return self.pack.provenance()

    def resolve_definition(self, content_id: str):
        """Return one fresh, normalized scenario construction record.

        Local `.var` records are normalized by the existing Roster.  The
        temporary roster result is copied into plain data before Scenario owns
        or mutates it, and an incomplete definition is rejected rather than
        silently dropping unresolved abilities.
        """
        from roster import Roster

        built = Roster(self).build(content_id)
        if built is None:
            return None
        if not built.complete:
            reasons = "; ".join(str(item) for item in built.unresolved[:3])
            raise ValueError("canonical definition %r is incomplete: %s"
                             % (content_id, reasons))
        unit = built.unit
        record = {
            "name": unit.name,
            "attack": unit.attack,
            "counter_attack": unit.counter_attack,
            "ranged_attack": unit.ranged_attack,
            "shooting_range": unit.shooting_range,
            "defence": unit.defence,
            "ranged_defence": unit.ranged_defence,
            "resist": unit.resist,
            "life": unit.life,
            "life_base": unit.life_base,
            "stamina": unit.stamina,
            "stamina_base": unit.stamina_base,
            "morale": unit.morale,
            "morale_base": unit.morale_base,
            "speed": unit.speed,
            "ammo": unit.ammo,
            "attack_bonus": unit.attack_bonus,
            "defence_bonus": unit.defence_bonus,
            "conditional_bonus": unit.conditional_bonus,
            "flags": sorted(unit.flags),
            "subtypes": sorted(unit.subtypes),
            "modifiers": [{
                "ability": modifier.ability,
                "handler": modifier.handler,
                "hook": modifier.hook.name,
                "power": modifier.power,
                "params": copy.deepcopy(modifier.params),
                "source": modifier.source,
            } for modifier in unit.modifiers],
        }
        return copy.deepcopy(record)
