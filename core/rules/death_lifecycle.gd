class_name DeathLifecycle
extends RefCounted

## Authoritative address-free tactical death lifecycle (CX-011).

const TRANSFER := 0x49
const REVIVE := 0x4A
const ROLLBACK := 0x5A
static func _runtime_marker(unit: Combatant, ability: int) -> Status:
	## Search runtime Status-owned modifiers only, never effective providers.
	for effect in unit.statuses:
		for modifier in effect.modifiers:
			if int(modifier.ability) == ability:
				return effect
	return null


static func _side_of(unit: Combatant, sides: Array) -> Variant:
	for side in sides:
		if side.units.has(unit):
			return side
	return null


static func transfer_to_opposite_side(unit: Combatant, sides: Array) -> bool:
	## Move the same logical object; do not copy or refresh battle state.
	var source: Variant = _side_of(unit, sides)
	var target: Variant = null
	for side in sides:
		if side != source:
			target = side
			break
	if source == null or target == null:
		return false
	source.units.erase(unit)
	if not target.units.has(unit):
		target.units.append(unit)
	return true


static func normalize_definition(specification: Dictionary,
		definition_id: int = -1) -> Dictionary:
	var out := specification.duplicate(true)
	if definition_id >= 0:
		out["definition_id"] = definition_id
	for pair in [["life", "life_base"], ["stamina", "stamina_base"],
			["morale", "morale_base"], ["ammo", "ammo_base"]]:
		if not out.has(pair[1]) and out.has(pair[0]):
			out[pair[1]] = int(out[pair[0]])
	for key in ["flags", "subtypes"]:
		if out.has(key) and typeof(out[key]) == TYPE_ARRAY:
			var membership: Dictionary = {}
			for value in out[key]:
				membership[StringName(String(value))] = true
			out[key] = membership
	return out


static func _append_scenario_event(event: Dictionary, scenario_log: Array) -> void:
	var keys: Array = event.keys()
	keys.erase("event")
	keys.erase("unit")
	keys.sort()
	var details: Array[String] = []
	for key in keys:
		details.append("%s=%s" % [String(key), str(event[key]).to_lower()
			if typeof(event[key]) == TYPE_BOOL else str(event[key])])
	var suffix := (" " + ",".join(details)) if not details.is_empty() else ""
	scenario_log.append("  [lifecycle] %s %s%s" % [
		event["unit"], event["event"], suffix])


static func resolve_for_scenario(unit: Combatant, battlefield: Battlefield,
		sides: Array, replacement_resolver: Callable,
		scenario_log: Array) -> Dictionary:
	return resolve(unit, battlefield, sides, replacement_resolver,
		Callable(DeathLifecycle, "_append_scenario_event").bind(scenario_log))


static func apply_aura_upkeep(unit: Combatant, auras_by_source: Dictionary,
		battlefield: Battlefield, side_of: Callable, fatal_resolver: Callable,
		fell_sink: Callable, line_sink: Callable) -> void:
	if not unit.alive:
		return
	var was_alive := unit.alive
	var result: Array = Auras.tick_for(unit, auras_by_source, battlefield, side_of)
	var totals: Dictionary = result[0]
	if totals.is_empty():
		return
	Auras.apply_tick(unit, totals)
	var parts: Array = []
	var keys: Array = totals.keys()
	keys.sort()
	for key in keys:
		parts.append("%s %+d" % [String(key), int(totals[key])])
	line_sink.call("  %s: auras (%s)" % [unit.label(), ", ".join(parts)])
	# Only this upkeep's living-to-dead transition is a new fatal event. A final
	# persistent dead record can remain in a side roster indefinitely.
	if was_alive and not unit.alive:
		var lifecycle: Dictionary = fatal_resolver.call(unit)
		if not bool(lifecycle["final_alive"]):
			fell_sink.call(unit)


static func scenario_position(unit: Combatant, battlefield: Battlefield) -> String:
	var position: Variant = battlefield.find_unit(unit)
	if not battlefield.contains(position) and unit.last_position != null:
		position = unit.last_position
	if not battlefield.contains(position):
		return "-"
	var offset := Battlefield.axial_to_offset(position)
	return "%d,%d" % [offset.x, offset.y]


static func has_scenario_final_details(unit: Combatant) -> bool:
	return unit.definition_id != 0 or unit.tier != 1 or unit.battle_owned \
		or unit.discarded or unit.morale_break_accumulator != 0 \
		or unit.last_position != null


static func scenario_final_details(unit: Combatant, side: Variant) -> Dictionary:
	return {
		"side": side.id if side != null else null,
		"definition_id": unit.definition_id,
		"content_id": unit.content_id,
		"tier": unit.tier,
		"morale": unit.morale,
		"ammo": unit.ammo,
		"morale_break_accumulator": unit.morale_break_accumulator,
		"damage_received": unit.damage_received.duplicate(),
		"battle_owned": unit.battle_owned,
		"discarded": unit.discarded,
	}


static func _emit(events: Array, sink: Callable, kind: String,
		unit: Combatant, details: Dictionary = {}) -> void:
	var event := {"event": kind,
		"unit": unit.instance_id if unit.instance_id != "" else unit.name}
	for key in details:
		event[key] = details[key]
	events.append(event)
	if sink.is_valid():
		sink.call(event)


