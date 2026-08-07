class_name ManualBattleSession
extends RefCounted

## One-command-at-a-time driver for an existing Scenario model. It owns no
## tactical state; every query and command reads or invokes the retained model.

var scenario: Scenario
var started: bool = false


func _init(p_scenario: Scenario) -> void:
	scenario = p_scenario


func begin() -> Dictionary:
	if started:
		return {"ok": false, "message": "manual battle already started"}
	var registry := AbilityRegistry.new()
	Handlers.register_all(registry)
	Damage.bind_pipeline(Pipeline.new(registry))
	Damage.bind_environment(Callable(scenario, "environment"))
	RoundLoop.begin_battle(scenario.state)
	scenario.emit("== %s (seed %d) ==" % [scenario.scenario_name, scenario.seed_value])
	scenario.emit("-- round %d, side %d first --" % [
		scenario.state.round_number, scenario.state.active_side])
	started = true
	return {"ok": true, "message": scenario.log.back(),
		"log": scenario.log.duplicate()}


func end() -> void:
	if started:
		Damage.bind_environment(Callable())
		Damage.bind_pipeline(null)
	started = false


func active_side_id() -> int:
	return scenario.state.active_side


func side_name(side_id: int) -> String:
	var side := scenario.state.side(side_id)
	return side.name if side != null else "Side %d" % side_id


func living_units(side_id: int = -1) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for side in scenario.state.sides:
		if side_id >= 0 and side.id != side_id:
			continue
		out.append_array(side.living())
	return out


func selectable_units() -> Array[Combatant]:
	if not started or battle_complete():
		return []
	return RoundLoop.activatable(scenario.state, scenario.state.active_side)


func can_select(unit: Combatant) -> bool:
	return unit != null and unit.alive and selectable_units().has(unit)


func unit_position(unit: Combatant) -> Vector2i:
	var axial := scenario.field.find_unit(unit)
	return Battlefield.axial_to_offset(axial) if scenario.field.contains(axial) \
		else Vector2i(-1, -1)


func reachable_cells(unit: Combatant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not can_select(unit) or unit.movement_remaining <= 0:
		return out
	var start := scenario.field.find_unit(unit)
	var cells: Array = scenario.field.reachable(
		start, unit.movement_remaining).keys()
	for axial in cells:
		if axial != start:
			out.append(Battlefield.axial_to_offset(axial))
	out.sort_custom(func(a: Vector2i, b: Vector2i):
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return out


func legal_melee_targets(unit: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	if not can_select(unit) or unit.action_spent:
		return out
	var own_side := scenario.side_of(unit)
	for target in living_units():
		if scenario.side_of(target) == own_side:
			continue
		if bool(scenario._approach_plan(unit, target)["ok"]):
			out.append(target)
	return out


func legal_ranged_targets(unit: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	if not can_select(unit) or unit.action_spent or unit.ammo <= 0 \
			or unit.shooting_range <= 0:
		return out
	var own_side := scenario.side_of(unit)
	var origin := scenario.field.find_unit(unit)
	for target in living_units():
		if scenario.side_of(target) == own_side:
			continue
		if Battlefield.distance(origin,
				scenario.field.find_unit(target)) <= unit.shooting_range:
			out.append(target)
	return out


func unit_action_possible(unit: Combatant) -> bool:
	return not reachable_cells(unit).is_empty() \
		or not legal_melee_targets(unit).is_empty() \
		or not legal_ranged_targets(unit).is_empty()


func battle_complete() -> bool:
	return RoundLoop.battle_over(scenario.state)


func winning_side_id() -> int:
	if not battle_complete():
		return -1
	for side in scenario.state.sides:
		if not side.living().is_empty():
			return side.id
	return -1


func issue_command(command: Dictionary) -> Dictionary:
	var before := scenario.log.size()
	var refusal := _validate_command(command)
	if refusal != "":
		return _refusal(refusal, before)
	var op := String(command.get("op", ""))
	if op == "end_phase":
		scenario.cmd_end_phase()
	else:
		var unit: Combatant = scenario.units[String(command["unit"])]
		match op:
			"move":
				var destination: Array = command["to"]
				scenario.cmd_move(unit, int(destination[0]), int(destination[1]))
			"attack":
				scenario.cmd_attack(unit, scenario.units[String(command["target"])])
			"shoot":
				scenario.cmd_shoot(unit, scenario.units[String(command["target"])])
			"rest":
				scenario.cmd_rest(unit)
	if battle_complete():
		scenario.emit("== battle over ==")
	elif op != "end_phase":
		scenario._auto_end_phase()
	return _result(true, before)


func _validate_command(command: Dictionary) -> String:
	var session_refusal := _validate_session()
	if session_refusal != "":
		return session_refusal
	var op := String(command.get("op", ""))
	if op == "end_phase":
		return ""
	if op not in ["move", "attack", "shoot", "rest"]:
		return "unknown command '%s'" % op
	var unit: Combatant = scenario.units.get(String(command.get("unit", "")))
	if unit == null:
		return "unknown unit '%s'" % command.get("unit", "")
	var actor_refusal := _validate_actor(unit)
	if actor_refusal != "":
		return actor_refusal
	return _validate_unit_command(unit, command, op)


func _validate_session() -> String:
	if not started:
		return "manual battle has not started"
	return "battle is already over" if battle_complete() else ""


func _validate_unit_command(unit: Combatant, command: Dictionary,
		op: String) -> String:
	if op == "move":
		return _validate_move(unit, command.get("to"))
	if op == "rest":
		return "%s has already acted" % unit.label() if unit.action_spent else ""
	return _validate_target(unit, String(command.get("target", "")), op)


func _validate_actor(unit: Combatant) -> String:
	if not unit.alive:
		return "%s is down and cannot act" % unit.label()
	if scenario.side_of(unit).id != scenario.state.active_side:
		return "%s is not in the active side's phase" % unit.label()
	if not ActionPoints.has_resources(unit):
		return "%s has no resources left this round" % unit.label()
	return ""


func _validate_move(unit: Combatant, destination_v: Variant) -> String:
	if typeof(destination_v) != TYPE_ARRAY or destination_v.size() != 2:
		return "movement destination is malformed"
	var destination := Vector2i(int(destination_v[0]), int(destination_v[1]))
	if not reachable_cells(unit).has(destination):
		return "%s cannot reach %d,%d" % [
			unit.label(), destination.x, destination.y]
	return ""


func _validate_target(unit: Combatant, target_id: String, op: String) -> String:
	var target: Combatant = scenario.units.get(target_id)
	if target == null:
		return "unknown target '%s'" % target_id
	var legal := legal_melee_targets(unit) if op == "attack" \
		else legal_ranged_targets(unit)
	if not legal.has(target):
		return "%s is not a legal %s target for %s" % [
			target.label(), "melee" if op == "attack" else "ranged",
			unit.label()]
	return ""


func _refusal(message: String, before: int) -> Dictionary:
	scenario.emit("refused: %s" % message)
	return _result(false, before)


func _result(ok: bool, before: int) -> Dictionary:
	var entries: Array = scenario.log.slice(before)
	return {
		"ok": ok,
		"message": " | ".join(entries),
		"log": entries,
		"battle_over": battle_complete(),
		"winner": winning_side_id(),
	}
