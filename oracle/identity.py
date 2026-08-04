"""Canonical content identity.

Content is identified by a pack-qualified, source-derived ID:

    genesis:unit/1
    new_horizons:unit/1
    genesis:upgrade/76
    genesis:ability/53

The display name is a LOCALIZATION field and is never an identity. It cannot be
one: Genesis and New Horizons share 69 unit names, and 27 of those carry
different stats — «Громила» is 14 attack in Genesis and 13 in NH, «Маг» is 4 and
2. A name-keyed lookup across packs therefore resolves to a plausible wrong
record instead of failing, which is the same class of defect as the
reference-table trap in tools/var/eador_var.py.

The numeric part is the SOURCE record ID, not a slug of the name, so it is
stable under translation, renaming, and re-extraction.

Namespaces mirror the source reference conventions documented in
docs/CONTENT_REFERENCE_MODEL.md, and the distinction between them is
load-bearing:

    unit      -> unit.var      record index
    upgrade   -> unit_upg.var  record index   (what unit.var Abilityes points at)
    ability   -> ability_num   `Number`       (what item/spell/medal Effects use)
    spell     -> spell.var     record index
    medal     -> medal.var     record index
    item      -> item.var      record index

`ability` is keyed by `Number` rather than by record index precisely because the
two are different namespaces over the same dense integer space.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# Table name -> ID kind. Tables absent here have no canonical identity yet.
KIND_FOR_TABLE = {
    "unit": "unit",
    "unit_upg": "upgrade",
    "ability_num": "ability",
    "spell": "spell",
    "medal": "medal",
    "item": "item",
}

# ability_num is addressed by its `Number` column; everything else by record
# index. See docs/CONTENT_REFERENCE_MODEL.md.
KEY_COLUMN_FOR_TABLE = {"ability_num": "Number"}

_ID_RE = re.compile(r"^(?P<pack>[a-z0-9_]+):(?P<kind>[a-z_]+)/(?P<num>\d+)$")


def make_id(pack: str, kind: str, number: int) -> str:
    """Canonical ID string. Callers should prefer ContentId objects."""
    return "%s:%s/%d" % (pack, kind, number)


@dataclass(frozen=True)
class ContentId:
    pack: str
    kind: str
    number: int

    def __str__(self) -> str:
        return make_id(self.pack, self.kind, self.number)

    @classmethod
    def parse(cls, text: str) -> "ContentId | None":
        m = _ID_RE.match(text or "")
        if m is None:
            return None
        return cls(m.group("pack"), m.group("kind"), int(m.group("num")))

    @classmethod
    def is_canonical(cls, text) -> bool:
        return isinstance(text, str) and _ID_RE.match(text) is not None


@dataclass
class Provenance:
    """Where a definition came from. Carried so a canonical ID can always be
    traced back to the original record without re-deriving it."""

    pack: str = ""
    source_kind: str = ""          # "var"
    source_file: str = ""          # "unit.var"
    source_record_index: int = -1  # record index within that file
    source_key: int = -1           # the addressed key (Number for abilities)
    source_opcode: int = -1        # Upg Type opcode, where one applies

    def as_dict(self) -> dict:
        d = {
            "pack": self.pack,
            "source_kind": self.source_kind,
            "source_file": self.source_file,
            "source_record_index": self.source_record_index,
        }
        if self.source_key >= 0:
            d["source_key"] = self.source_key
        if self.source_opcode >= 0:
            d["source_opcode"] = self.source_opcode
        return d


class AmbiguousName(LookupError):
    """A display name matched more than one record in the same pack.

    Cross-pack ambiguity cannot reach here — lookup is pack-scoped by
    construction, because a Roster wraps exactly one ContentPack.
    """


@dataclass
class Index:
    """Canonical-ID index over one pack's tables, with a transitional
    name index alongside it.

    Name lookup is deliberately pack-scoped and deliberately fails loudly on
    ambiguity. It exists so fixtures and callers can migrate incrementally, not
    as a supported addressing mode.
    """

    pack: str
    by_id: dict = field(default_factory=dict)          # str -> record
    _names: dict = field(default_factory=dict)         # (kind, name) -> [ids]

    def add_table(self, table_name: str, records: dict) -> None:
        kind = KIND_FOR_TABLE.get(table_name)
        if kind is None:
            return
        key_column = KEY_COLUMN_FOR_TABLE.get(table_name)
        for record_index, record in records.items():
            if not isinstance(record, dict):
                continue
            if key_column is not None:
                key = record.get(key_column)
                if not isinstance(key, int):
                    continue      # no addressable identity in this namespace
            else:
                key = record_index
            if not isinstance(key, int):
                continue
            cid = make_id(self.pack, kind, key)
            self.by_id[cid] = record
            name = record.get("Name")
            if isinstance(name, str) and name and name != "Пусто":
                self._names.setdefault((kind, name), []).append(cid)

    # -- lookup -------------------------------------------------------------

    def get(self, content_id: str):
        return self.by_id.get(content_id)

    def resolve(self, reference: str, kind: str = "unit"):
        """Canonical ID, or a transitional pack-scoped display name.

        Raises AmbiguousName when a name matches several records, rather than
        silently returning the first.
        """
        if ContentId.is_canonical(reference):
            return self.by_id.get(reference)
        ids = self._names.get((kind, reference), [])
        if not ids:
            return None
        if len(ids) > 1:
            raise AmbiguousName(
                "%r matches %d %s records in pack %r (%s); use a canonical ID"
                % (reference, len(ids), kind, self.pack, ", ".join(sorted(ids))))
        return self.by_id.get(ids[0])

    def id_for_name(self, name: str, kind: str = "unit") -> str | None:
        ids = self._names.get((kind, name), [])
        if len(ids) == 1:
            return ids[0]
        if len(ids) > 1:
            raise AmbiguousName(
                "%r matches %d %s records in pack %r" % (name, len(ids), kind, self.pack))
        return None

    def ids(self, kind: str = "unit") -> list:
        prefix = "%s:%s/" % (self.pack, kind)
        return sorted(i for i in self.by_id if i.startswith(prefix))
