"""Stable status-container, policy, and provider integration tests.

Lifecycle-boundary expectations are intentionally absent. R13 must establish any
automatic duration clock before round/selection/activation tests are added.
"""

from __future__ import annotations

import os
import sys

import combat
import content
import handlers
import statuses as st
from combat import AttackKind, Combatant
from modifier import Hook, Modifier, Pipeline
from statuses import PERMANENT, Stacking, StatusEffect

FAILS: list[str] = []


def check(ok: bool, what: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", what,
                          ("  — " + detail) if detail else ""))
    if not ok:
        FAILS.append(what)
        if "PYTEST_CURRENT_TEST" in os.environ:
            raise AssertionError(what)


def unit(**kw) -> Combatant:
    combatant = Combatant(name=kw.pop("name", "u"), life=30, life_base=30,
                          stamina=10, stamina_base=10,
                          morale=10, morale_base=10)
    for key, value in kw.items():
        setattr(combatant, key, value)
    if "life" in kw and "life_base" not in kw:
        combatant.life_base = kw["life"]
    if "stamina" in kw and "stamina_base" not in kw:
        combatant.stamina_base = kw["stamina"]
    if "morale" in kw and "morale_base" not in kw:
        combatant.morale_base = kw["morale"]
    return combatant


def modifier(stat: str, power: int = 3) -> Modifier:
    return Modifier(ability=2, handler="stat_delta", hook=Hook.STAT_PASSIVE,
                    power=power, params={"stat": stat}, source="synthetic status")


def pipeline() -> Pipeline:
    registry = content.AbilityRegistry()
    handlers.register_all(registry)
    return Pipeline(registry)


def test_duration_formula_and_rejection() -> None:
    print("\n[1] documented duration arithmetic and stable rejection")
    check(st.effective_duration(6, 3, 100, 7, 100, 2) == 4,
          "worked example resolves to four")
    check(st.effective_duration(6, 3, 200, 0, 0) == 12,
          "DurationMod 200 adds two per point")
    check(st.effective_duration(6, 3, 50, 0, 0) == 7,
          "DurationMod 50 truncates to one extra round")
    check(st.effective_duration(4, 0, 0, 20, 100) == 0,
          "stable resistance arithmetic can reduce duration to zero")
    target = unit()
    trace = st.apply(target, StatusEffect(id="resisted", duration=0, hostile=True))
    check(not target.statuses, "zero effective duration rejects application")
    check(trace.steps[0][0] == "resisted", "rejection is trace-visible")


def test_construction_isolation_and_serialization() -> None:
    print("\n[2] runtime instances and modifier payloads are isolated")
    prototype = StatusEffect(
        id="boon", name="Synthetic boon", source="fixture", duration=4, power=3,
        modifiers=[modifier("attack")], tags=("buff",))
    left, right = unit(name="left"), unit(name="right")
    st.apply(left, prototype.copy())
    st.apply(right, prototype.copy())
    left.statuses[0].duration = 1
    left.statuses[0].modifiers[0].params["stat"] = "defence"
    left.statuses[0].modifiers[0] = modifier("defence", 9)
    check(right.statuses[0].duration == 4, "status duration is not aliased")
    check(right.statuses[0].modifiers[0].power == 3,
          "modifier object is not aliased")
    check(right.statuses[0].modifiers[0].params == {"stat": "attack"},
          "modifier params are not aliased")
    serialized = right.statuses[0].to_dict()
    check(serialized["id"] == "boon" and serialized["duration"] == 4,
          "stable identity and duration serialize")
    check(serialized["modifiers"][0]["hook"] == "STAT_PASSIVE",
          "modifier payload serializes deterministically")


