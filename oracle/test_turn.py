"""
test_turn.py — action points and the round loop.

The tests that matter here are the RE-ENTRY ones. A model that resets state per
activation instead of per round passes every naive test and is farmable: yield
and reselect to collect a start-of-turn bonus twice, or to launder away the
"moved this round" penalty. Those cases are sections 3 and 4.

Run: python3 test_turn.py
"""

from __future__ import annotations

import os

import sys

from combat import Combatant
import turn
from turn import BattleState, Refusal, Side

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
    kw.setdefault("speed", 2)
    kw.setdefault("stamina", 10)
    kw.setdefault("stamina_base", 10)
    c = Combatant(name=name)
    for k, v in kw.items():
        if k == "flags":
            c.flags = set(v)
        else:
            setattr(c, k, v)
    turn.begin_round(c)
    return c


def test_effective_speed() -> None:
    print("\n[1] effective speed — documented stamina penalty, floor 1")
    for stamina, want in ((10, 3), (5, 3), (4, 2), (3, 2), (2, 1), (1, 1), (0, 1)):
        u = Combatant(speed=3, stamina=stamina, stamina_base=10)
        got = turn.effective_speed(u)[0]
        check(got == want, "speed 3 at stamina %d -> %d" % (stamina, want), "got %d" % got)
    u = Combatant(speed=1, stamina=0, stamina_base=10)
    check(turn.effective_speed(u)[0] == 1, "speed floors at 1, never 0 or negative")
    # R8: `004D0560` contains no modifier 0x12 check. The previous expectation
    # here — that «Неутомимый» keeps full speed — was an inference from "such a
    # unit never loses stamina", not evidence, and it fails once an effect sets
    # stamina directly. Modifier 0x12 suppresses stamina DEDUCTIONS, not the
    # speed penalty.
    u = Combatant(speed=3, stamina=0, flags={"Неутомимый"})
    check(turn.effective_speed(u)[0] == 1,
          "Неутомимый does NOT exempt the speed penalty (R8)",
          "got %d" % turn.effective_speed(u)[0])


def test_attack_cost() -> None:
    print("\n[2] attack stamina: -2 having moved, -1 in place")
    u = unit()
    turn.spend_attack(u)
    check(u.stamina == 9, "attacked without moving costs 1", "stamina %d" % u.stamina)
    u = unit()
    turn.spend_move(u, 1)
    turn.spend_attack(u)
    check(u.stamina == 8, "attacked after moving costs 2", "stamina %d" % u.stamina)


def test_reentry() -> None:
    print("\n[3] re-entry — a unit may be left and reselected in the same round")
    u = unit(speed=3)
    turn.spend_move(u, 1)
    check(turn.has_resources(u), "still selectable after partial movement")
    check(u.movement_remaining == 2, "movement carries across the yield",
          "remaining %d" % u.movement_remaining)
    turn.spend_move(u, 1)
    turn.spend_attack(u)
    check(not u.action_spent is False, "action spent after attacking")
    check(turn.has_resources(u), "still selectable: 1 movement left after acting")
    turn.spend_move(u, 1)
    check(not turn.has_resources(u), "exhausted once movement and action are gone")


def test_round_trip_still_counts() -> None:
    print("\n[4] a round trip is still movement — the farming cases")
    u = unit(speed=4)
    turn.spend_move(u, 2)          # out
    turn.spend_move(u, 2)          # back to the starting tile
    check(u.steps_this_round == 4,
          "steps accumulate as PATH LENGTH, not displacement",
          "steps %d" % u.steps_this_round)
    check(u.moved_this_round(),
          "ending where it started still counts as having moved")
    turn.spend_attack(u)
    check(u.stamina == 8, "so the attack costs 2, not 1", "stamina %d" % u.stamina)

    # The farming case: yielding and reselecting must not reset the counter.
    v = unit(speed=4)
    turn.spend_move(v, 1)
    steps_after_first = v.steps_this_round
    # ... another unit acts, control returns ...
    turn.spend_move(v, 1)
    check(v.steps_this_round == steps_after_first + 1,
          "steps survive the yield — no per-activation reset",
          "steps %d" % v.steps_this_round)


