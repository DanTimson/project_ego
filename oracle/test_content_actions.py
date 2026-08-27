"""DELIB-0004 production action-definition composition acceptance cells."""
from __future__ import annotations

import copy
import json

import pytest

import action_execution
import actions
import content
import content_actions as ca
import handlers
import scenario


def unit(name):
    return {"name": name, "life": 20, "attack": 6, "counter_attack": 3,
            "defence": 1, "stamina": 10, "morale": 10, "speed": 3}


def provider(pack="alpha", overlay=None):
    definitions = {f"{pack}:unit/1": unit("Actor"),
                   f"{pack}:unit/2": unit("Target")}
    return content.ScenarioContentProvider(pack, definitions, version="v1",
                                           action_overlay=overlay or {})


def spec_for(p, profile="native", commands=None):
    provenance = p.content_provenance()
    return {"name": "composition", "profile": profile, "seed": 3,
            "content": {"pack": provenance["pack"],
                        "version": provenance["version"]},
            "battlefield": {"width": 3, "height": 2},
            "sides": [
                {"id": 0, "units": [{"id": "actor", "def": f"{p.pack_id}:unit/1",
                                       "at": [0, 0]}]},
                {"id": 1, "units": [{"id": "target", "def": f"{p.pack_id}:unit/2",
                                       "at": [1, 0]}]},
            ], "commands": commands or []}


def novel(source=700, name="Novel", **extra):
    out = {"source_id": source, "name": name, "target": "enemy_melee"}
    out.update(extra)
    return out


def test_provider_is_production_source_and_scenarios_do_not_leak(monkeypatch):
    first = provider("one", {"definitions": [novel(7)],
                             "grants": {"one:unit/1": [{"source_id": 7}]}})
    second = provider("two", {"definitions": [novel(8)],
                              "grants": {"two:unit/1": [{"source_id": 8}]}})
    # Destroy the reference catalogue: production composition must be unaffected.
    monkeypatch.setattr(actions, "REFERENCE_CATALOGUE", {})
    a = scenario.Scenario(spec_for(first), content_provider=first)
    b = scenario.Scenario(spec_for(second), content_provider=second)
    assert set(a.catalogue) == {"one:action/7"}
    assert set(b.catalogue) == {"two:action/8"}
    assert set(a.unit_catalogues["actor"]) == {"one:action/7"}
    a.cmd_action(a.units["target"], "one:action/7", a.units["actor"])
    assert a.log[-1].endswith("action is not granted")
    assert "one:action/7" not in b.catalogue


def test_shared_and_novel_identity_and_recipe_separation():
    genesis = provider("genesis_mod", {
        "grants": {"genesis_mod:unit/1": [{"source_id": 59}]},
        "definitions": [novel(700)],
    })
    composed = genesis.compose_actions("genesis")
    assert composed.source_map[59] == "crushing_blow"
    assert action_execution.ActionRecipeResolver.resolve(
        composed.definitions["crushing_blow"]).supported
    assert composed.source_map[700] == "genesis_mod:action/700"
    sc = scenario.Scenario(spec_for(genesis, profile="genesis"), content_provider=genesis)
    sc.cmd_action(sc.units["actor"], "59", sc.units["target"])
    assert sc.log[-1] == "unknown action '59'"
    assert not action_execution.ActionRecipeResolver.resolve(
        composed.definitions["genesis_mod:action/700"]).supported

    other = provider("other", {"definitions": [novel(700)]})
    assert other.compose_actions("native").source_map[700] == "other:action/700"


def test_defaults_grants_and_isolated_allowlisted_override():
    overlay = {"definitions": [novel(700, magnitude=2)], "grants": {
        "alpha:unit/1": [{"source_id": 700, "overrides": {"magnitude": 9}}],
        "alpha:unit/2": [{"source_id": 700}],
    }}
    p = provider(overlay=overlay)
    sc = scenario.Scenario(spec_for(p), content_provider=p)
    shared = sc.catalogue["alpha:action/700"]
    first = sc.unit_catalogues["actor"]["alpha:action/700"]
    second = sc.unit_catalogues["target"]["alpha:action/700"]
    assert shared.magnitude == second.magnitude == 2
    assert first.magnitude == 9
    assert first is not second and first is not shared

    forbidden = copy.deepcopy(overlay)
    forbidden["grants"]["alpha:unit/1"][0]["overrides"] = {"cost_stamina": 0}
    with pytest.raises(ca.ActionCompositionError) as exc:
        provider(overlay=forbidden).compose_actions("native")
    assert exc.value.diagnostics[0]["code"] == "forbidden_override"


