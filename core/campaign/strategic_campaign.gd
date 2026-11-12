class_name StrategicCampaign
extends RefCounted

# Early refusals keep validation atomic and report the specific invalid field.
# gdlint: disable=max-returns

## Headless native campaign authority. Only collect/apply crosses the tactical boundary.
const SAVE_VERSION := 1
const MAX_GOLD := 1000000
const MAX_SERIAL := 1000000
var _content: Dictionary
var _state: Dictionary
var _roster: CampaignRoster
var _pending: CampaignEncounter
var _destination := ""


static func create(content: Dictionary) -> StrategicCampaign:
	var model := StrategicCampaign.new()
	model._content = content.duplicate(true)
	var entries: Array = []
	for member in content.opening:
		entries.append(model._entry(member.id, member.def, content.definitions[member.def].life))
	model._roster = CampaignRoster.create(entries, content.rules).roster
	model._state = {
		"position": "home",
		"owned": ["home"],
		"turn": 0,
		"gold": content.opening_gold,
		"status": "active",
		"next_recruit": 1,
		"battle_serial": 0
	}
	return model


func content() -> Dictionary:
	return _content.duplicate(true)


func snapshot() -> Dictionary:
	var result := _state.duplicate(true)
	result["roster"] = _roster.snapshot()
	return result


func in_battle() -> bool:
	return _pending != null


func query(command: String, destination: String = "") -> Dictionary:
	if _state.status != "active":
		return _refuse("Campaign complete. Start a new run to play again.")
	if in_battle():
		return _refuse("Return from the current encounter first.")
	match command:
		"travel":
			if (
				not _content.provinces.has(destination)
				or destination not in _content.provinces[_state.position].links
			):
				return _refuse("Choose an adjacent province.")
			if destination not in _state.owned and _state.battle_serial >= MAX_SERIAL:
				return _refuse("Encounter attempt limit reached. Start a new run.")
		"recover", "recruit":
			if _state.position != "home":
				return _refuse("Recovery and recruitment are available at Home.")
			var price: int = (
				_content.recovery_cost if command == "recover" else _content.recruit_cost
			)
			if _state.gold < price:
				return _refuse("Not enough gold before income.")
			if command == "recover" and not _has_wounds():
				return _refuse("No wounded survivors to heal. Casualties cannot recover.")
			if command == "recruit" and _living_count() >= _content.living_cap:
				return _refuse("The army already has four living members.")
		_:
			return _refuse("Unknown strategic command.")
	return {"ok": true, "reason": ""}


func travel(destination: String) -> Dictionary:
	var available := query("travel", destination)
	if not available.ok:
		return available
	if destination in _state.owned:
		_state.position = destination
		return _commit_turn("Friendly travel to " + destination)
	var serial: int = _state.battle_serial + 1
	var encounter_id := "%s:attempt-%d" % [destination, serial]
	var mapping: Dictionary = {}
	var source := _roster.snapshot()
	for member in source.entries.values():
		if member.life > 0:
			mapping[member.id] = {
				"instance_id": encounter_id + ":" + member.id,
				"at": _content.deployment[mapping.size()].duplicate()
			}
	var province: Dictionary = _content.provinces[destination]
	var enemies: Array = province.enemies.duplicate(true)
	for enemy in enemies:
		enemy.id = encounter_id + ":" + enemy.id
	var opened := CampaignEncounter.open(
		source, encounter_id, province.seed, mapping, _content.battlefield, enemies
	)
	if not opened.ok:
		return opened
	_state.battle_serial = serial
	_pending = opened.encounter
	_destination = destination
	return {"ok": true, "encounter": _pending, "reason": "Encounter opened; no turn spent."}


