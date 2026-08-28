"""CX-014 declarative data-defined action plan acceptance cells A-F."""
from __future__ import annotations

from dataclasses import FrozenInstanceError, replace
import copy

import pytest

import action_execution as ae
import actions
import combat
import content
import content_actions as ca
import declarative_action_recipe as dar
import scenario


def unit(name: str, **extra) -> dict:
    value = {"name": name, "life": 40, "life_base": 40, "attack": 9,
             "counter_attack": 0, "defence": 3, "stamina": 10,
             "stamina_base": 10, "morale": 10, "speed": 3}
    value.update(extra)
    return value


def attack_recipe(numerator=3, denominator=2) -> dict:
    return {"version": 1, "operations": [{
        "kind": "attack", "mode": "melee",
        "scale": {"numerator": numerator, "denominator": denominator},
    }]}


def fixed_drain(amount=-3) -> dict:
    return {"version": 1, "operations": [{
        "kind": "resource_delta", "target": "selected_enemy",
        "resource": "stamina", "amount": amount,
    }]}


def magnitude_drain() -> dict:
    return {"version": 1, "operations": [{
        "kind": "resource_delta", "target": "selected_enemy",
        "resource": "stamina",
        "amount": {"source": "action_magnitude", "sign": "negative"},
    }]}


def definition(source: int, recipe=None, *, name="Localized", magnitude=0,
               canonical_id=None, **extra) -> dict:
    value = {"source_id": source, "name": name, "target": "enemy_melee",
             "magnitude": magnitude}
    if recipe is not None:
        value["recipe"] = recipe
    if canonical_id is not None:
        value["canonical_id"] = canonical_id
    value.update(extra)
    return value


def provider(pack="alpha", overlay=None, *, target=None):
    definitions = {f"{pack}:unit/1": unit("Actor"),
                   f"{pack}:unit/2": target or unit("Target")}
    return content.ScenarioContentProvider(
        pack, definitions, version="v1", action_overlay=overlay or {})


def spec_for(p, *, profile="native", mode="strict", commands=None):
    value = {"name": "cx014", "profile": profile, "seed": 7,
             "death_replacement_load_mode": "permissive",
             "content": {"pack": p.pack_id, "version": "v1"},
             "battlefield": {"width": 3, "height": 2},
             "sides": [
                 {"id": 0, "units": [{"id": "actor",
                     "def": f"{p.pack_id}:unit/1", "at": [0, 0]}]},
                 {"id": 1, "units": [{"id": "target",
                     "def": f"{p.pack_id}:unit/2", "at": [1, 0]}]},
             ], "commands": commands or []}
    if mode != "strict":
        value["action_load_mode"] = mode
    return value


def overlay_for(*definitions, grants=None):
    return {"definitions": list(definitions), "grants": grants or {
        "alpha:unit/1": [{"source_id": definitions[0]["source_id"]}],
    }}


def test_declarative_melee_compiles_to_fresh_existing_typed_attack_plan():
    overlay = overlay_for(definition(700, attack_recipe(), name="First locale"))
    p = provider(overlay=overlay)
    composed = p.compose_actions("native")
    action = composed.definitions["alpha:action/700"]
    assert isinstance(action.declarative_recipe, dar.DeclarativeRecipe)
    first = ae.ActionRecipeResolver.resolve(action)
    second = ae.ActionRecipeResolver.resolve(replace(
        action, name="Completely different locale", source_id=999))
    assert first.supported and second.supported
    assert first.plan is not second.plan
    assert first.plan.operations is not second.plan.operations
    assert first.plan.operations[0] is not second.plan.operations[0]
    operation = first.plan.operations[0]
    assert isinstance(operation, ae.AttackOp)
    assert operation.mode is ae.AttackMode.MELEE
    assert (operation.initiating_attack_scale_numerator,
            operation.initiating_attack_scale_denominator) == (3, 2)
    with pytest.raises(FrozenInstanceError):
        operation.initiating_attack_scale_numerator = 9

    battle = scenario.Scenario(spec_for(p), content_provider=p)
    battle.cmd_action(battle.units["actor"], "700", battle.units["target"])
    assert battle.log[-1] == "unknown action '700'"
    battle.cmd_action(battle.units["actor"], "alpha:action/700",
                      battle.units["target"])
    assert any("resolved plan [AttackOp]" in line for line in battle.log)
    assert any("initiating attack scale 3/2" in line for line in battle.log)
    assert battle.units["target"].life < 40


