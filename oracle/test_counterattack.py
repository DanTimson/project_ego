"""
test_counterattack.py — melee retaliation.

The cases that matter are the ORDER ones. A counterattack model that always
resolves after the attack passes every naive test and gets `Первый удар`
exactly backwards — the ability's whole point is that a defender can kill an
attacker before the attack lands.

Run: python3 test_counterattack.py
"""

from __future__ import annotations

import os

import sys

import battlefield as bfmod
import combat
import counterattack as ca
import death_lifecycle as death
import statuses
import turn
from combat import AttackKind, Combatant, Rng
from counterattack import NoCounter
from modifier import Hook, Modifier

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


def unit(name="u", **kw) -> Combatant:
    kw.setdefault("attack", 8)
    kw.setdefault("counter_attack", 6)
    kw.setdefault("defence", 0)
    kw.setdefault("life", 30)
    kw.setdefault("stamina", 10)
    kw.setdefault("morale", 10)
    c = Combatant(name=name)
    flags = kw.pop("flags", [])
    for k, v in kw.items():
        setattr(c, k, v)
    c.flags = set(flags)
    c.life_base = kw.get("life", 30)
    c.stamina_base = 10
    c.morale_base = 10
    return c


def test_refusals() -> None:
    print("\n[1] when a counterattack does not happen")
    a, d = unit("a"), unit("d")
    check(ca.why_no_counter(d, a, AttackKind.MELEE) is NoCounter.NONE,
          "an ordinary melee attack is answered")
    check(ca.why_no_counter(d, a, AttackKind.RANGED) is NoCounter.RANGED,
          "a shot is not — every rule says «врукопашную»")

    check(ca.why_no_counter(unit("d", counter_attack=0), a, AttackKind.MELEE)
          is NoCounter.NO_STAT, "no counterattack value, no retaliation")
    check(ca.why_no_counter(unit("d", stamina=0), a, AttackKind.MELEE)
          is NoCounter.EXHAUSTED, "a unit at 0 stamina does not answer")
    check(ca.why_no_counter(unit("d", stamina=0, flags=["Неутомимый"]), a,
                            AttackKind.MELEE) is NoCounter.EXHAUSTED,
          "the Неутомимый compatibility flag does not bypass live exhaustion")

    resting = unit("d")
    resting.resting = True
    check(ca.why_no_counter(resting, a, AttackKind.MELEE) is NoCounter.RESTING,
          "resting forgoes counterattacks")
    check(ca.why_no_counter(unit("d", flags=["Не сражается"]), a, AttackKind.MELEE)
          is NoCounter.CANNOT_FIGHT, "«Не сражается» cannot retaliate either")

    dead = unit("d")
    dead.alive = False
    check(ca.why_no_counter(dead, a, AttackKind.MELEE) is NoCounter.DEAD,
          "the dead do not answer")


def test_effective_offensive_disable_and_live_exhaustion() -> None:
    print("\n[IR-2/IR-3] effective 0x26 and live zero-stamina eligibility")
    attacker = unit("a", life=50)

    status_disabled = unit("status-disabled", life=50)
    status_disabled.statuses = [statuses.StatusEffect(
        id="numeric-0x26",
        modifiers=[Modifier(ability=0x26, handler="modifier_0x26",
                            hook=Hook.DAMAGE_VS_TARGET)])]
    check(not status_disabled.has_flag("Не сражается")
          and ca.why_no_counter(status_disabled, attacker, AttackKind.MELEE)
          is NoCounter.CANNOT_FIGHT,
          "status-owned effective numeric 0x26 suppresses retaliation")

    aura_disabled = unit("aura-disabled", life=50)
    aura_modifier = Modifier(ability=0x26, handler="modifier_0x26",
                             hook=Hook.DAMAGE_VS_TARGET)
    combat.bind_environment(
        lambda candidate: [aura_modifier] if candidate is aura_disabled else [])
    try:
        check(ca.why_no_counter(aura_disabled, attacker, AttackKind.MELEE)
              is NoCounter.CANNOT_FIGHT,
              "eligible environment/aura-provided 0x26 suppresses retaliation")
    finally:
        combat.bind_environment(None)

    check(ca.why_no_counter(unit("positive", life=50), attacker,
                            AttackKind.MELEE) is NoCounter.NONE,
          "a defender without effective 0x26 remains eligible")

    exchange = ca.resolve(attacker, status_disabled, Rng(17))
    check(exchange.reason is NoCounter.CANNOT_FIGHT
          and not exchange.countered
          and [operation for operation, _damage in exchange.order
               if operation == "counter"] == [],
          "a full effective-0x26 exchange emits no counter operation",
          str(exchange.order))

    numeric_0x12 = Modifier(ability=0x12, handler="modifier_0x12",
                            hook=Hook.STAMINA)
    exhaustion_cases = [
        ("effective numeric 0x12", [numeric_0x12], set()),
        ("symbolic Неутомимый", [], {"Неутомимый"}),
        ("numeric 0x12 plus symbolic alias", [numeric_0x12], {"Неутомимый"}),
    ]
    for label, modifiers, flags in exhaustion_cases:
        defender = unit(label, stamina=0, flags=flags)
        defender.modifiers = list(modifiers)
        check(ca.why_no_counter(defender, attacker, AttackKind.MELEE)
              is NoCounter.EXHAUSTED,
              "%s does not bypass live exhaustion" % label)


