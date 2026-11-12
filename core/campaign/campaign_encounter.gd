class_name CampaignEncounter
extends RefCounted

## Owns one tactical lifetime, detached from its source roster snapshot.
const RosterModel = preload("res://core/campaign/campaign_roster.gd")
var session: ManualBattleSession
var _source: Dictionary
var _encounter_id: String
var _mapping: Dictionary
var _initial: Dictionary = {}
var _members: Dictionary = {}
var _instance_ids: Dictionary = {}
var _spec: Dictionary


static func open(source: Dictionary, encounter_id: String, seed_value: int,
		mapping: Dictionary, battlefield: Dictionary, enemies: Array) -> Dictionary:
	if not RosterModel.values_only(source) or not RosterModel.values_only(mapping) \
			or not RosterModel.values_only(enemies) or not RosterModel.values_only(battlefield) \
			or encounter_id.is_empty() or mapping.is_empty() \
			or not source.get("pins") is Dictionary \
			or not source.get("entries") is Dictionary \
			or not source.get("revision") is int or source.revision < 0 \
			or not source.pins.get("rules") is String \
			or source.pins.get("profile") != "native":
		return {"ok": false, "reason": "invalid encounter inputs"}
	var validated := RosterModel.create(source.entries.values(), source.pins.rules)
	if not validated.ok or validated.roster.snapshot().pins != source.pins \
			or validated.roster.snapshot().entries != source.entries:
		return {"ok": false, "reason": "invalid source snapshot or pins"}
	var definitions: Dictionary = {}
	var deployed: Array = []
	var ids: Dictionary = {}
	for entry in source.entries.values():
		definitions[entry.def] = entry.definition.duplicate(true)
	for roster_id in mapping:
		var placement: Variant = mapping[roster_id]
		if not source.entries.has(roster_id) or source.entries[roster_id].life <= 0 \
				or not placement is Dictionary or placement.size() != 2 \
				or not placement.get("instance_id") is String \
				or placement.instance_id.is_empty() or ids.has(placement.instance_id) \
				or not placement.get("at") is Array:
			return {"ok": false, "reason": "invalid deployment mapping"}
		ids[placement.instance_id] = true
		var entry: Dictionary = source.entries[roster_id]
		deployed.append({"id": placement.instance_id, "def": entry.def,
			"at": placement.at.duplicate(), "overrides": {"life": entry.life,
				"life_base": entry.definition.get("life_base", entry.definition.life)}})
	var provider := ScenarioContentProvider.new("campaign", definitions)
	if provider.content_provenance() != source.pins.content:
		return {"ok": false, "reason": "changed content pin"}
	var specification := {"name": encounter_id, "profile": "native", "seed": seed_value,
		"content": source.pins.content.duplicate(true), "battlefield": battlefield.duplicate(true),
		"sides": [{"id": 0, "name": "Azure", "is_attacker": true, "units": deployed},
			{"id": 1, "name": "Crimson", "units": enemies.duplicate(true)}]}
	var scenario := Scenario.new(specification, null, provider)
	if scenario.construction_error != "":
		return {"ok": false, "reason": scenario.construction_error}
	var encounter := CampaignEncounter.new()
	encounter.session = ManualBattleSession.new(scenario)
	encounter._source = source.duplicate(true)
	encounter._encounter_id = encounter_id
	encounter._mapping = mapping.duplicate(true)
	encounter._spec = scenario.spec.duplicate(true)
	for side in scenario.state.sides:
		for unit in side.units:
			encounter._members[unit] = side.id
			encounter._instance_ids[unit] = unit.instance_id
			encounter._initial[unit] = var_to_bytes_with_objects(unit.definition_snapshot())
	return {"ok": true, "encounter": encounter}


func collect() -> Dictionary:
	var scenario := session.scenario
	if not session.started or scenario.construction_error != "" \
			or scenario.runtime_error != "" or not session.battle_complete() \
			or scenario.profile != "native" or scenario.spec != _spec:
		return {"ok": false, "reason": "encounter unfinished, halted or changed"}
	var seen: Dictionary = {}
	for side in scenario.state.sides:
		for unit in side.units:
			if not _members.has(unit) or seen.has(unit) or _members[unit] != side.id \
					or unit.instance_id != _instance_ids[unit] \
					or unit.discarded or unit.battle_owned or not unit.original_definition.is_empty() \
					or var_to_bytes_with_objects(unit.definition_snapshot()) != _initial[unit] \
					or scenario.units.get(unit.instance_id) != unit:
				return {"ok": false, "reason": "unsupported ownership, identity or replacement"}
			seen[unit] = true
	if seen.size() != _members.size() or scenario.units.size() != _members.size():
		return {"ok": false, "reason": "unsupported summon or removed unit"}
	var results: Array = []
	for roster_id in _mapping:
		var instance_id: String = _mapping[roster_id].instance_id
		var unit: Combatant = scenario.units.get(instance_id)
		var entry: Dictionary = _source.entries[roster_id]
		if unit == null or _members.get(unit) != 0 or unit.content_id != entry.def \
				or unit.life < 0 \
				or unit.life > entry.definition.get("life_base", entry.definition.life) \
				or unit.alive != (unit.life > 0):
			return {"ok": false, "reason": "invalid mapped unit data"}
		results.append({"roster_id": roster_id, "instance_id": instance_id,
			"def": entry.def, "life": unit.life})
	return {"ok": true, "outcome": {"encounter_id": _encounter_id,
		"source_revision": _source.revision, "pins": _source.pins.duplicate(true),
		"owner": 0, "winner": session.winning_side_id(), "units": results}}
