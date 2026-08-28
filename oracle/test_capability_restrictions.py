"""CX-015 typed tactical capability restriction acceptance coverage."""
from __future__ import annotations

from dataclasses import fields

import action_execution
import actions
import battlefield as bfmod
import content
import scenario
import statuses as st
import turn
from combat import Combatant


CAPABILITIES = tuple(st.Capability)


class CountingRng:
    def __init__(self):
        self.calls = 0

    def roll(self, upper: int, stream: str = "combat") -> int:
        self.calls += 1
        return max(0, upper - 1)


def fighter(name: str, at: list[int]) -> dict:
    return {
        "name": name, "at": at, "life": 40, "life_base": 40,
        "attack": 9, "ranged_attack": 9, "shooting_range": 5, "ammo": 3,
        "ammo_base": 3, "counter_attack": 0, "defence": 1,
        "ranged_defence": 1, "speed": 3, "movement_remaining": 3,
        "stamina": 10, "stamina_base": 10, "morale": 10,
    }


def action_dict(action_id: str, magnitude: int = 4) -> dict:
    action = actions.REFERENCE_CATALOGUE[action_id]
    return {
        "id": action.id, "source_id": action.source_id, "name": "Synthetic",
        "target": 1, "cost_stamina": action.cost.stamina,
        "cost_ammo": action.cost.ammo,
        "consumes_action": action.cost.consumes_action,
        "attack_surcharge": action.cost.attack_surcharge,
        "magnitude": magnitude, "is_attack": action.is_attack,
        "damage_scale": action.damage_scale,
        "excluded_targets": list(action.excluded_targets),
    }


def battle(*, rng=None) -> scenario.Scenario:
    spec = {
        "name": "cx015", "profile": "native", "seed": 5,
        "battlefield": {"width": 4, "height": 3},
        "actions": [action_dict("crushing_blow"), action_dict("shield_bash")],
        "sides": [
            {"id": 0, "is_attacker": True, "leader_initiative": 1,
             "units": [fighter("actor", [0, 0])]},
            {"id": 1, "leader_initiative": 0,
             "units": [fighter("target", [1, 0])]},
        ], "commands": [],
    }
    return scenario.Scenario(spec, rng=rng)


def restrict(unit: Combatant, capability: st.Capability, identity="block"):
    effect = st.StatusEffect(
        id=identity, name="Synthetic %s block" % capability.value,
        duration=3, hostile=True, restrictions=(capability,))
    st.apply(unit, effect)
    return effect


def snapshot(sc: scenario.Scenario) -> tuple:
    actor, target = sc.units["actor"], sc.units["target"]
    return (
        actor.alive, actor.life, actor.stamina, actor.ammo, actor.action_spent,
        actor.movement_remaining, actor.steps_this_round, actor.forced_rest,
        actor.resting, tuple(actor.damage_received),
        bfmod.axial_to_offset(sc.field.find(actor)),
        target.alive, target.life, target.stamina, target.ammo, target.action_spent,
        target.movement_remaining, target.steps_this_round, target.forced_rest,
        target.resting, tuple(target.damage_received),
        bfmod.axial_to_offset(sc.field.find(target)),
        tuple((effect.id, effect.duration) for effect in actor.statuses),
        tuple((effect.id, effect.duration) for effect in target.statuses),
    )


def declarative_battle() -> scenario.Scenario:
    recipe = {"version": 1, "operations": [{
        "kind": "attack", "mode": "melee",
        "scale": {"numerator": 1, "denominator": 1},
    }]}
    actor_definition = fighter("Actor", [0, 0])
    target_definition = fighter("Target", [0, 0])
    actor_definition.pop("at")
    target_definition.pop("at")
    provider = content.ScenarioContentProvider(
        "alpha", {"alpha:unit/1": actor_definition,
                  "alpha:unit/2": target_definition},
        version="v1", action_overlay={
            "definitions": [{"source_id": 700, "name": "Synthetic pack action",
                             "target": "enemy_melee", "recipe": recipe}],
            "grants": {"alpha:unit/1": [{"source_id": 700}]},
        })
    spec = {
        "name": "cx015 declarative", "profile": "native", "seed": 5,
        "content": {"pack": "alpha", "version": "v1"},
        "battlefield": {"width": 3, "height": 2},
        "sides": [
            {"id": 0, "units": [{"id": "actor", "def": "alpha:unit/1",
                                  "at": [0, 0]}]},
            {"id": 1, "units": [{"id": "target", "def": "alpha:unit/2",
                                  "at": [1, 0]}]},
        ], "commands": [],
    }
    return scenario.Scenario(spec, content_provider=provider)


def test_independence_matrix_and_typed_diagnostics():
    for blocked in CAPABILITIES:
        unit = Combatant(name="unit")
        restrict(unit, blocked, blocked.value)
        for queried in CAPABILITIES:
            allowed, blocker = st.can_perform(unit, queried)
            assert allowed is (queried is not blocked)
            assert blocker == ("" if allowed else "Synthetic %s block" % blocked.value)

    unknown = st.can_perform(Combatant(name="unit"), "movement")
    assert unknown == (False, "unknown capability")


