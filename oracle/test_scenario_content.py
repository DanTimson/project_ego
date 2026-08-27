"""Portable canonical-definition scenario tests (synthetic content only)."""
from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest

import content
import handlers
import scenario


FIXTURE = Path(__file__).parents[1] / "tests" / "fixtures" / "scenario_content_fixture.json"


def fixture():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def provider(fx=None):
    fx = fx or fixture()
    p = fx["provider"]
    return content.ScenarioContentProvider(
        p["pack"], p["definitions"], version=p["version"], build=p["build"])


def canonical(fx=None):
    fx = fx or fixture()
    return copy.deepcopy(fx["canonical_spec"])


def inline_construction_spec():
    return {
        "name": "IR-1 inline construction", "profile": "native", "seed": 1,
        "battlefield": {"width": 2, "height": 2, "tiles": []},
        "sides": [
            {"id": 0, "units": [
                {"id": "one", "name": "One", "at": [0, 0]}]},
            {"id": 1, "units": [
                {"id": "two", "name": "Two", "at": [1, 1]}]},
        ],
        "commands": [],
    }


def test_inline_construction_fails_closed_for_identity_and_placement_errors():
    duplicate = inline_construction_spec()
    duplicate["sides"][1]["units"][0]["id"] = "one"
    with pytest.raises(ValueError, match="duplicate unit instance id"):
        scenario.Scenario(duplicate)

    occupied = inline_construction_spec()
    occupied["sides"][1]["units"][0]["at"] = [0, 0]
    with pytest.raises(ValueError, match="cannot place"):
        scenario.Scenario(occupied)

    out_of_bounds = inline_construction_spec()
    out_of_bounds["sides"][1]["units"][0]["at"] = [4, 4]
    with pytest.raises(ValueError, match="cannot place"):
        scenario.Scenario(out_of_bounds)

    valid = scenario.Scenario(inline_construction_spec())
    assert set(valid.units) == {"one", "two"}
    assert len(valid.sides) == 2
    assert all(valid.field.find(unit) is not None for unit in valid.units.values())


def test_canonical_and_inline_construction_are_equivalent_and_portable():
    fx = fixture()
    resolved = scenario.Scenario(canonical(fx), content_provider=provider(fx))
    inline = scenario.Scenario(copy.deepcopy(fx["inline_spec"]))
    ru = resolved.units["attacker-1"]
    iu = inline.units["attacker-1"]

    for field in ("name", "attack", "counter_attack", "defence", "life",
                  "life_base", "stamina", "stamina_base", "morale",
                  "morale_base", "speed", "flags", "subtypes"):
        assert getattr(ru, field) == getattr(iu, field)
    assert ru.content_id == "synthetic:unit/5"
    assert iu.content_id == ""
    assert ru.instance_id == iu.instance_id == "attacker-1"
    assert ru.name == iu.name == "Synthetic vanguard"
    assert ru.stamina == ru.stamina_base == 4  # override precedes defaults
    assert ru.life == ru.life_base == 15
    assert ru.morale == ru.morale_base == 10
    assert ru.modifiers[0].params == iu.modifiers[0].params
    assert len(resolved.auras_by_source[ru]) == len(inline.auras_by_source[iu]) == 1

    actual = resolved.run()
    inline_actual = inline.run()
    assert actual["log"] == fx["expected"]["log"] == inline_actual["log"]
    assert actual["final"] == fx["expected"]["final"] == inline_actual["final"]


def test_two_instances_share_a_definition_without_aliasing():
    fx = fixture()
    spec = canonical(fx)
    first = spec["sides"][0]["units"][0]
    second = copy.deepcopy(first)
    second["id"] = "attacker-2"
    second["at"] = [0, 1]
    spec["sides"][0]["units"].append(second)
    sc = scenario.Scenario(spec, content_provider=provider(fx))
    one, two = sc.units["attacker-1"], sc.units["attacker-2"]
    assert one is not two
    assert one.content_id == two.content_id == "synthetic:unit/5"
    assert one.instance_id != two.instance_id
    assert one.name == two.name
    one.modifiers[0].params["nested"]["order"].append(99)
    one.flags.add("instance-only")
    assert two.modifiers[0].params["nested"]["order"] == [2, 1]
    assert "instance-only" not in two.flags

    duplicate = canonical(fx)
    duplicate["sides"][0]["units"].append(copy.deepcopy(first))
    duplicate["sides"][0]["units"][1]["at"] = [0, 1]
    with pytest.raises(ValueError, match="duplicate unit instance id"):
        scenario.Scenario(duplicate, content_provider=provider(fx))