def test_stacking_policy() -> None:
    print("\n[3] stable per-effect stacking policy")
    cumulative = unit()
    for _ in range(3):
        st.apply(cumulative, StatusEffect(id="surge", duration=3,
                                          stacking=Stacking.CUMULATIVE))
    check(len(cumulative.statuses) == 3, "CUMULATIVE keeps separate instances")

    maximum = unit()
    for power in (2, 5, 3):
        st.apply(maximum, StatusEffect(id="squire", power=power,
                                      stacking=Stacking.MAXIMUM))
    check(len(maximum.statuses) == 1 and maximum.statuses[0].power == 5,
          "MAXIMUM keeps the strongest instance")

    refresh = unit()
    st.apply(refresh, StatusEffect(id="bless", duration=2, power=2,
                                   stacking=Stacking.REFRESH))
    st.apply(refresh, StatusEffect(id="bless", duration=5, power=4,
                                   stacking=Stacking.REFRESH))
    check(len(refresh.statuses) == 1
          and refresh.statuses[0].duration == 5
          and refresh.statuses[0].power == 4,
          "REFRESH merges duration and power maxima")

    unique = unit()
    st.apply(unique, StatusEffect(id="mark", duration=2, stacking=Stacking.UNIQUE))
    st.apply(unique, StatusEffect(id="mark", duration=9, stacking=Stacking.UNIQUE))
    check(len(unique.statuses) == 1 and unique.statuses[0].duration == 2,
          "UNIQUE ignores reapplication")


def test_explicit_manipulation() -> None:
    print("\n[4] explicit shortening and removal")
    target = unit()
    st.apply(target, StatusEffect(id="poison", duration=4, hostile=True,
                                  tags=("poison",), stacking=Stacking.CUMULATIVE))
    st.apply(target, StatusEffect(id="poison", duration=3, hostile=True,
                                  tags=("poison",), stacking=Stacking.CUMULATIVE))
    st.apply(target, StatusEffect(id="curse", duration=4, hostile=True,
                                  tags=("curse",)))
    st.apply(target, StatusEffect(id="bless", duration=5))
    st.reduce_duration(target, 2, tags=("poison", "bleeding"))
    check([effect.duration for effect in st.find(target, "poison")] == [2, 1],
          "tagged shortening updates every matching instance")
    check(st.find(target, "curse")[0].duration == 4,
          "tag filter leaves other hostiles unchanged")
    check(st.find(target, "bless")[0].duration == 5,
          "hostile-only default leaves friendly status unchanged")
    check(st.remove(target, "poison") == 2 and not st.find(target, "poison"),
          "explicit group removal removes every matching instance")

    st.reduce_duration(target, 4)
    check(not st.find(target, "curse"), "shortening to zero removes explicitly")
    st.apply(target, StatusEffect(id="innate", duration=PERMANENT, hostile=True))
    st.reduce_duration(target, 99)
    check(len(st.find(target, "innate")) == 1,
          "permanent status ignores explicit shortening")


def test_numeric_modifier_live_path_and_r6_separation() -> None:
    print("\n[5] status numbers use the live later-provider path")
    active_pipeline = pipeline()
    combat.bind_pipeline(active_pipeline)
    try:
        actor = unit(attack=5)
        st.apply(actor, StatusEffect(id="attack_boon", duration=4,
                                     modifiers=[modifier("attack", 3)]))
        check(combat.current_attack(actor, AttackKind.MELEE)[0] == 8,
              "status modifier raises live effective melee attack")
        st.remove(actor, "attack_boon")
        check(combat.current_attack(actor, AttackKind.MELEE)[0] == 5,
              "removal restores the live value")

        ranged = unit(ranged_attack=0)
        st.apply(ranged, StatusEffect(id="ranged_boon", duration=4,
                                      modifiers=[modifier("ranged_attack", 6)]))
        result, trace = combat.current_attack(ranged, AttackKind.RANGED)
        check(result == 0, "status cannot resurrect a zero R6 early-provider sum")
        check(not any(step[0] == "synthetic status" for step in trace.steps),
              "zero return occurs before the status later provider")
        ranged.ranged_attack = 1
        check(combat.current_attack(ranged, AttackKind.RANGED)[0] == 7,
              "nonzero early sum then consumes the status later provider")
    finally:
        combat.bind_pipeline(None)


