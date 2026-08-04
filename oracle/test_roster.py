"""
test_roster.py — building Combatants from the real corpus.

Everything before this used hand-written test units. This is the first module
tested against the actual .var data, and running it against real content is
what surfaced the compound-row bug that reasoning had not.

Run: python3 test_roster.py
"""

from __future__ import annotations

import json
import os
import sys

import content
import handlers
import roster
from modifier import Hook

FAILS: list[str] = []
TABLES = {"unit": "unit.json", "unit_upg": "unit_upg.json",
          "ability_num": "ability_num.json"}


def check(ok: bool, what: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", what,
                          ("  — " + detail) if detail else ""))
    if not ok:
        FAILS.append(what)


class PackUnavailable(Exception):
    """Local pack data is absent — not a rules failure."""


def pack_available(pack: str) -> bool:
    """Original .var data is never committed, so packs/<id>/data is generated
    locally and gitignored. On a fresh clone it is simply not there, and these
    tests have nothing to run against. Say so plainly instead of failing with an
    AttributeError on a None build."""
    return os.path.isdir(os.path.join("packs", pack, "data"))


def require(pack: str) -> None:
    if pack_available(pack):
        return
    msg = ("packs/%s/data is missing. Generate it from a local game install:\n"
           "    python3 tools/extract/build_pack.py <path-to>/var %s" % (pack, pack))
    try:
        import pytest
    except ImportError:
        raise PackUnavailable(msg)
    pytest.skip(msg)


def load(pack: str) -> roster.Roster:
    require(pack)
    reg = content.AbilityRegistry()
    handlers.register_all(reg)
    db = content.ContentDb.load(pack, "packs/%s" % pack, reg, TABLES)
    return roster.Roster(db)


def test_loads() -> None:
    print("\n[1] the corpus loads")
    r = load("genesis")
    check(len(r.names()) > 50, "vanilla roster has units", str(len(r.names())))
    check("Мечник" in r.names(), "and they are the ones we expect")
    check(r.build("Не существует") is None, "an unknown name returns None")


def test_stats_match_the_source() -> None:
    print("\n[2] stats come from the table, not from anywhere else")
    r = load("genesis")
    m = r.build("Мечник").unit
    check(m.life == 17 and m.attack == 7 and m.counter_attack == 7,
          "vanilla Мечник is 17/7/7",
          "%d/%d/%d" % (m.life, m.attack, m.counter_attack))
    check(m.life_base == m.life and m.stamina_base == m.stamina,
          "base values are seeded from current — the tables carry only one figure")

    nh = load("new_horizons").build("Мечник").unit
    check(nh.attack == 8, "and NH's Мечник is 8, not 7 — different pack, different unit",
          str(nh.attack))


def test_compound_rows() -> None:
    """The bug real data found: `Upg Type` and `Quantity` are PARALLEL LISTS
    when one upgrade grants several abilities. Treating them as scalars drops
    every ability after the first."""
    print("\n[3] compound upgrade rows grant every ability, not just the first")
    r = load("genesis")
    upg = r.upgrades
    compound = [x for x in upg.values() if isinstance(x.get("Upg Type"), list)]
    check(compound, "the corpus contains compound rows", str(len(compound)))

    lesser_undead = next((x for x in upg.values()
                          if x.get("Name") == "Младшая нежить"), None)
    check(lesser_undead is not None, "Младшая нежить is one of them")
    if lesser_undead:
        check(len(lesser_undead["Upg Type"]) == 4,
              "it grants four abilities in a single row",
              str(lesser_undead["Upg Type"]))
        check(len(lesser_undead["Quantity"]) == len(lesser_undead["Upg Type"]),
              "and Quantity is parallel to it")

    mismatched = [x for x in compound
                  if len(x["Upg Type"]) != len(x.get("Quantity", []))]
    check(not mismatched, "no row has mismatched parallel lengths",
          str(len(mismatched)))


