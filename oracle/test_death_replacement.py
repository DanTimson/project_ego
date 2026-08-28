from __future__ import annotations

import copy

import pytest

import battlefield as bfmod
import combat
import content
import death_lifecycle
import death_replacement as replacement
import statuses
from modifier import Hook, Modifier
import turn
import scenario


def definition(name: str, life: int = 20):
    return {"name": name, "tier": 1, "life_base": life, "stamina_base": 7,
            "morale_base": 9, "ammo_base": 3, "speed": 2, "modifiers": []}


def provider(pack="balance_mod", compatibility="genesis", missing=(), malformed=()):
    definitions = {}
    for source in (21, 37, 56, 65):
        if source not in missing:
            definitions[f"{pack}:unit/{source}"] = (
                "bad" if source in malformed
                else definition(f"modified-{source}", 100 + source))
    return content.ScenarioContentProvider(
        pack, definitions, compatibility=compatibility)


def marker():
    return statuses.StatusEffect(id="synthetic Genesis marker", modifiers=[Modifier(
        ability=replacement.GENESIS_REPLACEMENT_MARKER, handler="noop",
        hook=Hook.STAT_PASSIVE)])


def victim(tier=1):
    return combat.Combatant(name="victim", instance_id="victim", tier=tier,
                            life=0, life_base=10, alive=False, statuses=[marker()])


def lifecycle_case(unit):
    field = bfmod.Battlefield(3, 3)
    field.place(unit, bfmod.offset_to_axial(1, 1))
    sides = [turn.Side(0, "left", [unit]), turn.Side(1, "right", [])]
    return field, sides


def test_fixed_genesis_mapping_is_owned_by_dedicated_resolver():
    assert [replacement.GenesisDeathReplacementResolver.source_record_for_tier(t)
            for t in range(1, 5)] == [21, 37, 56, 65]
    with pytest.raises(ValueError, match="tier 1..4"):
        replacement.GenesisDeathReplacementResolver.source_record_for_tier(0)
    assert not hasattr(death_lifecycle, "replacement_id_for_tier")
    assert not hasattr(death_lifecycle, "REPLACEMENT_BY_TIER")


def test_custom_pack_genesis_compatibility_resolves_modified_selected_definition():
    resolver = replacement.GenesisDeathReplacementResolver("genesis", provider())
    decision = resolver.decision_for(victim(1))
    assert decision["status"] == "resolved"
    assert decision["definition_id"] == 21
    assert decision["definition"]["content_id"] == "balance_mod:unit/21"
    assert decision["definition"]["name"] == "modified-21"
    unit = victim(1)
    field, sides = lifecycle_case(unit)
    result = death_lifecycle.resolve(unit, field, sides, resolver.decision_for)
    assert result["branch"] == "replaced" and unit.life == 121
    assert unit.content_id == "balance_mod:unit/21"


def test_numeric_collision_and_rules_content_independence():
    collision = provider("unrelated", compatibility="unspecified")
    with pytest.raises(replacement.DeathReplacementConfigurationError) as exc:
        replacement.GenesisDeathReplacementResolver("genesis", collision)
    assert exc.value.diagnostics[0]["code"] == "genesis_content_compatibility_mismatch"
    native = replacement.GenesisDeathReplacementResolver("native", collision)
    assert native.decision_for(victim())["status"] == "not_applicable"
    native_with_genesis = replacement.GenesisDeathReplacementResolver("native", provider())
    assert native_with_genesis.decision_for(victim())["status"] == "not_applicable"


def test_explicit_override_is_observable_and_keeps_fixed_mapping():
    resolver = replacement.GenesisDeathReplacementResolver(
        "genesis", provider("odd_name", compatibility="new_horizons"),
        compatibility_override="genesis")
    state = resolver.normalized_state()
    assert state["compatibility_override"] is True
    assert state["compatibility_source"] == "load_override"
    assert any(d["code"] == "explicit_compatibility_override"
               for d in state["diagnostics"])
    assert resolver.decision_for(victim(4))["definition_id"] == 65