def test_full_disable_union_overlap_removal_and_explicit_expiry():
    unit = Combatant(name="unit")
    all_in_one = st.StatusEffect(
        id="all", restrictions=[capability.value for capability in CAPABILITIES]
        + ["melee"])
    assert len(all_in_one.restrictions) == 5
    st.apply(unit, all_in_one)
    assert all(not st.can_perform(unit, capability)[0] for capability in CAPABILITIES)
    assert all_in_one.to_dict()["restrictions"] == [c.value for c in CAPABILITIES]

    split = Combatant(name="split")
    for capability in CAPABILITIES:
        restrict(split, capability, capability.value)
    restrict(split, st.Capability.MELEE, "melee-second")
    assert all(not st.can_perform(split, capability)[0] for capability in CAPABILITIES)
    assert st.remove(split, "melee") == 1
    assert not st.can_perform(split, st.Capability.MELEE)[0]
    assert st.remove(split, "melee-second") == 1
    assert st.can_perform(split, st.Capability.MELEE)[0]
    assert all(not st.can_perform(split, capability)[0]
               for capability in CAPABILITIES if capability is not st.Capability.MELEE)

    expiring = Combatant(name="expiring")
    st.apply(expiring, st.StatusEffect(
        id="temporary", duration=1, hostile=True,
        restrictions=(st.Capability.RANGED,)))
    assert not st.can_perform(expiring, st.Capability.RANGED)[0]
    st.reduce_duration(expiring, 1)
    assert st.can_perform(expiring, st.Capability.RANGED)[0]


def test_copy_serialization_validation_and_generic_authority_removal():
    effect = st.StatusEffect(id="copy", restrictions=["movement", "movement"])
    clone = effect.copy()
    assert clone.restrictions == effect.restrictions == frozenset({st.Capability.MOVEMENT})
    assert clone.to_dict()["restrictions"] == ["movement"]
    try:
        st.StatusEffect(id="bad", restrictions=["raw-legacy-name"])
    except ValueError as exc:
        assert "unknown status capability" in str(exc)
    else:
        raise AssertionError("unknown capability was accepted")
    for malformed in (None, "movement", [1]):
        try:
            st.StatusEffect(id="malformed", restrictions=malformed)
        except ValueError:
            pass
        else:
            raise AssertionError("malformed restriction collection was accepted")
    assert "prevents_action" not in {item.name for item in fields(st.StatusEffect)}
    try:
        st.StatusEffect(id="obsolete", prevents_action=True)
    except TypeError:
        pass
    else:
        raise AssertionError("removed prevents_action input was accepted")
    assert not hasattr(st, "can_act")


def test_movement_precedence_and_integrated_refusals_are_mutation_free():
    spent = Combatant(name="spent", movement_remaining=0, action_spent=True)
    restrict(spent, st.Capability.MOVEMENT)
    assert turn.can_move(spent) is turn.Refusal.ACTION_SPENT
    spent.action_spent = False
    assert turn.can_move(spent) is turn.Refusal.RESTRICTED

    cases = [
        (st.Capability.MOVEMENT, lambda sc: sc.cmd_move(sc.units["actor"], 0, 1)),
        (st.Capability.MELEE, lambda sc: sc.cmd_attack(sc.units["actor"], sc.units["target"])),
        (st.Capability.RANGED, lambda sc: sc.cmd_shoot(sc.units["actor"], sc.units["target"])),
        (st.Capability.ACTIVATED_ACTION,
         lambda sc: sc.cmd_action(sc.units["actor"], "crushing_blow", sc.units["target"])),
        (st.Capability.ACTIVATED_ACTION,
         lambda sc: sc.cmd_action(sc.units["actor"], "shield_bash", sc.units["target"])),
    ]
    for capability, command in cases:
        rng = CountingRng()
        sc = battle(rng=rng)
        restrict(sc.units["actor"], capability)
        before = snapshot(sc)
        command(sc)
        assert snapshot(sc) == before
        assert rng.calls == 0
        assert capability.value in sc.log[-1]


def test_command_boundaries_are_independent():
    movement_only = battle(rng=CountingRng())
    restrict(movement_only.units["actor"], st.Capability.MOVEMENT)
    movement_only.cmd_attack(movement_only.units["actor"], movement_only.units["target"])
    assert movement_only.units["target"].life < 40

    melee_only = battle(rng=CountingRng())
    restrict(melee_only.units["actor"], st.Capability.MELEE)
    melee_only.cmd_action(melee_only.units["actor"], "crushing_blow",
                          melee_only.units["target"])
    assert melee_only.units["target"].life < 40

    activated_only = battle(rng=CountingRng())
    restrict(activated_only.units["actor"], st.Capability.ACTIVATED_ACTION)
    activated_only.cmd_attack(activated_only.units["actor"], activated_only.units["target"])
    assert activated_only.units["target"].life < 40

    ranged_only = battle(rng=CountingRng())
    restrict(ranged_only.units["actor"], st.Capability.RANGED)
    ranged_only.cmd_move(ranged_only.units["actor"], 0, 1)
    assert bfmod.axial_to_offset(ranged_only.field.find(ranged_only.units["actor"])) == (0, 1)


def test_declarative_activated_action_boundary():
    blocked = declarative_battle()
    restrict(blocked.units["actor"], st.Capability.ACTIVATED_ACTION)
    before = snapshot(blocked)
    blocked.cmd_action(blocked.units["actor"], "alpha:action/700",
                       blocked.units["target"])
    assert snapshot(blocked) == before
    assert "activated_action restricted" in blocked.log[-1]

    melee_only = declarative_battle()
    restrict(melee_only.units["actor"], st.Capability.MELEE)
    melee_only.cmd_action(melee_only.units["actor"], "alpha:action/700",
                          melee_only.units["target"])
    assert melee_only.units["target"].life < 40
    assert any("resolved plan [AttackOp]" in line for line in melee_only.log)

def test_restriction_serialization_canonicalizes_noncanonical_input() -> None:
    effect = st.StatusEffect(
        id="serialization-order",
        restrictions=["ranged", "movement"],
    )
    assert effect.to_dict()["restrictions"] == ["movement", "ranged"]
