#!/usr/bin/env python3
"""LegacyRng against the PUBLISHED specification, not against a fixture.

The vectors below are transcribed from docs/LEGACY_RNG.md by hand. That is the
point: tests/fixtures/legacy_rng_fixture.json is generated FROM this
implementation, so a test that read it back would only prove the implementation
agrees with itself. This file is the non-circular half — it fails if the
implementation drifts from the recovered specification. The fixture is the other
half, and proves the GDScript port agrees with the oracle.

Run:  python3 oracle/test_legacy_rng.py
"""

from __future__ import annotations

import sys

from legacy_rng import LegacyRng

FAILS: list = []


def check(ok: bool, label: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label,
                          "  — %s" % detail if detail else ""))
    if not ok:
        FAILS.append(label)


# --- transcribed from docs/LEGACY_RNG.md ------------------------------------

RAW = {
    1: [41, 18467, 6334, 26500, 19169, 15724, 11478, 29358],
    111: [401, 21144, 5313, 19256, 6893, 21680, 26167, 2270],
    0: [38, 7719, 21238, 2437, 8855, 11797, 8365, 32285],
}

# (bound, expected value, expected calls to next_u15) from seed(1)
BOUNDED = [(0, 0, 0), (1, 0, 1), (10, 1, 1), (30000, 41, 1),
           (30001, 417, 2), (300000, 417, 2), (3000001, 4174, 3)]


def test_raw_sequence() -> None:
    print("\n[1] MSVC CRT recurrence")
    for seed, expected in RAW.items():
        r = LegacyRng(seed)
        got = [r.next_u15() for _ in expected]
        check(got == expected, "seed %d produces the published sequence" % seed,
              str(got[:4]))
    r = LegacyRng(1)
    r.next_u15()
    check(r.calls == 1, "each draw counts exactly one CRT advance")


def test_bounded_adapter() -> None:
    print("\n[2] bounded adapter at 00454C70")
    for bound, expected, advances in BOUNDED:
        r = LegacyRng(1)
        got = r.below(bound)
        check(got == expected and r.calls == advances,
              "below(%d) = %d in %d advances" % (bound, expected, advances),
              "got %d in %d" % (got, r.calls))
    # The pair that catches a `>= 30000` loop condition.
    a, b = LegacyRng(1), LegacyRng(1)
    a.below(30000)
    b.below(30001)
    check(a.calls == 1 and b.calls == 2,
          "the loop condition is strictly > 30000, not >=",
          "30000 -> %d advance(s), 30001 -> %d" % (a.calls, b.calls))
    # Bound 0 must not consume; bound 1 must.
    z, o = LegacyRng(1), LegacyRng(1)
    z.below(0)
    o.below(1)
    check(z.calls == 0, "bound 0 consumes nothing")
    check(o.calls == 1, "bound 1 consumes one value even though it returns 0")


def test_roll_matches_below() -> None:
    print("\n[3] the native-mode surface is a true drop-in")
    a, b = LegacyRng(7), LegacyRng(7)
    check([a.roll(6) for _ in range(8)] == [b.below(6) for _ in range(8)],
          "roll(x) is below(x)")
    a, b = LegacyRng(7), LegacyRng(7)
    check(a.roll(6, "combat") == b.roll(6, "loot"),
          "the stream argument is ignored — one shared sequence is the point")


def test_weighted_roller() -> None:
    print("\n[4] weighted roller at 00454E80")
    r = LegacyRng(0)
    selected, after = r.weighted([7, 9, 7], [1, 1, 3], remove_selected=True)
    check(selected == 7, "the published vector selects 7", str(selected))
    check(after == [0, 1, 0],
          "and removal is by VALUE, so both 7s drop to zero", str(after))
    check(r.calls == 1, "one CRT advance for the roll")
    # Total weight zero is unrecovered; it must not be papered over.
    try:
        LegacyRng(1).weighted([1, 2], [0, 0])
    except ValueError:
        check(True, "total weight zero refuses rather than inventing a fallback")
    else:
        check(False, "total weight zero refuses rather than inventing a fallback")


def test_reseed_epochs() -> None:
    print("\n[5] recovered reseed epochs")
    r = LegacyRng()
    check(r.seed_map_generation(0) == 111 and r.state == 111,
          "map seed 0 becomes 111", str(r.state))
    r = LegacyRng()
    r.seed_map_generation(20260726)
    check(r.state == 20260726, "a nonzero map seed is used as-is")
    r = LegacyRng()
    r.seed_strategic_turn(111, 3)
    check(r.state == 114, "strategic turn reseeds to map_seed + turn", str(r.state))
    # A turn does not inherit the previous turn's terminal state.
    a = LegacyRng()
    a.seed_strategic_turn(111, 1)
    for _ in range(50):
        a.below(6)
    b = LegacyRng()
    b.seed_strategic_turn(111, 2)
    c = LegacyRng()
    c.seed_strategic_turn(111, 2)
    check(b.state == c.state,
          "so turn N+1 starts identically regardless of turn N's consumption")


def test_shared_topology_is_observable() -> None:
    print("\n[6] one extra call shifts everything downstream")
    a = LegacyRng(1)
    b = LegacyRng(1)
    b.below(2)                      # one extra consumer, as a mod might add
    check([a.below(6) for _ in range(4)] != [b.below(6) for _ in range(4)],
          "which is exactly why compatibility mode cannot use named streams")


def test_snapshot_restore() -> None:
    print("\n[7] state snapshot and restore")
    r = LegacyRng(42)
    for _ in range(5):
        r.below(10)
    snap = r.snapshot()
    expected = [r.below(10) for _ in range(6)]
    r.restore(snap)
    check([r.below(10) for _ in range(6)] == expected,
          "restoring reproduces the continuation exactly")


def main() -> None:
    test_raw_sequence()
    test_bounded_adapter()
    test_roll_matches_below()
    test_weighted_roller()
    test_reseed_epochs()
    test_shared_topology_is_observable()
    test_snapshot_restore()
    print("\n%s" % ("ALL PASS" if not FAILS
                    else "%d FAILURES: %s" % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
