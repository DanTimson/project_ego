"""
test_actions.py — legality and cost for activated abilities.

These are decidable from the actor alone, so they are testable now. Effects are
not: running them needs battle state (adjacency, corpses, target lists) that
does not exist yet.

Run: python3 test_actions.py
"""

from __future__ import annotations

import modifier_semantic as semantic

import os

import sys

from combat import Combatant
from modifier import Hook, Modifier
from actions import REFERENCE_CATALOGUE, Cost, Refusal, Target

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


def actor(**kw) -> Combatant:
    kw.setdefault("stamina", 10)
    kw.setdefault("stamina_base", 10)
    kw.setdefault("ammo", 4)
    c = Combatant()
    for k, v in kw.items():
        if k in ("flags", "subtypes"):
            setattr(c, k, set(v))
        else:
            setattr(c, k, v)
    return c


def test_catalogue() -> None:
    print("\n[1] catalogue integrity")
    check(len(REFERENCE_CATALOGUE) == 14, "fourteen activated abilities", str(len(REFERENCE_CATALOGUE)))
    check(all(a.id == key for key, a in REFERENCE_CATALOGUE.items()), "ids match keys")
    check(all(a.name for a in REFERENCE_CATALOGUE.values()), "every action is named")
    attacks = [a for a in REFERENCE_CATALOGUE.values() if a.is_attack]
    check(len(attacks) == 7, "seven actions perform an attack",
          ", ".join(a.id for a in attacks))
    check(all(a.cost.attack_surcharge for a in attacks),
          "every attacking action carries the documented +1 stamina surcharge")
    non_attacks = [a for a in REFERENCE_CATALOGUE.values() if not a.is_attack]
    check(not any(a.cost.attack_surcharge for a in non_attacks),
          "no non-attacking action carries the surcharge")


def test_surcharge() -> None:
    print("\n[2] the +1 stamina surcharge on attacking actions")
    u = actor()
    # Бешенство: documented 2, so 3 with the attack charged separately.
    check(REFERENCE_CATALOGUE["frenzy"].cost.resolve(u).stamina == 3,
          "Бешенство: documented 2 -> resolves to 3")
    # Удар щитом: documented 1 -> 2.
    check(REFERENCE_CATALOGUE["shield_bash"].cost.resolve(u).stamina == 2,
          "Удар щитом: documented 1 -> resolves to 2")
    # Марш-бросок performs no attack, so 3 stays 3.
    check(REFERENCE_CATALOGUE["forced_march"].cost.resolve(u).stamina == 3,
          "Марш-бросок: no attack, 3 stays 3")


def test_conditional_cost() -> None:
    print("\n[3] cost as a function of the actor")
    plain = actor()
    rat = actor(subtypes={"Крысолюд"})
    ce = REFERENCE_CATALOGUE["carrion_eater"]
    check(ce.cost.resolve(plain).consumes_action,
          "Трупоед consumes the action for most units")
    check(not ce.cost.resolve(rat).consumes_action,
          "Трупоед is free for Крысолюд")


def test_availability() -> None:
    print("\n[4] availability")
    check(REFERENCE_CATALOGUE["frenzy"].availability(actor(stamina=2)) is Refusal.NO_STAMINA,
          "Бешенство refused at stamina 2 (needs 3)")
    check(REFERENCE_CATALOGUE["frenzy"].availability(actor(stamina=3)) is Refusal.OK,
          "Бешенство allowed at stamina 3")
    check(REFERENCE_CATALOGUE["healing"].availability(actor(ammo=0)) is Refusal.NO_AMMO,
          "Целительство refused without ammo")
    check(REFERENCE_CATALOGUE["healing"].availability(actor(ammo=1)) is Refusal.OK,
          "Целительство allowed with 1 ammo")
    check(REFERENCE_CATALOGUE["turtle"].availability(actor(action_spent=True)) is Refusal.ACTION_SPENT,
          "action already spent this round")
    check(REFERENCE_CATALOGUE["turtle"].availability(actor(stamina=0)) is Refusal.EXHAUSTED,
          "nothing is available at 0 stamina")

    # Неутомимый never spends stamina, so stamina can never refuse.
    tireless = actor(stamina=0, flags={"Неутомимый"})
    check(REFERENCE_CATALOGUE["frenzy"].availability(tireless) is Refusal.OK,
          "Неутомимый is not blocked by stamina, even at 0")

    # A free action for the right subtype remains usable after acting.
    rat = actor(subtypes={"Крысолюд"}, action_spent=True)
    check(REFERENCE_CATALOGUE["carrion_eater"].availability(rat) is Refusal.OK,
          "Трупоед still available to Крысолюд after acting")