static func resolve(unit: Combatant, battlefield: Battlefield, sides: Array,
		replacement_resolver: Callable = Callable(),
		event_sink: Callable = Callable()) -> Dictionary:
	var events: Array = []
	_emit(events, event_sink, "death_started", unit)
	var original_side: Variant = _side_of(unit, sides)
	var position := battlefield.find_unit(unit)
	if battlefield.contains(position):
		unit.last_position = position

	# Preflight the already-computed replacement decision before morale,
	# rollback, or status consumption. Revival keeps its established precedence,
	# so a replacement decision it masks is not an exercised replacement path.
	var transfer_status := _runtime_marker(unit, TRANSFER)
	var revive_status := _runtime_marker(unit, REVIVE)
	var rollback_status := _runtime_marker(unit, ROLLBACK)
	var replacement_decision: Dictionary = (
		replacement_resolver.call(unit)
		if replacement_resolver.is_valid()
		else {"status": "not_applicable"}
	)
	var decision_status := String(replacement_decision.get("status", ""))
	var replacement_error := ""
	if revive_status == null:
		if decision_status not in ["not_applicable", "resolved", "unresolved"]:
			replacement_error = "death replacement resolver returned an invalid decision"
		elif decision_status == "unresolved":
			replacement_error = String(replacement_decision.get(
				"error", "applicable death replacement was unresolved"))
		elif decision_status == "resolved" \
				and typeof(replacement_decision.get("definition")) != TYPE_DICTIONARY:
			replacement_error = "resolved death replacement has no definition"
	if replacement_error != "":
		push_error(replacement_error)
		unit.life = 0
		unit.alive = false
		if battlefield.contains(position):
			battlefield.remove_occupant(position)
		_emit(events, event_sink, "death_resolution_failed", unit,
			{"error": replacement_error})
		return {"fatal_event": true, "final_alive": false,
			"branch": "invalid_replacement", "transferred": false,
			"error": replacement_error, "events": events}

	## Morale reacts to a fatal event only after its lifecycle can complete.
	if battlefield.contains(position) and original_side != null:
		for adjacent in battlefield.adjacent_occupants(position):
			if adjacent == unit or not adjacent.alive or adjacent.life <= 0:
				continue
			var delta := -1 if original_side.units.has(adjacent) else 1
			var applied := Damage.adjust_morale(adjacent, delta)
			_emit(events, event_sink, "death_morale", unit, {
				"target": adjacent.instance_id if adjacent.instance_id != "" else adjacent.name,
				"delta": delta, "applied": applied, "morale": adjacent.morale,
			})

	if rollback_status != null and not unit.original_definition.is_empty():
		unit.restore_definition(unit.original_definition)
		unit.original_definition.clear()
		var restored_speed := int(ActionPoints.effective_speed(unit)[0])
		unit.movement_remaining = mini(unit.movement_remaining, restored_speed)
		unit.ammo = mini(unit.ammo, unit.ammo_base)
		_emit(events, event_sink, "transformation_reverted", unit,
			{"definition_id": unit.definition_id})

	var cleared := unit.statuses.size()
	unit.statuses.clear()
	_emit(events, event_sink, "statuses_cleared", unit, {"count": cleared})

	var branch := "final"
	if revive_status != null:
		branch = "revived"
		unit.life = unit.life_base
		unit.morale_break_accumulator = 0
		unit.alive = true
		unit.discarded = false
		_emit(events, event_sink, "revived", unit, {"life": unit.life})
	elif decision_status == "resolved":
		branch = "replaced"
		var definition_v: Variant = replacement_decision.get("definition")
		var replacement_id := int(replacement_decision.get("definition_id", -1))
		var original_tier := int(replacement_decision.get("tier", unit.tier))
		unit.restore_definition(normalize_definition(definition_v, replacement_id))
		unit.original_definition.clear()
		unit.life = unit.life_base
		unit.stamina = unit.stamina_base
		unit.ammo = unit.ammo_base
		unit.morale = unit.morale_base
		unit.morale_break_accumulator = 0
		unit.alive = true
		unit.discarded = false
		_emit(events, event_sink, "replaced", unit,
			{"definition_id": replacement_id, "tier": original_tier})
	else:
		unit.life = 0
		unit.alive = false
		if battlefield.contains(position):
			battlefield.remove_occupant(position)
		if unit.battle_owned:
			unit.discarded = true
			if original_side != null:
				original_side.units.erase(unit)
		_emit(events, event_sink, "death_finalized", unit,
			{"battle_owned": unit.battle_owned, "discarded": unit.discarded})

	var transferred := false
	if transfer_status != null and not (branch == "final" and unit.battle_owned):
		transferred = transfer_to_opposite_side(unit, sides)
		if transferred:
			_emit(events, event_sink, "side_transferred", unit,
				{"side": _side_of(unit, sides).id})

	return {"fatal_event": true,
		"final_alive": unit.alive and unit.life > 0,
		"branch": branch, "transferred": transferred, "events": events}