def test_strict_validates_all_targets_and_malformed_targets():
    with pytest.raises(replacement.DeathReplacementConfigurationError) as missing:
        replacement.GenesisDeathReplacementResolver(
            "genesis", provider(missing=(56,)))
    assert any(d.get("source_record") == 56 for d in missing.value.diagnostics)
    with pytest.raises(replacement.DeathReplacementConfigurationError) as malformed:
        replacement.GenesisDeathReplacementResolver(
            "genesis", provider(malformed=(37,)))
    assert any(d.get("source_record") == 37 for d in malformed.value.diagnostics)


def test_permissive_retains_diagnostics_and_fails_only_exercised_missing_tier():
    resolver = replacement.GenesisDeathReplacementResolver(
        "genesis", provider(missing=(56,)), mode="permissive")
    assert any(d.get("source_record") == 56 for d in resolver.diagnostics)
    assert resolver.decision_for(victim(1))["status"] == "resolved"
    assert resolver.decision_for(victim(3))["status"] == "unresolved"
    unrelated = victim(1)
    unrelated.statuses = []
    assert resolver.decision_for(unrelated)["status"] == "not_applicable"
    field, sides = lifecycle_case(victim(3))
    with pytest.raises(ValueError, match="source record 56"):
        death_lifecycle.resolve(sides[0].units[0], field, sides,
                                resolver.decision_for)


def test_invalid_tier_fails_only_when_applicable_path_is_exercised():
    resolver = replacement.GenesisDeathReplacementResolver("genesis", provider())
    decision = resolver.decision_for(victim(5))
    assert decision["status"] == "unresolved" and "tier 1..4" in decision["error"]


def scenario_spec(**extra):
    spec = {"name": "replacement composition", "profile": "genesis", "seed": 1,
            "battlefield": {"width": 2, "height": 1},
            "sides": [{"id": 0, "units": [{"name": "actor", "at": [0, 0]}]},
                      {"id": 1, "units": [{"name": "target", "at": [1, 0]}]}],
            "commands": []}
    spec.update(extra)
    return spec


def test_scenario_strict_and_permissive_composition_root_behavior():
    with pytest.raises(replacement.DeathReplacementConfigurationError):
        scenario.Scenario(scenario_spec(), content_provider=provider(
            "collision", compatibility="unspecified"))
    strict = scenario.Scenario(scenario_spec(), content_provider=provider())
    assert strict.death_replacement_state["content_compatibility"] == "genesis"
    with pytest.raises(replacement.DeathReplacementConfigurationError):
        scenario.Scenario(scenario_spec(), content_provider=provider(missing=(65,)))
    permissive = scenario.Scenario(scenario_spec(
        death_replacement_load_mode="permissive"),
        content_provider=provider(missing=(65,)))
    permissive.cmd_rest(permissive.units["actor"])
    assert permissive.units["actor"].resting
    overridden = scenario.Scenario(scenario_spec(
        content_compatibility_override="genesis"),
        content_provider=provider("odd", compatibility="new_horizons"))
    assert overridden.death_replacement_state["compatibility_override"] is True


def test_legacy_profile_inheritance_is_separate_from_pack_id(tmp_path):
    pack_dir = tmp_path / "arbitrary_mod_name"
    pack_dir.mkdir()
    (pack_dir / "bindings.json").write_text(
        '{"pack":"arbitrary_mod_name","abilities":{}}', encoding="utf-8")
    db = content.ContentDb.load("arbitrary_mod_name", str(pack_dir),
                                content.AbilityRegistry(), legacy_profile="genesis")
    assert db.content_compatibility() == {
        "identity": "genesis", "source": "legacy_profile"}
    plain = content.ContentDb.load("genesis", str(pack_dir),
                                   content.AbilityRegistry())
    assert plain.content_compatibility()["identity"] == "unspecified"
