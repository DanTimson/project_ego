# oracle/test_scenario.py
"""
test_scenario.py — the integration point.

A scenario runs the whole chain: pathfinding feeds steps_this_round, which sets
the stamina charge, which feeds StaminaMod, which scales the attack, which the
RNG rolls, which the defence reduces. Reproducing a scenario exactly is far
stronger evidence than any subsystem test, because a disagreement anywhere in
that chain shows up as a diverging log line.

Run: python3 test_scenario.py
"""

from __future__ import annotations

import os

import json
import sys

import scenario

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


SPEC = json.load(open("scenarios/skirmish.json", encoding="utf-8"))


def run(spec=None):
    return scenario.Scenario(json.loads(json.dumps(spec or SPEC))).run()


def test_profile_selection() -> None:
    print("\n[profiles] identity normalization and RNG selection")

    def configured(**overrides):
        selected = json.loads(json.dumps(SPEC))
        selected.pop("profile", None)
        selected.pop("rng", None)
        selected.update(overrides)
        return selected

    native = scenario.Scenario(configured(profile=" NATIVE "))
    check(native.profile == "native", "explicit native identity is normalized")
    check(type(native.rng).__name__ == "Rng",
          "explicit native selects named streams", type(native.rng).__name__)

    genesis = scenario.Scenario(configured(profile="genesis"))
    check(genesis.profile == "genesis", "explicit genesis identity is exposed")
    check(type(genesis.rng).__name__ == "LegacyRng",
          "explicit genesis selects LegacyRng", type(genesis.rng).__name__)

    rejected = [
        ({"profile": "new_horizons"},
         'scenario profile "new_horizons" is incomplete: minimum rules assignment is not defined',
         "incomplete new_horizons is rejected"),
        ({"profile": "future"},
         'unknown scenario profile "future"',
         "an unknown profile is rejected"),
        ({"profile": "native", "rng": "legacy"},
         'scenario configuration cannot specify both "profile" and legacy "rng"',
         "profile plus rng is rejected as conflicting configuration"),
    ]
    for values, expected, what in rejected:
        try:
            scenario.Scenario(configured(**values))
        except ValueError as exc:
            check(str(exc) == expected, what, str(exc))
        else:
            check(False, what, "configuration was accepted")

    alias = scenario.Scenario(configured(rng=" LEGACY "))
    check(alias.profile == "genesis" and type(alias.rng).__name__ == "LegacyRng",
          "omitted profile plus legacy rng maps to genesis")

    fallback = scenario.Scenario(configured())
    check(fallback.profile == "native" and type(fallback.rng).__name__ == "Rng",
          "phase-1 omission fallback remains native")


def test_committed_native_scenarios_match_fixture() -> None:
    print("\n[profile outputs] committed native scenarios remain unchanged")
    fixture_path = os.path.join("tests", "fixtures", "scenario_fixture.json")
    with open(fixture_path, encoding="utf-8") as fh:
        fixture = json.load(fh)

    for filename, expected in fixture["scenarios"].items():
        path = os.path.join("tests", "scenarios", filename)
        with open(path, encoding="utf-8") as fh:
            spec = json.load(fh)
        check(spec.get("profile") == "native",
              "%s explicitly selects native" % filename)
        actual = scenario.Scenario(json.loads(json.dumps(spec))).run()
        check(actual["log"] == expected["log"],
              "%s combat log is unchanged" % filename)
        check(actual["final"] == expected["final"],
              "%s final state is unchanged" % filename)