def test_provider_definition_is_deep_copy_isolated():
    fx = fixture()
    p = provider(fx)
    before = p.resolve_definition("synthetic:unit/5")
    sc = scenario.Scenario(canonical(fx), content_provider=p)
    unit = sc.units["attacker-1"]
    unit.modifiers[0].params["nested"]["order"].reverse()
    unit.flags.add("battle-only")
    sc.auras_by_source[unit][0].only_subtypes += ("battle-only",)
    assert p.resolve_definition("synthetic:unit/5") == before
    assert fx["provider"]["definitions"]["synthetic:unit/5"] == before


def test_inline_scenario_never_requires_or_calls_a_provider():
    class ExplodingProvider:
        def content_provenance(self):
            raise AssertionError("inline scenario consulted content")
        def resolve_definition(self, _content_id):
            raise AssertionError("inline scenario resolved content")

    fx = fixture()
    without = scenario.Scenario(copy.deepcopy(fx["inline_spec"]))
    with_unused = scenario.Scenario(copy.deepcopy(fx["inline_spec"]),
                                    content_provider=ExplodingProvider())
    assert without.run() == with_unused.run()


@pytest.mark.parametrize("mutate,match", [
    (lambda s: s.pop("content"), "scenario-level"),
    (lambda s: s.__setitem__("content", {"version": "fixture-v1"}), 'requires non-empty "pack"'),
    (lambda s: s.__setitem__("content", {"pack": "synthetic"}), "requires version"),
    (lambda s: s["content"].__setitem__("fingerprint", "sha256:nope"), "64 lowercase"),
    (lambda s: s["content"].__setitem__("timestamp", "today"), "unknown scenario content provenance"),
])
def test_malformed_provenance_fails_before_battle_construction(mutate, match):
    spec = canonical()
    mutate(spec)
    with pytest.raises(ValueError, match=match):
        scenario.Scenario(spec, content_provider=provider())


def test_missing_provider_and_definition_fail_clearly():
    with pytest.raises(ValueError, match="injected content provider"):
        scenario.Scenario(canonical())
    spec = canonical()
    spec["sides"][0]["units"][0]["def"] = "synthetic:unit/999"
    with pytest.raises(ValueError, match="was not found"):
        scenario.Scenario(spec, content_provider=provider())


def test_pack_namespace_and_every_declared_discriminator_are_verified():
    spec = canonical()
    spec["sides"][0]["units"][0]["def"] = "other:unit/5"
    with pytest.raises(ValueError, match="namespace mismatch"):
        scenario.Scenario(spec, content_provider=provider())

    for key, replacement in (
        ("pack", "other"), ("version", "wrong"), ("build", "wrong"),
        ("fingerprint", "sha256:" + "0" * 64),
    ):
        mismatched = canonical()
        mismatched["content"][key] = replacement
        with pytest.raises(ValueError, match="mismatch for %s" % key) as exc:
            scenario.Scenario(mismatched, content_provider=provider())
        assert "expected" in str(exc.value) and "observed" in str(exc.value)


@pytest.mark.parametrize("field", ["id", "def", "at", "content_id",
                                    "instance_id", "pack", "provenance"])
def test_overrides_cannot_change_identity_placement_or_provenance(field):
    spec = canonical()
    spec["sides"][0]["units"][0]["overrides"][field] = "hidden"
    with pytest.raises(ValueError, match="forbidden fields"):
        scenario.Scenario(spec, content_provider=provider())


def test_unknown_overrides_and_mixed_inline_fields_are_rejected():
    spec = canonical()
    spec["sides"][0]["units"][0]["overrides"]["mystery_stat"] = 9
    with pytest.raises(ValueError, match="unknown or non-settable"):
        scenario.Scenario(spec, content_provider=provider())

    mixed = canonical()
    mixed["sides"][0]["units"][0]["attack"] = 99
    with pytest.raises(ValueError, match="mixes undeclared inline fields"):
        scenario.Scenario(mixed, content_provider=provider())


