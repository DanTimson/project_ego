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

enum Capability {
	MOVEMENT,
	MELEE,
	RANGED,
	CASTING,
	ACTIVATED_ACTION,
}

const PERMANENT := -1
const CAPABILITY_NAMES := {
	Capability.MOVEMENT: "movement",
	Capability.MELEE: "melee",
	Capability.RANGED: "ranged",
	Capability.CASTING: "casting",
	Capability.ACTIVATED_ACTION: "activated_action",
}
const CAPABILITIES_BY_NAME := {
	"movement": Capability.MOVEMENT,
	"melee": Capability.MELEE,
	"ranged": Capability.RANGED,
	"casting": Capability.CASTING,
	"activated_action": Capability.ACTIVATED_ACTION,
}

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
## Independently composable voluntary-command capabilities restricted while this
## status is effective. Values are normalized and deduplicated at construction.
var restrictions: Array[int] = []
var hostile: bool = false
var remove_on_damage: bool = false
var tags: Array[StringName] = []


static func from_dict(specification: Dictionary) -> Status:
	if specification.has("prevents_action"):
		return null
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
	var parsed := parse_restrictions(specification.get("restrictions", []))
	if not bool(parsed["ok"]):
		return null
	status.restrictions.assign(parsed["restrictions"])
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


## Strict address-free model/content boundary. Unknown names do not become an
## ignored (and therefore permission-granting) declaration.
static func parse_restrictions(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false, "restrictions": [],
			"reason": "status restrictions must be an array"}
	var parsed: Array[int] = []
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return {"ok": false, "restrictions": [],
				"reason": "status restriction values must be capability names"}
		var normalized := String(raw).strip_edges().to_lower()
		if not CAPABILITIES_BY_NAME.has(normalized):
			return {"ok": false, "restrictions": [],
				"reason": "unknown status capability '%s'" % normalized}
		var capability := int(CAPABILITIES_BY_NAME[normalized])
		if not parsed.has(capability):
			parsed.append(capability)
	return {"ok": true, "restrictions": parsed, "reason": ""}


static func is_capability(value: int) -> bool:
	return CAPABILITY_NAMES.has(value)


static func capability_name(value: int) -> String:
	return String(CAPABILITY_NAMES.get(value, "unknown"))


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
	out.restrictions.assign(restrictions)
	out.hostile = hostile
	out.remove_on_damage = remove_on_damage
	out.tags.assign(tags)
	for modifier in modifiers:
		out.modifiers.append(_copy_modifier(modifier))
	return out


func _serialized_restrictions() -> Array:
	# Restrictions are semantic set data; emit canonical Capability enum order.
	var ordered := restrictions.duplicate()
	ordered.sort()
	return ordered.map(func(value): return capability_name(int(value)))


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
		"restrictions": _serialized_restrictions(),
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
