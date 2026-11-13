class_name CrimsonPolicy
extends RefCounted

## Project EGO demo policy; no legacy AI or random selection.
const CRIMSON := 1
const COMMAND_LIMIT := 64


static func _live(session: ManualBattleSession, round_number: int,
		side_id: int = CRIMSON) -> bool:
	return session.started and session.scenario.runtime_error == "" \
		and not session.battle_complete() and session.active_side_id() == side_id \
		and session.scenario.state.round_number == round_number


static func _by_id(a: Combatant, b: Combatant) -> bool:
	return a.instance_id < b.instance_id


static func _nearest(session: ManualBattleSession, cell: Vector2i, side_id: int) -> int:
	var distance := 2147483647
	for enemy in session.living_units():
		if session.scenario.side_of(enemy).id != side_id:
			distance = mini(distance, Battlefield.distance(
				Battlefield.offset_to_axial(cell.x, cell.y),
				session.scenario.field.find_unit(enemy)))
	return distance


static func choose_command(session: ManualBattleSession, side_id: int = CRIMSON) -> Dictionary:
	if not _live(session, session.scenario.state.round_number, side_id):
		return {}
	var units := session.selectable_units()
	units.sort_custom(_by_id)
	for unit in units:
		for op in ["shoot", "attack"]:
			var targets := session.legal_ranged_targets(unit) if op == "shoot" \
				else session.legal_melee_targets(unit)
			targets.sort_custom(_by_id)
			if not targets.is_empty():
				return {"op": op, "unit": unit.instance_id,
					"target": targets[0].instance_id}
		var best_distance := _nearest(session, session.unit_position(unit), side_id)
		var best := Vector2i(-1, -1)
		# reachable_cells is row/column ordered; equal distances retain that order.
		for cell in session.reachable_cells(unit):
			var distance := _nearest(session, cell, side_id)
			if distance < best_distance:
				best_distance = distance
				best = cell
		if best.x >= 0:
			return {"op": "move", "unit": unit.instance_id, "to": [best.x, best.y]}
	return {}


static func run_phase(session: ManualBattleSession) -> Dictionary:
	var report := {"commands": [], "results": [], "reason": ""}
	var round_number := session.scenario.state.round_number
	for index in COMMAND_LIMIT:
		if not _live(session, round_number):
			return report
		var command := choose_command(session)
		if command.is_empty():
			break
		var result := session.issue_command(command)
		report.commands.append(command)
		report.results.append(result)
		if bool(result.get("errored", false)):
			report.reason = String(result.get("runtime_error", "Battle runtime error."))
			return report
		if not bool(result["accepted"]):
			report.reason = String(result["reason"])
			break
	if _live(session, round_number):
		var command := {"op": "end_phase"}
		var result := session.issue_command(command)
		report.commands.append(command)
		report.results.append(result)
		if not bool(result["accepted"]) or bool(result.get("errored", false)):
			report.reason = String(result.get("runtime_error", "")) \
				if bool(result.get("errored", false)) else String(result["reason"])
	return report
