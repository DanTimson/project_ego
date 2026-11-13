class_name ContestedCampaign
extends RefCounted

# Guards reject invalid commands before touching authoritative values.
# gdlint: disable=max-returns
const Validation = preload("res://core/campaign/contested_validation.gd")
const Policy = preload("res://core/campaign/strategic_policy.gd")
const SAVE_VERSION := 3
var _content: Dictionary
var _state: Dictionary
var _pending: CampaignEncounter
var _contest: Dictionary = {}


static func create(definition: Dictionary) -> ContestedCampaign:
	if Validation.definition_error(definition) != "":
		return null
	var model := ContestedCampaign.new()
	model._content = definition.duplicate(true)
	model._state = opening_state(definition)
	if Validation.state_error(definition, model._state) != "":
		return null
	return model


static func opening_state(definition: Dictionary) -> Dictionary:
	var state := {"round": 1, "completed": 0, "phase": "player", "status": "active",
		"rival_index": 0, "rival_commands": 0, "serial": 0, "next_army": 1,
		"next_unit": 1, "factions": {}, "provinces": {}, "armies": definition.armies.duplicate(true),
		"units": {}, "casualties": {}, "trace": []}
	for id in definition.factions:
		state.factions[id] = {"gold": definition.factions[id].gold, "service": 0, "services": []}
	for id in definition.provinces:
		state.provinces[id] = {"owner": definition.provinces[id].owner, "buildings": {}}
	for id in state.armies:
		state.armies[id]["formed_round"] = 0
	for authored in definition.units:
		var unit: Dictionary = authored.duplicate(true)
		unit["life"] = definition.definitions[unit.def].life
		unit["moved"] = unit.army != "" and state.armies[unit.army].moves == 0
		state.units[unit.id] = unit
	return state


func content() -> Dictionary:
	return _content.duplicate(true)


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func in_battle() -> bool:
	return _pending != null


func pending_encounter() -> CampaignEncounter:
	return _pending


func contest() -> Dictionary:
	return _contest.duplicate(true)


func active_faction() -> String:
	if _state.phase != "rival":
		return _content.player
	return rival_order()[_state.rival_index]


func rival_order() -> Array:
	var order: Array = _content.factions.keys()
	order.erase(_content.player)
	order.sort()
	return order


func members(army: String, province := "") -> Array:
	var result: Array = []
	for unit in _state.units.values():
		if unit.army == army and (army != "" or unit.province == province):
			result.append(unit.id)
	result.sort()
	return result


func field_at(province: String) -> String:
	for id in _state.armies:
		if _state.armies[id].province == province:
			return id
	return ""


func army_count(faction: String) -> int:
	var total := 0
	for army in _state.armies.values():
		if army.faction == faction:
			total += 1
	return total


func query(command: Dictionary) -> Dictionary:
	if _state.status != "active":
		return _refuse("Campaign complete.")
	if in_battle():
		return _refuse("Resolve the pending encounter first.")
	var op: String = command.get("op", "") if command.get("op", "") is String else ""
	var fields := {"travel": ["army", "to"], "transfer": ["unit", "army"],
		"form": ["province", "units"], "build": ["id"], "recruit": ["id"],
		"recover": ["units"], "end_turn": []}
	if not fields.has(op) or command.size() != fields[op].size() + 1:
		return _refuse("Unknown command or fields.")
	for key in fields[op]:
		if not command.has(key) or (key == "units" and not command[key] is Array) \
				or (key != "units" and not command[key] is String):
			return _refuse("Invalid command fields.")
	var faction := active_faction()
	match op:
		"end_turn":
			if _state.phase != "player":
				return _refuse("Rivals are still resolving.")
		"travel":
			return _travel_query(command.army, command.to, faction)
		"transfer":
			return _transfer_query(command.unit, command.army, faction)
		"form":
			return _form_query(command.province, command.units, faction)
		_:
			return _service_query(command, faction)
	return _ok("")


