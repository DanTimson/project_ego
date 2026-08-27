# oracle/test_scenario.py
"""
test_scenario.py — the integration point.

A scenario runs the whole chain: pathfinding updates live capacity and captures
command-entry position, the composed profile supplies primary-melee charge;
stamina scales the ordinary attack, the RNG rolls it, defence reduces it, then
charge is added. Reproducing
a scenario exactly is far stronger evidence than any subsystem test, because a
disagreement anywhere in that chain shows up as a diverging log line.

Run: python3 test_scenario.py
"""

from __future__ import annotations

import os

import json
import sys

import charge
import content
import scenario
import turn
from combat import Rng

FAILS: list[str] = []


class MaxRollRng:
    def roll(self, x: int, stream: str = "combat") -> int:
        return max(0, x - 1)


def trace_index(lines: list[str], fragment: str) -> int:
    return next((i for i, line in enumerate(lines) if fragment in line), -1)


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


def profile_combat_spec(profile="genesis", attacker_at=(0, 0),
                        target_at=(4, 0), *, charge_modifier=True) -> dict:
    attacker = {
        "name": "attacker", "at": list(attacker_at),
        "attack": 10, "ranged_attack": 10, "shooting_range": 8,
        "ammo": 3, "counter_attack": 0, "defence": 0,
        "ranged_defence": 0, "life": 100, "stamina": 10,
        "stamina_base": 10, "morale": 10, "speed": 8,
    }
    if charge_modifier:
        # The handler is deliberately inert: 0x25 applicability is resolved at
        # the Genesis composition seam, not by a generic damage hook.
        attacker["modifiers"] = [{
            "ability": 0x25, "handler": "genesis_charge",
            "hook": "DAMAGE_VS_TARGET", "source": "charge",
        }]
    target = {
        "name": "target", "at": list(target_at),
        "attack": 0, "counter_attack": 0, "defence": 0,
        "ranged_defence": 0, "life": 100, "stamina": 10,
        "morale": 10, "speed": 1,
    }
    return {
        "name": "combat profile integration", "profile": profile, "seed": 1,
        "battlefield": {"width": 8, "height": 3, "tiles": []},
        "sides": [
            {"id": 0, "is_attacker": True, "leader_initiative": 1,
             "units": [attacker]},
            {"id": 1, "leader_initiative": 0, "units": [target]},
        ],
        "commands": [{"op": "attack", "unit": "attacker",
                      "target": "target"}],
    }


def run_profile_combat(spec: dict) -> dict:
    # One injected named-stream generator isolates profile charge policy from
    # the independently profile-selected RNG topology.
    return scenario.Scenario(json.loads(json.dumps(spec)), rng=Rng(123)).run()


def with_charge_aura(spec: dict, source_at: tuple[int, int]) -> dict:
    """Grant 0x25 only while the attacker is adjacent to an aura source."""
    spec["sides"][0]["units"].append({
        "name": "charge aura source", "at": list(source_at),
        "attack": 0, "counter_attack": 0, "defence": 0,
        "ranged_defence": 0, "life": 100, "stamina": 10,
        "stamina_base": 10, "morale": 10, "speed": 0,
        "auras": [{
            "id": "charge-aura", "scope": "ADJACENT", "affects": "ALLY",
            "stacking": "MAXIMUM",
            "modifiers": [{
                "ability": 0x25, "handler": "genesis_charge",
                "hook": "DAMAGE_VS_TARGET",
            }],
        }],
    })
    return spec


def test_profile_selection() -> None:
    print("\n[profiles] strict identity and RNG selection")

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
        ({},
         'scenario configuration requires explicit "profile"; the omitted-profile native fallback was removed',
         "missing profile is rejected"),
        ({"rng": "legacy"},
         'scenario configuration key "rng" was removed; use explicit "profile" ("genesis" for LegacyRng or "native" for named streams)',
         "old rng key is rejected with migration guidance"),
        ({"profile": "native", "rng": "legacy"},
         'scenario configuration key "rng" was removed; use explicit "profile" ("genesis" for LegacyRng or "native" for named streams)',
         "rng is rejected even alongside a profile"),
        ({"profile": "new_horizons"},
         'scenario profile "new_horizons" is incomplete: minimum rules assignment is not defined',
         "incomplete new_horizons is rejected"),
        ({"profile": "future"},
         'unknown scenario profile "future"',
         "an unknown profile is rejected"),
    ]
    for values, expected, what in rejected:
        try:
            scenario.Scenario(configured(**values))
        except ValueError as exc:
            check(str(exc) == expected, what, str(exc))
        else:
            check(False, what, "configuration was accepted")

    injected = object()
    direct = scenario.Scenario(configured(profile="genesis"), rng=injected)
    check(direct.rng is injected,
          "direct RNG dependency injection remains supported")


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
    """The common movement path lowers live capacity before an attack."""
    print("\n[3] movement capacity -> attack stamina cost")
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