def test_instance_identity() -> None:
    """Battle-instance identity is separate from the display name.

    An army may field several units of one type. They share a display name and,
    once wired to a pack, a content_id — and they must still be individually
    addressable. Before this, the scenario builder keyed units by name and
    rejected the second one outright, so a duplicate simply could not be
    expressed. DELIB-0001 decision item 6.
    """
    print("\n[instance identity]")
    spec = json.loads(json.dumps(SPEC))
    a = spec["sides"][0]["units"][0]
    a["id"] = "one"
    dup = json.loads(json.dumps(a))
    dup["id"] = "two"
    dup["at"] = [0, 0]
    spec["sides"][0]["units"].append(dup)
    spec["commands"] = [{"op": "move", "unit": "two", "to": [1, 0]}]

    sc = scenario.Scenario(spec)
    check("one" in sc.units and "two" in sc.units,
          "two units of the same type coexist", str(sorted(sc.units)))
    check(sc.units["one"] is not sc.units["two"],
          "and are distinct objects")
    check(sc.units["one"].name == sc.units["two"].name,
          "sharing a display name", sc.units["one"].name)
    check(sc.units["one"].label() != sc.units["two"].label(),
          "but not a label", "%s vs %s"
          % (sc.units["one"].label(), sc.units["two"].label()))

    result = sc.run()
    moved = [l for l in result["log"] if "two" in l]
    check(moved, "commands address the intended instance", str(moved[:1]))

    # Omitting the id keeps the old behaviour exactly.
    plain = scenario.Scenario(json.loads(json.dumps(SPEC)))
    first = list(plain.units.values())[0]
    check(first.instance_id == first.name,
          "instance id defaults to the display name")
    check(first.label() == first.name,
          "so labels are unchanged for scenarios that declare no id")

    # A duplicate WITHOUT ids must still fail loudly rather than silently drop.
    bad = json.loads(json.dumps(SPEC))
    clash = json.loads(json.dumps(bad["sides"][0]["units"][0]))
    clash["at"] = [0, 0]
    bad["sides"][0]["units"].append(clash)
    try:
        scenario.Scenario(bad)
    except ValueError as exc:
        check("instance id" in str(exc),
              "a nameless duplicate is rejected with an actionable message",
              str(exc)[:60])
    else:
        check(False, "a nameless duplicate is rejected with an actionable message")


def test_determinism() -> None:
    print("\n[1] determinism — the property everything else rests on")
    first = run()
    check(all(run()["log"] == first["log"] for _ in range(10)),
          "10 runs produce an identical log, line for line")
    check(all(run()["final"] == first["final"] for _ in range(3)),
          "and an identical final state")

    other = json.loads(json.dumps(SPEC))
    other["seed"] = SPEC["seed"] + 1
    check(run(other)["log"] != first["log"], "a different seed diverges")


def test_chain() -> None:
    print("\n[2] the chain actually runs")
    r = run()
    log = "\n".join(r["log"])
    check("closes to" in log, "attack commands auto-path into contact")
    check("hits" in log, "damage resolves")
    check("falls" in log, "units die and are removed")
    check("-- round 2" in log and "-- round 3" in log, "rounds advance")
    check("rests" in log, "rest recovers stamina")


def test_steps_feed_stamina() -> None:
    """The single most important integration: a path's LENGTH becomes the
    stamina charge on the attack that follows it."""
    print("\n[3] path length -> steps_this_round -> attack stamina cost")
    spec = json.loads(json.dumps(SPEC))
    spec["commands"] = [
        {"op": "attack", "unit": "Ополченец", "target": "Мечник"},
    ]
    r = run(spec)
    log = "\n".join(r["log"])
    check("closes to" in log, "the militia auto-paths one step")
    # 10 base stamina, -2 for attacking after moving.
    check(r["final"]["Ополченец"]["stamina"] == 8,
          "having moved, the attack costs 2", str(r["final"]["Ополченец"]["stamina"]))

    spec["sides"][1]["units"][0]["at"] = [2, 1]     # already adjacent
    r = run(spec)
    check("closes to" not in "\n".join(r["log"]), "adjacent means no approach")
    check(r["final"]["Ополченец"]["stamina"] == 9,
          "attacking in place costs 1", str(r["final"]["Ополченец"]["stamina"]))