def test_unresolved_is_reported_not_dropped() -> None:
    print("\n[4] an unbound ability is reported, never silently dropped")
    r = load("genesis")
    built = r.build("Мечник")
    check(built.unit.name == "Мечник", "the unit still builds")
    check(built.unresolved, "with its unresolved abilities listed")
    first = built.unresolved[0]
    check(first.upgrade_name and first.reason,
          "each naming the upgrade and why it failed", str(first))
    # Three distinct failure modes, and the reason must name which one:
    #   opcode absent from the binding table entirely,
    #   present but bound to nothing in this pack,
    #   bound to a handler the engine does not implement.
    # The earlier assertion listed only the last two, so it could never pass
    # against a skeleton bindings.json where every opcode hits the first.
    categories = ("no binding table", "unbound in", "not implemented")
    check(any(c in first.reason for c in categories),
          "and naming which of the three failure modes it was", first.reason)


def bindings_available(pack: str = "genesis") -> bool:
    """The committed bindings.json is a skeleton with no opcodes bound; real
    bindings are generated locally by tools/extract/make_bindings.py and then
    hand-edited. Tests that need a *resolvable* ability depend on that step."""
    try:
        with open(os.path.join("packs", pack, "bindings.json"), encoding="utf-8") as fh:
            return bool(json.load(fh).get("abilities"))
    except (OSError, ValueError):
        return False


def test_resolved_becomes_a_modifier() -> None:
    print("\n[5] a bound ability becomes a real Modifier")
    if not bindings_available():
        print("  SKIP  packs/genesis/bindings.json binds no opcodes — "
              "regenerate with tools/extract/make_bindings.py")
        return
    r = load("genesis")
    found = None
    for name in r.names():
        built = r.build(name)
        if built and built.resolved:
            found = built
            break
    check(found is not None, "at least one unit has a resolvable ability")
    if found is None:
        return
    check(len(found.unit.modifiers) == len(found.resolved),
          "one modifier per resolved ability",
          "%d vs %d" % (len(found.unit.modifiers), len(found.resolved)))
    m = found.unit.modifiers[0]
    check(m.handler and isinstance(m.hook, Hook),
          "carrying a handler name and a hook", "%s @ %s" % (m.handler, m.hook.name))
    check(m.source, "and a source for the trace to attribute it by", m.source)


def test_coverage_is_the_content_progress_meter() -> None:
    print("\n[6] roster coverage — the content-side counterpart to the load report")
    r = load("genesis")
    cov = r.coverage()
    check(cov["units"] > 0, "every unit is examined", str(cov["units"]))
    check(cov["complete"] + cov["partial"] == cov["units"],
          "and each is either complete or partial, never both")
    check(cov["blockers"], "blockers are listed")
    check(cov["blockers"][0][1] >= cov["blockers"][-1][1],
          "ordered by how many units they block — that is the work queue")
    # The honest number: binding most opcodes does not mean most units work,
    # because the unbound ones cluster on the interesting abilities.
    check(cov["complete"] < cov["units"],
          "and the corpus is not yet fully playable, which the number says plainly",
          "%d of %d complete" % (cov["complete"], cov["units"]))


def test_both_packs() -> None:
    print("\n[7] both packs build")
    for pack in ("genesis", "new_horizons"):
        r = load(pack)
        cov = r.coverage(limit=40)
        check(cov["units"] > 0, "%s builds units" % pack,
              "%d complete, %d partial of %d"
              % (cov["complete"], cov["partial"], cov["units"]))


def test_determinism() -> None:
    print("\n[8] building is deterministic")
    r = load("genesis")
    a = r.build("Мечник")
    b = r.build("Мечник")
    check([m.ability for m in a.unit.modifiers] == [m.ability for m in b.unit.modifiers],
          "the same unit builds the same modifiers in the same order")
    check(a.unit is not b.unit, "but as separate instances — no shared state")


if __name__ == "__main__":
    try:
        test_loads()
        test_stats_match_the_source()
        test_compound_rows()
        test_unresolved_is_reported_not_dropped()
        test_resolved_becomes_a_modifier()
        test_coverage_is_the_content_progress_meter()
        test_both_packs()
        test_determinism()
    except PackUnavailable as exc:
        print("\nSKIPPED — %s" % exc)
        sys.exit(0)
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