def test_genesis_command_entry_charge() -> None:
    print("\n[R3] Genesis command-entry charge")

    adjacent = profile_combat_spec(attacker_at=(3, 0), target_at=(4, 0))
    adjacent_plain = profile_combat_spec(
        attacker_at=(3, 0), target_at=(4, 0), charge_modifier=False)
    no_move = run_profile_combat(adjacent)
    no_move_plain = run_profile_combat(adjacent_plain)
    check(no_move["final"]["target"]["life"]
          == no_move_plain["final"]["target"]["life"],
          "a no-movement attack receives zero charge")

    # Zero is still a RESOLVED Genesis charge value, not absence of the R3
    # consumer. Its combined-damage path caps the ordinary blow to current life;
    # native supplies None and retains its uncapped ordinary-damage accounting.
    genesis_cap = profile_combat_spec(
        profile="genesis", attacker_at=(3, 0), target_at=(4, 0))
    genesis_cap["sides"][1]["units"][0]["life"] = 3
    native_uncapped = profile_combat_spec(
        profile="native", attacker_at=(3, 0), target_at=(4, 0))
    native_uncapped["sides"][1]["units"][0]["life"] = 3
    genesis_cap_result = run_profile_combat(genesis_cap)
    native_uncapped_result = run_profile_combat(native_uncapped)
    check("hits target for 3" in "\n".join(genesis_cap_result["log"]),
          "resolved zero charge still uses Genesis combined/current-life cap")
    check("hits target for 9" in "\n".join(native_uncapped_result["log"]),
          "native zero-charge absence retains ordinary uncapped accounting")

    ordinary = profile_combat_spec(attacker_at=(0, 0), target_at=(4, 0))
    ordinary_plain = profile_combat_spec(
        attacker_at=(0, 0), target_at=(4, 0), charge_modifier=False)
    charged = run_profile_combat(ordinary)
    plain = run_profile_combat(ordinary_plain)
    check(charge.command_entry_charge((0, 0), (4, 0), True) == 2,
          "ordinary command-entry distance computes max(L1 - 2, 0)")
    check("closes to" in "\n".join(charged["log"]),
          "the charged command performs automatic approach movement")
    check(charged["final"]["target"]["life"]
          < plain["final"]["target"]["life"],
          "the pre-approach coordinates survive into the primary attack",
          "%d vs %d" % (charged["final"]["target"]["life"],
                         plain["final"]["target"]["life"]))

    # Existing adjacency-aura machinery makes applicability change across the
    # automatic approach without a production-only test hook.
    entry_aura_spec = with_charge_aura(profile_combat_spec(
        attacker_at=(0, 0), target_at=(4, 0), charge_modifier=False), (0, 1))
    entry_aura = scenario.Scenario(
        json.loads(json.dumps(entry_aura_spec)), rng=Rng(123))
    entry_attacker = entry_aura.units["attacker"]
    check(any(m.ability == 0x25 for m in entry_aura.environment(entry_attacker)),
          "0x25 is effective at command entry through an adjacent aura")
    entry_result = entry_aura.run()
    check(not any(m.ability == 0x25
                  for m in entry_aura.environment(entry_attacker)),
          "the entry aura is no longer effective after automatic approach")
    check(entry_result["final"]["target"]["life"]
          == charged["final"]["target"]["life"],
          "entry-only 0x25 still supplies charge before movement",
          "%d vs charged control %d" % (
              entry_result["final"]["target"]["life"],
              charged["final"]["target"]["life"]))

    exit_aura_spec = with_charge_aura(profile_combat_spec(
        attacker_at=(0, 0), target_at=(4, 0), charge_modifier=False), (3, 1))
    exit_aura = scenario.Scenario(
        json.loads(json.dumps(exit_aura_spec)), rng=Rng(123))
    exit_attacker = exit_aura.units["attacker"]
    check(not any(m.ability == 0x25
                  for m in exit_aura.environment(exit_attacker)),
          "0x25 is absent at command entry in the inverse aura vector")
    exit_result = exit_aura.run()
    check(any(m.ability == 0x25 for m in exit_aura.environment(exit_attacker)),
          "0x25 becomes effective only after automatic approach")
    check(exit_result["final"]["target"]["life"]
          == plain["final"]["target"]["life"],
          "post-approach-only 0x25 cannot retroactively supply charge",
          "%d vs plain control %d" % (
              exit_result["final"]["target"]["life"],
              plain["final"]["target"]["life"]))

    prior = profile_combat_spec(attacker_at=(1, 0), target_at=(4, 0))
    prior["commands"] = [
        {"op": "move", "unit": "attacker", "to": [0, 0]},
        {"op": "move", "unit": "attacker", "to": [1, 0]},
        {"op": "attack", "unit": "attacker", "target": "target"},
    ]
    prior_result = run_profile_combat(prior)
    same_entry = run_profile_combat(
        profile_combat_spec(attacker_at=(1, 0), target_at=(4, 0)))
    check(prior_result["final"]["attacker"]["steps_this_round"]
          > same_entry["final"]["attacker"]["steps_this_round"],
          "move-away-and-back accumulates diagnostic path steps")
    check(prior_result["final"]["target"]["life"]
          == same_entry["final"]["target"]["life"],
          "but prior path length does not accumulate Genesis charge")

    split = profile_combat_spec(attacker_at=(0, 0), target_at=(5, 0))
    split["commands"] = [
        {"op": "move", "unit": "attacker", "to": [1, 0]},
        {"op": "extra_turn", "unit": "attacker"},
        {"op": "attack", "unit": "attacker", "target": "target"},
    ]
    split_result = run_profile_combat(split)
    split_control = run_profile_combat(
        profile_combat_spec(attacker_at=(1, 0), target_at=(5, 0)))
    check(split_result["final"]["attacker"]["steps_this_round"]
          > split_control["final"]["attacker"]["steps_this_round"],
          "split activation preserves diagnostic prior movement")
    check(split_result["final"]["target"]["life"]
          == split_control["final"]["target"]["life"],
          "split activation recomputes charge from its command-entry tile")

    native = profile_combat_spec(
        profile="native", attacker_at=(0, 0), target_at=(4, 0))
    native_result = run_profile_combat(native)
    check(native_result["final"]["target"]["life"]
          == plain["final"]["target"]["life"],
          "the native counterpart receives no charge")


