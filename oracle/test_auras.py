# oracle/test_auras.py
"""
test_auras.py — continuous area effects.

The two properties worth defending:

  * DERIVED, NOT APPLIED. An aura depends on positions and on its source being
    alive. A model that applies it as a status on entry needs removal on every
    move, death and expiry, and gets one of them wrong. These tests move units
    and kill sources and expect the effect to follow.
  * STACKING IS PER-ABILITY. «эффекты всех лидеров складываются» versus
    «действует только самая сильная аура», both stated outright, so a global
    policy would be wrong for one of them.

Run: python3 test_auras.py
"""

from __future__ import annotations

import sys

import auras
import battlefield as bfmod
from auras import Aura, Scope, Side, Stacking
from battlefield import Battlefield, offset_to_axial
from combat import Combatant
from modifier import Hook, Modifier

FAILS: list[str] = []


def check(ok: bool, what: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", what,
                          ("  — " + detail) if detail else ""))
    if not ok:
        FAILS.append(what)


def unit(name, **kw) -> Combatant:
    kw.setdefault("life", 20)
    kw.setdefault("stamina", 10)
    c = Combatant(name=name)
    subs = kw.pop("subtypes", [])
    for k, v in kw.items():
        setattr(c, k, v)
    c.subtypes = set(subs)
    c.life_base = kw.get("life", 20)
    c.stamina_base = 10
    c.morale_base = 10
    return c


def valour(power=2, source=None) -> Aura:
    """Аура доблести: «Все дружественные воины вокруг получают +%d к
    дистанционной атаке (действует только самая сильная аура)»."""
    return Aura(id="valour", name="Аура доблести", scope=Scope.ADJACENT,
                affects=Side.ALLY, stacking=Stacking.MAXIMUM, power=power,
                source=source,
                modifiers=[Modifier(ability=400, handler="stat_delta",
                                    hook=Hook.STAT_PASSIVE, power=power,
                                    params={"stat": "ranged_attack"},
                                    source="Аура доблести")])


def inspiring(power=1, source=None) -> Aura:
    """Вдохновляющее присутствие: «все союзники НА ПОЛЕ БОЯ получают +%d
    (эффекты всех лидеров СКЛАДЫВАЮТСЯ)»."""
    return Aura(id="inspiring", name="Вдохновляющее присутствие",
                scope=Scope.BATTLEFIELD, affects=Side.ALLY,
                stacking=Stacking.CUMULATIVE, power=power, source=source,
                modifiers=[Modifier(ability=401, handler="stat_delta",
                                    hook=Hook.STAT_PASSIVE, power=power,
                                    params={"stat": "ranged_attack"},
                                    source="Вдохновляющее присутствие")])


def setup(*placements):
    """(unit, col, row, side) -> (field, side_of)."""
    field = Battlefield(7, 5)
    sides = {}
    for u, col, row, side in placements:
        field.place(u, offset_to_axial(col, row))
        sides[id(u)] = side
    return field, (lambda u: sides.get(id(u)))


def test_adjacency() -> None:
    print("\n[1] adjacent scope reaches neighbours and nobody else")
    src, near, far = unit("src"), unit("near"), unit("far")
    field, side_of = setup((src, 3, 2, 0), (near, 4, 2, 0), (far, 6, 2, 0))
    by_source = {src: [valour(source=src)]}

    check(len(auras.active_for(near, by_source, field, side_of)) == 1,
          "an adjacent ally is covered")
    check(len(auras.active_for(far, by_source, field, side_of)) == 0,
          "a distant ally is not")
    check(len(auras.active_for(src, by_source, field, side_of)) == 0,
          "and the projector is not in its own adjacency — «вокруг воина»")