def test_forced_rest() -> None:
    print("\n[5] zero stamina forces the next round to be spent resting")
    u = unit(stamina=2, stamina_recovery=1)
    turn.spend_move(u, 1)
    turn.spend_attack(u)           # -2, floors at 0
    check(u.stamina == 0 and u.forced_rest,
          "hitting 0 stamina sets forced_rest", "stamina %d" % u.stamina)
    turn.begin_round(u)
    check(u.stamina == 3, "next round rests: +2 base +1 recovery", "stamina %d" % u.stamina)
    check(u.movement_remaining == 0 and u.action_spent,
          "and the round is consumed entirely")
    check(not u.forced_rest, "the flag clears after being served")


def test_rest() -> None:
    print("\n[6] rest and its exceptions")
    u = unit(stamina=4, stamina_recovery=2)
    turn.rest(u)
    check(u.stamina == 8, "+2 base +2 recovery", "stamina %d" % u.stamina)
    check(u.resting and u.action_spent and u.movement_remaining == 0,
          "resting consumes the round and forgoes counterattacks")
    u = unit(stamina=9, stamina_recovery=5)
    turn.rest(u)
    check(u.stamina == 10, "capped at base stamina", "stamina %d" % u.stamina)
    u = unit(stamina=4, stamina_recovery=3, flags={"Зуд"})
    turn.rest(u)
    check(u.stamina == 6, "Зуд suppresses the recovery bonus, leaving +2",
          "stamina %d" % u.stamina)


def test_initiative() -> None:
    print("\n[7] initiative — army level, ties to the attacker")
    a = Side(id=0, name="A", leader_initiative=3, is_attacker=True)
    b = Side(id=1, name="B", leader_initiative=5)
    check(turn.first_side([a, b]) == 1, "higher leader initiative moves first")
    b.leader_initiative = 3
    check(turn.first_side([a, b]) == 0, "tie goes to the attacker")
    a.is_attacker = False
    b.is_attacker = True
    check(turn.first_side([a, b]) == 1, "tie goes to whichever side is attacking")


def test_round_loop() -> None:
    print("\n[8] round loop")
    a = Side(id=0, name="A", leader_initiative=5, is_attacker=True,
             units=[unit("a1"), unit("a2")])
    b = Side(id=1, name="B", leader_initiative=2, units=[unit("b1")])
    st = BattleState(sides=[a, b])
    turn.begin_battle(st)
    check(st.round_number == 1, "battle starts at round 1")
    check(st.active_side == 0, "higher initiative side is active first")
    check(len(turn.activatable(st, 0)) == 2, "both A units are selectable")

    for u in a.units:
        turn.spend_move(u, u.movement_remaining)
        turn.spend_attack(u)
    check(turn.phase_done(st, 0), "A's phase ends when nothing is selectable")

    started_new = turn.end_phase(st)
    check(not started_new and st.active_side == 1, "control passes to B")

    turn.spend_move(b.units[0], b.units[0].movement_remaining)
    turn.spend_attack(b.units[0])
    started_new = turn.end_phase(st)
    check(started_new and st.round_number == 2,
          "a new round begins when neither side can act", "round %d" % st.round_number)
    check(all(u.movement_remaining > 0 for u in a.units + b.units),
          "and every unit's movement is restored")
    check(all(u.steps_this_round == 0 for u in a.units + b.units),
          "and steps reset — once per round, at ROUND_START")