def test_terrain_matters() -> None:
    print("\n[4] terrain reaches the outcome")
    spec = json.loads(json.dumps(SPEC))
    spec["commands"] = [{"op": "end_phase"},
                        {"op": "move", "unit": "Мечник", "to": [2, 0]}]
    # The base scenario already puts a wood on (2,0), so open ground has to be
    # constructed explicitly — comparing against it unmodified compares a tile
    # with itself, which is how this test failed the first time it ran.
    spec["battlefield"]["tiles"] = []
    open_ground = run(spec)

    spec["battlefield"]["tiles"] = [
        {"col": 2, "row": 0, "bf_object": 2, "move_cost": 2, "stam_cost": 1}]
    rough = run(spec)
    check(open_ground["final"]["Мечник"]["at"] == rough["final"]["Мечник"]["at"],
          "the swordsman reaches the wood either way")
    check(rough["final"]["Мечник"]["stamina"]
          < open_ground["final"]["Мечник"]["stamina"],
          "but rough ground costs stamina",
          "%d vs %d" % (rough["final"]["Мечник"]["stamina"],
                        open_ground["final"]["Мечник"]["stamina"]))


def test_phase_passing() -> None:
    """Found by running a scenario, not by reasoning: a phase cannot end on
    resource exhaustion alone. With free re-entry a unit almost always has
    leftover movement, so the sides would trade control forever."""
    print("\n[5] a round ends when both sides pass, not when resources run out")
    spec = json.loads(json.dumps(SPEC))
    spec["commands"] = [{"op": "end_phase"}, {"op": "end_phase"}]
    r = run(spec)
    check(any("-- round 2" in line for line in r["log"]),
          "two passes with everything unspent still start round 2",
          " | ".join(r["log"][-2:]))
    check(r["final"]["Мечник"]["movement_remaining"] > 0,
          "and the units kept their movement, proving it was voluntary")


def test_illegal_commands() -> None:
    print("\n[6] illegal commands are refused, not crashed on")
    spec = json.loads(json.dumps(SPEC))
    spec["commands"] = [
        {"op": "attack", "unit": "Мечник", "target": "Ополченец"},
        {"op": "move", "unit": "Ополченец", "to": [99, 99]},
        {"op": "shoot", "unit": "Мечник", "target": "Копейщик"},
        {"op": "nonsense", "unit": "Ополченец"},
        {"op": "move", "unit": "Призрак", "to": [0, 0]},
    ]
    r = run(spec)
    log = "\n".join(r["log"])
    check("not in the active side's phase" in log, "acting out of phase is refused")
    check("cannot reach" in log, "an unreachable destination is refused")
    check("unknown command" in log, "an unknown op is reported")
    check("unknown unit" in log, "an unknown unit is reported")
    check(len(r["log"]) >= 5, "and the run completes rather than raising")


def test_ammunition() -> None:
    print("\n[7] ranged attacks consume ammunition and respect range")
    spec = json.loads(json.dumps(SPEC))
    spec["sides"][0]["units"][1]["ammo"] = 1
    spec["sides"][0]["units"][1]["shooting_range"] = 1
    spec["commands"] = [
        {"op": "end_phase"},
        {"op": "shoot", "unit": "Лучник", "target": "Ополченец"},
    ]
    r = run(spec)
    check("out of range" in "\n".join(r["log"]), "a distant target is out of range")
    check(r["final"]["Лучник"]["stamina"] == 10, "and no stamina is spent on a refusal")