def test_genesis_r8_live_capacity_integration() -> None:
    print("\n[R8] Genesis live-capacity attack stamina")
    spec = profile_combat_spec(
        attacker_at=(0, 0), target_at=(4, 0), charge_modifier=False)
    attacker = spec["sides"][0]["units"][0]
    attacker.update({"speed": 4, "stamina": 5, "stamina_base": 5})
    spec["battlefield"]["tiles"] = [
        {"col": 1, "row": 0, "stam_cost": 2}]
    spec["commands"] = [
        {"op": "move", "unit": "attacker", "to": [1, 0]},
        {"op": "shoot", "unit": "attacker", "target": "target"},
    ]
    result = run_profile_combat(spec)
    final = result["final"]["attacker"]
    check(final["steps_this_round"] == 1,
          "the R8 vector has movement history")
    check(final["movement_remaining"] == 0,
          "the ranged executor clears capacity after comparing live value 3")
    check(trace_index(result["log"], "effective speed 3") >= 0,
          "the pre-clear capacity/effective-speed comparison is trace-visible")
    check(final["stamina"] == 2,
          "strict live-capacity comparison charges 1, not history-based 2",
          "final stamina %d (history rule would leave 1)" % final["stamina"])

    restored = profile_combat_spec(
        attacker_at=(0, 0), target_at=(4, 0), charge_modifier=False)
    restored_attacker = restored["sides"][0]["units"][0]
    restored_attacker.update({"speed": 4, "stamina": 10,
                              "stamina_base": 10})
    restored["commands"] = [
        {"op": "move", "unit": "attacker", "to": [1, 0]},
        {"op": "extra_turn", "unit": "attacker"},
        {"op": "shoot", "unit": "attacker", "target": "target"},
    ]
    restored_run = run_profile_combat(restored)
    restored_result = restored_run["final"]["attacker"]
    check(restored_result["steps_this_round"] == 1
          and restored_result["movement_remaining"] == 0,
          "restored live capacity is compared, then ranged execution clears it")
    check(trace_index(restored_run["log"], "effective speed 4") >= 0,
          "restored capacity comparison survives reselection and is traced")
    check(restored_result["stamina"] == 9,
          "restored capacity costs 1 despite nonzero movement history")


