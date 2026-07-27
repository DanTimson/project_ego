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

import json
import sys

import scenario

FAILS: list[str] = []


def check(ok: bool, what: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", what,
                          ("  — " + detail) if detail else ""))
    if not ok:
        FAILS.append(what)


SPEC = json.load(open("scenarios/skirmish.json", encoding="utf-8"))


def run(spec=None):
    return scenario.Scenario(json.loads(json.dumps(spec or SPEC))).run()


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


if __name__ == "__main__":
    test_determinism()
    test_chain()
    test_steps_feed_stamina()
    test_terrain_matters()
    test_phase_passing()
    test_illegal_commands()
    test_ammunition()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