def test_fingerprint_is_stable_under_order_and_json_number_runtime_types():
    a = {"z": [3, {"b": 2, "a": 1}], "a": "value"}
    b = {"a": "value", "z": [3.0, {"a": 1.0, "b": 2.0}]}
    actual = content.canonical_fingerprint(a)
    assert actual == content.canonical_fingerprint(b)
    assert actual.startswith("sha256:") and len(actual) == 71


def test_synthetic_provider_observes_current_content_and_rejects_stale_assertion():
    definitions = {"synthetic:unit/1": {"name": "Before", "attack": 1}}
    current = content.ScenarioContentProvider("synthetic", definitions,
                                               version="v1")
    old_fingerprint = current.content_provenance()["fingerprint"]

    # The provider fingerprint is observed when provenance is requested, not a
    # construction-time cache.
    current._definitions["synthetic:unit/1"]["attack"] = 2
    changed_fingerprint = current.content_provenance()["fingerprint"]
    assert changed_fingerprint != old_fingerprint

    changed_definitions = copy.deepcopy(definitions)
    changed_definitions["synthetic:unit/1"]["attack"] = 2
    stale = content.ScenarioContentProvider(
        "synthetic", changed_definitions, version="v1",
        fingerprint=old_fingerprint)
    assert stale.fingerprint == changed_fingerprint
    with pytest.raises(ValueError, match="fingerprint assertion mismatch") as exc:
        stale.content_provenance()
    assert old_fingerprint in str(exc.value)
    assert changed_fingerprint in str(exc.value)


@pytest.mark.parametrize("mutate", [
    lambda pack: pack.tables["unit"][1].__setitem__("Attack", 2),
    lambda pack: setattr(pack.bindings[7], "uses", 2),
], ids=["table", "binding"])
def test_content_pack_recomputes_and_rejects_stale_declared_fingerprint(mutate):
    pack = content.ContentPack("synthetic")
    pack.version = "v1"
    pack.build = "build-1"
    pack.bindings[7] = content.Binding(
        opcode=7, name="Synthetic", hook="STAT_PASSIVE",
        handler="stat_delta", params={"stat": "attack"}, uses=1)
    pack.tables = {"unit": {1: {"Name": "Before", "Attack": 1}}}
    declared = content.canonical_fingerprint(pack.snapshot_payload())
    pack.declared_fingerprint = declared
    assert pack.provenance()["fingerprint"] == declared

    mutate(pack)
    observed = content.canonical_fingerprint(pack.snapshot_payload())
    assert observed != declared
    with pytest.raises(ValueError, match="pack fingerprint assertion mismatch") as exc:
        pack.provenance()
    assert declared in str(exc.value)
    assert observed in str(exc.value)


def test_inline_serialized_identity_fields_are_rejected():
    for field in ("content_id", "instance_id", "__scenario_resolved_content_id"):
        spec = copy.deepcopy(fixture()["inline_spec"])
        spec["sides"][0]["units"][0][field] = "spoofed"
        with pytest.raises(ValueError, match="inline unit.*serialized identity"):
            scenario.Scenario(spec)


def test_provider_free_inline_identity_comes_only_from_id():
    spec = copy.deepcopy(fixture()["inline_spec"])
    built = scenario.Scenario(spec).units["attacker-1"]
    assert built.content_id == ""
    assert built.instance_id == "attacker-1"


