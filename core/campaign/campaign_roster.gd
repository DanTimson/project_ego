class_name CampaignRoster
extends RefCounted

## Native in-memory values only. Tactical objects never belong to this model.
const DEFINITION_KEYS := [
	"name", "life", "life_base", "stamina", "stamina_base", "morale", "morale_base",
	"attack", "counter_attack", "ranged_attack", "shooting_range", "defence",
	"ranged_defence", "resist", "speed", "ammo", "ammo_base", "tier", "flags",
	"subtypes", "modifiers",
]
var _state: Dictionary = {}


static func values_only(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if not key is String or not values_only(value[key]):
				return false
		return true
	if value is Array:
		for item in value:
			if not values_only(item):
				return false
		return true
	return typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING] \
		or (value is float and is_finite(value))


static func create(entries: Array, rules_identity: String) -> Dictionary:
	if not values_only(entries) or entries.is_empty() or rules_identity.is_empty():
		return {"ok": false, "reason": "invalid roster values or rules pin"}
	var indexed: Dictionary = {}
	var definitions: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary or entry.size() != 4 \
				or not entry.get("id") is String or entry.id.is_empty() \
				or indexed.has(entry.id) or not entry.get("def") is String \
				or not entry.def.begins_with("campaign:unit/") or not ContentId.is_canonical(entry.def) \
				or not entry.get("definition") is Dictionary \
				or not entry.get("life") is int:
			return {"ok": false, "reason": "invalid or duplicate roster entry"}
		var definition: Dictionary = entry.definition
		for key in definition:
			if key not in DEFINITION_KEYS:
				return {"ok": false, "reason": "unsupported authored definition field"}
			var value: Variant = definition[key]
			if key == "name":
				if not value is String or value.is_empty():
					return {"ok": false, "reason": "invalid definition name"}
			elif key in ["flags", "subtypes", "modifiers"]:
				if not value is Array:
					return {"ok": false, "reason": "invalid definition collection"}
				for item in value:
					if (key == "modifiers" and not item is Dictionary) \
							or (key != "modifiers" and not item is String):
						return {"ok": false, "reason": "invalid definition item"}
			elif not value is int:
				return {"ok": false, "reason": "invalid definition number"}
		if not definition.get("life") is int or definition.life <= 0 \
				or definition.get("life_base", definition.life) < definition.life \
				or entry.life < 0 or entry.life > definition.get("life_base", definition.life) \
				or (definitions.has(entry.def) and definitions[entry.def] != definition):
			return {"ok": false, "reason": "invalid definition or life"}
		definitions[entry.def] = definition.duplicate(true)
		indexed[entry.id] = entry.duplicate(true)
	var provider := ScenarioContentProvider.new("campaign", definitions)
	var roster := CampaignRoster.new()
	roster._state = {"revision": 0, "entries": indexed, "receipts": {}, "pins": {
		"profile": "native", "rules": rules_identity,
		"content": provider.content_provenance(),
	}}
	return {"ok": true, "roster": roster}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func apply(outcome: Dictionary) -> Dictionary:
	if not values_only(outcome) or outcome.size() != 6 \
			or not outcome.get("encounter_id") is String or outcome.encounter_id.is_empty():
		return {"ok": false, "reason": "invalid outcome envelope"}
	var encounter_id: String = outcome.encounter_id
	if _state.receipts.has(encounter_id):
		var prior: Dictionary = _state.receipts[encounter_id]
		if prior.outcome == outcome:
			return {"ok": true, "receipt": prior.duplicate(true)}
		return {"ok": false, "reason": "conflicting encounter retry"}
	if not outcome.get("source_revision") is int \
			or outcome.source_revision != _state.revision \
			or outcome.get("pins") != _state.pins \
			or not outcome.get("owner") is int or outcome.owner != 0 \
			or not outcome.get("winner") is int or outcome.winner not in [-1, 0, 1] \
			or not outcome.get("units") is Array or outcome.units.is_empty():
		return {"ok": false, "reason": "stale revision, wrong pins or malformed outcome"}
	var error := _validate_units(outcome.units)
	if error != "":
		return {"ok": false, "reason": error}
	# Validate first; swap the complete roster/receipt state once.
	var next := _state.duplicate(true)
	for unit in outcome.units:
		next.entries[unit.roster_id].life = unit.life
	next.revision += 1
	var receipt := {"outcome": outcome.duplicate(true), "revision": next.revision}
	next.receipts[encounter_id] = receipt
	_state = next
	return {"ok": true, "receipt": receipt.duplicate(true)}


func _validate_units(units: Array) -> String:
	var seen: Dictionary = {}
	var instances: Dictionary = {}
	for unit in units:
		if not unit is Dictionary or unit.size() != 4 \
				or not unit.get("roster_id") is String \
				or not _state.entries.has(unit.roster_id) or seen.has(unit.roster_id) \
				or not unit.get("instance_id") is String or unit.instance_id.is_empty() \
				or instances.has(unit.instance_id) or not unit.get("life") is int:
			return "invalid mapped unit"
		var entry: Dictionary = _state.entries[unit.roster_id]
		if entry.life == 0 or unit.get("def") != entry.def \
				or unit.life < 0 \
				or unit.life > entry.definition.get("life_base", entry.definition.life):
			return "invalid mapped definition or life"
		seen[unit.roster_id] = true
		instances[unit.instance_id] = true
	return ""