func execute(command: Dictionary) -> Dictionary:
	var available := query(command)
	if not available.ok:
		return available
	var faction := active_faction()
	match command.op:
		"travel":
			return _travel(command.army, command.to)
		"transfer":
			var unit: Dictionary = _state.units[command.unit]
			var old: String = unit.army
			unit.army = command.army
			if unit.army != "" and unit.moved:
				_state.armies[unit.army].moves = 0
			_disband_empty(old)
		"form":
			var id := "formed-%d" % _state.next_army
			_state.next_army += 1
			_state.armies[id] = {"faction": faction, "province": command.province,
				"moves": 0, "formed_round": _state.round}
			for unit_id in command.units:
				_state.units[unit_id].army = id
		"build", "recruit", "recover":
			_service(command, faction)
		"end_turn":
			_state.phase = "rival"
			_note("End Turn: rival phases before payout")
			return _advance_rivals()
	_note("%s %s" % [faction, JSON.stringify(command)])
	return _ok("Command applied.")


func _travel_query(army_id: String, destination: String, faction: String) -> Dictionary:
	if not _state.armies.has(army_id) or _state.armies[army_id].faction != faction:
		return _refuse("Select an active faction army.")
	var army: Dictionary = _state.armies[army_id]
	if not _content.provinces.has(destination) \
			or destination not in _content.provinces[army.province].links:
		return _refuse("Choose an adjacent province.")
	if army.moves == 0:
		return _refuse("Army has no move this round.")
	for id in members(army_id):
		if _state.units[id].moved:
			return _refuse("A troop already moved this round.")
	var occupant := field_at(destination)
	if occupant != "" and _state.armies[occupant].faction == faction:
		return _refuse("One friendly field army per province.")
	if _state.serial >= 1000000:
		return _refuse("Encounter serial exhausted.")
	return _ok("")


func _transfer_query(id: String, army: String, faction: String) -> Dictionary:
	if not _state.units.has(id) or _state.units[id].faction != faction:
		return _refuse("Choose a living friendly troop.")
	var unit: Dictionary = _state.units[id]
	if unit.army == army or _state.provinces[unit.province].owner != faction:
		return _refuse("Transfer requires a different container at a friendly province.")
	if army != "" and (not _state.armies.has(army)
			or _state.armies[army].faction != faction
			or _state.armies[army].province != unit.province):
		return _refuse("Transfer requires a co-located friendly army.")
	var cap: int = _content.garrison_cap if army == "" else _content.army_cap
	if members(army, unit.province).size() >= cap:
		return _refuse("Destination roster is full.")
	return _ok("")


func _form_query(province: String, ids: Array, faction: String) -> Dictionary:
	if not _state.provinces.has(province) or _state.provinces[province].owner != faction:
		return _refuse("Form at a friendly province.")
	if field_at(province) != "" or army_count(faction) >= _content.army_limit:
		return _refuse("Field army limit or province occupied.")
	if ids.is_empty() or ids.size() > _content.army_cap or _state.next_army >= 1000000:
		return _refuse("Choose troops within army capacity.")
	var seen: Array = []
	for id in ids:
		if not id is String or id in seen or id not in members("", province):
			return _refuse("Choose distinct living garrison troops here.")
		seen.append(id)
	return _ok("")


