#!/usr/bin/env python3
"""Extension probe — DELIB-0001's empirical test for missing boundaries.

The agreed method was to stop arguing about which abstractions a mod would need
and instead make one real modification, letting the missing boundaries announce
themselves. Anything that requires an invasive engine edit identifies a real
seam; anything that does not means the abstraction was not needed.

This covers two of the three parts: ONE NEW ACTION and ONE ALTERED RULE. The
save/load round trip is deferred because no persistence layer exists — that is
tracked separately rather than smuggled in here.

The probe is written from OUTSIDE the engine's own modules: it may import them,
but it must not edit them. Every point where it has to reach past a public
surface is recorded as a finding.

Run:  python3 oracle/test_extension_probe.py
"""

from __future__ import annotations

import copy
import json
import os
import sys

import actions as actionsmod
import combat
import scenario
import turn

FAILS: list = []
FINDINGS: list = []

SPEC_PATH = os.path.join(os.path.dirname(__file__), "..",
                         "tests", "scenarios", "skirmish.json")


def check(ok: bool, label: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label,
                          "  - %s" % detail if detail else ""))
    if not ok:
        FAILS.append(label)
        # Under pytest, raise: check() otherwise only RECORDS a failure, so
        # `pytest oracle/` would report green while assertions fail. The
        # standalone runner still collects every failure before exiting.
        if "PYTEST_CURRENT_TEST" in os.environ:
            raise AssertionError(label)


def finding(text: str) -> None:
    FINDINGS.append(text)
    print("       FINDING: %s" % text)


def spec(**overrides) -> dict:
    with open(SPEC_PATH, encoding="utf-8") as fh:
        s = json.load(fh)
    s.update(overrides)
    return copy.deepcopy(s)


# --- part 1: one new action -------------------------------------------------

def test_a_new_action_needs_no_engine_edit() -> None:
    """Add an action the engine has never heard of and invoke it in a battle."""
    print("\n[1] one new action")

    braced = actionsmod.Action(
        id="mod_brace",
        name="Упор копья",
        cost=actionsmod.Cost(stamina=1),
        target=actionsmod.Target.SELF,
        grants=(("Защита", 2, 2),),
        notes="probe-only action, not Genesis content",
    )

    before = len(actionsmod.CATALOGUE)
    actionsmod.CATALOGUE[braced.id] = braced
    check(len(actionsmod.CATALOGUE) == before + 1,
          "a new action can be registered", braced.id)
    finding("registration goes through the CATALOGUE dict directly; `_add` is "
            "private, so there is no public registration function")

    try:
        s = spec(commands=[
            {"op": "end_phase"},
            {"op": "action", "unit": "Мечник", "action": "mod_brace"},
        ])
        sc = scenario.Scenario(s)
        result = sc.run()

        used = [l for l in result["log"] if "Упор копья" in l]
        check(used, "and invoked from a scenario with no engine edit",
              str(used[:1]))

        unit = sc.units["Мечник"]
        granted = [e for e in unit.statuses if e.source == "Упор копья"]
        check(granted, "its grant reaches the unit as a timed status",
              str([(e.name, e.duration, e.power) for e in granted]))
        check(any(e.power == 2 and e.duration == 2 for e in granted),
              "carrying the declared magnitude and duration")
        check(unit.stamina == 9, "and its cost was paid", "stamina %d" % unit.stamina)
    finally:
        actionsmod.CATALOGUE.pop(braced.id, None)


# --- part 2: one altered rule ----------------------------------------------

def test_an_altered_rule_needs_no_engine_edit() -> None:
    """Replace a recovered rule with a mod's own, without editing the module.

    Morale is the sharpest case: it is fully recovered, bit-exact, and used
    everywhere. If a mod can swap the curve without touching engine source, the
    `MoralePolicy` interface both sides deferred was genuinely unnecessary.
    """
    print("\n[2] one altered rule")

    original = combat.morale_percent
    check(combat.morale_mod(combat.Combatant(name="x", morale=21))[0] == 1.15,
          "baseline: morale 21 gives the recovered +15%")

    def flat_morale(u):
        """A mod's rule: every point above 10 is worth 1%, no bands."""
        return max(-60, min(40, u.morale - 10)), "flat mod curve"

    combat.morale_percent = flat_morale
    try:
        c = combat.Combatant(name="x", morale=21)
        check(combat.morale_mod(c)[0] == 1.11,
              "an altered curve takes effect through the multiplier view",
              "%.2f" % combat.morale_mod(c)[0])

        attacker = combat.Combatant(name="x", attack=100, morale=21,
                                    morale_base=10)
        value, _ = combat.current_attack(attacker, combat.AttackKind.MELEE)
        check(int(value) == 111,
              "and through the whole attack pipeline",
              "%d (recovered rule gives 115)" % int(value))
    finally:
        combat.morale_percent = original

    check(combat.morale_mod(combat.Combatant(name="x", morale=21))[0] == 1.15,
          "and the recovered rule is restored afterwards")

    finding("altering a rule works by rebinding a module-level function. That is "
            "enough for a probe and for tests, but it is process-global: two "
            "content packs could not use different curves in one process. No "
            "policy object is needed yet; one would be needed for concurrent "
            "profiles")


# --- part 3: what the probe could not do -----------------------------------

def test_the_boundaries_that_are_actually_missing() -> None:
    print("\n[3] boundaries the probe could not cross")

    attack_actions = [a for a in actionsmod.CATALOGUE.values() if a.is_attack]
    check(attack_actions, "attack-replacing actions exist in the catalogue",
          "%d of %d" % (len(attack_actions), len(actionsmod.CATALOGUE)))
    finding("attack-replacing actions cannot execute: they need the attack "
            "pipeline plus damage_scale, whose insertion point is open (FORMULAS "
            "§1.1). cmd_action refuses them explicitly rather than silently "
            "doing nothing")

    zero_magnitude = [a for a in actionsmod.CATALOGUE.values()
                      if not a.grants and not a.is_attack]
    check(zero_magnitude, "and effect actions carry no magnitudes yet",
          "%d actions" % len(zero_magnitude))
    finding("magnitudes come from unit_upg.Quantity and are not carried into "
            "Action instances, so healing/ammo effects have nothing to apply")

    finding("no persistence layer exists, so the save/load third of the probe "
            "cannot run at all; it is tracked as its own pending item")
    finding("action parity is now closed: the port has the Action model, Refusal "
            "reasons, a data-loaded catalogue and cmd_action. A scenario may "
            "declare its own `actions`, so a committed scenario is self-contained "
            "and both implementations build the catalogue from the same bytes")


def main() -> None:
    test_a_new_action_needs_no_engine_edit()
    test_an_altered_rule_needs_no_engine_edit()
    test_the_boundaries_that_are_actually_missing()
    print("\n%d finding(s):" % len(FINDINGS))
    for f in FINDINGS:
        print("  - %s" % f)
    print("\n%s" % ("ALL PASS" if not FAILS
                    else "%d FAILURES: %s" % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