def numeric_modifier(ability: int, stat: str = "", power: int = 0) -> dict:
    modifier = {
        "ability": ability, "handler": "modifier_%02x" % ability,
        "hook": "DAMAGE_VS_TARGET", "power": power,
        "source": "modifier %02x" % ability,
    }
    if stat:
        modifier.update({"handler": "stat_delta", "hook": "STAT_PASSIVE",
                         "params": {"stat": stat}})
    return modifier


def test_melee_numeric_tranche_integration() -> None:
    print("\n[integration] melee R3/R9/R10 ordering and live state")
    spec = {
        "name": "numeric melee integration", "profile": "genesis", "seed": 1,
        "battlefield": {"width": 8, "height": 3, "tiles": []},
        "sides": [
            {"id": 0, "is_attacker": True, "leader_initiative": 1,
             "units": [{
                 "name": "attacker", "at": [0, 0], "attack": 9,
                 "counter_attack": 0, "defence": 0, "life": 30,
                 "stamina": 10, "stamina_base": 10, "morale": 10,
                 "speed": 8, "conditional_bonus": 5,
                 "modifiers": [numeric_modifier(0x25)],
             }]},
            {"id": 1, "leader_initiative": 0, "units": [{
                "name": "target", "at": [4, 0], "attack": 0,
                "counter_attack": 0, "defence": 3, "life": 30,
                "stamina": 0, "morale": 10, "speed": 1,
                "modifiers": [numeric_modifier(4, "defence", 4)],
            }]},
        ],
        "commands": [{"op": "attack", "unit": "attacker",
                      "target": "target"}],
    }
    result = scenario.Scenario(spec, rng=MaxRollRng()).run()
    lines = result["log"]
    entry = trace_index(lines, "command-entry charge |")
    movement = trace_index(lines, "closes to")
    conditional = trace_index(lines, "conditional attack contribution")
    randomisation = trace_index(lines, "attack randomisation")
    provider = trace_index(lines, "defence provider total")
    halving = trace_index(lines, "zero-stamina defence halving")
    subtraction = trace_index(lines, "defence subtraction")
    consumption = trace_index(lines, "command-entry charge consumption")
    check(result["final"]["target"]["life"] == 19,
          "exact target life is 30 - (9 resolved + 2 charge) = 19")
    check(0 <= entry < movement,
          "modifier 0x25 applicability and value are traced before approach")
    check(conditional < randomisation < provider < halving < subtraction < consumption,
          "R10 -> randomisation -> R9 -> defence -> R3 consumption is trace-visible")
    check("value 2" in lines[entry],
          "command-entry trace records charge value 2")


def ranged_numeric_spec(base_ranged_attack: int = 20,
                        later_environment_provider: bool = False) -> dict:
    spec = {
        "name": "numeric ranged integration", "profile": "genesis", "seed": 1,
        "battlefield": {"width": 8, "height": 3,
                        "tiles": [{"col": 1, "row": 0, "stam_cost": 2}]},
        "sides": [
            {"id": 0, "is_attacker": True, "leader_initiative": 1,
             "units": [{
                 "name": "shooter", "at": [0, 0],
                 "ranged_attack": base_ranged_attack, "shooting_range": 8,
                 "ammo": 2, "counter_attack": 0, "defence": 0, "life": 30,
                 "stamina": 0, "stamina_base": 10, "morale": 10, "speed": 4,
                 "conditional_bonus": 5,
                 "modifiers": [numeric_modifier(0x12)],
             }]},
            {"id": 1, "leader_initiative": 0, "units": [{
                "name": "target", "at": [3, 0], "counter_attack": 0,
                "ranged_defence": 3, "life": 20, "stamina": 0,
                "morale": 10, "speed": 1,
                "modifiers": [numeric_modifier(5, "ranged_defence", 4)],
            }]},
        ],
        "commands": [
            {"op": "move", "unit": "shooter", "to": [1, 0]},
            {"op": "shoot", "unit": "shooter", "target": "target"},
        ],
    }
    if later_environment_provider:
        spec["sides"][0]["units"][0]["auras"] = [{
            "id": "later-ranged-provider", "name": "later ranged provider",
            "scope": "SELF", "affects": "ALLY",
            "modifiers": [numeric_modifier(2, "ranged_attack", 6)],
        }]
    return spec