func _service_query(command: Dictionary, faction: String) -> Dictionary:
	var home: String = _content.factions[faction].home
	if _state.provinces[home].owner != faction:
		return _refuse("Faction does not control its Home.")
	if _state.factions[faction].service == _state.round:
		return _refuse("One paid service per faction round.")
	var price: int = _content.recovery_cost
	var buildings: Dictionary = _state.provinces[home].buildings
	match command.op:
		"build":
			if not _content.buildings.has(command.id):
				return _refuse("Unknown building.")
			if buildings.has(command.id):
				return _refuse("Already built.")
			for prerequisite in _content.buildings[command.id].requires:
				if not buildings.has(prerequisite):
					return _refuse("Requires " + _content.buildings[prerequisite].name + ".")
			price = _content.buildings[command.id].cost
		"recruit":
			if not _content.recruits.has(command.id):
				return _refuse("Unknown recruit.")
			var option: Dictionary = _content.recruits[command.id]
			if option.requires != "" and not buildings.has(option.requires):
				return _refuse("Requires " + _content.buildings[option.requires].name + ".")
			if members("", home).size() >= _content.garrison_cap or _state.next_unit >= 1000000:
				return _refuse("Home garrison is full or allocation limit reached.")
			price = option.cost
		"recover":
			if command.units.is_empty():
				return _refuse("Select wounded troops at Home.")
			var seen: Array = []
			for id in command.units:
				if not id is String or id in seen or not _state.units.has(id):
					return _refuse("Choose distinct living wounded troops.")
				var unit: Dictionary = _state.units[id]
				if unit.faction != faction or unit.province != home \
						or unit.life >= _max_life(unit.def):
					return _refuse("Recovery targets must be wounded friendly troops at Home.")
				seen.append(id)
	if _state.factions[faction].gold < price:
		return _refuse("Not enough gold before income.")
	return _ok("")


func _service(command: Dictionary, faction: String) -> void:
	var home: String = _content.factions[faction].home
	var price: int = _content.recovery_cost
	var record := {"round": _state.round, "op": command.op, "id": ""}
	match command.op:
		"build":
			price = _content.buildings[command.id].cost
			_state.provinces[home].buildings[command.id] = _state.round
			record.id = command.id
		"recruit":
			price = _content.recruits[command.id].cost
			var id := "recruited-%d" % _state.next_unit
			_state.next_unit += 1
			_state.units[id] = {"id": id, "def": command.id, "life": _max_life(command.id),
				"faction": faction, "army": "", "province": home, "moved": false}
			record.id = id
		"recover":
			var life: int = _content.recovery_life + _bonus(home, "recovery", false)
			for id in command.units:
				var unit: Dictionary = _state.units[id]
				unit.life = mini(_max_life(unit.def), unit.life + life)
	_state.factions[faction].gold -= price
	_state.factions[faction].service = _state.round
	_state.factions[faction].services.append(record)


func _travel(army_id: String, destination: String) -> Dictionary:
	var army: Dictionary = _state.armies[army_id]
	var defenders := members("", destination)
	var field := field_at(destination)
	if field != "":
		defenders.append_array(members(field))
	defenders.sort()
	if _state.provinces[destination].owner == army.faction or defenders.is_empty():
		_spend_move(army_id)
		_relocate(army_id, destination)
		_state.provinces[destination].owner = army.faction
		_note("%s moves to %s; control %s" % [army_id, destination, army.faction])
		_check_terminal()
		return _ok("Moved; edge budget spent.")
	var serial: int = _state.serial + 1
	var encounter_id := "%s:attempt-%d" % [_content.id, serial]
	var attacker_side := 0 if army.faction == _content.player else 1
	# NPC/NPC contests have attacker on side zero and resolve with ordinary commands.
	var player_defending: bool = _state.provinces[destination].owner == _content.player
	if army.faction != _content.player and not player_defending:
		attacker_side = 0
	var participants: Array = [[], []]
	participants[attacker_side] = members(army_id)
	participants[1 - attacker_side] = defenders
	var entries: Array = []
	var mappings: Array = [{}, {}]
	var names: Array = ["", ""]
	names[attacker_side] = _content.factions[army.faction].name
	var defender: String = _state.provinces[destination].owner
	names[1 - attacker_side] = _content.factions[defender].name if defender != "" else "Neutral"
	for side in 2:
		for id in participants[side]:
			var unit: Dictionary = _state.units[id]
			entries.append({"id": id, "def": unit.def, "life": unit.life,
				"definition": _content.definitions[unit.def].duplicate(true)})
			mappings[side][id] = {"instance_id": encounter_id + ":" + id,
				"at": _content.deployment[side][mappings[side].size()].duplicate()}
	var opened := CampaignEncounter.open_contest(entries, _content.rules, encounter_id,
		_content.seed + _state.completed, mappings, _content.battlefield, attacker_side, names)
	if not opened.ok:
		return opened
	_pending = opened.encounter
	_state.serial = serial
	_contest = {"army": army_id, "from": army.province, "to": destination,
		"attacker": army.faction, "attacker_side": attacker_side,
		"defense": player_defending, "participants": participants}
	_note("Contest %s at %s; attacker side %d; phase suspended" % [
		encounter_id, destination, attacker_side])
	return {"ok": true, "reason": "Defend or concede." if player_defending else "Attack opened.",
		"encounter": _pending}


