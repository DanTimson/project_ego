"""
test_modifier.py — the pipeline that finally connects content to combat.

Until this existed, ContentDb.resolve() returned a handler name and nothing
called it. These tests check the join: a binding in packs/genesis/bindings.json
becomes a Modifier, which the Pipeline dispatches to a handler in handlers.py,
which changes a number that reaches the damage formula.

Run: python3 test_modifier.py
"""

from __future__ import annotations

import json
import os
import sys

import combat
import content
import handlers
from combat import AttackKind, Combatant
from content import AbilityRegistry, ContentDb
from modifier import Hook, Modifier, Pipeline, from_binding

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


def registry() -> AbilityRegistry:
    r = AbilityRegistry()
    handlers.register_all(r)
    return r


def pipeline() -> Pipeline:
    return Pipeline(registry())


def test_hook_order() -> None:
    print("\n[1] hook order is the architecture")
    order = [h.name for h in sorted(Hook)]
    check(order.index("STAT_PASSIVE") < order.index("DAMAGE_VS_TARGET"),
          "flat stat deltas resolve before conditional bonuses")
    check(order.index("EVASION") < order.index("DEFENCE_APPLY")
          < order.index("DAMAGE_TAKEN"),
          "the defender's chain runs evasion -> defence -> final reduction")
    check(order.index("ON_HIT") < order.index("COUNTERATTACK")
          < order.index("ON_KILL"),
          "riders fire in the documented sequence")
    check(all(isinstance(h.value, int) for h in Hook),
          "Hook is an IntEnum, so sorting IS the resolution order")


def test_stat_guard() -> None:
    print("\n[2] a stat modifier touches only its own stat")
    p = pipeline()
    m = Modifier(ability=2, handler="stat_delta", hook=Hook.STAT_PASSIVE,
                 power=3, params={"stat": "attack"}, source="Атака +3")
    v, _ = p.resolve(8, [m], Hook.STAT_PASSIVE, {"stat": "attack"})
    check(v == 11, "+3 reaches Attack", str(v))
    v, _ = p.resolve(5, [m], Hook.STAT_PASSIVE, {"stat": "defence"})
    check(v == 5, "and leaves Defence alone", str(v))


def test_unknown_handler() -> None:
    print("\n[3] an unbound opcode neither crashes nor silently vanishes")
    p = pipeline()
    m = Modifier(ability=99, handler="not_implemented", hook=Hook.STAT_PASSIVE,
                 power=5, params={"stat": "attack"}, source="opcode 99")
    v, t = p.resolve(8, [m], Hook.STAT_PASSIVE, {"stat": "attack"})
    check(v == 8, "the value is unchanged")
    check(any("no handler" in s[3] for s in t.steps),
          "but the trace records that it was skipped",
          "; ".join(s[3] for s in t.steps))


def test_stable_order() -> None:
    print("\n[4] modifier order is stable, not list order")
    p = pipeline()
    a = Modifier(ability=3, handler="stat_delta", hook=Hook.STAT_PASSIVE,
                 power=2, params={"stat": "defence"}, source="Защита +2")
    b = Modifier(ability=1, handler="stat_delta", hook=Hook.STAT_PASSIVE,
                 power=5, params={"stat": "defence"}, source="Защита +5")
    forwards, _ = p.resolve(10, [a, b], Hook.STAT_PASSIVE, {"stat": "defence"})
    backwards, _ = p.resolve(10, [b, a], Hook.STAT_PASSIVE, {"stat": "defence"})
    check(forwards == backwards == 17,
          "the same set in either list order gives the same result",
          "%s vs %s" % (forwards, backwards))

    # Non-commutative handlers must not share a hook — that is what the hook
    # ORDER is for. A halving belongs at DEFENCE_APPLY, downstream of the
    # additive stage, so the two can never interleave by accident.
    pierce = Modifier(ability=30, handler="armor_pierce", hook=Hook.DEFENCE_APPLY,
                      source="Бронебойный выстрел")
    v, _ = p.resolve(forwards, [pierce], Hook.DEFENCE_APPLY, {"stat": "defence"})
    check(v == 8.5, "and the halving runs at its own later hook, after the sum",
          str(v))