def test_ranged_numeric_tranche_integration() -> None:
    print("\n[integration] ranged R6/R8/R9/R11 ordering and live state")
    result = scenario.Scenario(ranged_numeric_spec(), rng=MaxRollRng()).run()
    lines = result["log"]
    shooter = result["final"]["shooter"]
    check(result["final"]["target"]["life"] == 16,
          "zero-stamina attack 8 randomises to 7, then R9 defence 3 gives 4 damage")
    check(shooter["stamina"] == 0 and shooter["movement_remaining"] == 0
          and shooter["steps_this_round"] == 1 and shooter["action_spent"],
          "modifier 0x12 preserves stamina while ranged execution ends activation")
    discriminator = trace_index(lines, "live-capacity stamina discriminator")
    check(discriminator >= 0 and "effective speed 2" in lines[discriminator]
          and "selected base cost 2" in lines[discriminator],
          "R8 traces capacity 1 < effective speed 2 and selects cost 2")
    check(trace_index(lines, "modifier 0x12 stamina mutation suppression") >= 0,
          "R11 suppression is visible at covered mutation sites")
    check(trace_index(lines, "defence provider total: 7 -> 7") >= 0
          and trace_index(lines, "zero-stamina defence halving: 7 -> 3") >= 0,
          "R9 ranged providers precede exact-zero halving")
    check(trace_index(lines, "conditional attack contribution") == -1,
          "the conditional numeric stage is excluded from ranged")

    zero_scenario = scenario.Scenario(
        ranged_numeric_spec(0, later_environment_provider=True), rng=MaxRollRng())
    later = zero_scenario.environment(zero_scenario.units["shooter"])
    check(any(m.power == 6 and m.params.get("stat") == "ranged_attack"
              for m in later),
          "distinguishing vector has a positive environment/aura provider")
    zero = zero_scenario.run()
    check(zero["final"]["target"]["life"] == 20,
          "R6 zero early sum returns before the positive later provider")
    check(trace_index(zero["log"], "ranged early provider total: 0 -> 0") >= 0
          and trace_index(zero["log"], "later ranged provider") == -1,
          "trace shows the accepted early cutoff without resolving the aura")


def test_cx012_one_shot_channel_integration() -> None:
    print("\n[CX-012] one-shot resistance/channel integration")
    spec = {
        "name": "CX-012 one-shot channel integration", "profile": "native", "seed": 9,
        "battlefield": {"width": 8, "height": 3, "tiles": []},
        "sides": [
            {"id": 0, "is_attacker": True, "leader_initiative": 1,
             "units": [{
                 "name": "shooter", "at": [0, 0], "ranged_attack": 20,
                 "shooting_range": 8, "ammo": 2, "counter_attack": 0,
                 "life": 30, "stamina": 10, "stamina_base": 10,
                 "morale": 10, "speed": 4,
                 "modifiers": [numeric_modifier(0x1C, power=1),
                               numeric_modifier(0x5F, power=3)],
             }]},
            {"id": 1, "leader_initiative": 0, "units": [{
                "name": "target", "at": [4, 0], "counter_attack": 0,
                "ranged_defence": 2, "resist": 7, "life": 30,
                "stamina": 10, "morale": 10, "speed": 1,
            }]},
        ],
        "commands": [
            {"op": "move", "unit": "shooter", "to": [1, 0]},
            {"op": "shoot", "unit": "shooter", "target": "target"},
        ],
    }
    battle = scenario.Scenario(spec, rng=MaxRollRng())
    result = battle.run()
    shooter = battle.units["shooter"]
    target = battle.units["target"]
    lines = result["log"]
    discriminator = trace_index(lines, "live-capacity stamina discriminator")
    capacity_clear = trace_index(lines, "ranged activation capacity clear")
    check(shooter.ammo == 1, "one successful cmd_shoot consumes exactly one ammo")
    check(target.life == 18 and target.damage_received == [0, 0, 12, 0],
          "0x1C + 0x5F resolves 16 - (7 - 3) once through channel 2")
    check(shooter.stamina == 8 and shooter.action_spent
          and shooter.movement_remaining == 0,
          "R8 cost 2 is applied and successful ranged resolution is terminal")
    check(0 <= discriminator < capacity_clear,
          "R8 live-capacity selection precedes CX-009 terminal clearing")
    check(trace_index(lines, "modifier 0x5F resistance subtraction")
          < trace_index(lines, "defence subtraction")
          < trace_index(lines, "ranged received-damage channel"),
          "resistance subtraction, resolver and channel decision are trace-visible")


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


