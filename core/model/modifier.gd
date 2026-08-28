class_name Modifier
extends RefCounted

## The atomic value type: one thing that changes one number.
##
## Innate ability, level-up perk, item enchant, spell buff, terrain, medal,
## aura — all of them are a Modifier. One type, one resolution path, one place
## to debug.
##
## `ability` is the opcode: opaque, meaningful only against its pack.
## `handler` is the engine function the pack's bindings resolved it to.
## Both are kept — the opcode identifies WHAT, the handler identifies HOW, and
## they differ per pack. Opcode 30 is magic immunity in Genesis and
## armour-piercing strike in New Horizons.

## Resolution order. Lower runs first. THE ORDER IS THE ARCHITECTURE: it decides
## rounding, clamping, and whether percentage modifiers compound. Reordering it
## changes every battle outcome.
##
## Only the hooks the engine actually reaches today are listed. The full 33-hook
## taxonomy is in tools/var/hooks.py; the gap between the two lists is an honest
## statement of what is implemented.
enum Hook {
	# attack, attacker side
	STAT_PASSIVE = 10,       ## flat deltas to a base stat, INSIDE the multipliers
	DAMAGE_BASE = 20,        ## reshapes the damage figure itself
	DAMAGE_VS_TARGET = 30,   ## conditional bonuses, OUTSIDE the multipliers

	# attack, defender side
	EVASION = 40,
	DEFENCE_APPLY = 50,
	DAMAGE_TAKEN = 60,

	# riders
	ON_HIT = 70,
	ON_DAMAGED = 80,
	COUNTERATTACK = 90,
	ON_KILL = 100,
	ON_DEATH = 110,

	# resources and state
	STAMINA = 120,
	MORALE = 130,
	AMMO = 140,
	STATUS_RESIST = 150,

	# passive
	AURA = 160,
}

var ability: int = 0
var handler: StringName = &""
var hook: Hook = Hook.STAT_PASSIVE
var power: int = 0
var params: Dictionary = {}
var source: String = ""
var duration: int = -1        ## -1 = permanent
## Canonical ModifierSemantic.Query values, distinct from the source opcode.
var semantics: Array[int] = []

## Morale demonstrably does not multiply conditional damage (Сокрушение зла and
## similar). Whether stamina and wound skip them too is undocumented — see
## OPEN_QUESTIONS item 7. Modifiers flagged here apply after all three.
var outside_multipliers: bool = false


static func make(p_ability: int, p_handler: StringName, p_hook: Hook,
		p_power: int = 0, p_params: Dictionary = {}, p_source: String = "",
		p_semantics: Variant = []) -> Modifier:
	var parsed := ModifierSemantic.parse(p_semantics)
	if not bool(parsed["ok"]):
		push_error(String(parsed["reason"]))
		return null
	var m := Modifier.new()
	m.ability = p_ability
	m.handler = p_handler
	m.hook = p_hook
	m.power = p_power
	m.params = p_params.duplicate(true)
	m.source = p_source
	m.semantics.assign(parsed["semantics"])
	return m


static func from_dict(specification: Dictionary, default_power: int = 0,
		default_source: String = "") -> Modifier:
	var parsed := ModifierSemantic.parse_names(specification.get("semantics", []))
	if not bool(parsed["ok"]):
		push_error(String(parsed["reason"]))
		return null
	return make(
		int(specification.get("ability", 0)),
		StringName(String(specification.get("handler", ""))),
		Hook[String(specification.get("hook", "STAT_PASSIVE"))],
		int(specification.get("power", default_power)),
		specification.get("params", {}),
		String(specification.get("source", default_source)),
		parsed["semantics"])


func has_semantic(query: ModifierSemantic.Query) -> bool:
	return semantics.has(int(query))


func semantic_names() -> Array[String]:
	return ModifierSemantic.names(semantics)


func copy() -> Modifier:
	var out := make(ability, handler, hook, power, params, source, semantics)
	out.duration = duration
	out.outside_multipliers = outside_multipliers
	return out


## Build from what ContentDb.resolve() returns.
static func from_binding(opcode: int, handler_name: StringName, p_params: Dictionary,
		p_power: int, p_hook: Hook, p_source: String = "",
		p_semantics: Variant = []) -> Modifier:
	return make(opcode, handler_name, p_hook, p_power, p_params, p_source, p_semantics)


func describe() -> String:
	var label: String = source if source != "" else String(handler)
	return label if power == 0 else "%s %+d" % [label, power]