def test_payment() -> None:
    print("\n[5] payment")
    u = actor(stamina=10, ammo=4)
    REFERENCE_CATALOGUE["frenzy"].pay(u)
    check(u.stamina == 7 and u.action_spent,
          "Бешенство spends 3 stamina and the action",
          "stamina %d, spent %s" % (u.stamina, u.action_spent))

    u = actor(stamina=10, ammo=4)
    REFERENCE_CATALOGUE["healing"].pay(u)
    check(u.ammo == 3 and u.stamina == 10,
          "Целительство spends ammo only", "ammo %d, stamina %d" % (u.ammo, u.stamina))

    u = actor(stamina=1, flags={"Неутомимый"})
    REFERENCE_CATALOGUE["forced_march"].pay(u)
    check(u.stamina == 1, "Неутомимый pays no stamina", "stamina %d" % u.stamina)

    u = actor(subtypes={"Крысолюд"})
    REFERENCE_CATALOGUE["carrion_eater"].pay(u)
    check(not u.action_spent, "Крысолюд keeps its action after Трупоед")

    u = actor(stamina=2)
    REFERENCE_CATALOGUE["forced_march"].pay(u)
    check(u.stamina == 0, "stamina floors at 0, never negative", "stamina %d" % u.stamina)


def test_interactions() -> None:
    print("\n[6] ability suppression and scaling")
    extra = REFERENCE_CATALOGUE["extra_shot"]
    check("Бронебойный выстрел" in extra.suppresses,
          "Дополнительный выстрел suppresses Бронебойный выстрел")
    check(("Точный выстрел", 0.5) in extra.scales,
          "Дополнительный выстрел halves Точный выстрел")
    check(("Точный выстрел", 2.0) in REFERENCE_CATALOGUE["sniper_shot"].scales,
          "Снайперский выстрел doubles Точный выстрел")
    check(not hasattr(REFERENCE_CATALOGUE["shield_bash"], "suppresses_counterattack"),
          "dead counterattack-suppression field is absent")
    check("Бестелесный" in REFERENCE_CATALOGUE["shield_bash"].excluded_targets,
          "Удар щитом does not affect incorporeal targets")
    check("Нежить" in REFERENCE_CATALOGUE["healing"].excluded_targets,
          "Целительство excludes undead")
    check(REFERENCE_CATALOGUE["power_shot"].damage_scale == 1.5
          and REFERENCE_CATALOGUE["crushing_blow"].damage_scale == 1.5,
          "both 'полтора раза' actions carry a 1.5 damage scale")
    check(REFERENCE_CATALOGUE["shield_bash"].damage_scale == 0.0,
          "Удар щитом deals no damage")


def test_modifier_0x12_action_payment() -> None:
    print("\n[R11] numeric modifier 0x12 suppresses action stamina payment")
    u = actor(stamina=4)
    u.modifiers.append(Modifier(
        ability=0x12, handler="modifier_0x12", hook=Hook.STAMINA,
        source="0x12",
        semantics=(semantic.Query.STAMINA_MUTATION_SUPPRESSED,)))
    trace = REFERENCE_CATALOGUE["forced_march"].pay(u)
    check(u.stamina == 4, "action-definition stamina cost is suppressed")
    check(any(step[0] == "stamina.mutation_suppressed"
              for step in trace.steps), "action suppression is trace-visible")


if __name__ == "__main__":
    test_catalogue()
    test_surcharge()
    test_conditional_cost()
    test_availability()
    test_payment()
    test_modifier_0x12_action_payment()
    test_interactions()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