func finish(encounter: CampaignEncounter) -> Dictionary:
	if encounter == null or encounter != _pending:
		return _refuse("No matching in-flight encounter.")
	var collected := encounter.collect_contest()
	if not collected.ok:
		return collected
	return _resolve(collected.winner, collected.units)


func abandon(encounter: CampaignEncounter) -> Dictionary:
	if encounter == null or encounter != _pending or _contest.defense \
			or _state.phase != "player":
		return _refuse("Only a player attack may be abandoned; defense must resolve or concede.")
	_pending.session.end()
	_pending = null
	_contest = {}
	_note("Attack abandoned; no ownership, life, budget or round changes")
	return _ok("Attack abandoned; map roster preserved.")


func concede() -> Dictionary:
	if not in_battle() or not _contest.defense:
		return _refuse("No player defense to concede.")
	var results: Array = []
	for side in 2:
		for id in _contest.participants[side]:
			results.append({"roster_id": id, "def": _state.units[id].def,
				"life": _state.units[id].life if side == _contest.attacker_side else 0})
	_note("Defense conceded: all defending troops become casualties; attackers retain opening life")
	return _resolve(_contest.attacker_side, results)


func _resolve(winner: int, results: Array) -> Dictionary:
	# Collection has validated the entire detached battle. Build replacement before publication.
	var next: Dictionary = _state.duplicate(true)
	var expected: Array = _contest.participants[0] + _contest.participants[1]
	var seen: Array = []
	if winner not in [-1, 0, 1] or results.size() != expected.size():
		return _refuse("Incomplete strategic result.")
	for result in results:
		if result.roster_id not in expected or result.roster_id in seen \
				or not next.units.has(result.roster_id) \
				or next.units[result.roster_id].def != result.def \
				or not result.life is int or result.life < 0 or result.life > _max_life(result.def):
			return _refuse("Stale strategic participant.")
		seen.append(result.roster_id)
		next.units[result.roster_id].life = result.life
		if result.life == 0:
			var dead: Dictionary = next.units[result.roster_id].duplicate(true)
			dead.army = ""
			dead.province = ""
			next.casualties[dead.id] = dead
			next.units.erase(dead.id)
	_state = next
	var army_id: String = _contest.army
	if _state.armies.has(army_id):
		_spend_move(army_id)
	if winner == _contest.attacker_side:
		_state.provinces[_contest.to].owner = _contest.attacker
		_relocate(army_id, _contest.to)
	for id in _state.armies.keys():
		_disband_empty(id)
	_note("Resolved %s at %s exactly once; winner side %d" % [army_id, _contest.to, winner])
	_pending.session.end()
	_pending = null
	_contest = {}
	_check_terminal()
	if _state.phase == "rival" and _state.status == "active":
		return _advance_rivals()
	return _ok("Encounter applied to both rosters and control.")


func _advance_rivals() -> Dictionary:
	var order := rival_order()
	while _state.rival_index < order.size() and _state.status == "active":
		var faction: String = order[_state.rival_index]
		if _state.rival_commands >= _content.policy.commands:
			_note(faction + " command bound reached; holds remaining actions")
			_state.rival_index += 1
			_state.rival_commands = 0
			continue
		var command: Dictionary = Policy.choose(self, faction)
		if command.is_empty():
			_note(faction + " holds")
			_state.rival_index += 1
			_state.rival_commands = 0
			continue
		# Increment before opening battle; resume cannot replay this rival command.
		_state.rival_commands += 1
		var result := execute(command)
		if not result.ok:
			return result
		if in_battle():
			if _contest.defense:
				return result
			return _auto_contest()
	if _state.status == "active":
		_complete_round()
	return _ok("Rivals completed; " + _state.status + ".")