def test_fixed_and_magnitude_stamina_recipes_reuse_drain_only_primitive():
    fixed_overlay = overlay_for(definition(701, fixed_drain(-3)))
    fixed_provider = provider(overlay=fixed_overlay)
    fixed = scenario.Scenario(spec_for(fixed_provider), content_provider=fixed_provider)
    fixed.cmd_action(fixed.units["actor"], "alpha:action/701", fixed.units["target"])
    assert fixed.units["target"].stamina == 7
    assert fixed.units["target"].life == 40
    assert fixed.units["target"].damage_received == [0, 0, 0, 0]
    assert not any(" hits " in line or " counters" in line for line in fixed.log)

    magnitude_overlay = overlay_for(
        definition(702, magnitude_drain(), magnitude=2), grants={
            "alpha:unit/1": [{"source_id": 702,
                              "overrides": {"magnitude": 5}}]})
    magnitude_provider = provider(overlay=magnitude_overlay)
    magnitude = scenario.Scenario(spec_for(magnitude_provider),
                                  content_provider=magnitude_provider)
    shared = magnitude.catalogue["alpha:action/702"]
    granted = magnitude.unit_catalogues["actor"]["alpha:action/702"]
    assert shared.magnitude == 2 and granted.magnitude == 5
    assert shared.declarative_recipe == granted.declarative_recipe
    magnitude.cmd_action(magnitude.units["actor"], "alpha:action/702",
                         magnitude.units["target"])
    assert magnitude.units["target"].stamina == 5
    assert shared.magnitude == 2

    immune_provider = provider(overlay=magnitude_overlay, target=unit("Target", modifiers=[{
        "ability": 0x12, "handler": "grant_flag", "power": 1,
        "semantics": ["stamina.mutation_suppressed"],
        "params": {"flag": "cx014-0x12"}}]))
    immune = scenario.Scenario(spec_for(immune_provider),
                               content_provider=immune_provider)
    immune.cmd_action(immune.units["actor"], "alpha:action/702",
                      immune.units["target"])
    assert immune.units["target"].stamina == 10
    assert any("stamina.mutation_suppressed" in line
               for line in immune.log)


def test_ordered_drains_then_final_attack_execute_in_declared_order():
    ordered = {"version": 1, "operations": [
        {"kind": "resource_delta", "target": "selected_enemy",
         "resource": "stamina", "amount": -1},
        {"kind": "resource_delta", "target": "selected_enemy",
         "resource": "stamina", "amount": -2},
        {"kind": "attack", "mode": "melee",
         "scale": {"numerator": 1, "denominator": 1}},
    ]}
    p = provider(overlay=overlay_for(definition(703, ordered)))
    battle = scenario.Scenario(spec_for(p), content_provider=p)
    battle.cmd_action(battle.units["actor"], "alpha:action/703",
                      battle.units["target"])
    operations = [line for line in battle.log if "  [action] operation " in line]
    assert ["ResourceDeltaOp" in operations[0], "ResourceDeltaOp" in operations[1],
            "AttackOp" in operations[2]] == [True, True, True]
    assert battle.units["target"].stamina == 7
    assert battle.units["target"].alive


INVALID_RECIPES = {
    "unknown operation": {"version": 1, "operations": [{"kind": "teleport"}]},
    "invalid attack ratio": attack_recipe(3, 0),
    "positive resource delta": fixed_drain(1),
    "two attacks": {"version": 1, "operations": [
        {"kind": "attack", "mode": "melee", "scale": {"numerator": 1, "denominator": 1}},
        {"kind": "attack", "mode": "melee", "scale": {"numerator": 1, "denominator": 1}}]},
    "operation after attack": {"version": 1, "operations": [
        {"kind": "attack", "mode": "melee", "scale": {"numerator": 1, "denominator": 1}},
        {"kind": "resource_delta", "target": "selected_enemy", "resource": "stamina", "amount": -1}]},
    "empty": {"version": 1, "operations": []},
}