def test_action_terminality() -> None:
    print("\n[CX-009] terminal actions close only their actor's activation")

    def fighter(name: str, at: list[int], **overrides) -> dict:
        unit = {
            "name": name, "at": at, "attack": 8, "ranged_attack": 8,
            "shooting_range": 8, "ammo": 2, "counter_attack": 3,
            "defence": 0, "ranged_defence": 0, "life": 40,
            "stamina": 10, "stamina_base": 10, "morale": 10, "speed": 5,
        }
        unit.update(overrides)
        return unit

    melee_spec = {
        "name": "melee terminality", "profile": "native", "seed": 9,
        "battlefield": {"width": 7, "height": 3, "tiles": []},
        "sides": [
            {"id": 0, "is_attacker": True, "leader_initiative": 2,
             "units": [fighter("actor", [0, 0]), fighter("ally", [0, 2])]},
            {"id": 1, "leader_initiative": 1,
             "units": [fighter("defender", [3, 0], attack=1)]},
        ],
        "commands": [
            {"op": "move", "unit": "actor", "to": [1, 0]},
            {"op": "attack", "unit": "actor", "target": "defender"},
            {"op": "move", "unit": "actor", "to": [0, 0]},
            {"op": "attack", "unit": "actor", "target": "defender"},
        ],
    }
    melee = scenario.Scenario(melee_spec)
    melee_result = melee.run()
    actor = melee.units["actor"]
    ally = melee.units["ally"]
    defender = melee.units["defender"]
    check(actor.action_spent and actor.movement_remaining > 0
          and not turn.has_resources(actor),
          "move -> melee is terminal despite leftover movement")
    check(melee.state.active_side == 0 and turn.has_resources(ally),
          "melee ends only its actor; the same side's ally remains eligible")
    check(not defender.action_spent and turn.has_resources(defender),
          "the defender's counterattack does not spend its activation")
    check(sum("actor has already acted" in line for line in melee_result["log"]) == 1
          and "actor cannot reach 0,0" in "\n".join(melee_result["log"]),
          "movement and a second attack are refused after terminal melee")

    refused_spec = json.loads(json.dumps(melee_spec))
    refused_spec["sides"][0]["units"] = [fighter("actor", [0, 0], speed=1),
                                           fighter("ally", [0, 2])]
    refused_spec["sides"][1]["units"] = [fighter("defender", [6, 0])]
    refused_spec["commands"] = [
        {"op": "attack", "unit": "actor", "target": "defender"}]
    refused = scenario.Scenario(refused_spec)
    refused_result = refused.run()
    check("cannot reach" in "\n".join(refused_result["log"])
          and not refused.units["actor"].action_spent,
          "an unreachable melee refusal is non-terminal")

    ranged_spec = json.loads(json.dumps(melee_spec))
    ranged_spec["name"] = "ranged terminality"
    ranged_spec["sides"][1]["units"][0]["at"] = [5, 0]
    ranged_spec["commands"] = [
        {"op": "move", "unit": "actor", "to": [1, 0]},
        {"op": "shoot", "unit": "actor", "target": "defender"},
        {"op": "shoot", "unit": "actor", "target": "defender"},
        {"op": "move", "unit": "actor", "to": [0, 0]},
    ]
    ranged = scenario.Scenario(ranged_spec)
    ranged_result = ranged.run()
    ranged_actor = ranged.units["actor"]
    discriminator = trace_index(ranged_result["log"],
                                "live-capacity stamina discriminator")
    capacity_clear = trace_index(ranged_result["log"],
                                 "ranged activation capacity clear")
    check(ranged_actor.action_spent and ranged_actor.movement_remaining == 0
          and ranged_actor.ammo == 1,
          "move/history -> ranged is terminal and a refused second shot spends no ammo")
    check(0 <= discriminator < capacity_clear,
          "R8 evaluates live capacity before ranged terminal clearing")
    check(sum("actor has already acted" in line for line in ranged_result["log"]) == 1
          and "actor cannot reach 0,0" in "\n".join(ranged_result["log"]),
          "shooting and movement are refused after terminal ranged resolution")

    action_spec = {
        "name": "active action terminality", "profile": "native", "seed": 3,
        "battlefield": {"width": 5, "height": 3, "tiles": []},
        "actions": [
            {"id": "shield_bash", "source_id": 388, "name": "Localized",
             "target": 1, "cost_stamina": 1, "attack_surcharge": True,
             "consumes_action": True, "magnitude": 1,
             "excluded_targets": ["Бестелесный"]},
        ],
        "sides": [
            {"id": 0, "is_attacker": True, "leader_initiative": 2,
             "units": [fighter("consumer", [0, 0]),
                       fighter("exception", [0, 2], stamina=1)]},
            {"id": 1, "leader_initiative": 1,
             "units": [fighter("target", [2, 0]),
                       fighter("target2", [1, 2])]},
        ],
        "commands": [
            {"op": "move", "unit": "consumer", "to": [1, 0]},
            {"op": "action", "unit": "consumer", "action": "shield_bash",
             "target": "target"},
            {"op": "move", "unit": "consumer", "to": [0, 0]},
            {"op": "action", "unit": "consumer", "action": "shield_bash",
             "target": "target"},
            {"op": "action", "unit": "exception", "action": "shield_bash",
             "target": "target2"},
            {"op": "move", "unit": "exception", "to": [0, 1]},
        ],
    }
    active = scenario.Scenario(action_spec)
    active_result = active.run()
    consumer = active.units["consumer"]
    exception = active.units["exception"]
    active_log = "\n".join(active_result["log"])
    check(consumer.action_spent and consumer.movement_remaining > 0
          and not turn.has_resources(consumer),
          "resolved consuming typed Action policy terminates the actor")
    check("consumer cannot reach 0,0" in active_log
          and "cannot use shield_bash: already acted" in active_log,
          "ordinary and consuming-action follow-ups are refused")
    check("cannot use shield_bash: not enough stamina" in active_log
          and exception.stamina == 1,
          "an unavailable typed action refusal is non-terminal and spends nothing")
    check(not exception.action_spent and exception.steps_this_round == 1
          and turn.has_resources(exception),
          "a refused typed Action leaves the actor eligible")


