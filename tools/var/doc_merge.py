"""
doc_merge.py — join Eadoropedia ability descriptions onto the opcode corpus and
re-derive hook assignments from the text rather than from the name.

The Eadoropedia ability page carries what look like the game's own tooltip
templates (they still contain the `%d` / `%s` substitution markers), which makes
them the most authoritative source available short of the binary. Where the text
disagrees with the name-based guess in hooks.py, the text wins.

Join is by exact ability NAME, not by number: the wiki build and the local var
set disagree on numbering, and names are stable where numbers are not.

Usage:
    python3 doc_merge.py <var-dir> <abil_doc.json>            # coverage + corrections
    python3 doc_merge.py <var-dir> <abil_doc.json> --table    # full merged markdown
    python3 doc_merge.py <var-dir> <abil_doc.json> --gaps     # opcodes with no doc entry
"""

from __future__ import annotations

import json
import re
import sys
import collections

import eador_var as E
import hooks as H

# --------------------------------------------------------------------------
# Text signals. Each is a phrase that appears in the Russian tooltip and
# identifies where the ability fires. Ordered: first match wins.
# --------------------------------------------------------------------------

SIGNALS: list[tuple[str, str, str]] = [
    (r'ответный удар прежде|прежде, чем его ударит',      "COUNTERATTACK", "pre-emptive retaliation, not initiative"),
    (r'к его защите добавляется|увеличить свою защиту',   "DEFENCE_APPLY", "adds to Defence"),
    (r'дистанционная защита.*меньш|защита.*счита\w+ в \d+ раза', "DEFENCE_APPLY", "defence divided, not subtracted"),
    (r'дистанционная атака считается ниже',               "ATTACK_ACCURACY", "reduces the attacker's ranged figure"),
    (r'снижает его боевой дух|боевой дух.*снижа',         "MORALE", "morale debuff"),
    (r'боевой дух.*увеличива|не может быть ниже',         "MORALE", "morale buff or floor"),
    (r'Убив противника|когда.*гибнет|при гибели',         "ON_KILL", "fires on a death"),
    (r'При получении тяжёлого ранения|Получая урон',      "ON_DAMAGED", "fires when damaged"),
    (r'Атакуя противника врукопашную',                    "ON_HIT", "fires on a landed melee attack"),
    (r'восстанавливает.*жизни каждый ход|каждый ход.*восстанавлива', "REGEN", "per-round tick"),
    (r'Во время отдыха|вне боя',                          "BATTLE_END", "out-of-combat recovery, not a combat hook"),
    (r'тратится \d+ выстрел|тратится выстрелов',          "AMMO", "consumes ammunition"),
    (r'Особое умение, позволяющее',                       "TURN_START", "ACTIVATED ability — an action, not a passive"),
    (r'На воина не действуют|не действует',               "STATUS_RESIST", "immunity / exclusion"),
    (r'в начале хода',                                    "TURN_START", "start-of-turn effect"),
    (r'до конца следующего хода|до следующего хода',      "TURN_END", "expires on a turn boundary — stateful"),
]

# phrases that mean the ability carries per-turn or accumulating state
STATEFUL = [
    (r'за ход\)',                     "per-turn use cap"),
    (r'увеличивает его защиту от следующих', "accumulates per incoming shot"),
    (r'до конца следующего хода',     "decays on a turn boundary"),
    (r'каждый ход теряет',            "per-round self-damage"),
    (r'впитывает его способность',    "transfers between units on death"),
]


def load_docs(path: str) -> dict[str, str]:
    raw = json.load(open(path, encoding="utf-8"))
    out = {}
    for _, lines in raw.items():
        if not lines:
            continue
        out[lines[0].strip()] = " ".join(lines[1:]).strip()
    return out


def signal_hook(text: str):
    for pattern, hook, why in SIGNALS:
        if re.search(pattern, text):
            return hook, why
    return None, None


def stateful_flags(text: str):
    return [why for pattern, why in STATEFUL if re.search(pattern, text)]


def merge(var_dir: str, doc_path: str):
    docs = load_docs(doc_path)
    rows = H.build(var_dir)
    for r in rows:
        text = docs.get(r["name"])
        r["doc"] = text
        r["doc_hook"], r["doc_why"] = signal_hook(text) if text else (None, None)
        r["stateful"] = stateful_flags(text) if text else []
    return rows


def report(rows):
    total = len(rows)
    have = [r for r in rows if r["doc"]]
    print(f"documented: {len(have)}/{total} opcodes\n")

    unresolved = [r for r in rows
                  if (r["conf"] == "low" or r["hook"] == "UNCLASSIFIED") and not r["doc"]]
    print(f"still needing play observation (low confidence AND no doc): {len(unresolved)}")
    for r in sorted(unresolved, key=lambda x: -x["uses"])[:15]:
        print(f"   {r['opcode']:>5}  uses {r['uses']:>3}  {r['name']}")

    print("\n--- corrections: doc text contradicts the name-based hook ---")
    bad = [r for r in have if r["doc_hook"] and r["doc_hook"] != r["hook"]]
    bad.sort(key=lambda x: -x["uses"])
    for r in bad[:25]:
        print(f"\n  {r['name']}  (opcode {r['opcode']}, {r['uses']} options)")
        print(f"     guessed {r['hook']}  ->  {r['doc_hook']}   [{r['doc_why']}]")
        print(f"     {r['doc'][:180]}")
    print(f"\n  ({len(bad)} corrections total)")

    print("\n--- abilities carrying per-turn or accumulating STATE ---")
    st = [r for r in have if r["stateful"]]
    st.sort(key=lambda x: -x["uses"])
    for r in st[:20]:
        print(f"  {r['name']:32} {', '.join(r['stateful'])}")
    print(f"  ({len(st)} total — each needs a state slot on the unit, not just a modifier)")


def table(rows):
    print("| opcode | name | hook (final) | from | uses | state | description |")
    print("|---|---|---|---|---|---|---|")
    for r in sorted(rows, key=lambda x: (H.HOOK_ORDER[x["doc_hook"] or x["hook"]], -x["uses"])):
        final = r["doc_hook"] or r["hook"]
        src = "doc" if r["doc_hook"] else ("name/" + r["conf"])
        desc = (r["doc"] or "")[:160].replace("|", "/")
        state = ";".join(r["stateful"])
        print(f"| {r['opcode']} | {r['name']} | {final} | {src} | {r['uses']} | {state} | {desc} |")


if __name__ == "__main__":
    var_dir = sys.argv[1]
    doc_path = sys.argv[2]
    rows = merge(var_dir, doc_path)
    if "--table" in sys.argv:
        table(rows)
    elif "--gaps" in sys.argv:
        for r in sorted((x for x in rows if not x["doc"]), key=lambda x: -x["uses"]):
            print(f"{r['opcode']:>5}  uses {r['uses']:>3}  {r['hook']:18} {r['name']}")
    else:
        report(rows)