def test_content_db_adapts_existing_roster_loader_to_the_provider_seam(tmp_path):
    pack_dir = tmp_path / "synthetic"
    (pack_dir / "data").mkdir(parents=True)
    (pack_dir / "bindings.json").write_text(json.dumps({
        "pack": "synthetic", "version": "db-v1", "build": "db-build",
        "abilities": {},
    }), encoding="utf-8")
    (pack_dir / "data" / "unit.json").write_text(json.dumps({"records": [{
        "index": 5, "Name": "Database synthetic", "Life": 8,
        "Attack": 3, "CounterAttack": 2, "Defence": 1,
        "RangedDefence": 0, "Resist": 0, "Speed": 2,
        "RangedAttack": 0, "ShootingRange": 0, "Ammo": 0,
        "Stamina": 6, "Morale": 9, "Subtype": [77], "Abilityes": [],
    }]}), encoding="utf-8")
    registry = content.AbilityRegistry()
    handlers.register_all(registry)
    db = content.ContentDb.load("synthetic", str(pack_dir), registry,
                                {"unit": "unit.json"})
    provenance = db.content_provenance()
    assert provenance["pack"] == "synthetic"
    assert provenance["version"] == "db-v1"
    assert provenance["build"] == "db-build"
    assert provenance["fingerprint"].startswith("sha256:")
    resolved = db.resolve_definition("synthetic:unit/5")
    assert resolved["name"] == "Database synthetic"
    resolved["subtypes"].append("changed")
    assert db.resolve_definition("synthetic:unit/5")["subtypes"] == ["77"]

    spec = canonical()
    spec["content"] = provenance
    spec["sides"][0]["units"][0] = {
        "id": "db-1", "def": "synthetic:unit/5", "at": [0, 0],
        "overrides": {"stamina": 4},
    }
    sc = scenario.Scenario(spec, content_provider=db)
    assert sc.units["db-1"].content_id == "synthetic:unit/5"
    assert sc.units["db-1"].instance_id == "db-1"
    assert sc.units["db-1"].name == "Database synthetic"


def test_generated_cross_language_fixture_matches_python():
    fx = fixture()
    p = provider(fx)
    assert p.fingerprint == fx["provider"]["fingerprint"]
    canonical_sc = scenario.Scenario(canonical(fx), content_provider=p)
    result = canonical_sc.run()
    assert result["log"] == fx["expected"]["log"]
    assert result["final"] == fx["expected"]["final"]



def test_inline_lifecycle_state_is_accepted_but_canonical_runtime_state_is_closed():
    inline = copy.deepcopy(fixture()["inline_spec"])
    unit_spec = inline["sides"][0]["units"][0]
    unit_spec.update({
        "ammo_base": 7, "tier": 3, "definition_id": 900,
        "morale_break_accumulator": 20, "damage_received": [1, 2, 3, 4],
        "original_definition": {"name": "original", "definition_id": 5,
                                "tier": 2, "ammo_base": 4},
        "battle_owned": True, "discarded": True,
    })
    built = scenario.Scenario(inline).units["attacker-1"]
    assert built.ammo_base == 7 and built.tier == 3 and built.definition_id == 900
    assert built.morale_break_accumulator == 20
    assert built.damage_received == [1, 2, 3, 4]
    assert built.original_definition["definition_id"] == 5
    assert built.battle_owned and built.discarded

    runtime_values = {
        "morale_break_accumulator": 10,
        "damage_received": [1, 0, 0, 0],
        "original_definition": {},
        "battle_owned": True,
        "discarded": True,
        "last_position": [0, 0],
    }
    for field, value in runtime_values.items():
        changed = fixture()
        changed["provider"]["definitions"]["synthetic:unit/5"][field] = value
        changed_provider = provider(changed)
        changed_spec = canonical(changed)
        changed_spec["content"] = changed_provider.content_provenance()
        with pytest.raises(ValueError, match="unknown construction field"):
            scenario.Scenario(changed_spec, content_provider=changed_provider)

        override = canonical()
        override["sides"][0]["units"][0]["overrides"][field] = value
        with pytest.raises(ValueError, match="unknown or non-settable"):
            scenario.Scenario(override, content_provider=provider())


def test_canonical_definition_identity_cannot_be_spoofed_but_static_fields_remain_settable():
    spec = canonical()
    spec["sides"][0]["units"][0]["overrides"]["definition_id"] = 999
    with pytest.raises(ValueError, match="forbidden fields: definition_id"):
        scenario.Scenario(spec, content_provider=provider())

    changed = fixture()
    changed["provider"]["definitions"]["synthetic:unit/5"]["definition_id"] = 999
    changed_provider = provider(changed)
    changed_spec = canonical(changed)
    changed_spec["content"] = changed_provider.content_provenance()
    with pytest.raises(ValueError, match="scenario-owned fields: definition_id"):
        scenario.Scenario(changed_spec, content_provider=changed_provider)

    static_override = canonical()
    static_override["sides"][0]["units"][0]["overrides"].update(
        {"ammo_base": 6, "tier": 3})
    built = scenario.Scenario(static_override, content_provider=provider()).units["attacker-1"]
    assert built.ammo_base == 6 and built.tier == 3