func finish(encounter: CampaignEncounter) -> Dictionary:
	if encounter == null or encounter != _pending:
		return _refuse("No matching in-flight encounter.")
	var collected := encounter.collect()
	if not collected.ok:
		return collected
	var applied := _roster.apply(collected.outcome)
	if not applied.ok:
		return applied
	var destination := _destination
	_pending = null
	_destination = ""
	if collected.outcome.winner == 0:
		_state.owned.append(destination)
		_state.owned.sort()
		_state.position = destination
		if destination == "keep":
			_state.status = "victory"
	else:
		_state.status = "defeat"
	return _commit_turn("Encounter resolved at " + destination)


func abandon(encounter: CampaignEncounter) -> Dictionary:
	if encounter == null or encounter != _pending:
		return _refuse("No matching in-flight encounter.")
	_pending.session.end()
	_pending = null
	_destination = ""
	return {"ok": true, "reason": "Encounter abandoned; no result or turn applied."}


func recover() -> Dictionary:
	var available := query("recover")
	if not available.ok:
		return available
	var entries: Array = _roster.snapshot().entries.values()
	for member in entries:
		if member.life > 0:
			member.life = mini(
				member.definition.get("life_base", member.definition.life),
				member.life + _content.recovery_life
			)
	_replace_roster(entries)
	_state.gold -= _content.recovery_cost
	return _commit_turn("Paid recovery at Home")


func recruit() -> Dictionary:
	var available := query("recruit")
	if not available.ok:
		return available
	var entries: Array = _roster.snapshot().entries.values()
	entries.append(
		_entry(
			"recruit-%d" % _state.next_recruit,
			_content.recruit_def,
			_content.definitions[_content.recruit_def].life
		)
	)
	_replace_roster(entries)
	_state.next_recruit += 1
	_state.gold -= _content.recruit_cost
	return _commit_turn("Recruited Home Guard")


func checkpoint() -> Dictionary:
	if in_battle():
		return _refuse("Checkpoint is available only on the strategic map.")
	var members: Array = []
	for member in _roster.snapshot().entries.values():
		members.append({"id": member.id, "def": member.def, "life": member.life})
	return {
		"ok": true,
		"data":
		{
			"version": SAVE_VERSION,
			"content": _content.id,
			"fingerprint": JSON.stringify(_content).sha256_text(),
			"state": _state.duplicate(true),
			"members": members
		}
	}


## Builds an independent replacement. Failure never mutates the caller's run.
static func from_checkpoint(content_definition: Dictionary, data: Variant) -> Dictionary:
	var model := create(content_definition)
	var reason := model._validate_checkpoint(data)
	if reason != "":
		return _refuse(reason)
	return {"ok": true, "campaign": model}


static func _whole(value: Variant, low: int, high: int) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and value >= low
		and value <= high
		and float(value) == floorf(float(value))
	)


