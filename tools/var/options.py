"""
options.py — transpose Eador's unit-major level lists into option-major
availability schedules, the shape the remake's option layer wants.

Eador stores, per unit, twenty lists of (upgrade_id, weight). The pool a unit
draws from at level L is the CUMULATIVE union of lists 1..L, with weight
re-added on recurrence. This script inverts that into, per (unit, option), a
schedule of (level, weight_added) plus the running total, so the option layer
can answer "what is in this unit's pool at level L and with what weight"
without rescanning.

Also emits, per unit, the pool size and total weight at each level — which is
the quickest sanity check that the cumulative reading is right: pool sizes
should grow monotonically, and by mid-levels should comfortably exceed the two
choices the game offers.

Usage:
    python3 options.py <var-dir>                  # summary
    python3 options.py <var-dir> --unit <name>    # one unit's schedule
    python3 options.py <var-dir> --json out.json  # full transposition
"""

from __future__ import annotations

import json
import re
import sys
import collections
import statistics as st

import eador_var as E

MAX_LEVEL = 20


def level_rows(rec, lvl: int):
    v = rec.get(f"Lvl {lvl:02d} upgrades")
    if not isinstance(v, list) or not v:
        return []
    rows = v if isinstance(v[0], list) else [v]
    return [(r[0], r[1]) for r in rows
            if isinstance(r, list) and len(r) == 2 and r[0]]


def transpose(directory: str):
    units = E.parse(f"{directory}/unit.var")
    upg = E.parse(f"{directory}/unit_upg.var").by_index()

    out = {}
    for rec in units.records:
        name = rec.get("Name")
        if not name or name == "Пусто":
            continue
        # option_id -> [(level, weight_added), ...]
        sched: dict[int, list] = collections.defaultdict(list)
        for lvl in range(1, MAX_LEVEL + 1):
            for oid, w in level_rows(rec, lvl):
                sched[oid].append((lvl, w))

        options = []
        for oid, grants in sorted(sched.items()):
            row = upg.get(oid)
            options.append({
                "option": oid,
                "name": row.get("Name") if row else "?MISSING",
                "once": bool(row.get("Only Once")) if row else None,
                "needs": row.get("Need") if row else None,
                "opcode": row.get("Upg Type") if row else None,
                "magnitude": row.get("Quantity") if row else None,
                "grants": grants,                      # [(level, weight_added)]
                "first_level": grants[0][0],
                "total_weight": sum(w for _, w in grants),
            })

        # cumulative pool profile
        profile = []
        seen, total = set(), 0
        for lvl in range(1, MAX_LEVEL + 1):
            for oid, w in level_rows(rec, lvl):
                seen.add(oid)
                total += w
            profile.append({"level": lvl, "distinct": len(seen), "weight": total})

        out[name] = {"index": rec.index, "options": options, "profile": profile}
    return out


def summarise(data):
    print(f"{len(data)} units transposed\n")
    for lvl in (1, 3, 5, 10, 20):
        d = [u["profile"][lvl - 1]["distinct"] for u in data.values()]
        w = [u["profile"][lvl - 1]["weight"] for u in data.values()]
        print(f"  at level {lvl:2}: pool holds {st.median(d):5.1f} distinct options "
              f"(min {min(d)}, max {max(d)}), median total weight {st.median(w):6.1f}")
    print()
    n_at_1 = sum(1 for u in data.values() if u["profile"][0]["distinct"] < 2)
    print(f"  units whose level-1 pool has fewer than 2 options: {n_at_1}")
    print("  (any nonzero count here is a case the draw procedure must handle)")
    print()
    recur = [len(o["grants"]) for u in data.values() for o in u["options"]]
    print(f"  option grants per (unit, option): median {st.median(recur)}, max {max(recur)}")
    print(f"  options granted more than once  : "
          f"{sum(1 for r in recur if r > 1)} of {len(recur)}")


def show_unit(data, name):
    key = next((k for k in data if k.lower() == name.lower()), None)
    if key is None:
        key = next((k for k in data if name.lower() in k.lower()), None)
    if key is None:
        print(f"no unit matching {name!r}")
        return
    u = data[key]
    print(f"=== {key} (unit /{u['index']})\n")
    print(f"{'opt':>5} {'lvls (weight)':32} {'tot':>4} {'1st':>4} once  name")
    for o in sorted(u["options"], key=lambda x: (x["first_level"], -x["total_weight"])):
        g = " ".join(f"L{l}:{w}" for l, w in o["grants"])
        print(f"{o['option']:>5} {g:32} {o['total_weight']:>4} {o['first_level']:>4} "
              f"{'Y' if o['once'] else '.':>4}  {o['name']}")
    print("\ncumulative pool profile:")
    print("  " + "  ".join(f"L{p['level']}:{p['distinct']}/{p['weight']}"
                           for p in u["profile"] if p["distinct"]))


if __name__ == "__main__":
    d = sys.argv[1] if len(sys.argv) > 1 else "var"
    data = transpose(d)
    if "--unit" in sys.argv:
        show_unit(data, sys.argv[sys.argv.index("--unit") + 1])
    elif "--json" in sys.argv:
        path = sys.argv[sys.argv.index("--json") + 1]
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=1)
        print(f"wrote {path}")
    else:
        summarise(data)