def test_extra_turns() -> None:
    print("\n[9] extra turns — spells and on-kill abilities")
    # Рывок: plain second turn, no round-start effects.
    u = unit(speed=3)
    turn.spend_move(u, 3)
    turn.spend_attack(u)
    check(not turn.has_resources(u), "spent unit has nothing left")
    granted, _ = turn.grant_extra_turn(u)
    check(granted and turn.has_resources(u), "Рывок hands back movement and action")
    check(u.movement_remaining == 3, "full movement restored",
          "%d" % u.movement_remaining)
    check(u.steps_this_round == 3,
          "steps do NOT reset — charge keeps accumulating across both turns",
          "steps %d" % u.steps_this_round)
    # R8: the discriminator is live capacity, not movement history. Рывок has
    # just restored movement_remaining to the full effective speed, so capacity
    # is NOT below effective speed and the second attack costs 1, not 2. The
    # previous expectation encoded the superseded `steps_this_round > 0` rule —
    # and this is exactly the case R8 names as the one it gets wrong.
    turn.spend_attack(u)
    check(u.stamina == 10 - 2 - 1,
          "the second attack costs 1: capacity was restored, so movement "
          "history does not charge it (R8)",
          "stamina %d" % u.stamina)

    # A rest already taken is not undone by being handed another turn.
    v = unit(stamina=4, stamina_recovery=1)
    turn.rest(v)
    turn.grant_extra_turn(v)
    check(v.resting, "resting persists through an extra turn — counterattacks stay forfeit")

    # The limiter: Кровавое безумие is «только один раз за ход».
    w = unit()
    ok1, _ = turn.grant_extra_turn(w, source="Кровавое безумие", once_per_round=True)
    turn.spend_attack(w)
    ok2, _ = turn.grant_extra_turn(w, source="Кровавое безумие", once_per_round=True)
    check(ok1 and not ok2,
          "Кровавое безумие fires once per round, not once per turn")
    check(w.action_spent, "so the chain stops — the action is not handed back again")
    ok3, _ = turn.grant_extra_turn(w, source="Азарт Охотника", once_per_round=True)
    check(ok3, "a different source is tracked separately")

    # And the limiter survives the extra turn it granted — otherwise infinite chain.
    x = unit()
    turn.grant_extra_turn(x, source="Кровавое безумие", once_per_round=True)
    check(not turn.may_trigger_once(x, "Кровавое безумие"),
          "the limiter is NOT cleared by the refresh it caused")
    turn.begin_round(x)
    check(turn.may_trigger_once(x, "Кровавое безумие"),
          "only a true round start clears it")

    # fire_round_start distinguishes the two spell shapes.
    y = unit(stamina=2, stamina_recovery=1)
    turn.spend_move(y, 1)
    turn.spend_attack(y)                       # -> 0 stamina, forced_rest
    check(y.forced_rest, "exhausted, forced rest pending")
    turn.grant_extra_turn(y, fire_round_start=False)
    check(y.forced_rest and turn.has_resources(y),
          "a resources-only grant lets an exhausted unit act, rest still pending")
    z = unit(stamina=2, stamina_recovery=1)
    turn.spend_move(z, 1)
    turn.spend_attack(z)
    turn.grant_extra_turn(z, fire_round_start=True)
    check(not z.forced_rest and z.stamina == 3,
          "a round-start grant serves the forced rest instead", "stamina %d" % z.stamina)


def test_group_grants() -> None:
    print("\n[10] group grants with filters and exclusions")
    caster = unit("caster")
    demons = [unit("d1"), unit("d2")]
    undead = [unit("u1")]
    for d in demons:
        d.subtypes = {"Демон"}
    undead[0].subtypes = {"Нежить"}
    servant = unit("servant")
    servant.subtypes = {"Нежить", "Слуга Смерти"}
    everyone = demons + undead + [servant, caster]
    for u in everyone:
        turn.spend_move(u, u.movement_remaining)
        turn.spend_attack(u)

    # Искажение Хаоса — all friendly demons.
    traces = turn.grant_extra_turn_to(
        everyone, predicate=lambda u: "Демон" in u.subtypes)
    check(len(traces) == 2, "Искажение Хаоса reaches both demons only",
          "%d" % len(traces))
    check(all(turn.has_resources(d) for d in demons), "and they can act again")
    check(not turn.has_resources(caster), "the caster is untouched by the filter")

    # Клич некроманта — all friendly undead EXCEPT слуги Смерти.
    for u in everyone:
        u.action_spent = True
        u.movement_remaining = 0
    traces = turn.grant_extra_turn_to(
        everyone, exclude=(servant,), predicate=lambda u: "Нежить" in u.subtypes)
    check(len(traces) == 1, "Клич некроманта skips слуги Смерти", "%d" % len(traces))
    check(turn.has_resources(undead[0]) and not turn.has_resources(servant),
          "the excluded servant stays spent")

    # The caster-excluded pattern.
    for u in everyone:
        u.action_spent = True
        u.movement_remaining = 0
    traces = turn.grant_extra_turn_to(everyone, exclude=(caster,))
    check(len(traces) == len(everyone) - 1 and not turn.has_resources(caster),
          "excluding the caster works the same way", "%d" % len(traces))


if __name__ == "__main__":
    test_effective_speed()
    test_attack_cost()
    test_reentry()
    test_round_trip_still_counts()
    test_forced_rest()
    test_rest()
    test_initiative()
    test_round_loop()
    test_extra_turns()
    test_group_grants()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