def test_flag() -> None:
    print("\n[5] yes/no answers go through flag(), not resolve()")
    p = pipeline()
    m = Modifier(ability=60, handler="immunity", hook=Hook.STATUS_RESIST,
                 params={"against": "яд"}, source="Иммунитет к яду")
    check(p.flag([m], Hook.STATUS_RESIST, {"against": "яд"}), "the named immunity asserts")
    check(not p.flag([m], Hook.STATUS_RESIST, {"against": "огонь"}),
          "and does not answer for a different school")
    check(not p.flag([], Hook.STATUS_RESIST, {"against": "яд"}),
          "no modifiers means no immunity")


def test_conditional_bonus() -> None:
    print("\n[6] conditional bonuses sit outside the multiplier chain")
    p = pipeline()
    m = Modifier(ability=210, handler="bonus_vs_subtype", hook=Hook.DAMAGE_VS_TARGET,
                 power=4, params={"subtype": "Нежить"}, source="Сокрушение зла",
                 outside_multipliers=True)
    undead = Combatant(name="skeleton")
    undead.subtypes = {"Нежить"}
    living = Combatant(name="militia")
    v, _ = p.resolve(10, [m], Hook.DAMAGE_VS_TARGET, {"target": undead})
    check(v == 14, "+4 against the named subtype", str(v))
    v, _ = p.resolve(10, [m], Hook.DAMAGE_VS_TARGET, {"target": living})
    check(v == 10, "nothing against anyone else", str(v))
    check(m.outside_multipliers,
          "and the modifier is flagged so morale cannot scale it")


def test_additive_before_multiplicative() -> None:
    """The documented order, now enforced through the pipeline rather than by
    a hardcoded scalar field."""
    print("\n[7] modifiers land INSIDE the multiplier chain")
    combat.bind_pipeline(pipeline())
    try:
        u = Combatant(name="Мечник", attack=8, life_base=17, life=17,
                      stamina=10, stamina_base=10, morale=10, morale_base=10)
        u.modifiers = [Modifier(ability=2, handler="stat_delta",
                                hook=Hook.STAT_PASSIVE, power=2,
                                params={"stat": "attack"}, source="Атака +2")]
        healthy, _ = combat.current_attack(u, AttackKind.MELEE)
        check(healthy == 10.0, "8 + 2 with no penalties", str(healthy))

        u.stamina = 3          # StaminaMod 0.7
        wounded, t = combat.current_attack(u, AttackKind.MELEE)
        check(abs(wounded - 7.0) < 1e-9,
              "(8 + 2) * 0.7 = 7.0, not 8 * 0.7 + 2 = 7.6",
              str(wounded))
        check(any("Атака +2" in s[0] for s in t.steps),
              "and the trace names the modifier that did it")
    finally:
        combat.bind_pipeline(None)