def _invalid_overlays():
    valid = novel(1, "Unrelated")
    return {
        "malformed_binding": {"definitions": [valid, {"source_id": "bad"}]},
        "missing_binding": {"definitions": [valid], "required_source_ids": [99]},
        "identity_collision": {"definitions": [valid, novel(2, "Collision",
                                                               canonical_id="alpha:action/1"),
                                                    novel(3, "Unrelated collision survivor")]},
        "unresolved_grant": {"definitions": [valid], "grants": {
            "alpha:unit/1": [{"source_id": 99}]}}
    }


@pytest.mark.parametrize("code,overlay", _invalid_overlays().items())
def test_strict_fails_closed_permissive_keeps_diagnostics_and_unrelated(code, overlay):
    p = provider(overlay=overlay)
    with pytest.raises(ca.ActionCompositionError) as exc:
        p.compose_actions("native", ca.STRICT)
    assert code in {item["code"] for item in exc.value.diagnostics}

    result = p.compose_actions("native", ca.PERMISSIVE)
    assert code in {item["code"] for item in result.diagnostics}
    # Every permissive case preserves at least one unrelated valid definition.
    assert result.definitions


def test_permissive_unresolved_invocation_refuses_explicitly():
    overlay = {"definitions": [novel(1)], "grants": {
        "alpha:unit/1": [{"source_id": 99}]}}
    p = provider(overlay=overlay)
    spec = spec_for(p, commands=[{"op": "action", "unit": "actor",
                                 "target": "target", "action": "alpha:action/99"}])
    spec["action_load_mode"] = "permissive"
    sc = scenario.Scenario(spec, content_provider=p)
    assert any(item["code"] == "unresolved_grant" for item in sc.action_diagnostics)
    sc.cmd_action(sc.units["actor"], "alpha:action/99", sc.units["target"])
    assert any("unresolved action grant" in line for line in sc.log)
    sc.cmd_rest(sc.units["target"])
    assert sc.units["target"].resting


def test_valid_novel_without_recipe_is_composed_then_refused_as_unsupported():
    overlay = {"definitions": [novel(700)], "grants": {
        "alpha:unit/1": [{"source_id": 700}]}}
    p = provider(overlay=overlay)
    spec = spec_for(p, commands=[{"op": "action", "unit": "actor",
                                 "target": "target", "action": "alpha:action/700"}])
    sc = scenario.Scenario(spec, content_provider=p)
    assert "alpha:action/700" in sc.catalogue
    sc.cmd_action(sc.units["actor"], "alpha:action/700", sc.units["target"])
    assert sc.log[-1] == "Actor(actor): action alpha:action/700 is known but unsupported"


def test_profile_defaults_and_overlay_inheritance_are_pack_qualified():
    base = provider("legacy", {"definitions": [novel(700)]})
    genesis = base.compose_actions("genesis")
    native = base.compose_actions("native")
    nh = base.compose_actions("new_horizons")
    assert genesis.source_map[59] == "crushing_blow"
    assert 59 not in native.source_map and 59 not in nh.source_map
    assert genesis.source_map[700] == native.source_map[700] == "legacy:action/700"
    assert set(genesis.definitions) == {"crushing_blow", "shield_bash",
                                        "legacy:action/700"}


def test_legacy_var_grant_inherits_genesis_stock_without_manifest(tmp_path):
    pack_dir = tmp_path / "legacy"
    (pack_dir / "data").mkdir(parents=True)
    (pack_dir / "bindings.json").write_text(json.dumps({
        "pack": "legacy", "version": "v1", "abilities": {}}), encoding="utf-8")
    tables = {
        "unit.json": {"records": [{"index": 1, "Name": "Legacy actor",
            "Life": 20, "Attack": 6, "CounterAttack": 3, "Defence": 1,
            "Stamina": 10, "Morale": 10, "Speed": 3,
            "Abilityes": [{"ref": 1}]}]},
        "unit_upg.json": {"records": [{"index": 1, "Name": "Tracked grant",
                                         "Upg Type": 388, "Quantity": 7}]},
        "ability_num.json": {"records": [{"index": 1, "Number": 388,
                                            "Name": "Tracked action"}]},
    }
    for name, payload in tables.items():
        (pack_dir / "data" / name).write_text(json.dumps(payload), encoding="utf-8")
    registry = content.AbilityRegistry(); handlers.register_all(registry)
    db = content.ContentDb.load("legacy", str(pack_dir), registry,
        {"unit": "unit.json", "unit_upg": "unit_upg.json",
         "ability_num": "ability_num.json"})
    provenance = db.content_provenance()
    spec = {"name": "legacy", "profile": "genesis", "seed": 1,
            "content": {"pack": "legacy", "version": "v1"},
            "battlefield": {"width": 2, "height": 1}, "sides": [
                {"id": 0, "units": [{"id": "legacy-1", "def": "legacy:unit/1",
                                       "at": [0, 0]}]},
                {"id": 1, "units": [{"id": "dummy", "name": "Dummy",
                                       "life": 10, "at": [1, 0]}]}], "commands": []}
    sc = scenario.Scenario(spec, content_provider=db)
    granted = sc.unit_catalogues["legacy-1"]["shield_bash"]
    assert granted.magnitude == 7
    assert sc.catalogue["shield_bash"].magnitude == 0


