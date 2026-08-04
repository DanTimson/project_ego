"""
eador_var.py — unified parser + schema inference for Eador: Genesis / New Horizons .var files.

Grammar (recovered from all 62 files in the NH data set):

    file        := header? record*
    header      := "Quantity:" INT          # declared record count, EXCLUDES record /0
    record      := "/" INT LABEL? field*
    field       := KEY ":" value TERM?
    value       := scalar | tuple | list
    list        := "(" item ( ";" item )* ")"
    item        := scalar ( "," scalar )*
    TERM        := ";"                      # ends a field GROUP, not a string

Key points that a naive line-oriented parser gets wrong:

  1. ';' is a group terminator, not a string delimiter. `Name: X;` is a
     one-element group; in the Abilityes block only the LAST line carries ';'.
  2. Inside parentheses the separators invert relative to intuition:
     ';' separates rows, ',' separates columns within a row.
  3. `(a, b)` is ambiguous between a 2-tuple and a 2-element list. Arity is
     field-dependent and CANNOT be recovered lexically — it needs a declared
     schema. This is the single irreducible obstacle to a generic
     var -> relational conversion.
  4. Keys are not a closed vocabulary. Inside a modifier block the key is a
     free-form symbolic label (effectively a comment) and the VALUE is the
     real reference. THE TRAP: two visually identical idioms point at two
     DIFFERENT tables, and nothing lexical distinguishes them --

        unit.var    "Abilityes:"  Parry: 590   -> unit_upg.var  index 590
        item.var    "Effects:"    Defence: 4   -> ability_num.var Number 4
        spell.var   "Effects:"    Damage: 1    -> ability_num.var Number 4
        medal.var   "Effects:"    Life: 1      -> ability_num.var Number 1

     unit_upg entries are CURRIED modifiers (opcode + magnitude baked in);
     item/spell/medal effects are UNCURRIED (bare opcode, magnitude supplied
     by the following `Power:` line, plus `Duration:`/`Area:`). Because both
     ID spaces are dense and overlapping, resolving a reference against the
     wrong table succeeds ~97% of the time and returns silent nonsense. Any
     port must carry typed reference IDs, never bare ints.
  5. `Quantity` appears both as a file header and as a record field in
     guard/quest/shard_bonus/unit_upg. Scope matters.
  6. 14 files have no Quantity header; 4 of those are flat key-value with no
     records at all; stat.var uses parenthesised column headers over
     `Lvl<N>: a, b, c` rows and needs a bespoke reader.
  7. Encoding is CP1251. Line endings CRLF. Trailing tabs after terminators.

Usage:
    python3 eador_var.py <dir>              # schema report for every file
    python3 eador_var.py <dir> --json out/  # dump parsed records as JSON
    python3 eador_var.py <dir> --xref       # cross-reference integrity check
"""

from __future__ import annotations

import json
import os
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field as dc_field

ENCODING = "cp1251"

RE_HEADER = re.compile(r"^\s*Quantity:\s*(\d+)\s*$", re.M)
RE_RECORD = re.compile(r"^/(\d+)[ \t]*(.*)$", re.M)
RE_FIELD = re.compile(r"^([^:\n]{1,60}?):[ \t]*(.*)$")
RE_SECTION = re.compile(r"^([A-Za-z][A-Za-z ]*)\(([^)]*)\)\s*$")

# ---------------------------------------------------------------- unit schema

RE_LVL_UPGRADE = re.compile(r"Lvl \d+ (upgrades|loot)$")


def unit_ability_refs(record):
    """Yield (label, unit_upg_index) for each ability in a unit.var record.

    Identified STRUCTURALLY, by position: the `Abilityes:` block is exactly the
    fields between the `Abilityes` marker and the first `Lvl NN upgrades/loot`
    row, in file order (which parse() preserves in `record.order`).

    This is what the format actually says, and it avoids the reference-table
    trap. An exclusion allowlist looks equivalent and is not: Genesis unit
    records carry `Race` and `UnitKind` metadata ints that New Horizons does not,
    they sit BEFORE the marker, and they resolve to a perfectly valid unit_upg
    index (1 -> «Жизнь +1»). An allowlist tuned on NH data therefore attaches two
    phantom abilities to every Genesis unit while xref still reports zero
    dangling references. Position excludes them for free.

    Shared by xref() and tools/extract/build_pack.py so the two cannot drift.
    """
    order = record.order
    try:
        start = order.index("Abilityes") + 1
    except ValueError:
        return
    for k in order[start:]:
        if RE_LVL_UPGRADE.match(k):
            break
        v = record.fields.get(k)
        if isinstance(v, int) and v:
            yield k, v


# ---------------------------------------------------------------- values


