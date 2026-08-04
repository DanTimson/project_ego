"""
test_content.py — pack loading, the registry, and the unbound report.

The report is the project's progress meter, so what it must get right is the
DISTINCTION between three failure kinds. Conflating them would make the number
comfortable and useless:

    unbound   the pack leaves the handler empty        -> work not started
    missing   the pack names a handler we don't have   -> a typo or a rename
    orphaned  we implement a handler nothing binds to  -> dead code

Run: python3 test_content.py
"""

from __future__ import annotations

import json
import os
import sys
import tempfile

import content
from content import AbilityRegistry, ContentDb, ContentPack

FAILS: list[str] = []


def check(ok: bool, what: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", what,
                          ("  — " + detail) if detail else ""))
    if not ok:
        FAILS.append(what)
        # Under pytest, raise: check() otherwise only RECORDS a failure, so
        # `pytest oracle/` would report green while assertions fail. The
        # standalone runner still collects every failure before exiting.
        if "PYTEST_CURRENT_TEST" in os.environ:
            raise AssertionError(what)


def registry(*names) -> AbilityRegistry:
    r = AbilityRegistry()
    for n in names:
        r.register(n, lambda ctx, v, p: v)
    return r


def write_pack(tmp: str, pack_id: str, abilities: dict) -> str:
    d = os.path.join(tmp, pack_id)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "bindings.json"), "w", encoding="utf-8") as fh:
        json.dump({"pack": pack_id, "abilities": abilities}, fh, ensure_ascii=False)
    return d


def test_registry() -> None:
    print("\n[1] registry")
    r = AbilityRegistry()
    r.register("a", lambda ctx, v, p: v + 1)
    check(r.has("a") and not r.has("b"), "membership")
    check(r.call("a", {}, 1, {}) == 2, "dispatch reaches the handler")
    try:
        r.register("a", lambda ctx, v, p: v)
        check(False, "double registration is rejected")
    except ValueError:
        check(True, "double registration is rejected")


def test_report_distinguishes_failures() -> None:
    print("\n[2] the report separates unbound / missing / orphaned")
    with tempfile.TemporaryDirectory() as tmp:
        d = write_pack(tmp, "t", {
            "1": {"name": "bound", "hook": "STAT_PASSIVE", "handler": "known", "uses": 5},
            "2": {"name": "empty", "hook": "STAT_PASSIVE", "handler": "", "uses": 9},
            "3": {"name": "typo", "hook": "ON_HIT", "handler": "nonexistent", "uses": 1},
        })
        db = ContentDb.load("t", d, registry("known", "unused"))
        rep = db.report
        check(rep.total == 3, "counts every opcode", str(rep.total))
        check([o for o, _, _ in rep.unbound] == [2], "unbound: empty handler")
        check([o for o, _, _ in rep.missing] == [3], "missing: handler not implemented")
        check(rep.orphaned == ["unused"], "orphaned: implemented, bound to nothing")
        check(rep.usable == 1, "usable counts only opcodes that can actually run",
              str(rep.usable))
        check(not rep.ok, "a pack with holes is not ok")


def test_clean_pack() -> None:
    print("\n[3] a fully bound pack reports ok")
    with tempfile.TemporaryDirectory() as tmp:
        d = write_pack(tmp, "t", {
            "1": {"name": "a", "hook": "STAT_PASSIVE", "handler": "h1", "uses": 1},
            "2": {"name": "b", "hook": "ON_HIT", "handler": "h2", "uses": 1},
        })
        db = ContentDb.load("t", d, registry("h1", "h2"))
        check(db.report.ok, "ok when nothing is unbound, missing or orphaned")
        check(db.report.usable == 2, "both usable")


def test_degraded_load() -> None:
    print("\n[4] failures degrade rather than crash")
    with tempfile.TemporaryDirectory() as tmp:
        db = ContentDb.load("missing", os.path.join(tmp, "nope"), registry())
        check(db.report.errors and "not found" in db.report.errors[0],
              "an absent bindings file is an error, not an exception")
        check(not db.report.ok, "and the pack is not ok")

        d = os.path.join(tmp, "bad")
        os.makedirs(d)
        open(os.path.join(d, "bindings.json"), "w").write("{not json")
        db = ContentDb.load("bad", d, registry())
        check(bool(db.report.errors), "malformed JSON is reported, not raised")

        d = write_pack(tmp, "declared", {"1": {"name": "a", "handler": "h", "uses": 0}})
        db = ContentDb.load("wrong_id", d, registry("h"))
        check(any("declare" in e for e in db.report.errors),
              "a pack id mismatch is caught")


def test_resolve() -> None:
    print("\n[5] resolve")
    with tempfile.TemporaryDirectory() as tmp:
        d = write_pack(tmp, "t", {
            "1": {"name": "life", "handler": "stat_delta",
                  "params": {"stat": "life"}, "uses": 1},
            "2": {"name": "empty", "handler": "", "uses": 1},
            "3": {"name": "typo", "handler": "nope", "uses": 1},
        })
        db = ContentDb.load("t", d, registry("stat_delta"))
        check(db.resolve(1) == ("stat_delta", {"stat": "life"}), "bound opcode resolves")
        check(db.resolve(2) == (None, {}), "unbound resolves to nothing")
        check(db.resolve(3) == (None, {}), "missing handler resolves to nothing")
        check(db.resolve(999) == (None, {}), "unknown opcode resolves to nothing")


def test_packs_disagree() -> None:
    print("\n[6] the same opcode means different things in different packs")
    with tempfile.TemporaryDirectory() as tmp:
        a = write_pack(tmp, "genesis", {
            "30": {"name": "Иммунитет к магии", "handler": "magic_immunity", "uses": 1}})
        b = write_pack(tmp, "new_horizons", {
            "30": {"name": "Бронебойный удар", "handler": "armor_pierce", "uses": 1}})
        reg = registry("magic_immunity", "armor_pierce")
        ga = ContentDb.load("genesis", a, reg)
        gb = ContentDb.load("new_horizons", b, reg)
        check(ga.resolve(30)[0] == "magic_immunity"
              and gb.resolve(30)[0] == "armor_pierce",
              "opcode 30 dispatches differently per pack — no conditional in the rules")


def test_real_packs() -> None:
    print("\n[7] the generated skeletons")
    reg = registry("stat_delta", "grant_spell", "immunity", "resistance")
    for pack in ("genesis", "new_horizons"):
        path = os.path.join("packs", pack)
        if not os.path.exists(os.path.join(path, "bindings.json")):
            print("  SKIP  %s not generated" % pack)
            continue
        db = ContentDb.load(pack, path, reg)
        if db.report.total == 0:
            # The COMMITTED bindings.json is a skeleton that binds no opcodes;
            # real bindings are generated locally by make_bindings.py and then
            # hand-edited. With a skeleton there is no progress meter to assert
            # against, which is not a rules failure.
            print("  SKIP  %s binds no opcodes — regenerate with "
                  "tools/extract/make_bindings.py" % pack)
            continue
        rep = db.report
        check(rep.total > 0 and not rep.errors, "%s loads cleanly" % pack,
              rep.summary())
        check(rep.unbound, "%s has unbound opcodes — an honest progress meter" % pack,
              "%d unbound" % len(rep.unbound))
        check(all(uses >= 0 for _, _, uses in rep.unbound),
              "%s unbound entries carry their usage count for prioritising" % pack)


if __name__ == "__main__":
    test_registry()
    test_report_distinguishes_failures()
    test_clean_pack()
    test_degraded_load()
    test_resolve()
    test_packs_disagree()
    test_real_packs()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