def test_follows_movement() -> None:
    """The property that makes derivation worth it."""
    print("\n[2] the effect follows movement with no bookkeeping")
    src, ally = unit("src"), unit("ally")
    field, side_of = setup((src, 3, 2, 0), (ally, 6, 2, 0))
    by_source = {src: [valour(source=src)]}
    check(not auras.modifiers_for(ally, by_source, field, side_of),
          "out of range to begin with")

    field.remove(offset_to_axial(6, 2))
    field.place(ally, offset_to_axial(4, 2))
    check(len(auras.modifiers_for(ally, by_source, field, side_of)) == 1,
          "walks into range and is covered")

    field.remove(offset_to_axial(4, 2))
    field.place(ally, offset_to_axial(6, 2))
    check(not auras.modifiers_for(ally, by_source, field, side_of),
          "walks out again and is not")


def test_dead_source() -> None:
    print("\n[3] «пока воин жив» — a dead source projects nothing")
    src, ally = unit("src"), unit("ally")
    field, side_of = setup((src, 3, 2, 0), (ally, 4, 2, 0))
    by_source = {src: [valour(source=src)]}
    check(len(auras.modifiers_for(ally, by_source, field, side_of)) == 1,
          "covered while the source lives")
    src.alive = False
    check(not auras.modifiers_for(ally, by_source, field, side_of),
          "and not once it dies")


def test_battlefield_scope() -> None:
    print("\n[4] battlefield scope ignores distance")
    src, far = unit("src"), unit("far")
    field, side_of = setup((src, 0, 0, 0), (far, 6, 4, 0))
    by_source = {src: [inspiring(source=src)]}
    check(len(auras.modifiers_for(far, by_source, field, side_of)) == 1,
          "«все союзники на поле боя» reaches the far corner")


def test_sides() -> None:
    print("\n[5] side filters")
    src, ally, foe = unit("src"), unit("ally"), unit("foe")
    field, side_of = setup((src, 3, 2, 0), (ally, 4, 2, 0), (foe, 3, 1, 1))

    ally_only = {src: [valour(source=src)]}
    check(auras.modifiers_for(ally, ally_only, field, side_of),
          "an ALLY aura reaches allies")
    check(not auras.modifiers_for(foe, ally_only, field, side_of),
          "and not enemies")

    drain = Aura(id="withering", name="Аура увядания", scope=Scope.ADJACENT,
                 affects=Side.ENEMY, power=1, source=src, tick={"stamina": -1})
    enemy_only = {src: [drain]}
    check(auras.active_for(foe, enemy_only, field, side_of),
          "an ENEMY aura reaches enemies")
    check(not auras.active_for(ally, enemy_only, field, side_of),
          "and spares allies")

    # Аура смерти: «все живые войска», regardless of side
    death = Aura(id="death", name="Аура смерти", scope=Scope.ADJACENT,
                 affects=Side.ALL, power=2, source=src, tick={"life": -2},
                 except_subtypes=("Привратник Смерти",))
    everyone = {src: [death]}
    check(auras.active_for(ally, everyone, field, side_of)
          and auras.active_for(foe, everyone, field, side_of),
          "an ALL aura is indifferent to side — Аура смерти drains its own army too")


def test_subtype_filters() -> None:
    print("\n[6] subtype filters are per-aura")
    src = unit("src")
    mortal = unit("mortal", subtypes=["Смертный"])
    undead = unit("undead", subtypes=["Нежить"])
    gatekeeper = unit("gate", subtypes=["Смертный", "Привратник Смерти"])
    field, side_of = setup((src, 3, 2, 0), (mortal, 4, 2, 0),
                           (undead, 3, 1, 0), (gatekeeper, 2, 2, 0))

    # Аура жизни: «смертные, демоны и герои» — not undead
    life = {src: [Aura(id="life", name="Аура жизни", scope=Scope.ADJACENT,
                       affects=Side.ALLY, power=2, source=src,
                       tick={"life": 2},
                       only_subtypes=("Смертный", "Демон", "Герой"))]}
    check(auras.active_for(mortal, life, field, side_of),
          "Аура жизни reaches the mortal")
    check(not auras.active_for(undead, life, field, side_of),
          "and not the undead — «живые союзные войска»")

    # Аура смерти spares «Привратников Смерти»
    death = {src: [Aura(id="death", scope=Scope.ADJACENT, affects=Side.ALL,
                        power=2, source=src, tick={"life": -2},
                        except_subtypes=("Привратник Смерти",))]}
    check(auras.active_for(mortal, death, field, side_of),
          "Аура смерти reaches ordinary troops")
    check(not auras.active_for(gatekeeper, death, field, side_of),
          "and spares Привратников Смерти")