def parse_scalar(tok: str):
    tok = tok.strip()
    if re.fullmatch(r"-?\d+", tok):
        return int(tok)
    if re.fullmatch(r"-?\d*\.\d+", tok):
        return float(tok)
    return tok


def parse_value(raw: str):
    """Return (value, terminated). `terminated` = the field group ended with ';'."""
    raw = raw.rstrip(" \t")
    terminated = raw.endswith(";")
    if terminated:
        raw = raw[:-1].rstrip(" \t")

    if raw.startswith("(") and raw.endswith(")"):
        inner = raw[1:-1].strip()
        if not inner:
            return [], terminated
        rows = [r for r in inner.split(";")]
        parsed = []
        for row in rows:
            cols = [parse_scalar(c) for c in row.split(",") if c.strip() != ""]
            if not cols:
                continue
            parsed.append(cols[0] if len(cols) == 1 else cols)
        return parsed, terminated

    if "," in raw:
        return [parse_scalar(c) for c in raw.split(",")], terminated

    return parse_scalar(raw), terminated


def split_groups(body: str):
    """Split a record body into field groups.

    THE central rule of the format: a group ends at a ';' that is not inside
    parentheses. A group may span many physical lines (dialog.var narration,
    the multi-line Abilityes block). Splitting on '\\n' is the mistake that
    makes this format look harder than it is.

    Groups not closed by ';' before a blank-line break are emitted as-is, so
    terminator-less files (terrain.var, ability_num.var) still parse.
    """
    out, buf, depth = [], [], 0
    for ch in body:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        if ch == ";" and depth == 0:
            out.append("".join(buf))
            buf = []
            continue
        buf.append(ch)
    out.append("".join(buf))

    flat = []
    for g in out:
        # an unterminated group may hold several single-line fields
        if ":" in g and g.count("\n") and not re.search(r"\([^)]*\n", g):
            chunk = []
            for line in g.split("\n"):
                if RE_FIELD.match(line.strip()) and chunk:
                    flat.append("\n".join(chunk))
                    chunk = []
                chunk.append(line)
            if chunk:
                flat.append("\n".join(chunk))
        else:
            flat.append(g)
    return [g.strip() for g in flat if g.strip()]


# ---------------------------------------------------------------- records


@dataclass
class Record:
    index: int
    label: str = ""
    fields: dict = dc_field(default_factory=dict)
    order: list = dc_field(default_factory=list)

    def get(self, key, default=None):
        return self.fields.get(key, default)


@dataclass
class VarFile:
    name: str
    declared: int | None
    records: list
    globals: dict
    warnings: list

    def by_index(self):
        return {r.index: r for r in self.records}


def parse(path: str) -> VarFile:
    text = open(path, "rb").read().decode(ENCODING, errors="replace")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    name = os.path.basename(path)
    warnings: list[str] = []

    m = RE_HEADER.search(text[:200])
    declared = int(m.group(1)) if m else None

    marks = list(RE_RECORD.finditer(text))
    preamble = text[: marks[0].start()] if marks else text

    globals_: dict = {}
    for line in preamble.split("\n"):
        line = line.strip()
        if not line or line.startswith("Quantity:") and declared is not None:
            continue
        sec = RE_SECTION.match(line)
        if sec:
            globals_.setdefault("__sections__", []).append(
                {"name": sec.group(1).strip(), "columns": [c.strip() for c in sec.group(2).split(",")]}
            )
            continue
        f = RE_FIELD.match(line)
        if f:
            val, _ = parse_value(f.group(2))
            globals_[f.group(1).strip()] = val

    records = []
    for i, mk in enumerate(marks):
        start = mk.end()
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        rec = Record(index=int(mk.group(1)), label=mk.group(2).strip())
        for grp in split_groups(text[start:end]):
            head, sep, tail = grp.partition(":")
            if not sep or "\n" in head:
                # bare marker line (*Attitude*, Terrain_Possibility) or stray text
                bare = grp.strip()
                if bare:
                    rec.fields.setdefault("__markers__", []).append(bare[:80])
                continue
            key = head.strip()
            val, _ = parse_value(tail)
            if key in rec.fields:
                # repeated key -> promote to list (happens in Abilityes-style blocks)
                prev = rec.fields[key]
                rec.fields[key] = prev + [val] if isinstance(prev, list) else [prev, val]
            else:
                rec.fields[key] = val
                rec.order.append(key)
        records.append(rec)

    if declared is not None:
        # invariant across the whole data set: len(records) == declared + 1
        # (record /0 is the reserved "Пусто" / null entry and is not counted)
        if len(records) != declared + 1:
            warnings.append(
                f"{name}: Quantity={declared} but {len(records)} records "
                f"(expected {declared + 1} including /0)"
            )
    if records:
        idx = [r.index for r in records]
        if idx != sorted(idx):
            warnings.append(f"{name}: record indices not monotonic")
        dupes = [k for k, v in Counter(idx).items() if v > 1]
        if dupes:
            warnings.append(f"{name}: duplicate record indices {dupes[:10]}")

    return VarFile(name, declared, records, globals_, warnings)


