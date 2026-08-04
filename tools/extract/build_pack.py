"""
build_pack.py — extract a local install's .var files into pack data.

    python3 tools/extract/build_pack.py <var-dir> <pack-id>

Writes packs/<pack-id>/data/*.json, which is GITIGNORED. The .var data belongs
to Bokulev and Jazz; what the repo ships is the opcode->handler bindings, which
are our work. This script is how anyone with their own copy of the game
reproduces the data half.

Only the tables the battle layer reads are converted. The rest of the corpus
(dialog, events, provinces) is left alone until something needs it — converting
everything would put 8 MB of someone else's content in a working directory for
no benefit.
"""

from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "var"))

import eador_var as E

## Tables the tactical layer reads. Extend as subsystems land.
TABLES = [
    "unit",          # the roster
    "unit_upg",      # curried modifiers and level-up options
    "ability_num",   # opcode declarations and display metadata
    "unit_class",    # Пехота / Стрелок / Кавалерия / ...
    "bf_object",     # battlefield tile types
    "terrain",       # province terrain -> passable/impassable tile pair
    "spell",         # for when casting lands
    "medal",         # a fourth modifier source
]


def convert(var_dir: str, pack_id: str) -> None:
    dest = os.path.join("packs", pack_id, "data")
    os.makedirs(dest, exist_ok=True)
    written, absent = [], []
    for name in TABLES:
        source = os.path.join(var_dir, "%s.var" % name)
        if not os.path.exists(source):
            absent.append(name)
            continue
        vf = E.parse(source)
        records = []
        for r in vf.records:
            row = {"index": r.index, "label": r.label, **r.fields}
            if name == "unit":
                # parse() flattens the multi-line `Abilityes:` block into
                # free-form-label int fields, so record["Abilityes"] arrives as
                # "" and the roster's `for entry in rec.get("Abilityes", [])`
                # silently attaches nothing. Rebuild the typed list the roster
                # already expects, and drop the flat refs plus the now-empty
                # marker so the ability set lives in exactly one place.
                refs = list(E.unit_ability_refs(r))
                for label, _ref in refs:
                    row.pop(label, None)
                row["Abilityes"] = [{"ref_label": label, "ref": ref}
                                    for label, ref in refs]
            records.append(row)
        payload = {
            "file": vf.name,
            "declared_quantity": vf.declared,
            "records": records,
        }
        out = os.path.join(dest, "%s.json" % name)
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False)
        written.append("%s (%d records)" % (name, len(vf.records)))
        if vf.warnings:
            print("  ! %s: %s" % (name, vf.warnings[0]), file=sys.stderr)

    print("%s -> %s" % (pack_id, dest))
    for w in written:
        print("   %s" % w)
    if absent:
        print("   absent: %s" % ", ".join(absent))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    convert(sys.argv[1], sys.argv[2])
