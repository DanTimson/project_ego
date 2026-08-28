from __future__ import annotations

from dataclasses import FrozenInstanceError, replace
import copy

import pytest

import action_execution as ae
import actions
import combat
import scenario
from combat import AttackKind, Combatant
from modifier import Hook, Modifier


def _action_dict(action_id: str, *, magnitude: int = 0, name: str = "Localized") -> dict:
    action = actions.REFERENCE_CATALOGUE[action_id]
    return {
        "id": action.id, "source_id": action.source_id, "name": name,
        "target": 1, "cost_stamina": action.cost.stamina,
        "cost_ammo": action.cost.ammo,
        "consumes_action": action.cost.consumes_action,
        "attack_surcharge": action.cost.attack_surcharge,
        "magnitude": magnitude, "is_attack": action.is_attack,
        "damage_scale": action.damage_scale,
        "excluded_targets": list(action.excluded_targets),
    }


def _fighter(name: str, at: list[int], **overrides) -> dict:
    unit = {
        "name": name, "at": at, "life": 30, "life_base": 30,
        "attack": 9, "counter_attack": 5, "defence": 3,
        "speed": 2, "stamina": 10, "stamina_base": 10, "morale": 10,
    }
    unit.update(overrides)
    return unit


def _run_action(action_id: str = "shield_bash", *, magnitude: int = 4,
                actor: dict | None = None, target: dict | None = None,
                target_at: list[int] | None = None,
                command_target: str | None = "target", allied: bool = False,
                profile: str = "native"):
    actor = actor or _fighter("actor", [1, 1])
    target = target or _fighter("target", target_at or [2, 1])
    command = {"op": "action", "unit": "actor", "action": action_id}
    if command_target is not None:
        command["target"] = command_target
    sides = [
        {"id": 0, "is_attacker": True, "leader_initiative": 2,
         "units": [actor] + ([target] if allied else [])},
        {"id": 1, "leader_initiative": 1,
         "units": [] if allied else [target]},
    ]
    spec = {
        "name": "typed action vector", "profile": profile, "seed": 19,
        "death_replacement_load_mode": "permissive",
        "battlefield": {"width": 6, "height": 4, "tiles": []},
        "actions": ([] if action_id == "nonesuch" else
                    [_action_dict(action_id, magnitude=magnitude)]),
        "sides": sides, "commands": [command],
    }
    battle = scenario.Scenario(copy.deepcopy(spec))
    return battle, battle.run()


def test_plan_resolution_is_typed_immutable_and_identity_based() -> None:
    assert {key: value.source_id for key, value in actions.REFERENCE_CATALOGUE.items()} == {
        "extra_shot": 20, "power_shot": 361, "crushing_blow": 59,
        "whirlwind": 66, "shield_bash": 388, "frenzy": 454,
        "turtle": 458, "forced_march": 29, "sniper_shot": 360,
        "healing": 24, "repair": 374, "gather_ammo": 23,
        "carrion_eater": 49, "strike_and_return": 518,
    }
    assert actions.canonical_id_for_source(59, actions.REFERENCE_CATALOGUE) == "crushing_blow"
    assert actions.canonical_id_for_source(388, actions.REFERENCE_CATALOGUE) == "shield_bash"
    assert actions.canonical_id_for_source(999999, actions.REFERENCE_CATALOGUE) is None
    crushing = actions.REFERENCE_CATALOGUE["crushing_blow"]
    renamed = replace(crushing, name="Any locale at all")
    before = copy.deepcopy(crushing)
    r1 = ae.ActionRecipeResolver.resolve(crushing)
    r2 = ae.ActionRecipeResolver.resolve(renamed)
    assert r1.supported and r2.supported
    assert r1.plan == r2.plan
    assert len(r1.plan.operations) == 1
    attack = r1.plan.operations[0]
    assert isinstance(attack, ae.AttackOp)
    assert attack.mode is ae.AttackMode.MELEE
    assert not hasattr(attack, "suppresses_counterattack")
    assert (attack.initiating_attack_scale_numerator,
            attack.initiating_attack_scale_denominator) == (3, 2)
    assert crushing == before and crushing.source_id == 59

    shield = replace(actions.REFERENCE_CATALOGUE["shield_bash"], magnitude=7,
                     name="Not Russian")
    shield_resolution = ae.ActionRecipeResolver.resolve(shield)
    resource = shield_resolution.plan.operations[0]
    assert isinstance(resource, ae.ResourceDeltaOp)
    assert (resource.target, resource.resource, resource.amount) == (
        ae.OperationTarget.SELECTED_ENEMY, ae.Resource.STAMINA, -7)
    with pytest.raises(ValueError, match="supports drains only"):
        ae.ResourceDeltaOp(ae.OperationTarget.SELECTED_ENEMY,
                           ae.Resource.STAMINA, 1)
    assert shield.source_id == 388

    separate = ae.ActionRecipeResolver.resolve(crushing)
    assert separate.plan is not r1.plan
    assert separate.plan.operations is not r1.plan.operations
    assert separate.plan.operations[0] is not attack
    with pytest.raises(FrozenInstanceError):
        attack.initiating_attack_scale_numerator = 9

    unsupported = ae.ActionRecipeResolver.resolve(actions.REFERENCE_CATALOGUE["extra_shot"])
    assert not unsupported.supported and unsupported.plan is None


