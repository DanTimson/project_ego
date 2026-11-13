class_name StrategicCampaign
extends RefCounted

# Early refusals keep validation atomic and report the specific invalid field.
# gdlint: disable=max-returns

## Headless native campaign authority. Only collect/apply crosses the tactical boundary.
const SAVE_VERSION := 2
const MAX_GOLD := 1000000
const MAX_SERIAL := 1000000
var _content: Dictionary
var _state: Dictionary
var _roster: CampaignRoster
var _pending: CampaignEncounter
var _destination := ""


static func create(content: Dictionary) -> StrategicCampaign:
	if validate_definition(content) != "":
		return null
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
		"battle_serial": 0,
		"buildings": [],
		"recruit_turns": []
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
		"recover", "recruit", "build":
			if _state.position != "home":
				return _refuse("Construction, recovery and recruitment require the army at Home.")
			var price: int = _content.recovery_cost
			if command == "build":
				if not _content.get("buildings", {}).has(destination):
					return _refuse("Unknown building.")
				if has_building(destination):
					return _refuse("Already built.")
				var building: Dictionary = _content.buildings[destination]
				for prerequisite in building.requires:
					if not has_building(prerequisite):
						return _refuse("Requires " + _content.buildings[prerequisite].name + ".")
				price = building.cost
			elif command == "recruit":
				var type: String = _content.recruit_def if destination == "" else destination
				if not recruit_options().has(type):
					return _refuse("Unknown recruit definition.")
				var option: Dictionary = recruit_options()[type]
				if option.requires != "" and not has_building(option.requires):
					return _refuse("Requires " + _content.buildings[option.requires].name + ".")
				price = option.cost
				if _living_count() >= _content.living_cap:
					return _refuse("The army already has four living members.")
			if _state.gold < price:
				return _refuse("Not enough gold before income.")
			if command == "recover" and not _has_wounds():
				return _refuse("No wounded survivors to heal. Casualties cannot recover.")
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
				member.life + recovery_life()
			)
	_replace_roster(entries)
	_state.gold -= _content.recovery_cost
	return _commit_turn("Paid recovery at Home")


func recruit(type: String = "") -> Dictionary:
	if type == "":
		type = _content.recruit_def
	var available := query("recruit", type)
	if not available.ok:
		return available
	var entries: Array = _roster.snapshot().entries.values()
	entries.append(
		_entry(
			"recruit-%d" % _state.next_recruit,
			type,
			_content.definitions[type].life
		)
	)
	_replace_roster(entries)
	_state.next_recruit += 1
	_state.gold -= recruit_options()[type].cost
	_state.recruit_turns.append(_state.turn + 1)
	return _commit_turn("Recruited " + _content.definitions[type].name)


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
	if model == null:
		return _refuse("Invalid campaign definition.")
	if data is Dictionary and _whole(data.get("version"), 1, 1):
		var legacy: Dictionary = content_definition.get("legacy_v1", {})
		if legacy.is_empty():
			return _refuse("Unsupported checkpoint version.")
		var restored := create(legacy)
		if restored == null:
			return _refuse("Invalid legacy campaign definition.")
		var legacy_reason := restored._validate_checkpoint(data, true)
		if legacy_reason != "":
			return _refuse(legacy_reason)
		model._state = restored._state.duplicate(true)
		model._replace_roster(restored._roster.snapshot().entries.values())
		return {"ok": true, "campaign": model}
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


