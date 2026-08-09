class_name Status
extends RefCounted

## Address-free battle-time status instance.
##
## A Status owns the mutable duration/stack state and Modifier objects contributed
## while it is active. Automatic ageing is deliberately not part of this model:
## the lifecycle clock, including UNTIL_NEXT_TURN, remains unresolved.

enum Stacking {
	CUMULATIVE,
	MAXIMUM,
	REFRESH,
	UNIQUE,
}

const PERMANENT := -1

## Project-local effect identity and stacking group. This is not a pack content ID
## or display text; two cumulative instances may intentionally share it.
var id: StringName = &""
var name: String = ""
var source: String = ""
var duration: int = PERMANENT
var power: int = 0
var modifiers: Array[Modifier] = []
## Payload retained for the pre-existing explicit lifecycle-step reference helper.
## No battle event invokes it in the stable runtime tranche.
var tick: Dictionary = {}
var decay_per: Array = []
var stacking: Stacking = Stacking.REFRESH
var prevents_action: bool = false
var hostile: bool = false
var remove_on_damage: bool = false
var tags: Array[StringName] = []


static func from_dict(specification: Dictionary) -> Status:
	var status := Status.new()
	status.id = StringName(String(specification["id"]))
	status.name = String(specification.get("name", ""))
	status.source = String(specification.get("source", ""))
	status.duration = int(specification.get("duration", PERMANENT))
	status.power = int(specification.get("power", 0))
	status.tick = specification.get("tick", {}).duplicate(true)
	if specification.has("decay_per"):
		status.decay_per = specification["decay_per"].duplicate(true)
	status.stacking = Stacking[String(specification.get("stacking", "REFRESH"))]
	status.prevents_action = bool(specification.get("prevents_action", false))
	status.hostile = bool(specification.get("hostile", false))
	status.remove_on_damage = bool(specification.get("remove_on_damage", false))
	for tag in specification.get("tags", []):
		status.tags.append(StringName(String(tag)))
	for modifier_spec in specification.get("modifiers", []):
		status.modifiers.append(Modifier.make(
			int(modifier_spec.get("ability", 0)),
			StringName(String(modifier_spec["handler"])),
			Modifier.Hook[String(modifier_spec.get("hook", "STAT_PASSIVE"))],
			int(modifier_spec.get("power", 0)),
			modifier_spec.get("params", {}).duplicate(true),
			String(modifier_spec.get("source", status.name))))
	return status


func describe() -> String:
	var label: String = name if name != "" else String(id)
	return label if duration == PERMANENT else "%s (%d)" % [label, duration]


func copy() -> Status:
	var out := Status.new()
	out.id = id
	out.name = name
	out.source = source
	out.duration = duration
	out.power = power
	out.tick = tick.duplicate(true)
	out.decay_per = decay_per.duplicate(true)
	out.stacking = stacking
	out.prevents_action = prevents_action
	out.hostile = hostile
	out.remove_on_damage = remove_on_damage
	out.tags.assign(tags)
	for modifier in modifiers:
		out.modifiers.append(_copy_modifier(modifier))
	return out


func to_dict() -> Dictionary:
	var serialized_modifiers: Array = []
	for modifier in modifiers:
		serialized_modifiers.append({
			"ability": modifier.ability,
			"handler": String(modifier.handler),
			"hook": _enum_name(Modifier.Hook, modifier.hook),
			"power": modifier.power,
			"params": modifier.params.duplicate(true),
			"source": modifier.source,
		})
	var serialized_tags: Array[String] = []
	for tag in tags:
		serialized_tags.append(String(tag))
	var out := {
		"id": String(id),
		"name": name,
		"source": source,
		"duration": duration,
		"power": power,
		"tick": tick.duplicate(true),
		"decay_per": decay_per.duplicate(true),
		"stacking": _enum_name(Stacking, stacking),
		"prevents_action": prevents_action,
		"hostile": hostile,
		"tags": serialized_tags,
		"modifiers": serialized_modifiers,
	}
	if remove_on_damage:
		out["remove_on_damage"] = true
	return out


static func _copy_modifier(modifier: Modifier) -> Modifier:
	var out := Modifier.make(modifier.ability, modifier.handler, modifier.hook,
		modifier.power, modifier.params.duplicate(true), modifier.source)
	out.duration = modifier.duration
	out.outside_multipliers = modifier.outside_multipliers
	return out


static func _enum_name(values: Dictionary, value: int) -> String:
	for key in values:
		if int(values[key]) == value:
			return String(key)
	return str(value)
