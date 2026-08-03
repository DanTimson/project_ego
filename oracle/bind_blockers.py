"""
bind_blockers.py — bind the opcodes that block the most units.

    python3 tools/extract/bind_blockers.py <pack-id>

Reads packs/<id>/bindings.json, fills in the entries listed below, writes it
back. Idempotent: an entry already carrying a handler is left alone, so a
hand-edited binding is never clobbered by a rerun.

WHY A SCRIPT AND NOT HAND EDITING. The mapping below is a REVIEWABLE CLAIM about
what each opcode does, sitting next to the documentation sentence it came from.
Hand-editing 30 JSON entries buries the same information in a diff nobody reads.

Opcodes are per-pack: this table is written for the Genesis numbering, and
applying it to New Horizons would be wrong for the reassigned ones (30, 39, 42,
96 among others). The script checks the ability NAME before writing, and skips
anything whose name does not match — so a wrong pack fails loudly and harmlessly.
"""

from __future__ import annotations

import json
import os
import sys

## opcode -> (expected name, handler, params)
##
## The expected name is the safety catch. Genesis and NH disagree about what
## several of these opcodes mean, and a silent mis-bind would be invisible until
## units started behaving wrongly.
BINDINGS = {
    # --- presence-only: the rules already check these flags -----------------
    13: ("Не чувствует боли", "grant_flag", {"flag": "Не чувствует боли"}),
    18: ("Неутомимый", "grant_flag", {"flag": "Неутомимый"}),
    19: ("Неустрашимый", "grant_flag", {"flag": "Неустрашимый"}),
    26: ("Ловкость", "grant_flag", {"flag": "Ловкость"}),
    16: ("Первый удар", "grant_flag", {"flag": "Первый удар"}),
    38: ("Не сражается", "grant_flag", {"flag": "Не сражается"}),
    14: ("Летающий", "grant_flag", {"flag": "Летающий"}),
    15: ("Низколетающий", "grant_flag", {"flag": "Низколетающий"}),
    25: ("Берсерк", "grant_flag", {"flag": "Берсерк"}),
    63: ("Топчет", "grant_flag", {"flag": "Топчет"}),
    97: ("Реинкарнация", "grant_flag", {"flag": "Реинкарнация"}),
    96: ("Ядовитая плоть", "grant_flag", {"flag": "Ядовитая плоть"}),
    65: ("Атака всех врагов", "grant_flag", {"flag": "Атака всех врагов"}),

    # --- terrain knowledge --------------------------------------------------
    # «тратит только единицу скорости ... и не тратит выносливость. Кроме того,
    # каждый пункт знания выше первого увеличивает защиту и контратаку на 1»
    32: ("Знание леса", "terrain_knowledge", {"terrain": "forest"}),
    33: ("Знание холмов", "terrain_knowledge", {"terrain": "hills"}),
    34: ("Знание болот", "terrain_knowledge", {"terrain": "swamp"}),

    # --- damage typing ------------------------------------------------------
    # «спасает не защита, а сопротивление»
    27: ("Магический удар", "damage_type", {"type": "magic", "applies_to": "melee"}),
    28: ("Магический выстрел", "damage_type", {"type": "magic", "applies_to": "ranged"}),

    # --- defence bypass: handlers that already existed, never bound ----------
    39: ("Бронебойный удар", "armor_pierce", {}),
    17: ("Бронебойный выстрел", "armor_pierce", {}),
    76: ("Точный удар", "defence_ignore", {}),
    77: ("Точный выстрел", "defence_ignore", {}),

    # --- per-round recovery -------------------------------------------------
    48: ("Регенерация", "regeneration", {}),

    # --- province layer: bound to an explicit no-op, not left unbound --------
    55: ("Осада", "strategic_only", {}),
    56: ("Мародер", "strategic_only", {}),
    58: ("Грабитель", "strategic_only", {}),
}


def apply(pack_id: str) -> None:
    path = os.path.join("packs", pack_id, "bindings.json")
    with open(path, encoding="utf-8") as fh:
        payload = json.load(fh)

    abilities = payload["abilities"]
    bound, skipped, mismatched = [], [], []

    for opcode, (expected, handler, params) in sorted(BINDINGS.items()):
        entry = abilities.get(str(opcode))
        if entry is None:
            skipped.append("%d: not in this pack" % opcode)
            continue
        if entry.get("name") != expected:
            mismatched.append("%d: expected %r, pack says %r"
                              % (opcode, expected, entry.get("name")))
            continue
        if entry.get("handler"):
            skipped.append("%d: already bound to %r" % (opcode, entry["handler"]))
            continue
        entry["handler"] = handler
        if params:
            entry["params"] = params
        entry.pop("hook_confidence", None)
        bound.append("%d %s -> %s" % (opcode, expected, handler))

    total = len(abilities)
    now_bound = sum(1 for e in abilities.values() if e.get("handler"))
    payload["summary"] = {"opcodes": total, "bound": now_bound,
                          "unbound": total - now_bound}

    head = json.dumps({k: v for k, v in payload.items() if k != "abilities"},
                      ensure_ascii=False, indent=1)
    lines = [head[:-2] + ",", ' "abilities": {']
    items = sorted(abilities.items(), key=lambda kv: int(kv[0]))
    for i, (k, v) in enumerate(items):
        lines.append('  "%s": %s%s' % (k, json.dumps(v, ensure_ascii=False),
                                       "," if i < len(items) - 1 else ""))
    lines.append(" }")
    lines.append("}")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    print("%s: %d newly bound, %d now bound of %d"
          % (pack_id, len(bound), now_bound, total))
    for b in bound:
        print("   + %s" % b)
    for m in mismatched:
        print("   ! %s" % m)
    if skipped:
        print("   (%d skipped)" % len(skipped))


if __name__ == "__main__":
    apply(sys.argv[1] if len(sys.argv) > 1 else "genesis")