def test_zero_movement_unspent_action_adjacent_melee() -> None:
    print("\n[IR-4] zero movement retains an unspent adjacent melee")
    spec = {
        "name": "IR-4 movement/action distinction", "profile": "native", "seed": 4,
        "battlefield": {"width": 3, "height": 2, "tiles": []},
        "sides": [
            {"id": 0, "is_attacker": True, "leader_initiative": 2,
             "units": [{
                 "name": "actor", "at": [0, 0], "attack": 8,
                 "counter_attack": 3, "defence": 0, "life": 40,
                 "stamina": 10, "stamina_base": 10, "morale": 10,
                 "speed": 1,
             }]},
            {"id": 1, "leader_initiative": 1,
             "units": [{
                 "name": "defender", "at": [2, 0], "attack": 1,
                 "counter_attack": 0, "defence": 0, "life": 40,
                 "stamina": 10, "stamina_base": 10, "morale": 10,
                 "speed": 1,
             }]},
        ],
        "commands": [],
    }
    manual = scenario.Scenario(spec)
    turn.begin_battle(manual.state)
    actor = manual.units["actor"]
    defender = manual.units["defender"]

    manual.cmd_move(actor, 1, 0)
    check(actor.movement_remaining == 0 and actor.steps_this_round == 1,
          "movement is exhausted to zero through the manual Scenario command")
    check(not actor.action_spent and turn.has_resources(actor)
          and actor in turn.activatable(manual.state, 0)
          and manual.field.find(actor).distance(manual.field.find(defender)) == 1,
          "the zero-movement actor remains selectable for adjacent melee")

    defender_life_before = defender.life
    combat_log_start = len(manual.log)
    manual.cmd_attack(actor, defender)
    combat_events = manual.log[combat_log_start:]
    check(defender.life < defender_life_before
          and any("actor hits defender" in event for event in combat_events),
          "adjacent melee succeeds and emits the expected combat event")
    check(actor.action_spent and not turn.has_resources(actor),
          "only the successful melee makes the action terminal")


