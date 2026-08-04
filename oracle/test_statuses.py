"""
test_statuses.py — timed effects.

Two things here are easy to get wrong and expensive to notice later:

  * TICK BEFORE AGEING. An effect that deals damage on the round it expires
    should still deal it. Ageing first silently drops the last tick of every
    damage-over-time effect, which looks like a balance problem rather than a
    bug.
  * STACKING IS PER-EFFECT. «кумулятивному воздействию» stacks; «не
    складываются, вместо этого выбирается» takes the maximum. A single global
    policy would be wrong for one of them whichever way it went.

Run: python3 test_statuses.py
"""

from __future__ import annotations

import os

import sys

import statuses as st
from combat import Combatant
from modifier import Hook, Modifier
from statuses import PERMANENT, Stacking, StatusEffect

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


def unit(**kw) -> Combatant:
    kw.setdefault("life", 30)
    kw.setdefault("stamina", 10)
    kw.setdefault("morale", 10)
    c = Combatant(name=kw.pop("name", "u"))
    for k, v in kw.items():
        setattr(c, k, v)
    c.life_base = kw.get("life", 30)
    c.stamina_base = 10
    c.morale_base = 10
    return c


def dark_surge(duration=3) -> StatusEffect:
    """Всплеск Тьмы: «каждый ход в течение 3 ходов ... будет терять по 4 единицы
    жизни и по 2 единицы выносливости и боевого духа»."""
    return StatusEffect(id="dark_surge", name="Всплеск Тьмы", duration=duration,
                        tick={"life": -4, "stamina": -2, "morale": -2},
                        stacking=Stacking.CUMULATIVE, hostile=True,
                        tags=("curse",))


def test_duration_formula() -> None:
    print("\n[1] duration against the page's worked example")
    got = st.effective_duration(base=6, concentration=3, duration_mod=100,
                                target_resist=7, resist_duration=100,
                                thaumaturgy=2)
    check(got == 4, "conc 3, thaum 2, resist 7, base 6 -> 4 rounds", str(got))
    check(st.effective_duration(6, 3, 200, 0, 0) == 12,
          "DurationMod 200 is two rounds per point",
          str(st.effective_duration(6, 3, 200, 0, 0)))
    check(st.effective_duration(6, 3, 50, 0, 0) == 7,
          "DurationMod 50 is one per two points",
          str(st.effective_duration(6, 3, 50, 0, 0)))
    check(st.effective_duration(4, 0, 0, 20, 100) == 0,
          "a heavily resisting target shrugs it off entirely")


def test_tick_before_ageing() -> None:
    print("\n[2] the tick lands on the round the effect expires")
    u = unit(life=30)
    st.apply(u, dark_surge(duration=1))
    st.tick_round(u)
    check(u.life == 26, "the last round still deals its damage", str(u.life))
    check(not u.statuses, "and the effect is gone afterwards")


def test_three_round_dot() -> None:
    print("\n[3] a three-round effect ticks three times, not two or four")
    u = unit(life=30, stamina=10, morale=10)
    st.apply(u, dark_surge(3))
    for _ in range(4):
        st.tick_round(u)
    check(u.life == 18, "3 x -4 life", str(u.life))
    check(u.stamina == 4, "3 x -2 stamina", str(u.stamina))
    check(u.morale == 4, "3 x -2 morale", str(u.morale))
    check(not u.statuses, "and nothing lingers")


def test_stacking() -> None:
    print("\n[4] stacking is per-effect, not global")
    u = unit(life=40)
    for _ in range(3):
        st.apply(u, dark_surge(3))
    check(len(u.statuses) == 3, "«кумулятивное воздействие» stacks",
          str(len(u.statuses)))
    st.tick_round(u)
    check(u.life == 40 - 12, "and three instances each tick", str(u.life))

    # Оруженосец: «не складываются между собой, вместо этого выбирается» the max
    v = unit()
    for power in (2, 5, 3):
        st.apply(v, StatusEffect(id="squire", name="Оруженосец", power=power,
                                 stacking=Stacking.MAXIMUM))
    check(len(v.statuses) == 1, "MAXIMUM keeps a single instance")
    check(v.statuses[0].power == 5, "and it is the strongest",
          str(v.statuses[0].power))

    w = unit()
    st.apply(w, StatusEffect(id="bless", duration=2, stacking=Stacking.REFRESH))
    st.apply(w, StatusEffect(id="bless", duration=5, stacking=Stacking.REFRESH))
    check(len(w.statuses) == 1 and w.statuses[0].duration == 5,
          "REFRESH extends rather than stacking", str(w.statuses[0].duration))

    x = unit()
    st.apply(x, StatusEffect(id="mark", duration=2, stacking=Stacking.UNIQUE))
    st.apply(x, StatusEffect(id="mark", duration=9, stacking=Stacking.UNIQUE))
    check(len(x.statuses) == 1 and x.statuses[0].duration == 2,
          "UNIQUE ignores the second application entirely")