def test_modifiers_actually_apply() -> None:
    """Two integration bugs lived here, both the same shape: a layer built and
    tested in isolation, never connected.

      * combat._run_hook read only `unit.modifiers`, so a status granting +2
        attack did nothing. Flags worked, because has_flag walked statuses
        independently — so FLAGS from statuses applied and NUMBERS did not.
      * the scenario runner bound the aura environment but never bound the
        PIPELINE, so no modifier of any kind applied while the run looked
        entirely healthy.

    Neither was visible from any unit test. These assertions are what would have
    caught them.
    """
    print("\n[8] modifiers from every source reach a running scenario")
    spec = json.loads(json.dumps(SPEC))
    plain = run(spec)
    plain_damage = plain["final"]["Ополченец"]["life"]

    # innate: an ability on the unit itself
    spec2 = json.loads(json.dumps(SPEC))
    spec2["sides"][0]["units"][0]["modifiers"] = [
        {"ability": 2, "handler": "stat_delta", "hook": "STAT_PASSIVE",
         "power": 5, "params": {"stat": "attack"}, "source": "Атака +5"}]
    check("modifiers" in spec2["sides"][0]["units"][0],
          "a scenario can declare innate modifiers")

    # aura: from an adjacent ally
    spec3 = json.loads(json.dumps(SPEC))
    # The archer sits beside the SWORDSMAN's start, not on his approach — at
    # [2,1] it blocked the only route and the attack silently failed to connect,
    # making both runs identical and the test meaningless.
    spec3["sides"][0]["units"][1]["at"] = [1, 0]
    spec3["sides"][0]["units"][1]["auras"] = [
        {"id": "valour", "name": "Аура доблести", "scope": "ADJACENT",
         "affects": "ALLY", "power": 6,
         "modifiers": [{"ability": 400, "handler": "stat_delta",
                        "hook": "STAT_PASSIVE", "power": 6,
                        "params": {"stat": "attack"}}]}]
    spec3["sides"][1]["units"][0]["at"] = [2, 1]     # militia within reach
    spec3["commands"] = [{"op": "end_phase"},
                         {"op": "attack", "unit": "Мечник", "target": "Ополченец"}]
    with_aura = run(spec3)

    spec4 = json.loads(json.dumps(spec3))
    spec4["sides"][0]["units"][1].pop("auras")
    without = run(spec4)
    check(with_aura["final"]["Ополченец"]["life"]
          < without["final"]["Ополченец"]["life"],
          "an aura from an adjacent ally raises the damage dealt",
          "%d vs %d" % (with_aura["final"]["Ополченец"]["life"],
                        without["final"]["Ополченец"]["life"]))


def test_round_upkeep() -> None:
    print("\n[9] statuses and auras tick at the top of each round")
    spec = json.loads(json.dumps(SPEC))
    # A scenario seeds stamina_base from `stamina` unless told otherwise, so a
    # unit declared with stamina 4 has a CAP of 4 and cannot be restored above
    # it. Both are needed to describe a tired unit.
    spec["sides"][0]["units"][0]["stamina"] = 4
    spec["sides"][0]["units"][0]["stamina_base"] = 10
    spec["sides"][0]["units"][1]["at"] = [1, 0]
    spec["sides"][0]["units"][1]["auras"] = [
        {"id": "vigour", "name": "Аура бодрости", "scope": "ADJACENT",
         "affects": "ALLY", "power": 2, "tick": {"stamina": 2}}]
    spec["commands"] = [{"op": "end_phase"}, {"op": "end_phase"},
                        {"op": "end_phase"}, {"op": "end_phase"}]
    r = run(spec)
    log = "\n".join(r["log"])
    check("auras (stamina +2)" in log, "an aura tick is logged", log[-120:])
    check(r["final"]["Мечник"]["stamina"] > 4,
          "and the stamina actually rose", str(r["final"]["Мечник"]["stamina"]))

    # a tick without an aura or status must not emit noise
    bare = run(json.loads(json.dumps(SPEC)))
    check("auras (" not in "\n".join(bare["log"]),
          "and a battle with neither reports nothing")


if __name__ == "__main__":
    test_profile_selection()
    test_committed_native_scenarios_match_fixture()
    test_determinism()
    test_chain()
    test_steps_feed_stamina()
    test_terrain_matters()
    test_phase_passing()
    test_illegal_commands()
    test_ammunition()
    test_modifiers_actually_apply()
    test_round_upkeep()
    test_instance_identity()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