def test_phase_passing() -> None:
    """A voluntary pass remains necessary while eligible units are unspent."""
    print("\n[5] two voluntary side passes advance a fully unspent round")
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


def test_aura_round_upkeep() -> None:
    print("\n[9] existing aura upkeep remains active")
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

    # upkeep without an aura must not emit noise
    bare = run(json.loads(json.dumps(SPEC)))
    check("auras (" not in "\n".join(bare["log"]),
          "and a battle with neither reports nothing")


def test_status_runtime_scenario() -> None:
    print("\n[CX-010] first-class status scenario and no implicit lifecycle")
    with open("tests/scenarios/status_runtime.json", encoding="utf-8") as handle:
        spec = json.load(handle)
    active = run(spec)
    plain_spec = json.loads(json.dumps(spec))
    plain_spec["sides"][0]["units"][0].pop("statuses")
    plain = run(plain_spec)
    actor = active["final"]["status_actor"]
    check(len(actor.get("statuses", [])) == 1,
          "inline synthetic unit statuses are accepted")
    status_state = actor["statuses"][0]
    check(active["final"]["target"]["life"] < plain["final"]["target"]["life"],
          "status numeric modifier changes real scenario damage",
          "%d vs %d" % (active["final"]["target"]["life"],
                         plain["final"]["target"]["life"]))
    check(status_state["id"] == "synthetic_attack"
          and status_state["duration"] == 2,
          "status identity and duration survive a full activation boundary")
    check(status_state["modifiers"][0]["params"] == {"stat": "attack"},
          "final state exposes the deterministic modifier payload")
    check(any("statuses [Synthetic attack boon (2)]" in line
              for line in active["log"]),
          "initial status state is trace-visible")
    check(sum("statuses [" in line for line in active["log"]) == 1,
          "round transition does not auto-tick or re-emit lifecycle state")


def test_status_canonical_schema_boundary() -> None:
    print("\n[CX-010] status input remains synthetic-scenario-only")

    def canonical_spec(overrides=None):
        return {
            "content": {"pack": "synthetic", "version": "cx-010"},
            "sides": [{"id": 0, "units": [{
                "id": "canonical-1", "def": "synthetic:unit/1", "at": [0, 0],
                "overrides": overrides or {},
            }]}],
        }

    status_data = [{"id": "runtime-only", "name": "Runtime only"}]
    cases = [
        (
            {"name": "Canonical", "statuses": status_data},
            canonical_spec(),
            "canonical content definitions reject statuses",
            "canonical definition 'synthetic:unit/1' contains unknown construction fields: statuses",
        ),
        (
            {"name": "Canonical"},
            canonical_spec({"statuses": status_data}),
            "canonical overrides reject statuses",
            "canonical unit 'canonical-1' overrides unknown or non-settable fields: statuses",
        ),
    ]
    for definition, specification, what, expected in cases:
        provider = content.ScenarioContentProvider(
            "synthetic", {"synthetic:unit/1": definition}, version="cx-010")
        try:
            scenario.Scenario.prepare_content(specification, provider)
        except ValueError as exc:
            check(str(exc) == expected, what, str(exc))
        else:
            check(False, what, "statuses were accepted")


if __name__ == "__main__":
    test_profile_selection()
    test_committed_native_scenarios_match_fixture()
    test_determinism()
    test_chain()
    test_steps_feed_stamina()
    test_genesis_command_entry_charge()
    test_genesis_r8_live_capacity_integration()
    test_melee_numeric_tranche_integration()
    test_ranged_numeric_tranche_integration()
    test_cx012_one_shot_channel_integration()
    test_terrain_matters()
    test_zero_movement_unspent_action_adjacent_melee()
    test_phase_passing()
    test_illegal_commands()
    test_ammunition()
    test_modifiers_actually_apply()
    test_aura_round_upkeep()
    test_status_runtime_scenario()
    test_status_canonical_schema_boundary()
    test_instance_identity()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