def test_attacker_side_suppression() -> None:
    print("\n[2] the attacker can avoid retaliation")
    d = unit("d")
    check(ca.why_no_counter(d, unit("a", flags=["Ловкость"]), AttackKind.MELEE)
          is NoCounter.EVADED,
          "Ловкость — «атаковать врукопашную, избегая ответных ударов»")
    check(ca.why_no_counter(d, unit("a", flags=["Касание вампира"]),
                            AttackKind.MELEE) is NoCounter.EVADED,
          "Касание вампира — «не получать контратаки»")

    import inspect
    check("action" not in inspect.signature(ca.why_no_counter).parameters,
          "dead action metadata is no longer a counterattack input")


def test_first_strike_order() -> None:
    print("\n[3] Первый удар reorders — the case a naive model gets backwards")
    a, d = unit("a"), unit("d", flags=["Первый удар"])
    check(ca.strikes_first(d, a), "a first-strike defender goes first")
    check(not ca.strikes_first(unit("d"), a), "an ordinary defender does not")
    check(not ca.strikes_first(unit("d", flags=["Первый удар"]),
                               unit("a", flags=["Первый удар"])),
          "two first-strikers cancel to the normal order, not a race")
    check(not ca.strikes_first(a, unit("a", flags=["Первый удар"])),
          "and it is the DEFENDER's ability that matters, not the attacker's")

    ex = ca.resolve(unit("a"), unit("d", flags=["Первый удар"]), Rng(1))
    check(ex.counter_first and ex.order[0][0] == "counter",
          "so the retaliation lands before the attack",
          str([o[0] for o in ex.order]))
    ex = ca.resolve(unit("a"), unit("d"), Rng(1))
    check(ex.order[0][0] == "attack" and ex.order[1][0] == "counter",
          "and the normal order is attack then counter",
          str([o[0] for o in ex.order]))


def test_lethal_first_strike() -> None:
    print("\n[4] a lethal first strike stops the attack")
    frail = unit("a", life=1)
    killer = unit("d", counter_attack=40, flags=["Первый удар"])
    ex = ca.resolve(frail, killer, Rng(3))
    check(ex.attacker_died, "the counter kills the attacker")
    check(ex.attack_damage == 0 and len(ex.order) == 1,
          "and the attack never lands — see OPEN_QUESTIONS item 18",
          str(ex.order))


def test_dead_defender_does_not_answer() -> None:
    print("\n[5] a defender killed by the blow does not answer it")
    ex = ca.resolve(unit("a", attack=60), unit("d", life=1), Rng(5))
    check(ex.defender_died, "the attack kills")
    check(not ex.countered and ex.reason is NoCounter.DEAD,
          "and no retaliation follows", ex.reason.value)
    check(len(ex.order) == 1, "one blow, not two", str(ex.order))


