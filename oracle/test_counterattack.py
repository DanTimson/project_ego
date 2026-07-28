"""
test_counterattack.py — melee retaliation.

The cases that matter are the ORDER ones. A counterattack model that always
resolves after the attack passes every naive test and gets `Первый удар`
exactly backwards — the ability's whole point is that a defender can kill an
attacker before the attack lands.

Run: python3 test_counterattack.py
"""

from __future__ import annotations

import sys

import counterattack as ca
from combat import AttackKind, Combatant, Rng
from counterattack import NoCounter

FAILS: list[str] = []


def check(ok: bool, what: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", what,
                          ("  — " + detail) if detail else ""))
    if not ok:
        FAILS.append(what)


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
                            AttackKind.MELEE) is NoCounter.NONE,
          "unless it is Неутомимый and never loses stamina")

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


def test_attacker_side_suppression() -> None:
    print("\n[2] the attacker can avoid retaliation")
    d = unit("d")
    check(ca.why_no_counter(d, unit("a", flags=["Ловкость"]), AttackKind.MELEE)
          is NoCounter.EVADED,
          "Ловкость — «атаковать врукопашную, избегая ответных ударов»")
    check(ca.why_no_counter(d, unit("a", flags=["Касание вампира"]),
                            AttackKind.MELEE) is NoCounter.EVADED,
          "Касание вампира — «не получать контратаки»")

    class ShieldBash:
        suppresses_counterattack = True

    check(ca.why_no_counter(d, unit("a"), AttackKind.MELEE, ShieldBash())
          is NoCounter.SUPPRESSED,
          "Удар щитом suppresses it from the action side")


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


def test_determinism() -> None:
    print("\n[10] determinism")
    def once():
        return ca.resolve(unit("a"), unit("d"), Rng(42)).order
    first = once()
    check(all(once() == first for _ in range(10)),
          "the same seed gives the same exchange", str(first))


if __name__ == "__main__":
    test_refusals()
    test_attacker_side_suppression()
    test_first_strike_order()
    test_lethal_first_strike()
    test_dead_defender_does_not_answer()
    test_counter_uses_its_own_stat()
    test_ranged_is_free()
    test_morale_share()
    test_rider_suppression()
    test_determinism()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