def test_integer_only_signed_scale_uses_realistic_odd_values() -> None:
    assert [combat.trunc0_ratio(value, 3, 2)
            for value in (1, 3, 9, 19, -3)] == [1, 4, 13, 28, -4]


def test_plan_executor_owns_ordered_operation_iteration() -> None:
    plan = ae.ActionExecutionPlan((
        ae.AttackOp(ae.AttackMode.MELEE, 3, 2),
        ae.ResourceDeltaOp(ae.OperationTarget.SELECTED_ENEMY,
                           ae.Resource.STAMINA, 0),
    ))
    seen = []
    result = ae.ActionPlanExecutor.execute(
        plan,
        attack_primitive=lambda operation: seen.append(operation.kind),
        resource_delta_primitive=lambda operation: seen.append(operation.kind))
    assert seen == ["AttackOp", "ResourceDeltaOp"]
    assert result == (None, None)


def test_plan_creation_and_refusal_are_mutation_free() -> None:
    unit = Combatant(stamina=10, life=20)
    action = replace(actions.REFERENCE_CATALOGUE["shield_bash"], magnitude=4)
    before = copy.deepcopy(unit.__dict__)
    ae.ActionRecipeResolver.resolve(action)
    assert unit.__dict__ == before

    cases = [
        _run_action("nonesuch"),
        _run_action("extra_shot"),
        _run_action(actor=_fighter("actor", [1, 1], stamina=1)),
        _run_action(command_target=None),
        _run_action(command_target="absent"),
        _run_action(allied=True),
        _run_action(target=_fighter("target", [2, 1], alive=False, life=0)),
        _run_action(target_at=[5, 3]),
        _run_action(target=_fighter("target", [2, 1], flags=["Бестелесный"])),
    ]
    for battle, result in cases:
        actor = battle.units["actor"]
        assert (actor.stamina, actor.action_spent) == (
            int(next(u for side in battle.spec["sides"] for u in side["units"]
                     if u["name"] == "actor")["stamina"]), False)
        assert not any(" requests action " in line for line in result["log"])


def test_crushing_blow_uses_one_scaled_primary_and_shared_exchange() -> None:
    class ZeroRng:
        @staticmethod
        def roll(_n, _stream="attack"):
            return 0

    attacker = Combatant(name="a", attack=9, counter_attack=2, life=30,
                         life_base=30, stamina=10, stamina_base=10, morale=10)
    defender = Combatant(name="d", defence=8, counter_attack=5, life=30,
                         life_base=30, stamina=10, stamina_base=10, morale=10)
    op = ae.ActionRecipeResolver.resolve(
        actions.REFERENCE_CATALOGUE["crushing_blow"]).plan.operations[0]
    damage, traces = combat.resolve_attack(
        attacker, defender, AttackKind.MELEE, ZeroRng(),
        initiating_scale_numerator=op.initiating_attack_scale_numerator,
        initiating_scale_denominator=op.initiating_attack_scale_denominator)
    # Independent arithmetic: effective 9 -> trunc0(9*3/2)=13 -> roll 15 -> 8 defence = 7.
    # Scaling final ordinary damage would instead produce trunc0((10-8)*3/2)=3.
    assert damage == 7 and damage != 3
    assert sum(step[0] == "initiating attack scale 3/2"
               for trace in traces for step in trace.steps) == 1

    battle, result = _run_action("crushing_blow")
    actor, target = battle.units["actor"], battle.units["target"]
    lines = result["log"]
    assert actor.stamina == 9 and actor.action_spent
    assert target.damage_received[0] > 0
    assert sum("initiating attack scale 3/2" in line for line in lines) == 1
    assert not any("attack stamina mutation" in line for line in lines)
    assert any("counters" in line for line in lines)
    assert not target.action_spent

    charge_actor = _fighter("actor", [1, 1], modifiers=[{
        "ability": 0x25, "handler": "grant_flag", "power": 1,
        "params": {"flag": "test-0x25"}}])
    _charged, charged_result = _run_action(
        "crushing_blow", actor=charge_actor, profile="genesis")
    assert any("command-entry charge" in line for line in charged_result["log"])
    assert any("command-entry charge consumption" in line
               for line in charged_result["log"])

    # The ephemeral context reaches only the initiating primary; a later ordinary
    # calculation and the defender counter remain unscaled.
    later, later_traces = combat.resolve_attack(
        Combatant(attack=9, life=30, life_base=30, stamina=10,
                  stamina_base=10, morale=10),
        Combatant(defence=8, life=30, life_base=30, stamina=10,
                  stamina_base=10, morale=10),
        AttackKind.MELEE, ZeroRng())
    assert later == 2
    assert not any("initiating attack scale" in step[0]
                   for trace in later_traces for step in trace.steps)