def test_counter_uses_its_own_stat() -> None:
    """«Сила ответного удара» is a separate stat, not a copy of Attack."""
    print("\n[6] retaliation uses CounterAttack, not Attack")
    weak_counter = ca.resolve(unit("a", attack=1),
                              unit("d", attack=50, counter_attack=1), Rng(9))
    strong_counter = ca.resolve(unit("a", attack=1),
                                unit("d", attack=1, counter_attack=50), Rng(9))
    check(strong_counter.counter_damage > weak_counter.counter_damage,
          "a high CounterAttack retaliates harder regardless of Attack",
          "%d vs %d" % (strong_counter.counter_damage,
                        weak_counter.counter_damage))


def test_ranged_is_free() -> None:
    print("\n[7] shots are unanswered")
    ex = ca.resolve(unit("a", ranged_attack=8), unit("d"), Rng(11),
                    kind=AttackKind.RANGED)
    check(not ex.countered and ex.reason is NoCounter.RANGED,
          "no retaliation against a shot")
    check(len(ex.order) == 1, "one blow only", str(ex.order))


def test_primary_melee_charge_consumption() -> None:
    print("\n[8] command-entry charge is flat post-defence melee damage")

    # Defence drives ordinary damage to zero. A pre-randomisation, pre-defence,
    # conditional-power, or multiplier-stage insertion is absorbed here; only
    # the required post-defence insertion inflicts all six charge damage.
    ordinary = ca.resolve(
        unit("a", attack=3),
        unit("d", counter_attack=0, defence=20, life=30), Rng(1))
    charged_defender = unit("d", counter_attack=0, defence=20, life=30)
    charged = ca.resolve(unit("a", attack=3), charged_defender, Rng(1),
                         primary_melee_charge=6)
    check(ordinary.attack_damage == 0,
          "the distinguishing vector resolves ordinary damage to zero",
          str(ordinary.attack_damage))
    check(charged.attack_damage == ordinary.attack_damage + 6,
          "defence does not absorb flat post-defence charge",
          "%d = %d + 6" % (charged.attack_damage, ordinary.attack_damage))

    # The current-life cap applies to the sum, and the exact capped number is
    # what the existing exchange accumulator/order path publishes and subtracts.
    capped_defender = unit("d", counter_attack=0, defence=0, life=5)
    capped = ca.resolve(unit("a", attack=3), capped_defender, Rng(1),
                        primary_melee_charge=6)
    check(capped.attack_damage == 5 and capped.order[0] == ("attack", 5),
          "combined capped damage reaches accounting and attack consumers",
          "accumulator %d, order %s" % (capped.attack_damage, capped.order))
    check(capped_defender.life == 0 and capped.defender_died,
          "life subtraction consumes the same combined capped damage")

    # Adding post-resolution charge neither consumes RNG nor changes the
    # retaliation resolver. Compare the same ordinary exchange with and without
    # a nonlethal charge contribution.
    plain_exchange = ca.resolve(
        unit("a", attack=3, life=50),
        unit("d", counter_attack=7, defence=0, life=50), Rng(7))
    charged_exchange = ca.resolve(
        unit("a", attack=3, life=50),
        unit("d", counter_attack=7, defence=0, life=50), Rng(7),
        primary_melee_charge=2)
    check(charged_exchange.counter_damage == plain_exchange.counter_damage,
          "retaliation remains charge-free and RNG-identical",
          "%d vs %d" % (charged_exchange.counter_damage,
                         plain_exchange.counter_damage))

    ranged_plain = ca.resolve(
        unit("a", ranged_attack=3),
        unit("d", counter_attack=0, ranged_defence=0, life=30), Rng(9),
        kind=AttackKind.RANGED)
    ranged_with_charge = ca.resolve(
        unit("a", ranged_attack=3),
        unit("d", counter_attack=0, ranged_defence=0, life=30), Rng(9),
        kind=AttackKind.RANGED, primary_melee_charge=20)
    check(ranged_with_charge.attack_damage == ranged_plain.attack_damage,
          "ranged attacks ignore the primary-melee charge parameter")