func _validate_checkpoint(data: Variant) -> String:
	if not data is Dictionary or data.size() != 5:
		return "Malformed checkpoint envelope."
	if not _whole(data.get("version"), SAVE_VERSION, SAVE_VERSION):
		return "Unsupported checkpoint version."
	if (
		data.get("content") != _content.id
		or data.get("fingerprint") != JSON.stringify(_content).sha256_text()
	):
		return "Checkpoint content does not match this authored campaign."
	if not data.get("state") is Dictionary or not data.get("members") is Array:
		return "Malformed strategic state or roster."
	var state: Dictionary = data.state.duplicate(true)
	if (
		state.size() != 7
		or not state.get("position") is String
		or not _content.provinces.has(state.position)
		or not state.get("owned") is Array
		or not state.get("status") is String
		or state.status not in ["active", "victory", "defeat"]
	):
		return "Invalid map position or campaign status."
	var bounds := {
		"turn": _content.turn_limit,
		"gold": MAX_GOLD,
		"next_recruit": _content.turn_limit + 1,
		"battle_serial": MAX_SERIAL
	}
	for key in bounds:
		if not _whole(state.get(key), 1 if key == "next_recruit" else 0, bounds[key]):
			return "Invalid strategic number: " + key
		state[key] = int(state[key])
	var total_income := 0
	for province in _content.provinces.values():
		total_income += province.income
	if state.gold > _content.opening_gold + state.turn * total_income:
		return "Gold exceeds the campaign income range."
	var owned: Array = state.owned
	var seen: Dictionary = {}
	for province in owned:
		if not province is String or not _content.provinces.has(province) or seen.has(province):
			return "Invalid or duplicate province ownership."
		seen[province] = true
	if "home" not in owned or state.position not in owned:
		return "Position must be friendly and Home must remain owned."
	# Captures must form a connected path from Home; disconnected ownership is impossible.
	var reachable: Array = ["home"]
	for province in reachable:
		for neighbor in _content.provinces[province].links:
			if neighbor in owned and neighbor not in reachable:
				reachable.append(neighbor)
	if (
		reachable.size() != owned.size()
		or owned.size() - 1 > state.turn
		or state.battle_serial < owned.size() - 1
		or owned.size() - 1 + state.next_recruit - 1 > state.turn
	):
		return "Ownership or action counters are inconsistent."
	if (
		(state.status == "victory") != ("keep" in owned)
		or (state.status == "victory" and state.position != "keep")
		or (state.status == "active" and state.turn >= _content.turn_limit)
		or (state.status == "defeat" and state.turn == 0)
	):
		return "Terminal campaign state is inconsistent."
	var entries: Array = []
	var ids: Dictionary = {}
	var expected: Dictionary = {}
	for member in _content.opening:
		expected[member.id] = member.def
	for index in range(1, state.next_recruit):
		expected["recruit-%d" % index] = _content.recruit_def
	if data.members.size() != expected.size():
		return "Missing or extra roster members."
	var living := 0
	for member in data.members:
		if (
			not member is Dictionary
			or member.size() != 3
			or not member.get("id") is String
			or not expected.has(member.id)
			or ids.has(member.id)
			or member.get("def") != expected[member.id]
		):
			return "Invalid roster identity or type."
		var definition: Dictionary = _content.definitions[member.def]
		if not _whole(member.get("life"), 0, definition.get("life_base", definition.life)):
			return "Invalid roster life."
		ids[member.id] = true
		living += 1 if member.life > 0 else 0
		entries.append(_entry(member.id, member.def, int(member.life)))
	if living > _content.living_cap or (living == 0 and state.status != "defeat"):
		return "Invalid living roster count."
	if state.status == "defeat":
		if living == 0:
			var turns_before_loss: int = owned.size() - 1 + state.next_recruit - 1
			if state.turn <= turns_before_loss or state.battle_serial < owned.size():
				return "Battle defeat requires a separate turn and encounter attempt."
		elif state.turn < _content.turn_limit:
			return "Defeat before the turn limit requires a lost battle."
	_state = state
	_replace_roster(entries)
	return ""


func _entry(id: String, type: String, life: int) -> Dictionary:
	return {
		"id": id,
		"def": type,
		"life": life,
		"definition": _content.definitions[type].duplicate(true)
	}


func _replace_roster(entries: Array) -> void:
	# Service/save boundaries reconstruct only persistent values. Old encounter objects
	# cannot commit again: finish requires the exact current in-flight bridge.
	_roster = CampaignRoster.create(entries, _content.rules).roster


func _living_count() -> int:
	var count := 0
	for member in _roster.snapshot().entries.values():
		count += 1 if member.life > 0 else 0
	return count


func _has_wounds() -> bool:
	for member in _roster.snapshot().entries.values():
		if (
			member.life > 0
			and member.life < member.definition.get("life_base", member.definition.life)
		):
			return true
	return false


func _commit_turn(reason: String) -> Dictionary:
	_state.turn += 1
	var income := 0
	for province in _state.owned:
		income += _content.provinces[province].income
	_state.gold += income
	# Capture/Keep victory precedes the turn-limit check, including the final turn.
	if _state.status == "active" and _state.turn >= _content.turn_limit:
		_state.status = "defeat"
	return {"ok": true, "reason": "%s. Turn %d; income +%d." % [reason, _state.turn, income]}


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
