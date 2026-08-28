"""CX-017 tranche-1 semantic modifier boundary acceptance coverage."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

import combat
import content
import modifier_semantic as semantic
import turn
from modifier import Hook, Modifier
from roster import Roster
from tools.extract import make_bindings


def modifier(query, *, ability=0, hook=Hook.STAT_PASSIVE):
    return Modifier(ability=ability, handler="noop", hook=hook,
                    semantics=(query,), params={"nested": {"value": 1}})


def write_binding(tmp_path: Path, pack_id: str, abilities: dict) -> Path:
    directory = tmp_path / pack_id
    directory.mkdir()
    (directory / "bindings.json").write_text(json.dumps({
        "pack": pack_id, "abilities": abilities,
    }), encoding="utf-8")
    return directory


def registry():
    result = content.AbilityRegistry()
    result.register("noop", lambda _ctx, value, _params: value)
    return result


def test_vocabulary_normalization_copy_and_native_serialization():
    values = semantic.normalize([
        "morale.underflow_suppressed",
        "stamina.mutation_suppressed",
        "morale.underflow_suppressed",
    ])
    assert values == (
        semantic.Query.STAMINA_MUTATION_SUPPRESSED,
        semantic.Query.MORALE_UNDERFLOW_SUPPRESSED,
    )
    native = Modifier(ability=0, handler="noop", hook=Hook.STAMINA,
                      semantics=values, params={"nested": {"value": 1}})
    clone = native.copy()
    clone.params["nested"]["value"] = 2
    assert native.params["nested"]["value"] == 1
    assert native.to_dict()["semantics"] == [
        "stamina.mutation_suppressed", "morale.underflow_suppressed"]
    assert native.ability == 0 and native.has_semantic(values[0])
    with pytest.raises(ValueError, match="unknown modifier semantic"):
        Modifier(ability=0, handler="noop", hook=Hook.STAMINA,
                 semantics=("plugin.opaque",))


def test_binding_schema_is_strict_deduplicated_and_numeric_neutral(tmp_path):
    directory = write_binding(tmp_path, "arbitrary", {
        "18": {"handler": "noop", "semantics": [
            "morale.underflow_suppressed", "stamina.mutation_suppressed",
            "stamina.mutation_suppressed"]},
        "19": {"handler": "noop"},
        "38": {"handler": "noop", "semantics": ["plugin.opaque"]},
    })
    db = content.ContentDb.load("arbitrary", str(directory), registry())
    assert db.resolve_semantics(18) == (
        semantic.Query.STAMINA_MUTATION_SUPPRESSED,
        semantic.Query.MORALE_UNDERFLOW_SUPPRESSED)
    assert db.resolve_semantics(19) == ()
    assert db.pack.binding(38) is None
    assert any("unknown modifier semantic" in error for error in db.report.errors)

    # Pack id, compatibility label, and numeric coincidence grant no meaning.
    genesis_named = write_binding(tmp_path, "genesis", {
        "18": {"handler": "noop"}, "19": {"handler": "noop"},
        "38": {"handler": "noop"}})
    collision = content.ContentDb.load("genesis", str(genesis_named), registry(),
                                       legacy_profile="genesis")
    assert all(collision.resolve_semantics(opcode) == ()
               for opcode in (18, 19, 38))


def test_generated_genesis_mapping_is_profile_qualified(monkeypatch):
    class Parsed:
        records = [{"Number": opcode, "Name": "Synthetic %d" % opcode}
                   for opcode in (18, 19, 38)]
    monkeypatch.setattr(make_bindings.E, "parse", lambda _path: Parsed())
    monkeypatch.setattr(make_bindings.H, "build", lambda _path: [
        {"opcode": opcode, "hook": "STAT_PASSIVE", "conf": "low", "uses": 1}
        for opcode in (18, 19, 38)])
    genesis = make_bindings.build("unused", "genesis")["abilities"]
    arbitrary = make_bindings.build("unused", "arbitrary")["abilities"]
    assert genesis["18"]["semantics"] == ["stamina.mutation_suppressed"]
    assert genesis["38"]["semantics"] == ["combat.melee_exchange_suppressed"]
    assert genesis["19"]["semantics"] == ["morale.underflow_suppressed"]
    assert all("semantics" not in arbitrary[str(opcode)]
               for opcode in (18, 19, 38))


def test_roster_translates_only_explicit_binding_semantics(tmp_path):
    directory = write_binding(tmp_path, "legacy", {
        "18": {"handler": "noop", "hook": "STAMINA",
               "semantics": ["stamina.mutation_suppressed"]}})
    pack = content.ContentPack("legacy")
    errors = pack.load_bindings(str(directory / "bindings.json"))
    pack.tables = {
        "unit": {1: {"index": 1, "Name": "Bound", "Abilityes": [1]}},
        "unit_upg": {1: {"index": 1, "Name": "Legacy", "Upg Type": 18,
                         "Quantity": 0}},
        "ability_num": {1: {"index": 1, "Number": 18, "Name": "Legacy"}},
    }
    reg = registry()
    db = content.ContentDb(pack, reg, pack.report(reg, errors))
    built = Roster(db).build("legacy:unit/1")
    assert built.complete
    runtime = built.unit.modifiers[0]
    assert runtime.ability == 18
    assert runtime.has_semantic(semantic.Query.STAMINA_MUTATION_SUPPRESSED)


def test_stamina_semantic_and_raw_negative_control():
    protected = combat.Combatant(stamina=3, stamina_base=10, speed=3,
                                 modifiers=[modifier(
        semantic.Query.STAMINA_MUTATION_SUPPRESSED, hook=Hook.STAMINA)])
    protected.movement_remaining = 3
    turn.spend_move(protected, 1, stamina_cost=2)
    assert protected.stamina == 3
    # Low-stamina combat penalties remain live.
    assert combat.stamina_mod(protected)[0] == pytest.approx(0.7)

    raw = combat.Combatant(stamina=3, stamina_base=10, speed=3,
                           modifiers=[Modifier(18, "noop", Hook.STAMINA)])
    raw.movement_remaining = 3
    turn.spend_move(raw, 1, stamina_cost=2)
    assert raw.stamina == 1


def test_melee_semantic_provider_coverage_and_raw_negative_control():
    protected = combat.Combatant(attack=7, counter_attack=7, ranged_attack=7)
    semantic_modifier = modifier(semantic.Query.MELEE_EXCHANGE_SUPPRESSED,
                                 hook=Hook.DAMAGE_VS_TARGET)
    combat.bind_environment(lambda unit: [semantic_modifier]
                            if unit is protected else [])
    try:
        assert combat.current_attack(protected, combat.AttackKind.MELEE)[0] == 0
        assert combat.current_attack(protected, combat.AttackKind.COUNTER)[0] == 0
        assert combat.current_attack(protected, combat.AttackKind.RANGED)[0] == 7
    finally:
        combat.bind_environment(None)
    raw = combat.Combatant(attack=7, counter_attack=7,
                           modifiers=[Modifier(38, "noop", Hook.DAMAGE_VS_TARGET)])
    assert combat.current_attack(raw, combat.AttackKind.MELEE)[0] == 7


def test_morale_underflow_semantic_is_narrow_and_raw_is_neutral():
    protected = combat.Combatant(morale=0, modifiers=[modifier(
        semantic.Query.MORALE_UNDERFLOW_SUPPRESSED, hook=Hook.MORALE)])
    assert not combat.adjust_morale(protected, -2)
    assert (protected.morale, protected.morale_break_accumulator) == (0, 0)
    # It does not bypass the ordinary low-morale combat multiplier.
    assert combat.morale_mod(protected)[0] == pytest.approx(0.4)

    raw = combat.Combatant(morale=0,
                           modifiers=[Modifier(19, "noop", Hook.MORALE)])
    assert combat.adjust_morale(raw, -2)
    assert (raw.morale, raw.morale_break_accumulator) == (0, 20)
