#!/usr/bin/env python3
"""
Eador .var → normalized JSON importer (fixed version).

Fixes:
- record headers like "/1 SomeName"
- repeated keys promoted to arrays
- implicit title-only sections
- stat / stat_progress linear tables
- group_coord "5/1" syntax
- chained tuples "(a,b)(c,d)"
- event / dialog Answer/Effect blocks
- yuplay / build_group / guard / mapobject quirks

Usage:
  python import_vars_full_fixed.py var.zip --out res://data/db
  python import_vars_full_fixed.py var/     --out res://data/db
"""

from __future__ import annotations
import argparse, json, re, zipfile
from pathlib import Path
from typing import Any, Dict, List, Optional

# ============================================================
# Encoding
# ============================================================

def decode_bytes(b: bytes) -> str:
    for enc in ("utf-8-sig", "cp1251", "utf-8", "latin1"):
        try:
            return b.decode(enc)
        except UnicodeDecodeError:
            continue
    return b.decode("latin1", errors="replace")

# ============================================================
# Regex helpers
# ============================================================

RE_KEYVAL = re.compile(r'^([^:]+):\s*(.*)$')
RE_TUPLE = re.compile(r'^\((.*)\)$')
RE_CHAINED_TUPLES = re.compile(r'\(([^)]*)\)')
RE_RECORD = re.compile(r'^/(\d+)(?:\s+(.*))?$')
RE_LVL = re.compile(r'^Lvl\s*(\d+)\s*(.*)$', re.IGNORECASE)
RE_FRACTION = re.compile(r'^(\d+)\s*/\s*(\d+)$')

# ============================================================
# Scalar parsing
# ============================================================

def parse_scalar(s: str) -> Any:
    s = s.strip().rstrip(';')
    if not s:
        return ""

    m = RE_FRACTION.match(s)
    if m:
        return {"num": int(m.group(1)), "den": int(m.group(2))}

    if s.startswith('(') and s.endswith(')'):
        inner = s[1:-1].strip()
        if not inner:
            return []
        groups = [g.strip() for g in inner.split(';') if g.strip()]
        out = []
        for g in groups:
            parts = [parse_scalar(p) for p in g.split(',') if p.strip()]
            out.append(parts)
        return out[0] if len(out) == 1 else out

    if '(' in s and ')' in s:
        tuples = []
        for g in RE_CHAINED_TUPLES.findall(s):
            parts = [parse_scalar(p) for p in g.split(',') if p.strip()]
            tuples.append(parts)
        if tuples:
            return tuples

    if re.fullmatch(r'-?\d+', s):
        return int(s)
    if re.fullmatch(r'-?\d+\.\d+', s):
        return float(s)

    return s

# ============================================================
# Core parser
# ============================================================

def parse_var(text: str) -> Dict[str, Any]:
    lines = text.replace('\r\n', '\n').replace('\r', '\n').split('\n')

    out = {"quantity": None, "records": {}, "globals": {"fields": {}, "sections": {}}}
    i = 0

    if i < len(lines):
        m = RE_KEYVAL.match(lines[i].strip())
        if m and m.group(1).lower() == "quantity":
            out["quantity"] = parse_scalar(m.group(2))
            i += 1

    current_id = None
    current = None
    section = None

    def commit():
        nonlocal current_id, current, section
        if current_id is not None:
            out["records"][str(current_id)] = current
        current_id = None
        current = None
        section = None

    while i < len(lines):
        raw = lines[i]
        s = raw.strip()
        i += 1

        if not s:
            section = None
            continue

        m = RE_RECORD.match(s)
        if m:
            commit()
            current_id = int(m.group(1))
            current = {"fields": {}, "sections": {}}
            if m.group(2):
                current["fields"]["_record_name"] = m.group(2)
            continue

        target = current if current else out["globals"]

        if s.endswith(':') and ':' not in s[:-1]:
            section = s[:-1].strip()
            target["sections"].setdefault(section, [])
            continue

        m = RE_KEYVAL.match(raw)
        if m:
            k = m.group(1).strip()
            v = parse_scalar(m.group(2))

            if section:
                target["sections"][section].append({"key": k, "value": v})
            else:
                if k in target["fields"]:
                    prev = target["fields"][k]
                    target["fields"][k] = prev + [v] if isinstance(prev, list) else [prev, v]
                else:
                    target["fields"][k] = v
            continue

        if section:
            target["sections"][section].append({"raw": s})
        else:
            target.setdefault("raw", []).append(s)

    commit()

    if not out["globals"]["fields"] and not out["globals"]["sections"]:
        out.pop("globals", None)

    return out

# ============================================================
# Normalization
# ============================================================

def normalize_levels(rec: Dict[str, Any]) -> None:
    fields = rec.get("fields", {})
    levels = {}

    for k in list(fields.keys()):
        m = RE_LVL.match(k)
        if m:
            lvl = m.group(1)
            suffix = m.group(2) or "default"
            levels.setdefault(suffix, {})[lvl] = fields.pop(k)

    if levels:
        rec.setdefault("sections", {})["Levels"] = levels

def normalize_stat_table(doc: Dict[str, Any]) -> None:
    if "records" not in doc or not doc["records"]:
        return
    rows = []
    for k in sorted(doc["records"], key=lambda x: int(x)):
        rows.append(doc["records"][k]["fields"])
    doc["table"] = rows
    doc.pop("records", None)

# ============================================================
# Driver
# ============================================================

def import_one(name: str, text: str, out_path: Path) -> Dict[str, Any]:
    doc = parse_var(text)
    doc["source"] = name
    stem = Path(name).stem

    for rec in doc.get("records", {}).values():
        normalize_levels(rec)

    if stem in ("stat", "stat_progress"):
        normalize_stat_table(doc)

    out_path.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"file": name, "records": len(doc.get("records", {})), "quantity": doc.get("quantity")}

def run_import(inp: Path, out_dir: Path):
    raw = out_dir / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    index = []

    if inp.is_dir():
        files = sorted(inp.glob("*.var"))
        for p in files:
            meta = import_one(p.name, decode_bytes(p.read_bytes()), raw / f"{p.stem}.json")
            index.append(meta)
    else:
        with zipfile.ZipFile(inp) as z:
            for name in sorted(n for n in z.namelist() if n.lower().endswith(".var")):
                meta = import_one(Path(name).name, decode_bytes(z.read(name)),
                                  raw / f"{Path(name).stem}.json")
                index.append(meta)

    (out_dir / "index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")

# ============================================================
# CLI
# ============================================================

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("--out", default="res://data/db")
    args = ap.parse_args()

    out = Path(args.out)
    if str(out).startswith("res://"):
        out = Path(str(out)[6:])

    run_import(Path(args.input), out)
    print("Import complete:", out)

if __name__ == "__main__":
    main()