def test_real_pack_binding() -> None:
    """The join this whole module exists for: a line in the shipped bindings
    file becomes a number change in combat."""
    print("\n[8] end to end, from packs/genesis/bindings.json")
    if not os.path.isdir(os.path.join("packs", "genesis", "data")):
        # Original .var data is never committed; the pack is generated locally.
        print("  SKIP  packs/genesis/data is missing — generate it with "
              "tools/extract/build_pack.py")
        return
    reg = registry()
    db = ContentDb.load("genesis", "packs/genesis", reg)
    if not db.pack.bindings:
        # The committed bindings.json is a skeleton with no opcodes bound.
        # Regenerate it locally before expecting a resolvable ability.
        print("  SKIP  packs/genesis/bindings.json binds no opcodes — "
              "regenerate with tools/extract/make_bindings.py")
        return
    check(not db.report.errors, "the genesis pack loads", db.report.summary())

    # Find a bound stat_delta opcode and drive it through the pipeline.
    found = None
    for opcode, b in sorted(db.pack.bindings.items()):
        if b.handler == "stat_delta" and b.params.get("stat") == "attack":
            found = (opcode, b)
            break
    check(found is not None, "the pack binds an Attack stat_delta opcode")
    if found is None:
        return
    opcode, b = found
    handler, params = db.resolve(opcode)
    check(handler == "stat_delta", "and resolve() returns its handler",
          "opcode %d = %s" % (opcode, b.name))

    m = from_binding(opcode, handler, params, power=3,
                     hook=Hook.STAT_PASSIVE, source=b.name)
    combat.bind_pipeline(Pipeline(reg))
    try:
        u = Combatant(name="test", attack=8, life_base=10, life=10,
                      stamina=10, stamina_base=10, morale=10, morale_base=10)
        plain, _ = combat.current_attack(u, AttackKind.MELEE)
        u.modifiers = [m]
        boosted, t = combat.current_attack(u, AttackKind.MELEE)
        check(boosted == plain + 3,
              "a bindings entry raises the attack by its power",
              "%s -> %s via %s" % (plain, boosted, b.name))
        check(any(b.name in s[0] for s in t.steps),
              "and the trace attributes it by the ability's own name")
    finally:
        combat.bind_pipeline(None)


def test_spell_grants() -> None:
    print("\n[9] spell grants are enumerable rather than numeric")
    mods = [
        Modifier(ability=2010, handler="grant_spell", hook=Hook.STAT_PASSIVE,
                 params={"spell": "Сглаз"}, source="Заклятье «Сглаз»"),
        Modifier(ability=2011, handler="grant_spell", hook=Hook.STAT_PASSIVE,
                 params={"spell": "Благословение"}, source="Заклятье «Благословение»"),
        Modifier(ability=2, handler="stat_delta", hook=Hook.STAT_PASSIVE,
                 power=1, params={"stat": "attack"}, source="Атака +1"),
    ]
    known = handlers.spells_granted(mods)
    check(known == {"Сглаз", "Благословение"},
          "walking the modifiers lists what the unit knows", str(sorted(known)))
    p = pipeline()
    v, _ = p.resolve(8, mods, Hook.STAT_PASSIVE, {"stat": "attack"})
    check(v == 9, "and granting a spell changes no number", str(v))


def test_derived_flags() -> None:
    """A flag is derived from the modifier list, not stored on the unit.

    This is what makes a temporary flag work at all. The alternative — having
    the roster run grant_flag at build time and mutate `flags` — is correct for
    innate abilities and silently wrong for every buff, which is the worse
    failure: it looks right in tests built from unit.var and breaks the first
    time a spell is cast.
    """
    print("\n[10] flags derive from modifiers and statuses")
    import statuses as st

    u = Combatant(name="u", life_base=20, life=5, stamina=10, stamina_base=10,
                  morale=10, morale_base=10)
    check(not u.has_flag("Не чувствует боли"), "a bare unit has no flags")
    check(abs(combat.wound_mod(u)[0] - 0.75) < 1e-9,
          "and takes the wound penalty", str(combat.wound_mod(u)[0]))

    innate = Modifier(ability=13, handler="grant_flag", hook=Hook.STAT_PASSIVE,
                      params={"flag": "Не чувствует боли"},
                      source="Не чувствует боли")
    u.modifiers.append(innate)
    check(u.has_flag("Не чувствует боли"), "an ability grants it")
    check(combat.wound_mod(u)[0] == 1.0,
          "and the EXISTING wound rule honours it, unchanged",
          str(combat.wound_mod(u)[0]))
    check(u.all_flags() == {"Не чувствует боли"}, "all_flags collects it")

    # the case the design exists for
    v = Combatant(name="v", life_base=20, life=5, stamina=10, stamina_base=10,
                  morale=10, morale_base=10)
    v.statuses.append(st.StatusEffect(
        id="rage", name="Боевое безумие", duration=2,
        modifiers=[Modifier(ability=25, handler="grant_flag",
                            hook=Hook.STAT_PASSIVE,
                            params={"flag": "Не чувствует боли"},
                            source="Боевое безумие")]))
    check(v.has_flag("Не чувствует боли"), "a status grants it too")
    check(combat.wound_mod(v)[0] == 1.0, "with the same effect")
    for _ in range(2):
        st.tick_round(v)
    check(not v.has_flag("Не чувствует боли"), "and it vanishes when the status expires")
    check(abs(combat.wound_mod(v)[0] - 0.75) < 1e-9,
          "restoring the penalty with no separate bookkeeping")

    # grant_flag itself must not mutate — that was the whole point
    reg = registry()
    p = Pipeline(reg)
    w = Combatant(name="w")
    p.resolve(0, [innate], Hook.STAT_PASSIVE, {"unit": w, "stat": "attack"})
    check(w.flags == set(), "grant_flag is a no-op: it never writes to `flags`")