def test_external_shortening() -> None:
    print("\n[5] durations are a target other effects act on")
    u = unit()
    st.apply(u, dark_surge(5))
    st.apply(u, StatusEffect(id="bless", name="Благословение", duration=5))
    st.reduce_duration(u, 2)
    hostile = st.find(u, "dark_surge")[0]
    friendly = st.find(u, "bless")[0]
    check(hostile.duration == 3, "Разрушение заклинаний shortens the hostile one",
          str(hostile.duration))
    check(friendly.duration == 5, "and leaves the blessing alone",
          str(friendly.duration))

    v = unit()
    st.apply(v, StatusEffect(id="poison", duration=4, hostile=True,
                             tags=("poison",)))
    st.apply(v, StatusEffect(id="curse", duration=4, hostile=True,
                             tags=("curse",)))
    st.reduce_duration(v, 2, tags=("poison", "bleeding"))
    check(st.find(v, "poison")[0].duration == 2,
          "Опытный лекарь shortens poison specifically")
    check(st.find(v, "curse")[0].duration == 4, "and not the curse")

    w = unit()
    st.apply(w, StatusEffect(id="doom", duration=1, hostile=True))
    st.reduce_duration(w, 3)
    check(not w.statuses, "shortening past zero removes the effect")


def test_stat_decay() -> None:
    """Паутина: «каждые 10 единиц атаки, контратаки или магической
    дистанционной атаки цели снижает длительность опутывания на 1»."""
    print("\n[6] Паутина decays against the target's own stats")
    web = lambda: StatusEffect(id="web", name="Паутина", duration=6,
                               prevents_action=True, hostile=True,
                               decay_per=("attack_group", 10))
    weak = unit(attack=5, counter_attack=3, ranged_attack=0)
    st.apply(weak, web())
    st.tick_round(weak)
    check(st.find(weak, "web")[0].duration == 5,
          "a weak target loses the normal one round",
          str(st.find(weak, "web")[0].duration))

    strong = unit(attack=25, counter_attack=8, ranged_attack=0)
    st.apply(strong, web())
    st.tick_round(strong)
    check(st.find(strong, "web")[0].duration == 3,
          "attack 25 sheds 2 extra rounds per tick",
          str(st.find(strong, "web")[0].duration))
    check(st.decay_from_stats(web(), strong) == 2,
          "and it takes the BEST of the three stats, not their sum")


def test_prevents_action() -> None:
    print("\n[7] «не может действовать»")
    u = unit()
    ok, _ = st.can_act(u)
    check(ok, "an unaffected unit can act")
    st.apply(u, StatusEffect(id="petrified", name="Окаменение", duration=3,
                             prevents_action=True, hostile=True))
    ok, why = st.can_act(u)
    check(not ok and why == "Окаменение", "Окаменение prevents it", why)


def test_modifiers_flow_through() -> None:
    print("\n[8] a status changes numbers through the normal pipeline")
    u = unit()
    check(st.active_modifiers(u) == [], "no effects, no modifiers")
    boon = StatusEffect(
        id="ancestral", name="Ярость предков", duration=4,
        modifiers=[Modifier(ability=2, handler="stat_delta",
                            hook=Hook.STAT_PASSIVE, power=3,
                            params={"stat": "attack"}, source="Ярость предков")])
    st.apply(u, boon)
    mods = st.active_modifiers(u)
    check(len(mods) == 1 and mods[0].power == 3,
          "an active effect contributes its modifiers")
    for _ in range(4):
        st.tick_round(u)
    check(st.active_modifiers(u) == [],
          "and they vanish with it, without any separate bookkeeping")


def test_lethal_tick() -> None:
    print("\n[9] a tick can kill")
    u = unit(life=3)
    st.apply(u, dark_surge(3))
    st.tick_round(u)
    check(not u.alive, "damage over time kills like anything else")


def test_permanent() -> None:
    print("\n[10] permanent effects never age out")
    u = unit()
    st.apply(u, StatusEffect(id="innate", duration=PERMANENT))
    for _ in range(20):
        st.tick_round(u)
    check(len(u.statuses) == 1, "20 rounds later it is still there")
    st.reduce_duration(u, 5, hostile_only=False)
    check(len(u.statuses) == 1, "and shortening cannot remove it either")


if __name__ == "__main__":
    test_duration_formula()
    test_tick_before_ageing()
    test_three_round_dot()
    test_stacking()
    test_external_shortening()
    test_stat_decay()
    test_prevents_action()
    test_modifiers_flow_through()
    test_lethal_tick()
    test_permanent()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