# ---------------------------------------------------------------- schema


def infer_schema(vf: VarFile) -> dict:
    n = len(vf.records)
    seen = Counter()
    types = defaultdict(Counter)
    arity = defaultdict(Counter)
    for r in vf.records:
        for k, v in r.fields.items():
            nk = re.sub(r"\d+", "#", k)
            seen[nk] += 1
            if isinstance(v, list):
                types[nk]["list"] += 1
                arity[nk][len(v)] += 1
            elif isinstance(v, int):
                types[nk]["int"] += 1
            elif isinstance(v, float):
                types[nk]["float"] += 1
            else:
                types[nk]["str"] += 1
    out = {}
    for k, c in seen.items():
        out[k] = {
            "presence": f"{c}/{n}",
            "required": c == n,
            "types": dict(types[k]),
            "list_arities": dict(sorted(arity[k].items())) if k in arity else None,
        }
    return out


def report(directory: str):
    files = sorted(f for f in os.listdir(directory) if f.endswith(".var"))
    total_warn = 0
    for fn in files:
        vf = parse(os.path.join(directory, fn))
        sch = infer_schema(vf)
        req = sum(1 for v in sch.values() if v["required"])
        opt = len(sch) - req
        ambiguous = [
            k for k, v in sch.items()
            if v["list_arities"] and len(v["list_arities"]) > 1
        ]
        print(
            f"{fn:24} recs={len(vf.records):<5} declared={str(vf.declared):<6} "
            f"keys={len(sch):<4} req={req:<3} opt={opt:<4} "
            f"var-arity-fields={len(ambiguous)}"
        )
        for w in vf.warnings[:3]:
            print(f"    ! {w}")
        total_warn += len(vf.warnings)
    print(f"\ntotal warnings: {total_warn}")


def xref(directory: str):
    """Integrity check on the references that actually matter for the sim core."""
    P = lambda f: parse(os.path.join(directory, f))
    unit, upg, abil = P("unit.var"), P("unit_upg.var"), P("ability_num.var")
    upg_ix = upg.by_index()
    abil_by_number = {
        r.get("Number"): r for r in abil.records if isinstance(r.get("Number"), int)
    }

    dangling_ability, dangling_upgrade = Counter(), Counter()
    for r in unit.records:
        for k, v in r.fields.items():
            if RE_LVL_UPGRADE.match(k):
                rows = v if isinstance(v, list) else []
                for row in rows:
                    uid = row[0] if isinstance(row, list) else row
                    if isinstance(uid, int) and uid and uid not in upg_ix:
                        dangling_upgrade[uid] += 1
        for _label, ref in unit_ability_refs(r):
            if ref not in upg_ix:
                dangling_ability[ref] += 1

    orphan_opcodes = Counter()
    for r in upg.records:
        ut = r.get("Upg Type")
        if isinstance(ut, int) and ut not in abil_by_number:
            orphan_opcodes[ut] += 1

    print(f"unit ability refs not in unit_upg.var : {len(dangling_ability)} distinct")
    print(f"level-up refs not in unit_upg.var     : {len(dangling_upgrade)} distinct")
    print(
        f"unit_upg 'Upg Type' opcodes with no ability_num.Number declaration: "
        f"{len(orphan_opcodes)} distinct, {sum(orphan_opcodes.values())} uses"
    )
    print("  -> these are the candidate hardcoded-in-exe behaviours:")
    for op, cnt in orphan_opcodes.most_common(25):
        names = [
            r.get("Name") for r in upg.records if r.get("Upg Type") == op
        ][:2]
        print(f"     opcode {op:<5} used {cnt:<3}x  e.g. {names}")


def dump_json(directory: str, outdir: str):
    os.makedirs(outdir, exist_ok=True)
    for fn in sorted(f for f in os.listdir(directory) if f.endswith(".var")):
        vf = parse(os.path.join(directory, fn))
        payload = {
            "file": vf.name,
            "declared_quantity": vf.declared,
            "globals": vf.globals,
            "records": [
                {"index": r.index, "label": r.label, **r.fields} for r in vf.records
            ],
        }
        dest = os.path.join(outdir, fn.replace(".var", ".json"))
        with open(dest, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=1)
    print(f"wrote {outdir}")


if __name__ == "__main__":
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    if "--xref" in sys.argv:
        xref(d)
    elif "--json" in sys.argv:
        dump_json(d, sys.argv[sys.argv.index("--json") + 1])
    else:
        report(d)