func _validate_checkpoint(data: Variant, legacy := false) -> String:
	if not data is Dictionary or data.size() != 5:
		return "Malformed checkpoint envelope."
	var version := 1 if legacy else SAVE_VERSION
	if not _whole(data.get("version"), version, version):
		return "Unsupported checkpoint version."
	if (
		not data.get("content") is String
		or not data.get("fingerprint") is String
		or data.get("content") != _content.id
		or data.get("fingerprint") != JSON.stringify(_content).sha256_text()
	):
		return "Checkpoint content does not match this authored campaign."
	if not data.get("state") is Dictionary or not data.get("members") is Array:
		return "Malformed strategic state or roster."
	var state: Dictionary = data.state.duplicate(true)
	if (
		state.size() != (7 if legacy else 9)
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
	if legacy:
		state["buildings"] = []
		state["recruit_turns"] = range(1, state.next_recruit)
	var construction_reason := _validate_actions(state, data.members, legacy)
	if construction_reason != "":
		return construction_reason
	var total_income := 0
	for province in _content.provinces.values():
		total_income += province.income
	var ceiling: int = _content.opening_gold + state.turn * total_income
	for built in state.buildings:
		var building: Dictionary = _content.buildings[built.id]
		ceiling -= building.cost
		if building.effect == "income":
			ceiling += (state.turn - int(built.turn)) * building.value
	for member in data.members:
		if (member is Dictionary and member.get("id") is String
			and member.id.begins_with("recruit-")):
			ceiling -= recruit_options().get(member.get("def"), {"cost": 0}).cost
	if state.gold > ceiling:
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
		or owned.size() - 1 + state.next_recruit - 1 + state.buildings.size() > state.turn
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
		expected["recruit-%d" % index] = _content.recruit_def if legacy else ""
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
			or not member.get("def") is String
			or (expected[member.id] != "" and member.get("def") != expected[member.id])
			or not _content.definitions.has(member.get("def"))
			or (expected[member.id] == "" and not recruit_options().has(member.get("def")))
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
			if (state.turn in state.recruit_turns or (not state.buildings.is_empty()
				and state.buildings[-1].turn == state.turn)):
				return "Battle defeat cannot share a Home action turn."
			var turns_before_loss: int = (
				owned.size() - 1 + state.next_recruit - 1 + state.buildings.size())
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
		income += province_income(province)
	_state.gold += income
	# Capture/Keep victory precedes the turn-limit check, including the final turn.
	if _state.status == "active" and _state.turn >= _content.turn_limit:
		_state.status = "defeat"
	return {"ok": true, "reason": "%s. Turn %d; income +%d." % [reason, _state.turn, income]}


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func has_building(id: String) -> bool:
	for built in _state.buildings:
		if built.id == id:
			return true
	return false


func recruit_options() -> Dictionary:
	return _content.get("recruits", {
		_content.recruit_def: {"cost": _content.recruit_cost, "requires": ""}
	}).duplicate(true)


func province_income(id: String) -> int:
	return int(_content.provinces[id].income) + (_bonus("income") if id == "home" else 0)


func recovery_life() -> int:
	return int(_content.recovery_life) + _bonus("recovery")


func _bonus(effect: String) -> int:
	var total := 0
	for built in _state.buildings:
		var building: Dictionary = _content.buildings[built.id]
		if building.effect == effect:
			total += building.value
	return total


func build(id: String) -> Dictionary:
	var available := query("build", id)
	if not available.ok:
		return available
	_state.gold -= _content.buildings[id].cost
	# Credit the existing income before activation: a building cannot pay for itself.
	var result := _commit_turn(
		"Built " + _content.buildings[id].name + "; benefit activates after income")
	_state.buildings.append({"id": id, "turn": _state.turn})
	return result


func catalogue() -> Array:
	var rows: Array = []
	for id in _content.get("buildings", {}):
		var row: Dictionary = _content.buildings[id].duplicate(true)
		row["id"] = id
		row["legality"] = query("build", id)
		row["state"] = "Built" if has_building(id) else "Available" if row.legality.ok else "Locked"
		rows.append(row)
	return rows


static func validate_definition(definition: Dictionary) -> String:
	var buildings: Variant = definition.get("buildings", {})
	var recruits: Variant = definition.get("recruits", {})
	if (not buildings is Dictionary or not recruits is Dictionary
		or not definition.get("definitions") is Dictionary
		or not definition.get("recruit_def") is String
		or not definition.definitions.has(definition.recruit_def)
		or (not recruits.is_empty() and not recruits.has(definition.recruit_def))):
		return "Invalid catalogue or default recruit reference."
	for id in buildings:
		var row: Variant = buildings[id]
		if (not row is Dictionary or not row.get("name") is String
			or not _whole(row.get("cost"), 1, MAX_GOLD) or not row.get("requires") is Array
			or row.get("effect") not in ["income", "recovery", "recruit"]):
			return "Invalid building."
		if row.effect == "recruit":
			if (not row.get("value") is String or not recruits.has(row.value)
			or not recruits[row.value] is Dictionary
			or not recruits[row.value].get("requires") is String
				or recruits[row.value].get("requires") != id):
				return "Invalid building recruit reference."
		elif not _whole(row.get("value"), 1, 100):
			return "Invalid building effect."
		for prerequisite in row.requires:
			if not prerequisite is String or not buildings.has(prerequisite):
				return "Missing prerequisite."
	var resolved: Array = []
	for iteration in buildings.size():
		for id in buildings:
			if id not in resolved and buildings[id].requires.all(
				func(key: String) -> bool: return key in resolved):
				resolved.append(id)
	if resolved.size() != buildings.size():
		return "Cyclic prerequisites."
	for type in recruits:
		var option: Variant = recruits[type]
		if (not definition.definitions.has(type) or not option is Dictionary
			or not _whole(option.get("cost"), 1, MAX_GOLD)
			or not option.get("requires") is String):
			return "Invalid recruit."
		if option.requires != "" and (not buildings.has(option.requires)
			or buildings[option.requires].effect != "recruit"
			or buildings[option.requires].value != type):
			return "Invalid recruit unlock."
	return ""


func _validate_actions(state: Dictionary, members: Array, legacy: bool) -> String:
	if not state.get("buildings") is Array or not state.get("recruit_turns") is Array:
		return "Invalid construction or recruitment history."
	if state.recruit_turns.size() != state.next_recruit - 1:
		return "Recruitment counters are inconsistent."
	var built_turns: Dictionary = {}
	var occupied: Array = []
	var previous := 0
	for built in state.buildings:
		if (not built is Dictionary or built.size() != 2
			or not _content.get("buildings", {}).has(built.get("id"))
			or built_turns.has(built.id) or not _whole(built.get("turn"), 1, state.turn)
			or built.turn <= previous):
			return "Unknown, duplicate or inconsistent construction."
		for prerequisite in _content.buildings[built.id].requires:
			if not built_turns.has(prerequisite):
				return "Construction prerequisite order is inconsistent."
		previous = int(built.turn)
		built_turns[built.id] = previous
		occupied.append(previous)
	previous = 0
	for turn in state.recruit_turns:
		if not _whole(turn, 1, state.turn) or turn <= previous or turn in occupied:
			return "Recruitment turns are inconsistent."
		previous = int(turn)
		occupied.append(previous)
	if not legacy and state.turn in occupied and state.position != "home":
		return "A Home action cannot finish at another province."
	if legacy:
		return ""
	for member in members:
		if not member is Dictionary or not member.get("id") is String:
			return "Invalid roster identity."
		if not member.id.begins_with("recruit-"):
			continue
		var suffix: String = member.id.trim_prefix("recruit-")
		if not suffix.is_valid_int():
			return "Invalid recruit identity."
		var index := int(suffix) - 1
		if (index < 0 or index >= state.recruit_turns.size()
			or not recruit_options().has(member.get("def"))):
			return "Invalid recruit type or counter."
		var required: String = recruit_options()[member.def].requires
		if required != "" and (not built_turns.has(required)
			or built_turns[required] >= state.recruit_turns[index]):
			return "Recruit requires an earlier building."
	return ""