def test_crushing_blow_retaliation_gates_and_death_sink() -> None:
    evasive, evasive_result = _run_action(
        "crushing_blow", actor=_fighter("actor", [1, 1], flags=["Ловкость"]))
    assert not any("counters" in line for line in evasive_result["log"])
    assert evasive.units["actor"].life == 30

    fatal, fatal_result = _run_action(
        "crushing_blow", target=_fighter("target", [2, 1], life=1,
                                          life_base=1, counter_attack=9))
    target = fatal.units["target"]
    assert (not target.alive and target.damage_received[0] > 0
            and target.damage_received[1:] == [0, 0, 0])
    assert sum("target falls" in line for line in fatal_result["log"]) == 1


def test_shield_bash_is_a_gated_stamina_delta_only() -> None:
    battle, result = _run_action(
        "shield_bash", magnitude=4,
        target=_fighter("target", [2, 1], flags=["Первый удар"]))
    actor, target = battle.units["actor"], battle.units["target"]
    assert actor.stamina == 8 and actor.action_spent
    assert target.stamina == 6 and target.life == 30
    assert target.damage_received == [0, 0, 0, 0]
    assert not target.action_spent
    assert not any(word in "\n".join(result["log"])
                   for word in (" hits ", " counters", "attack randomisation"))

    floor, _ = _run_action(
        "shield_bash", magnitude=4,
        target=_fighter("target", [2, 1], stamina=2, stamina_base=10))
    assert floor.units["target"].stamina == 0

    immune_target = _fighter("target", [2, 1], stamina=7, modifiers=[{
        "ability": 0x12, "handler": "grant_flag", "power": 1,
        "semantics": ["stamina.mutation_suppressed"],
        "params": {"flag": "test-0x12"}}])
    immune, immune_result = _run_action(
        "shield_bash", magnitude=4, target=immune_target)
    assert immune.units["target"].stamina == 7
    assert any("stamina.mutation_suppressed" in line
               for line in immune_result["log"])

    aura_provider = {"auras": [{
        "id": "effective-0x12", "scope": "ADJACENT", "affects": "ENEMY",
        "modifiers": [{"ability": 0x12, "handler": "grant_flag", "power": 1,
                       "semantics": ["stamina.mutation_suppressed"],
                       "params": {"flag": "aura-0x12"}}],
    }]}
    aura_immune, _ = _run_action(
        "shield_bash", magnitude=4,
        actor=_fighter("actor", [1, 1], **aura_provider),
        target=_fighter("target", [2, 1], stamina=7))
    assert aura_immune.units["target"].stamina == 7
    assert not aura_immune.units["target"].has_modifier_id(0x12)

    raw = Combatant(name="raw", stamina=7)
    raw.modifiers.append(Modifier(0x12, "grant_flag", Hook.STAT_PASSIVE,
                                  power=1, params={"flag": "raw-0x12"}))
    combat.apply_tactical_stamina_drain(
        raw, -2, semantic_suppression_effective=False)
    assert raw.stamina == 5
    with pytest.raises(ValueError, match="supports drains only"):
        combat.apply_tactical_stamina_drain(raw, 1)

    immune_actor = _fighter("actor", [1, 1], modifiers=[{
        "ability": 0x12, "handler": "grant_flag", "power": 1,
        "semantics": ["stamina.mutation_suppressed"],
        "params": {"flag": "test-0x12"}}])
    actor_immune, _ = _run_action(
        "shield_bash", magnitude=4, actor=immune_actor)
    assert actor_immune.units["actor"].stamina == 10
    assert actor_immune.units["actor"].action_spent


def test_committed_typed_action_scenario_has_independent_expected_state() -> None:
    import json
    with open("tests/scenarios/actions.json", encoding="utf-8") as fh:
        battle = scenario.Scenario(json.load(fh))
    result = battle.run()
    assert result["final"]["CrusherTarget"]["life"] == 19
    assert result["final"]["Crusher"]["life"] == 26
    assert result["final"]["Crusher"]["stamina"] == 9
    assert result["final"]["BashTarget"]["life"] == 25
    assert result["final"]["BashTarget"]["stamina"] == 5
    assert result["final"]["Basher"]["stamina"] == 8
    assert any("crushing_blow resolved plan [AttackOp]" in line
               for line in result["log"])
    assert any("shield_bash resolved plan [ResourceDeltaOp]" in line
               for line in result["log"])
