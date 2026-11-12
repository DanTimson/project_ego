extends SceneTree

const DEMO := "res://scenarios/playable_tactical_slice.json"
const DemoContent = preload("res://game/tactical/tactical_demo_content.gd")
const SEEDS := [42, 137, 65537, 20260806]
const COMMAND_LIMIT := 128


func _initialize() -> void:
	if not _test_occupied_move():
		quit(1)
		return
	for seed in SEEDS:
		var run := _drive(seed)
		if run.is_empty() or not _replay(seed, run["commands"], run["expected_final"]):
			quit(1)
			return
		print("PASS: seed %d finishes and replays (%d commands)" % [seed, run["commands"].size()])
	quit(0)


func _session(seed: int) -> ManualBattleSession:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DEMO))
	spec["seed"] = seed
	var provider := DemoContent.provider_for(spec)
	var battle := Scenario.new(spec, null, provider)
	var setup := DemoContent.setup_opening_restriction(battle)
	var session := ManualBattleSession.new(battle)
	if not setup.is_empty() or not session.begin()["ok"]:
		return null
	return session


func _snapshot(session: ManualBattleSession) -> Dictionary:
	var battle := session.scenario
	var units := battle.final_state()
	for id in battle.units:
		var unit: Combatant = battle.units[id]
		units[id].merge({"morale": unit.morale, "forced_rest": unit.forced_rest,
			"resting": unit.resting, "once_per_round": unit.once_per_round.duplicate(true),
			"morale_break": unit.morale_break_accumulator})
	var occupancy := {}
	for cell in battle.field.tiles:
		var occupant: Combatant = battle.field.tile(cell).occupant
		if occupant != null:
			occupancy[cell] = occupant.instance_id
	var rosters := {}
	for side in battle.state.sides:
		var ids: Array[String] = []
		for unit in side.units:
			ids.append(unit.instance_id)
		rosters[side.id] = [side.passed, ids]
	return {"units": units, "occupancy": occupancy, "rosters": rosters,
		"round": battle.state.round_number, "side": battle.state.active_side,
		"rng_calls": battle.rng.calls.duplicate(true),
		"rng_streams": battle.rng._streams.duplicate(true),
		"events": battle.log.duplicate(), "error": battle.runtime_error}


func _board_consistent(session: ManualBattleSession) -> bool:
	var battle := session.scenario
	var occupants := {}
	for cell in battle.field.tiles:
		var unit: Combatant = battle.field.tile(cell).occupant
		if unit == null:
			continue
		if not unit.alive or unit.life <= 0 or occupants.has(unit) \
				or battle.units.get(unit.instance_id) != unit:
			return false
		occupants[unit] = true
	var roster := {}
	for side in battle.state.sides:
		for unit in side.units:
			if roster.has(unit) or battle.units.get(unit.instance_id) != unit:
				return false
			roster[unit] = true
	for unit in battle.units.values():
		var living: bool = unit.alive and unit.life > 0
		if living != occupants.has(unit) or (living and not roster.has(unit)):
			return false
	return battle.state.side(session.active_side_id()) != null


func _choose(session: ManualBattleSession, choices: RandomNumberGenerator) -> Dictionary:
	if session.active_side_id() == CrimsonPolicy.CRIMSON:
		var command := CrimsonPolicy.choose_command(session)
		return command if not command.is_empty() else {"op": "end_phase"}
	# After the first two mixed Azure rounds, let the opponent finish the encounter.
	if session.scenario.state.round_number > 2:
		return {"op": "end_phase"}
	var candidates: Array[Dictionary] = [{"op": "end_phase"}]
	for unit in session.selectable_units():
		var id: String = unit.instance_id
		candidates.append({"op": "rest", "unit": id})
		for target in session.legal_ranged_targets(unit):
			candidates.append({"op": "shoot", "unit": id, "target": target.instance_id})
		for target in session.legal_melee_targets(unit):
			candidates.append({"op": "attack", "unit": id, "target": target.instance_id})
		for cell in session.reachable_cells(unit):
			candidates.append({"op": "move", "unit": id, "to": [cell.x, cell.y]})
		for target in session.living_units(CrimsonPolicy.CRIMSON):
			var action := {"op": "action", "unit": id, "action": String(DemoContent.ACTION_ID),
				"target": target.instance_id}
			if session.query_command(action)["accepted"]:
				candidates.append(action)
	return candidates[choices.randi_range(0, candidates.size() - 1)]


func _fail(seed: int, reason: String, commands: Array) -> bool:
	print("FAIL: seed %d: %s" % [seed, reason])
	print("Commands: ", JSON.stringify(commands))
	return false


func _test_occupied_move() -> bool:
	var seed := 42
	var session := _session(seed)
	if session == null:
		return _fail(seed, "could not start occupied-destination test", [])
	var command := {"op": "move", "unit": "azure-vanguard-01", "to": [0, 3]}
	var before := _snapshot(session)
	var query := session.query_command(command)
	var refusal := session.issue_command(command)
	if query["accepted"] or refusal["accepted"] or query["reason"] != refusal["reason"] \
			or refusal["state_changed"] or _snapshot(session) != before \
			or not _board_consistent(session):
		return _fail(seed, "occupied destination must refuse without moving either unit", [command])
	print("PASS: occupied destination preserves both units and command state")
	return true


func _drive(seed: int) -> Dictionary:
	var session := _session(seed)
	var trace: Array[Dictionary] = []
	if session == null:
		_fail(seed, "could not start demo", trace)
		return {}
	var choices := RandomNumberGenerator.new()
	choices.seed = seed
	for index in COMMAND_LIMIT:
		var before := _snapshot(session)
		var command := _choose(session, choices)
		trace.append(command)
		if not session.query_command(command)["accepted"] or _snapshot(session) != before:
			_fail(seed, "chosen command was illegal or advisory lookup mutated state", trace)
			return {}
		var result := session.issue_command(command)
		if not result["accepted"] or result["errored"] or not _board_consistent(session):
			_fail(seed, "authoritative execution or occupancy invariant failed", trace)
			return {}
		if session.battle_complete():
			return {"commands": trace, "expected_final": _snapshot(session)}
	_fail(seed, "battle did not finish within %d commands" % COMMAND_LIMIT, trace)
	return {}


func _replay(seed: int, trace: Array[Dictionary], expected_final: Dictionary) -> bool:
	var session := _session(seed)
	if session == null:
		return _fail(seed, "could not start replay", trace)
	for index in trace.size():
		var command := trace[index]
		var before := _snapshot(session)
		var invalid := {"op": "move", "unit": "unknown-instance", "to": [0, 0]}
		if command.has("unit") and index % 2 == 0:
			invalid = {"op": "move", "unit": command["unit"], "to": [-1, -1]}
		var refusal := session.issue_command(invalid)
		if refusal["accepted"] or refusal["state_changed"] or refusal["errored"] \
				or _snapshot(session) != before:
			return _fail(seed, "refusal mutated state at step %d: %s" % [index, invalid],
				trace.slice(0, index + 1))
		if not session.query_command(command)["accepted"] or _snapshot(session) != before:
			return _fail(seed, "replay advisory mutated state at step %d" % index,
				trace.slice(0, index + 1))
		var result := session.issue_command(command)
		if not result["accepted"] or result["errored"] or not _board_consistent(session):
			return _fail(seed, "replay execution failed at step %d" % index,
				trace.slice(0, index + 1))
	if not session.battle_complete() or _snapshot(session) != expected_final:
		return _fail(seed, "final state, events or RNG diverged", trace)
	return true
