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

import json
import os

import identity
from dataclasses import dataclass, field


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
