class_name DeathLifecycle
extends RefCounted

## Authoritative address-free tactical death lifecycle (CX-011).

const TRANSFER := 0x49
const REVIVE := 0x4A
const ROLLBACK := 0x5A
const REPLACE := 0x5B
const REPLACEMENT_BY_TIER := {1: 21, 2: 37, 3: 56, 4: 65}


static func replacement_id_for_tier(tier: int) -> int:
	assert(REPLACEMENT_BY_TIER.has(tier),
		"death replacement requires original tier 1..4")
	return int(REPLACEMENT_BY_TIER.get(tier, 0))


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


static func _replacement_definition(unit: Combatant, definition_id: int,
		content_provider: Variant) -> Variant:
	if content_provider == null:
		return null
	var source_id := String(unit.original_definition.get(
		"content_id", unit.content_id))
	var marker := ":unit/"
	if source_id.find(marker) < 0:
		return null
	var canonical_id := source_id.split(marker)[0] + marker + str(definition_id)
	var definition_v: Variant = content_provider.call(
		"resolve_definition", canonical_id)
	if typeof(definition_v) != TYPE_DICTIONARY:
		return null
	var definition: Dictionary = definition_v.duplicate(true)
	definition["content_id"] = canonical_id
	var built_modifiers: Array = []
	for modifier_v in definition.get("modifiers", []):
		if modifier_v is Modifier:
			built_modifiers.append(modifier_v)
		else:
			var modifier: Dictionary = modifier_v
			built_modifiers.append(Modifier.make(
				int(modifier.get("ability", 0)),
				StringName(String(modifier["handler"])),
				Modifier.Hook[String(modifier.get("hook", "STAT_PASSIVE"))],
				int(modifier.get("power", 0)),
				modifier.get("params", {}).duplicate(true),
				String(modifier.get("source", modifier["handler"]))))
	definition["modifiers"] = built_modifiers
	return definition


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
		sides: Array, content_provider: Variant, scenario_log: Array) -> Dictionary:
	return resolve(unit, battlefield, sides,
		Callable(DeathLifecycle, "_replacement_definition").bind(content_provider),
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
		definition_resolver: Callable = Callable(),
		event_sink: Callable = Callable()) -> Dictionary:
	var events: Array = []
	_emit(events, event_sink, "death_started", unit)
	var original_side: Variant = _side_of(unit, sides)
	var position := battlefield.find_unit(unit)
	if battlefield.contains(position):
		unit.last_position = position

	## Morale reacts to the fatal event before any survival branch.
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

	var transfer_status := _runtime_marker(unit, TRANSFER)
	var revive_status := _runtime_marker(unit, REVIVE)
	var replace_status := _runtime_marker(unit, REPLACE)
	var rollback_status := _runtime_marker(unit, ROLLBACK)

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
	elif replace_status != null:
		branch = "replaced"
		var original_tier := int(unit.original_definition.get("tier", unit.tier))
		var replacement_id := replacement_id_for_tier(original_tier)
		assert(definition_resolver.is_valid(),
			"death replacement requires a definition resolver")
		var definition_v: Variant = definition_resolver.call(unit, replacement_id)
		assert(typeof(definition_v) == TYPE_DICTIONARY,
			"replacement definition %d was not resolved" % replacement_id)
		if typeof(definition_v) != TYPE_DICTIONARY:
			return {"fatal_event": true, "final_alive": false,
				"branch": "invalid_replacement", "transferred": false,
				"events": events}
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