def test_flag_modifier_live_consumer() -> None:
    print("\n[6] status-carried flag reaches an existing consumer")
    wounded = unit(life=5, life_base=20)
    flag = Modifier(ability=13, handler="grant_flag", hook=Hook.STAT_PASSIVE,
                    params={"flag": "Не чувствует боли"}, source="status flag")
    st.apply(wounded, StatusEffect(id="painless", duration=4, modifiers=[flag]))
    check(wounded.has_flag("Не чувствует боли"), "Combatant.has_flag sees it")
    check(combat.wound_mod(wounded)[0] == 1.0,
          "the existing wound consumer sees the status flag")
    st.remove(wounded, "painless")
    check(combat.wound_mod(wounded)[0] < 1.0,
          "removal restores the existing wound penalty")


def test_typed_capability_policy() -> None:
    print("\n[7] typed capability policy")
    target = unit()
    allowed, reason = st.can_perform(target, st.Capability.MELEE)
    check(allowed and reason == "", "an unrestricted capability is allowed")
    st.apply(target, StatusEffect(
        id="synthetic-melee", name="Synthetic melee block", duration=3,
        restrictions=(st.Capability.MELEE,), hostile=True))
    allowed, reason = st.can_perform(target, st.Capability.MELEE)
    check(not allowed and reason == "Synthetic melee block",
          "a typed restriction identifies its blocking status")
    check(st.can_perform(target, st.Capability.MOVEMENT)[0],
          "a melee restriction does not become a universal gate")


def dark_surge(duration: int = 3) -> StatusEffect:
    return StatusEffect(id="dark_surge", name="Всплеск Тьмы", duration=duration,
                        tick={"life": -4, "stamina": -2, "morale": -2},
                        stacking=Stacking.CUMULATIVE, hostile=True,
                        tags=("curse",))


def test_provisional_explicit_lifecycle_reference() -> None:
    """Retain pre-CX-010 reference vectors without binding them to battle time."""
    print("\n[provisional lifecycle reference — not R13 truth]")
    last = unit(life=30)
    st.apply(last, dark_surge(1))
    st.tick_round(last)
    check(last.life == 26 and not last.statuses,
          "explicit reference step applies payload before provisional expiry")

    three = unit(life=30)
    st.apply(three, dark_surge(3))
    for _ in range(4):
        st.tick_round(three)
    check((three.life, three.stamina, three.morale) == (18, 4, 4)
          and not three.statuses,
          "pre-existing three-step reference vector remains unchanged")

    cumulative = unit(life=40)
    for _ in range(3):
        st.apply(cumulative, dark_surge(3))
    st.tick_round(cumulative)
    check(cumulative.life == 28,
          "pre-existing cumulative payload reference remains unchanged")

    web = lambda: StatusEffect(id="web", name="Паутина", duration=6,
                               hostile=True, decay_per=("attack_group", 10))
    weak = unit(attack=5, counter_attack=3, ranged_attack=0)
    strong = unit(attack=25, counter_attack=8, ranged_attack=0)
    st.apply(weak, web())
    st.apply(strong, web())
    st.tick_round(weak)
    st.tick_round(strong)
    check(st.find(weak, "web")[0].duration == 5,
          "pre-existing weak stat-decay reference remains unchanged")
    check(st.find(strong, "web")[0].duration == 3
          and st.decay_from_stats(web(), strong) == 2,
          "pre-existing strong stat-decay reference remains unchanged")

    expiring = unit()
    st.apply(expiring, StatusEffect(id="temporary", duration=2,
                                    modifiers=[modifier("attack")]))
    st.tick_round(expiring)
    st.tick_round(expiring)
    check(not st.active_modifiers(expiring),
          "pre-existing explicit expiry removes modifier provider")

    lethal = unit(life=3)
    st.apply(lethal, dark_surge(3))
    st.tick_round(lethal)
    check(not lethal.alive, "pre-existing lethal payload reference remains unchanged")

    permanent = unit()
    st.apply(permanent, StatusEffect(id="innate", duration=PERMANENT))
    for _ in range(20):
        st.tick_round(permanent)
    check(len(permanent.statuses) == 1,
          "pre-existing permanent reference survives explicit steps")


if __name__ == "__main__":
    test_duration_formula_and_rejection()
    test_construction_isolation_and_serialization()
    test_stacking_policy()
    test_explicit_manipulation()
    test_numeric_modifier_live_path_and_r6_separation()
    test_flag_modifier_live_consumer()
    test_typed_capability_policy()
    test_provisional_explicit_lifecycle_reference()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
