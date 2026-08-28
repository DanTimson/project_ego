class_name ManualBattleSession
extends RefCounted

## Presentation facade for one retained Scenario. It owns no tactical state or
## formulas: advisory queries and authoritative execution both delegate to the
## same Scenario command gate.

var scenario: Scenario
var started: bool = false
var _pipeline: Pipeline


func _init(p_scenario: Scenario) -> void:
	scenario = p_scenario
	var registry := AbilityRegistry.new()
	Handlers.register_all(registry)
	_pipeline = Pipeline.new(registry)


func begin() -> Dictionary:
	if started:
		return {"ok": false, "message": "manual battle already started"}
	if scenario == null or scenario.construction_error != "" \
			or scenario.field == null or scenario.state == null:
		var detail := "invalid Scenario" if scenario == null else scenario.construction_error
		return {"ok": false,
			"message": "scenario construction failed: %s" % detail,
			"error": detail}
	RoundLoop.begin_battle(scenario.state)
	scenario.emit("== %s (seed %d) ==" % [scenario.scenario_name, scenario.seed_value])
	scenario.emit("-- round %d, side %d first --" % [
		scenario.state.round_number, scenario.state.active_side])
	started = true
	return {"ok": true, "message": scenario.log.back(),
		"log": scenario.log.duplicate()}


func end() -> void:
	_unbind_rules()
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
	return scenario.unit_position_offset(unit)


func reachable_cells(unit: Combatant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not can_select(unit):
		return out
	for row in scenario.field.height:
		for col in scenario.field.width:
			var cell := Vector2i(col, row)
			var query := query_command({
				"op": "move", "unit": unit.instance_id, "to": [col, row],
			})
			if bool(query["accepted"]):
				out.append(cell)
	return out


func legal_melee_targets(unit: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	if unit == null:
		return out
	for target in living_units():
		var query := query_command({
			"op": "attack", "unit": unit.instance_id,
			"target": target.instance_id,
		})
		if bool(query["accepted"]):
			out.append(target)
	return out


func legal_ranged_targets(unit: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	if unit == null:
		return out
	for target in living_units():
		var query := query_command({
			"op": "shoot", "unit": unit.instance_id,
			"target": target.instance_id,
		})
		if bool(query["accepted"]):
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


## Advisory legality. The result comes from Scenario's execution gate but does
## not reserve state; callers must still trust issue_command().
func query_command(command: Dictionary) -> Dictionary:
	var refusal := _session_refusal()
	if refusal != "":
		return _result(false, _command_name(command), refusal, [], false)
	var query := scenario.query_command(command)
	return _result(bool(query["accepted"]), String(query["command"]),
		String(query["reason"]), [], false)


## Authoritative command execution. Damage's process-global bindings are scoped
## to this call and cleared before returning so alternating sessions cannot
## retain one another's environment.
func issue_command(command: Dictionary) -> Dictionary:
	var refusal := _session_refusal()
	if refusal != "":
		return _result(false, _command_name(command), refusal, [], false)
	_bind_rules()
	var result := scenario.execute_command(command)
	_unbind_rules()
	result["battle_over"] = battle_complete()
	result["winner"] = winning_side_id()
	return result


## Neutral presentation query used by inspection/tests. No formula is copied
## here; it invokes Damage under this session's scoped environment.
func current_attack(unit: Combatant,
		kind: Combatant.AttackKind = Combatant.AttackKind.MELEE) -> float:
	_bind_rules()
	var result: Array = Damage.current_attack(unit, kind)
	_unbind_rules()
	return float(result[0])


func _bind_rules() -> void:
	Damage.bind_pipeline(_pipeline)
	Damage.bind_environment(Callable(scenario, "environment"))


func _unbind_rules() -> void:
	Damage.bind_environment(Callable())
	Damage.bind_pipeline(null)


func _session_refusal() -> String:
	if not started:
		return "manual battle has not started"
	if scenario.runtime_error != "":
		return "battle halted after fatal resolution failure: %s" % scenario.runtime_error
	return "battle is already over" if battle_complete() else ""


func _command_name(command: Dictionary) -> String:
	var op := String(command.get("op", ""))
	return {"attack": "melee", "shoot": "ranged", "end_phase": "pass"}.get(op, op)


func _result(accepted: bool, command: String, reason: String,
		events: Array, state_changed: bool) -> Dictionary:
	return {
		"accepted": accepted,
		"command": command,
		"reason": reason,
		"events": events,
		"state_changed": state_changed,
		"errored": scenario.runtime_error != "" if scenario != null else false,
		"runtime_error": scenario.runtime_error if scenario != null else "",
		"ok": accepted,
		"message": reason if not accepted else " | ".join(events),
		"log": events,
		"battle_over": battle_complete() if started else false,
		"winner": winning_side_id() if started else -1,
	}
