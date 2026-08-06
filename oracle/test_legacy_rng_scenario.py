#!/usr/bin/env python3
"""LegacyRng driving a real battle, not just vectors.

`oracle/test_legacy_rng.py` proves the generator matches the recovered
specification, and `tests/test_legacy_rng.gd` proves the port matches the
oracle. Neither proves the seam is actually load-bearing: a generator can pass
every vector while nothing in the battle path ever calls it.

This closes DELIB-0001's pending item "exercise LegacyRng through an end-to-end
combat or scenario path".

Run:  python3 oracle/test_legacy_rng_scenario.py
"""

from __future__ import annotations

import copy
import json
import os
import sys

import scenario
from legacy_rng import LegacyRng

FAILS: list = []

SPEC_PATH = os.path.join(os.path.dirname(__file__), "..",
                         "tests", "scenarios", "skirmish.json")


def check(ok: bool, label: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label,
                          "  — %s" % detail if detail else ""))
    if not ok:
        FAILS.append(label)
        # Under pytest, raise: check() otherwise only RECORDS a failure, so
        # `pytest oracle/` would report green while assertions fail. The
        # standalone runner still collects every failure before exiting.
        if "PYTEST_CURRENT_TEST" in os.environ:
            raise AssertionError(label)


def spec(**overrides) -> dict:
    with open(SPEC_PATH, encoding="utf-8") as fh:
        s = json.load(fh)
    s.update(overrides)
    return copy.deepcopy(s)


def test_the_seam_is_selected_by_the_spec() -> None:
    print("\n[1] the composition root selects the generator")
    native = scenario.Scenario(spec(profile="native"))
    legacy = scenario.Scenario(spec(profile="genesis"))
    check(native.profile == "native" and type(native.rng).__name__ == "Rng",
          '"profile": "native" selects named streams', type(native.rng).__name__)
    check(legacy.profile == "genesis" and isinstance(legacy.rng, LegacyRng),
          '"profile": "genesis" selects LegacyRng', type(legacy.rng).__name__)

    migration = spec()
    migration.pop("profile", None)
    migration["rng"] = "legacy"
    try:
        scenario.Scenario(migration)
    except ValueError as exc:
        check("rng" in str(exc) and "removed" in str(exc),
              'serialized "rng" selector is rejected with migration guidance',
              str(exc))
    else:
        check(False, 'serialized "rng" selector is rejected with migration guidance')

    injected = LegacyRng(12345)
    direct = scenario.Scenario(spec(profile="genesis"), rng=injected)
    check(direct.rng is injected, "direct injection overrides the spec")


def test_the_battle_actually_consumes_it() -> None:
    print("\n[2] the battle path really draws from the injected state")
    r = LegacyRng(1)
    before = r.calls
    result = scenario.Scenario(spec(profile="genesis"), rng=r).run()
    check(r.calls > before,
          "running a battle advances the injected CRT state",
          "%d advances" % (r.calls - before))
    check(result.get("log"), "and the battle produced a log")


def test_legacy_battles_are_reproducible() -> None:
    print("\n[3] same seed, same battle")
    a = scenario.Scenario(spec(profile="genesis")).run()
    b = scenario.Scenario(spec(profile="genesis")).run()
    check(a["log"] == b["log"], "identical logs from identical seeds")
    c = scenario.Scenario(spec(profile="genesis", seed=99)).run()
    check(c["log"] != a["log"], "a different seed diverges")


def test_legacy_and_native_diverge() -> None:
    print("\n[4] the two generators are genuinely different battles")
    native = scenario.Scenario(spec(profile="native")).run()
    legacy = scenario.Scenario(spec(profile="genesis")).run()
    check(native["log"] != legacy["log"],
          "so compatibility mode is observable at the battle level, "
          "not just in the generator")


def test_shared_topology_reaches_the_battle() -> None:
    """The property that forced this seam to exist, at battle scale.

    Under LegacyRng one extra draw anywhere shifts the whole battle. Under named
    streams it does not. That is the entire reason compatibility mode cannot use
    named streams, and it should be asserted where it actually bites.
    """
    print("\n[5] one extra draw shifts a legacy battle, but not a native one")
    clean = LegacyRng(1)
    disturbed = LegacyRng(1)
    disturbed.below(2)                     # as an added mod subsystem would
    a = scenario.Scenario(spec(profile="genesis"), rng=clean).run()
    b = scenario.Scenario(spec(profile="genesis"), rng=disturbed).run()
    check(a["log"] != b["log"],
          "legacy: an unrelated draw changes the battle")

    from combat import Rng
    c = scenario.Scenario(spec(profile="native"), rng=Rng(1)).run()
    d_rng = Rng(1)
    d_rng.roll(2, "loot")                  # a different named stream
    d = scenario.Scenario(spec(profile="native"), rng=d_rng).run()
    check(c["log"] == d["log"],
          "native: an unrelated stream does not")


def test_trace_records_the_battle() -> None:
    print("\n[6] the compatibility trace is usable for diffing call order")
    r = LegacyRng(1)
    r.enable_trace(True)
    scenario.Scenario(spec(profile="genesis"), rng=r).run()
    check(r.trace, "a battle produces trace entries", "%d entries" % len(r.trace))
    if r.trace:
        entry = r.trace[0]
        check(all(k in entry for k in
                  ("epoch", "consumer", "bound", "state_before",
                   "state_after", "advances", "value")),
              "each entry carries the fields LEGACY_RNG.md specifies",
              ", ".join(sorted(entry)))
        check(sum(e["advances"] for e in r.trace) == r.calls,
              "and the advance counts reconcile with the state")


def main() -> None:
    test_the_seam_is_selected_by_the_spec()
    test_the_battle_actually_consumes_it()
    test_legacy_battles_are_reproducible()
    test_legacy_and_native_diverge()
    test_shared_topology_reaches_the_battle()
    test_trace_records_the_battle()
    print("\n%s" % ("ALL PASS" if not FAILS
                    else "%d FAILURES: %s" % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