def test_morale_share() -> None:
    print("\n[8] a kill by counterattack is worth half the morale")
    check(ca.morale_kill_share(AttackKind.MELEE) == 1.0, "melee kill: full")
    check(ca.morale_kill_share(AttackKind.COUNTER) == 0.5,
          "counter kill: half — «получит только половину этого значения»")
    check(ca.morale_kill_share(AttackKind.RANGED) == 0.5, "ranged kill: half")


def test_rider_suppression() -> None:
    print("\n[9] whether an on-hit rider fires during a counter is per-ability")
    check(not ca.rider_fires("Смертельное касание", AttackKind.COUNTER),
          "Смертельное касание — «не действует при контратаках»")
    check(ca.rider_fires("Смертельное касание", AttackKind.MELEE),
          "but it does on a normal attack")
    check(ca.rider_fires("Парализующее касание", AttackKind.COUNTER),
          "Парализующее касание — «атаки, контратаки и выстрелы»")


def test_fatal_event_melee_lifecycle_sequencing() -> None:
    print("\n[CX-011] fatal event versus final alive sequencing")

    def revive_marker():
        return statuses.StatusEffect(
            id="runtime-revive",
            modifiers=[Modifier(ability=death.REVIVE, handler="add_flat",
                                hook=Hook.STAT_PASSIVE)])

    def exchange(attacker, defender):
        field = bfmod.Battlefield(3, 2)
        sides = [turn.Side(id=0, name="left", units=[attacker]),
                 turn.Side(id=1, name="right", units=[defender])]
        field.place(attacker, bfmod.offset_to_axial(0, 0))
        field.place(defender, bfmod.offset_to_axial(1, 0))
        ca.bind_death_resolver(
            lambda casualty: death.resolve(casualty, field, sides))
        try:
            return ca.resolve(attacker, defender, Rng(17))
        finally:
            ca.bind_death_resolver(None)

    attacker = unit("initiator", attack=30, life=1)
    attacker.statuses = [revive_marker()]
    defender = unit("first striker", counter_attack=100, life=30,
                    flags={"Первый удар"})
    revived_first = exchange(attacker, defender)
    check(revived_first.attacker_fatal_event and not revived_first.attacker_died,
          "lethal first strike records fatal_event separately from final alive")
    check([entry[0] for entry in revived_first.order] == ["counter", "attack"],
          "revived initiator still executes its primary")

    attacker = unit("doomed initiator", attack=30, life=1)
    defender = unit("first striker", counter_attack=100, life=30,
                    flags={"Первый удар"})
    final_first = exchange(attacker, defender)
    check([entry[0] for entry in final_first.order] == ["counter"],
          "lethal first strike without survival suppresses primary")

    attacker = unit("initiator", attack=100, life=30)
    defender = unit("revived defender", counter_attack=30, life=1)
    defender.statuses = [revive_marker()]
    revived_primary = exchange(attacker, defender)
    check(revived_primary.defender_fatal_event and not revived_primary.defender_died,
          "lethal primary can leave defender finally alive")
    check([entry[0] for entry in revived_primary.order] == ["attack"],
          "fatal initiating primary suppresses ordinary retaliation after revival")

    attacker = unit("initiator", attack=1, life=30)
    defender = unit("ordinary defender", counter_attack=30, defence=0, life=50)
    nonfatal = exchange(attacker, defender)
    check([entry[0] for entry in nonfatal.order] == ["attack", "counter"],
          "nonfatal primary control retains ordinary retaliation")


def test_determinism() -> None:
    print("\n[10] determinism")
    def once():
        return ca.resolve(unit("a"), unit("d"), Rng(42)).order
    first = once()
    check(all(once() == first for _ in range(10)),
          "the same seed gives the same exchange", str(first))


if __name__ == "__main__":
    test_refusals()
    test_effective_offensive_disable_and_live_exhaustion()
    test_attacker_side_suppression()
    test_first_strike_order()
    test_lethal_first_strike()
    test_dead_defender_does_not_answer()
    test_counter_uses_its_own_stat()
    test_ranged_is_free()
    test_primary_melee_charge_consumption()
    test_morale_share()
    test_rider_suppression()
    test_fatal_event_melee_lifecycle_sequencing()
    test_determinism()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