def test_new_handler_families() -> None:
    print("\n[11] the handler families that closed the blockers")
    p = pipeline()

    # terrain knowledge: «каждый пункт знания выше первого увеличивает защиту
    # и контратаку на 1» — rank 1 gives movement relief only
    for rank, expect in ((1, 5), (2, 6), (3, 7)):
        m = Modifier(ability=32, handler="terrain_knowledge",
                     hook=Hook.STAT_PASSIVE, power=rank,
                     params={"terrain": "forest"}, source="Знание леса")
        got, _ = p.resolve(5, [m], Hook.STAT_PASSIVE, {"stat": "defence"})
        check(got == expect, "Знание леса rank %d -> defence %d" % (rank, expect),
              str(got))
    m = Modifier(ability=32, handler="terrain_knowledge", hook=Hook.STAT_PASSIVE,
                 power=3, params={"terrain": "forest"}, source="Знание леса")
    got, _ = p.resolve(9, [m], Hook.STAT_PASSIVE, {"stat": "attack"})
    check(got == 9, "and it does not touch Attack", str(got))
    check(handlers.knows_terrain([m], "forest") == 3, "rank is queryable")
    check(handlers.knows_terrain([m], "swamp") == 0, "for the right terrain only")

    # damage typing: «спасает не защита, а сопротивление»
    magic = Modifier(ability=27, handler="damage_type", hook=Hook.DAMAGE_BASE,
                     params={"type": "magic", "applies_to": "melee"},
                     source="Магический удар")
    check(handlers.defence_stat_for([magic], False) == "resist",
          "a magical melee attack resolves against Resist")
    check(handlers.defence_stat_for([magic], True) == "ranged_defence",
          "but its RANGED attack still uses ranged defence")
    check(handlers.defence_stat_for([], False) == "defence",
          "and an ordinary attacker uses Defence")

    # strategic-only: bound to an explicit no-op rather than left unbound
    siege = Modifier(ability=55, handler="strategic_only", hook=Hook.STAT_PASSIVE,
                     power=3, source="Осада")
    got, _ = p.resolve(10, [siege], Hook.STAT_PASSIVE, {"stat": "attack"})
    check(got == 10, "Осада changes nothing in a battle", str(got))

    regen = [Modifier(ability=48, handler="regeneration", hook=Hook.STAT_PASSIVE,
                      power=2, source="Регенерация")]
    check(handlers.regeneration_rate(regen) == 2, "regeneration rate is queryable")


if __name__ == "__main__":
    test_hook_order()
    test_stat_guard()
    test_unknown_handler()
    test_stable_order()
    test_flag()
    test_conditional_bonus()
    test_additive_before_multiplicative()
    test_real_pack_binding()
    test_spell_grants()
    test_derived_flags()
    test_new_handler_families()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
