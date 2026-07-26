#!/usr/bin/env python3
"""
Eador .var → normalized JSON importer (full collection).

Usage:
  python import_vars_full.py var.zip --out res://data/db
  python import_vars_full.py var/     --out res://data/db
"""

from __future__ import annotations
import argparse, json, re, zipfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

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
# Parsing primitives
# ============================================================

_KEYVAL_RE = re.compile(r'^([^:]+):\s*(.*)$')
_TUPLE_RE = re.compile(r'^\((.*)\)$')
_LVL_RE   = re.compile(r'^Lvl\s*(\d+)\s*(.*)$', re.IGNORECASE)

def parse_scalar(s: str) -> Any:
    s = s.strip()
    if not s:
        return ""

    if s.endswith(';'):
        s = s[:-1].rstrip()

    # tuple / list
    m = _TUPLE_RE.match(s)
    if m:
        inner = m.group(1).strip()
        if not inner:
            return []
        groups = [g.strip() for g in inner.split(';') if g.strip()]
        out = []
        for g in groups:
            parts = [parse_scalar(p) for p in g.split(',') if p.strip()]
            out.append(parts)
        return out[0] if len(out) == 1 else out

    if re.fullmatch(r'-?\d+', s):
        return int(s)
    if re.fullmatch(r'-?\d+\.\d+', s):
        return float(s)

    return s

# ============================================================
# Core parser
# ============================================================

def parse_var_text(text: str) -> Dict[str, Any]:
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    lines = text.split('\n')

    out = {
        "quantity": None,
        "globals": {"fields": {}, "sections": {}},
        "records": {}
    }

    i = 0
    if i < len(lines):
        m = _KEYVAL_RE.match(lines[i].strip())
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
        line = lines[i]
        s = line.strip()

        if not s:
            section = None
            i += 1
            continue

        if s.startswith('/') and s[1:].isdigit():
            commit()
            current_id = int(s[1:])
            current = {"fields": {}, "sections": {}}
            i += 1
            continue

        target = current if current else out["globals"]

        if s.endswith(':') and ':' not in s[:-1]:
            section = s[:-1].strip()
            target["sections"].setdefault(section, [])
            i += 1
            continue

        m = _KEYVAL_RE.match(line)
        if m:
            k = m.group(1).strip()
            v = parse_scalar(m.group(2))

            if section:
                target["sections"][section].append({"key": k, "value": v})
            else:
                target["fields"][k] = v
            i += 1
            continue

        # fallback
        if section:
            target["sections"][section].append({"raw": s})
        else:
            target.setdefault("raw", []).append(s)
        i += 1

    commit()

    if not out["globals"]["fields"] and not out["globals"]["sections"]:
        out.pop("globals", None)

    return out

# ============================================================
# Normalization (generic)
# ============================================================

def normalize_levels(rec: Dict[str, Any]) -> None:
    fields = rec.get("fields", {})
    moved = {}

    for k in list(fields.keys()):
        m = _LVL_RE.match(k)
        if not m:
            continue
        lvl = m.group(1)
        suffix = m.group(2).strip() or "default"
        moved.setdefault(suffix, {})[lvl] = fields.pop(k)

    if moved:
        rec.setdefault("sections", {})["Levels"] = moved

def normalize_record(stem: str, rec: Dict[str, Any]) -> None:
    normalize_levels(rec)

# ============================================================
# Reporting
# ============================================================

def shape(v: Any) -> str:
    if isinstance(v, int): return "int"
    if isinstance(v, float): return "float"
    if isinstance(v, list): return "list"
    if isinstance(v, dict): return "dict"
    if isinstance(v, str): return "str"
    return "other"

# ============================================================
# Import drivers
# ============================================================

def import_one(name: str, text: str, out: Path,
               report: Dict, xref: Dict) -> Dict[str, Any]:

    doc = parse_var_text(text)
    doc["source"] = name
    stem = Path(name).stem

    for rec in doc.get("records", {}).values():
        normalize_record(stem, rec)

        for k, v in rec.get("fields", {}).items():
            report.setdefault(stem, {}).setdefault(k, set()).add(shape(v))
            if isinstance(v, int):
                xref.setdefault(stem, {}).setdefault(k, set()).add(v)

    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    return {
        "file": name,
        "records": len(doc.get("records", {})),
        "quantity": doc.get("quantity")
    }

def import_all(input_path: Path, out_dir: Path) -> None:
    raw = out_dir / "raw"
    raw.mkdir(parents=True, exist_ok=True)

    index = []
    report: Dict[str, Dict[str, Set[str]]] = {}
    xref: Dict[str, Dict[str, Set[int]]] = {}

    if input_path.is_dir():
        files = sorted(input_path.glob("*.var"))
        for p in files:
            meta = import_one(
                p.name,
                decode_bytes(p.read_bytes()),
                raw / f"{p.stem}.json",
                report, xref
            )
            index.append(meta)
    else:
        with zipfile.ZipFile(input_path) as z:
            for name in sorted(n for n in z.namelist() if n.lower().endswith(".var")):
                meta = import_one(
                    Path(name).name,
                    decode_bytes(z.read(name)),
                    raw / f"{Path(name).stem}.json",
                    report, xref
                )
                index.append(meta)

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "index.json").write_text(json.dumps(index, indent=2), encoding="utf-8")
    (out_dir / "report.json").write_text(
        json.dumps({k: {f: sorted(v) for f, v in d.items()} for k, d in report.items()},
                   indent=2, ensure_ascii=False),
        encoding="utf-8"
    )
    (out_dir / "xref.json").write_text(
        json.dumps({k: {f: sorted(v) for f, v in d.items()} for k, d in xref.items()},
                   indent=2),
        encoding="utf-8"
    )
    (out_dir / "rules_template.json").write_text(
        json.dumps({"mappings": {}}, indent=2),
        encoding="utf-8"
    )

# ============================================================
# CLI
# ============================================================

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="Folder with .var or zip file")
    ap.add_argument("--out", default="data/db")
    args = ap.parse_args()

    out = Path(args.out)
    if str(out).startswith("res://"):
        out = Path(str(out)[6:])

    import_all(Path(args.input), out)
    print("Imported .var collection into", out)

if __name__ == "__main__":
    main()