def test_stacking() -> None:
    print("\n[7] stacking is per-ability, stated outright by both")
    ally = unit("ally")
    a, b, c = unit("a"), unit("b"), unit("c")
    field, side_of = setup((ally, 3, 2, 0), (a, 4, 2, 0), (b, 2, 2, 0),
                           (c, 3, 1, 0))

    # «действует только самая сильная аура»
    strongest = {a: [valour(2, a)], b: [valour(5, b)], c: [valour(3, c)]}
    active = auras.active_for(ally, strongest, field, side_of)
    check(len(active) == 1, "MAXIMUM keeps one aura", str(len(active)))
    check(active[0].power == 5, "the strongest", str(active[0].power))
    mods = auras.modifiers_for(ally, strongest, field, side_of)
    check(len(mods) == 1 and mods[0].power == 5, "and only its modifier")

    # «эффекты всех лидеров складываются»
    leaders = {a: [inspiring(1, a)], b: [inspiring(2, b)], c: [inspiring(3, c)]}
    active = auras.active_for(ally, leaders, field, side_of)
    check(len(active) == 3, "CUMULATIVE keeps all three", str(len(active)))
    check(sum(x.power for x in active) == 6, "and they sum to 6",
          str(sum(x.power for x in active)))


def test_ticks_sum() -> None:
    print("\n[8] opposing ticks sum rather than one winning")
    target = unit("target", life=20)
    target.life = 10          # wounded, so healing has room; the helper seeds
                              # life_base from `life`, and a unit at full health
                              # correctly refuses to be healed
    healer, killer = unit("healer"), unit("killer")
    field, side_of = setup((target, 3, 2, 0), (healer, 4, 2, 0), (killer, 2, 2, 1))
    by_source = {
        healer: [Aura(id="life", name="Аура жизни", scope=Scope.ADJACENT,
                      affects=Side.ALLY, power=3, source=healer,
                      tick={"life": 3})],
        killer: [Aura(id="death", name="Аура смерти", scope=Scope.ADJACENT,
                      affects=Side.ALL, power=2, source=killer,
                      tick={"life": -2})],
    }
    totals, _ = auras.tick_for(target, by_source, field, side_of)
    check(totals == {"life": 1}, "+3 and -2 net to +1", str(totals))
    auras.apply_tick(target, totals)
    check(target.life == 11, "and are applied", str(target.life))

    target.life = target.life_base
    auras.apply_tick(target, {"life": 5})
    check(target.life == target.life_base, "healing caps at base life",
          str(target.life))

    frail = unit("frail", life=1)
    auras.apply_tick(frail, {"life": -3})
    check(not frail.alive, "and an aura can kill")


def test_modifiers_reach_the_pipeline() -> None:
    print("\n[9] aura modifiers are ordinary modifiers")
    import combat
    import content
    import handlers
    from modifier import Pipeline

    reg = content.AbilityRegistry()
    handlers.register_all(reg)
    p = Pipeline(reg)

    src, ally = unit("src"), unit("ally", ranged_attack=6)
    field, side_of = setup((src, 3, 2, 0), (ally, 4, 2, 0))
    by_source = {src: [valour(3, src)]}
    mods = auras.modifiers_for(ally, by_source, field, side_of)
    got, _ = p.resolve(ally.ranged_attack, mods, Hook.STAT_PASSIVE,
                       {"stat": "ranged_attack"})
    check(got == 9, "an aura raises the stat through the normal pipeline",
          str(got))


if __name__ == "__main__":
    test_adjacency()
    test_follows_movement()
    test_dead_source()
    test_battlefield_scope()
    test_sides()
    test_subtype_filters()
    test_stacking()
    test_ticks_sum()
    test_modifiers_reach_the_pipeline()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