func _auto_contest() -> Dictionary:
	_pending.session.begin()
	for index in 256:
		if _pending.session.battle_complete():
			return finish(_pending)
		var command := Policy.tactical_command(_pending.session)
		var issued := _pending.session.issue_command(command)
		if not issued.accepted:
			return _refuse("Rival tactical resolution halted: " + issued.reason)
	return _refuse("Rival tactical command bound reached.")


func _complete_round() -> void:
	var factions: Array = _content.factions.keys()
	factions.sort()
	for faction in factions:
		var income := 0
		for id in _state.provinces:
			if _state.provinces[id].owner == faction:
				income += province_income(id, true)
		_state.factions[faction].gold += income
		_note("%s payout round %d: +%dg (prior-round facilities only)" % [
			faction, _state.round, income])
	_state.completed += 1
	_check_terminal()
	_state.rival_index = 0
	_state.rival_commands = 0
	if _state.status != "active":
		return
	_state.round += 1
	_state.phase = "player"
	for army in _state.armies.values():
		army.moves = 1
	for unit in _state.units.values():
		unit.moved = false
	_note("Player round %d: all army and troop movement refreshed" % _state.round)


func _check_terminal() -> void:
	var home: String = _content.factions[_content.player].home
	if _state.provinces[home].owner != _content.player:
		_state.status = "defeat"
	elif _state.provinces[_content.objective].owner == _content.player:
		_state.status = "victory"
	elif _state.completed >= _content.round_limit:
		_state.status = "defeat"
	if _state.status != "active":
		_state.phase = "complete"
		_state.rival_index = 0
		_state.rival_commands = 0


func province_income(id: String, payout := false) -> int:
	return _content.provinces[id].income + _bonus(id, "income", payout)


func _bonus(province: String, effect: String, delayed: bool) -> int:
	var value := 0
	for id in _state.provinces[province].buildings:
		if _content.buildings[id].effect == effect and (not delayed \
				or _state.provinces[province].buildings[id] < _state.round):
			value += _content.buildings[id].value
	return value


func _max_life(type: String) -> int:
	return _content.definitions[type].get("life_base", _content.definitions[type].life)


func _spend_move(id: String) -> void:
	_state.armies[id].moves = 0
	for unit in members(id):
		_state.units[unit].moved = true


func _relocate(id: String, destination: String) -> void:
	if not _state.armies.has(id):
		return
	_state.armies[id].province = destination
	for unit in members(id):
		_state.units[unit].province = destination


func _disband_empty(id: String) -> void:
	if id != "" and members(id).is_empty():
		_state.armies.erase(id)


func _note(message: String) -> void:
	_state.trace.append(message)


func checkpoint() -> Dictionary:
	if in_battle() or _state.phase == "rival":
		return _refuse("Save only at a quiescent player map boundary.")
	return {"ok": true, "data": {"version": SAVE_VERSION, "mode": "contested",
		"content": _content.id, "fingerprint": JSON.stringify(_content).sha256_text(),
		"state": snapshot()}}


static func from_checkpoint(definition: Dictionary, data: Variant) -> Dictionary:
	var model := create(definition)
	if model == null:
		return _refuse("Invalid contested definition.")
	var normalized: Variant = Validation.normalize(data)
	if not normalized is Dictionary or normalized.keys().size() != 5 \
			or normalized.get("version") != SAVE_VERSION or normalized.get("mode") != "contested" \
			or normalized.get("content") != definition.id \
			or normalized.get("fingerprint") != JSON.stringify(definition).sha256_text() \
			or not normalized.get("state") is Dictionary:
		return _refuse("Wrong mode, version or content fingerprint.")
	var reason := Validation.state_error(definition, normalized.state)
	if reason != "":
		return _refuse(reason)
	model._state = normalized.state.duplicate(true)
	return {"ok": true, "campaign": model}


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _ok(reason: String) -> Dictionary:
	return {"ok": true, "reason": reason}