@pytest.mark.parametrize("label,recipe", INVALID_RECIPES.items())
def test_invalid_recipe_strict_fails_permissive_refuses_without_partial_execution(
        label, recipe):
    invalid = definition(710, recipe, name="Invalid")
    valid = definition(711, fixed_drain(-2), name="Unrelated")
    overlay = overlay_for(invalid, valid, grants={
        "alpha:unit/1": [{"source_id": 710}, {"source_id": 711}]})
    p = provider(overlay=overlay)
    with pytest.raises(ca.ActionCompositionError) as exc:
        p.compose_actions("native", ca.STRICT)
    assert "invalid_declarative_recipe" in {d["code"] for d in exc.value.diagnostics}

    composed = p.compose_actions("native", ca.PERMISSIVE)
    assert "alpha:action/710" in composed.definitions
    assert "alpha:action/711" in composed.definitions
    battle = scenario.Scenario(spec_for(p, mode="permissive"), content_provider=p)
    actor, target = battle.units["actor"], battle.units["target"]
    before = (actor.stamina, actor.action_spent, target.life, target.stamina)
    battle.cmd_action(actor, "alpha:action/710", target)
    assert "invalid declarative recipe" in battle.log[-1]
    assert (actor.stamina, actor.action_spent, target.life, target.stamina) == before
    battle.cmd_action(actor, "alpha:action/711", target)
    assert target.stamina == before[3] - 2, label


def test_shared_recipe_override_is_diagnostic_and_engine_recipe_wins():
    attempted = definition(59, {"version": 1, "operations": [{"kind": "unknown"}]},
                           name="Attempt", shared_id="crushing_blow", replace=True)
    unrelated = definition(720, fixed_drain(-1))
    overlay = {"definitions": [attempted, unrelated], "grants": {
        "alpha:unit/1": [{"source_id": 59}, {"source_id": 720}]}}
    p = provider(overlay=overlay)
    with pytest.raises(ca.ActionCompositionError) as exc:
        p.compose_actions("genesis", ca.STRICT)
    assert {d["code"] for d in exc.value.diagnostics} == {"shared_recipe_override"}
    composed = p.compose_actions("genesis", ca.PERMISSIVE)
    assert composed.definitions["crushing_blow"].declarative_recipe is None
    built_in = ae.ActionRecipeResolver.resolve(composed.definitions["crushing_blow"])
    assert isinstance(built_in.plan.operations[0], ae.AttackOp)
    battle = scenario.Scenario(spec_for(p, profile="genesis", mode="permissive"),
                               content_provider=p)
    battle.cmd_action(battle.units["actor"], "crushing_blow", battle.units["target"])
    assert any("crushing_blow resolved plan [AttackOp]" in line for line in battle.log)
    assert battle.units["target"].life < 40
    unrelated_battle = scenario.Scenario(
        spec_for(p, profile="genesis", mode="permissive"), content_provider=p)
    unrelated_battle.cmd_action(unrelated_battle.units["actor"],
                                "alpha:action/720",
                                unrelated_battle.units["target"])
    assert unrelated_battle.units["target"].stamina == 9


def test_pack_identity_isolation_and_localization_independence():
    one = provider("one", {"definitions": [definition(730, fixed_drain(-1), name="One")],
        "grants": {"one:unit/1": [{"source_id": 730}]}})
    two = provider("two", {"definitions": [definition(730, fixed_drain(-4), name="Two")],
        "grants": {"two:unit/1": [{"source_id": 730}]}})
    a1 = one.compose_actions("native").definitions["one:action/730"]
    a2 = two.compose_actions("native").definitions["two:action/730"]
    assert ae.ActionRecipeResolver.resolve(a1).plan.operations[0].amount == -1
    assert ae.ActionRecipeResolver.resolve(a2).plan.operations[0].amount == -4
    renamed = replace(a1, name="Translated")
    assert ae.ActionRecipeResolver.resolve(renamed).plan.operations[0].amount == -1

    theft = {"definitions": [definition(
        731, fixed_drain(-1), canonical_id="two:action/731")]}
    with pytest.raises(ca.ActionCompositionError):
        provider("one", theft).compose_actions("native")
    permissive = provider("one", theft).compose_actions("native", ca.PERMISSIVE)
    assert "two:action/731" not in permissive.definitions


def test_cx013_shared_and_other_reference_boundaries_remain_unchanged():
    crushing = ae.ActionRecipeResolver.resolve(actions.REFERENCE_CATALOGUE["crushing_blow"])
    shield = ae.ActionRecipeResolver.resolve(replace(
        actions.REFERENCE_CATALOGUE["shield_bash"], magnitude=4))
    assert isinstance(crushing.plan.operations[0], ae.AttackOp)
    assert isinstance(shield.plan.operations[0], ae.ResourceDeltaOp)
    unsupported = set(actions.REFERENCE_CATALOGUE) - {"crushing_blow", "shield_bash"}
    assert len(unsupported) == 12
    assert all(not ae.ActionRecipeResolver.resolve(
        actions.REFERENCE_CATALOGUE[action_id]).supported for action_id in unsupported)
    assert not hasattr(actions.Action, "suppresses_counterattack")
    assert not hasattr(ae.AttackOp, "suppresses_counterattack")