@pytest.mark.parametrize("bad_quantity", ["bad", [7]])
def test_malformed_legacy_action_quantity_stays_action_validation(
        tmp_path, bad_quantity):
    pack_dir = tmp_path / "legacy"
    (pack_dir / "data").mkdir(parents=True)
    (pack_dir / "bindings.json").write_text(json.dumps({
        "pack": "legacy", "version": "v1", "abilities": {}}), encoding="utf-8")
    tables = {
        "unit.json": {"records": [{"index": 1, "Name": "Legacy actor",
            "Life": 20, "Attack": 6, "CounterAttack": 3, "Defence": 1,
            "Stamina": 10, "Morale": 10, "Speed": 3,
            "Abilityes": [{"ref": 1}]}]},
        "unit_upg.json": {"records": [{"index": 1, "Name": "Malformed grant",
            "Upg Type": 388, "Quantity": bad_quantity}]},
        "ability_num.json": {"records": [{"index": 1, "Number": 388,
            "Name": "Tracked action"}]},
    }
    for name, payload in tables.items():
        (pack_dir / "data" / name).write_text(json.dumps(payload), encoding="utf-8")
    registry = content.AbilityRegistry()
    handlers.register_all(registry)
    db = content.ContentDb.load("legacy", str(pack_dir), registry,
        {"unit": "unit.json", "unit_upg": "unit_upg.json",
         "ability_num": "ability_num.json"})
    spec = {"name": "legacy", "profile": "genesis", "seed": 1,
            "content": {"pack": "legacy", "version": "v1"},
            "battlefield": {"width": 2, "height": 1}, "sides": [
                {"id": 0, "units": [{"id": "legacy-1", "def": "legacy:unit/1",
                                     "at": [0, 0]}]},
                {"id": 1, "units": [{"id": "dummy", "name": "Dummy",
                                     "life": 10, "at": [1, 0]}]}], "commands": []}

    with pytest.raises(ca.ActionCompositionError) as exc:
        scenario.Scenario(copy.deepcopy(spec), content_provider=db)
    assert {d["code"] for d in exc.value.diagnostics} == {"malformed_grant"}

    spec["action_load_mode"] = "permissive"
    sc = scenario.Scenario(spec, content_provider=db)
    assert any(d["code"] == "malformed_grant" for d in sc.action_diagnostics)
    assert "shield_bash" not in sc.unit_catalogues["legacy-1"]
    assert sc.action_refusals["legacy-1"]["shield_bash"]
    sc.cmd_action(sc.units["legacy-1"], "shield_bash", sc.units["dummy"])
    assert "unresolved action grant" in sc.log[-1]
    sc.cmd_rest(sc.units["dummy"])
    assert sc.units["dummy"].resting


def test_cl1_parser_drops_dead_field_and_ordinary_retaliation_remains():
    parsed = actions.action_from_dict({"id": "x", "name": "X",
                                       "suppresses_counterattack": True})
    assert not hasattr(parsed, "suppresses_counterattack")


def test_provider_composed_cx013_end_to_end_behaviour_is_preserved():
    overlay = {"grants": {"alpha:unit/1": [
        {"source_id": 59},
        {"source_id": 388, "overrides": {"magnitude": 4}},
    ]}}
    p = provider(overlay=overlay)
    crushing = scenario.Scenario(spec_for(p, profile="genesis"), content_provider=p)
    target = crushing.units["target"]
    crushing.cmd_action(crushing.units["actor"], "crushing_blow", target)
    assert any("resolved plan [AttackOp]" in line for line in crushing.log)
    assert target.life < target.life_base

    shield = scenario.Scenario(spec_for(p, profile="genesis"), content_provider=p)
    shield_target = shield.units["target"]
    before_life, before_stamina = shield_target.life, shield_target.stamina
    shield.cmd_action(shield.units["actor"], "shield_bash", shield_target)
    assert shield_target.life == before_life
    assert shield_target.stamina == before_stamina - 4
    assert any("resolved plan [ResourceDeltaOp]" in line for line in shield.log)


def test_strict_scenario_construction_fails_before_runtime_state():
    p = provider(overlay={"definitions": [{"source_id": "bad"}]})
    with pytest.raises(ca.ActionCompositionError):
        scenario.Scenario(spec_for(p), content_provider=p)
