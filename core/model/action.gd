class_name Action
extends RefCounted

## Activated abilities — things a unit CHOOSES to do, competing for its action.
##
## Distinct in kind from Modifier, which intervenes passively in the resolution
## pipeline. The tell in the source documentation is uniform: «Особое умение,
## позволяющее воину…» plus a cost.
##
## Three properties of the set drove this design; see oracle/actions.py for the
## evidence.
##
##  1. COST IS NOT IN THE DATA. unit_upg.Quantity carries the effect MAGNITUDE,
##     never the cost. Costs are literals in the prose, so they come from the
##     pack bindings, not from the .var tables.
##  2. ACTIONS SUPPRESS AND SCALE OTHER ABILITIES for the duration of the attack
##     they perform. This is not a cost-and-effect model.
##  3. COST DEPENDS ON THE ACTOR. Трупоед is free for Крысолюд.
##
## Plus the documented global rule: an activated ability costs 1 MORE stamina
## than stated, because the attack itself is charged separately.

enum Target {
	SELF,
	ENEMY_MELEE,
	ENEMY_RANGED,
	ALL_ADJACENT_ENEMIES,
	ALLY_IN_SHOOTING_RANGE,
	CORPSE,
	NONE,
}

## Why an action is unavailable. Distinct values because the UI must say which
## and the AI must know whether waiting would help.
enum Refusal {
	OK,
	NO_STAMINA,
	NO_AMMO,
	ACTION_SPENT,
	EXHAUSTED,
	NO_LEGAL_TARGET,
}

const REFUSAL_TEXT: Dictionary = {
	Refusal.OK: "ok",
	Refusal.NO_STAMINA: "not enough stamina",
	Refusal.NO_AMMO: "not enough ammo",
	Refusal.ACTION_SPENT: "already acted this round",
	Refusal.EXHAUSTED: "forced to rest at 0 stamina",
	Refusal.NO_LEGAL_TARGET: "no legal target",
}

var id: StringName
var name: String
## Original/source ability identity retained only at the content boundary.
## Runtime recipes resolve from canonical `id` and never dispatch on this.
var source_id: int = -1
var target: Target = Target.SELF

# --- cost ------------------------------------------------------------------
var cost_stamina: int = 0
var cost_ammo: int = 0
var consumes_action: bool = true
## «тратится на 1 Выносливость больше … она тратится за факт атаки»
var attack_surcharge: bool = false
## Subtypes that pay no action cost.
var free_action_for: Array[StringName] = []

# --- effect ----------------------------------------------------------------
## From unit_upg.Quantity. Meaning is per-action: heal amount, stamina drained,
## ammo collected, defence bonus.
var magnitude: int = 0
var is_attack: bool = false
## «в полтора раза большие повреждения» = 1.5. For the accepted selected
## ordinary-attack branch this adds trunc0(effective attack / 2) before
## conditional contribution, randomisation and defence. Ranged action execution
## remains outside the currently accepted boundary.
var damage_scale: float = 1.0
var suppresses: Array[StringName] = []
## ability name -> factor, applied for the duration of this action
var scales: Dictionary = {}
var excluded_targets: Array[StringName] = []
## [ability_name, magnitude_or_null, duration]
var grants: Array = []
var notes: String = ""
## Composition-owned normalized recipe metadata. Runtime callers receive only a
## deep copy, so a per-unit grant or plan resolution cannot mutate the shared
## canonical definition.
var _declarative_recipe: Dictionary = {}
var declarative_recipe_error: String = ""


func set_declarative_recipe(recipe: Dictionary) -> void:
	_declarative_recipe = recipe.duplicate(true)
	declarative_recipe_error = ""


func set_declarative_recipe_error(message: String) -> void:
	_declarative_recipe = {}
	declarative_recipe_error = message


func has_declarative_recipe() -> bool:
	return not _declarative_recipe.is_empty()


func declarative_recipe() -> Dictionary:
	return _declarative_recipe.duplicate(true)


func resolved_stamina() -> int:
	return cost_stamina + (1 if attack_surcharge else 0)


func resolved_consumes_action(actor: Combatant) -> bool:
	if not consumes_action:
		return false
	for s in free_action_for:
		if actor.has_subtype(s):
			return false
	return true


## Decidable from the actor alone. Target legality belongs to the battle layer,
## which knows what is adjacent and what is dead.
func availability(actor: Combatant,
		modifier_0x12_effective: bool = false) -> Refusal:
	var stamina_suppressed := (modifier_0x12_effective
		or actor.has_modifier_id(0x12) or actor.has_flag(&"Неутомимый"))
	if actor.action_spent and resolved_consumes_action(actor):
		return Refusal.ACTION_SPENT
	# At 0 stamina the unit is forced to Rest — «в свой следующий ход
	# принудительно выполняет команду Отдых» — so nothing else is available.
	if actor.stamina <= 0 and not stamina_suppressed:
		return Refusal.EXHAUSTED
	var need: int = resolved_stamina()
	if need > 0 and not stamina_suppressed and actor.stamina < need:
		return Refusal.NO_STAMINA
	if cost_ammo > 0 and actor.ammo < cost_ammo:
		return Refusal.NO_AMMO
	return Refusal.OK


func is_available(actor: Combatant,
		modifier_0x12_effective: bool = false) -> bool:
	return availability(actor, modifier_0x12_effective) == Refusal.OK


func pay(actor: Combatant,
		modifier_0x12_effective: bool = false) -> Trace:
	var t := Trace.new("%s.action_stamina_cost" % actor.name)
	var stamina_suppressed := (modifier_0x12_effective
		or actor.has_modifier_id(0x12) or actor.has_flag(&"Неутомимый"))
	var requested := resolved_stamina()
	t.base = float(actor.stamina)
	if requested > 0 and stamina_suppressed:
		t.step("modifier 0x12 stamina mutation suppression", t.base, t.base,
			"requested action stamina cost %d" % requested)
	elif requested > 0:
		actor.stamina = maxi(0, actor.stamina - requested)
		t.step("action stamina mutation", t.base, float(actor.stamina),
			"resolved action cost")
	actor.ammo = maxi(0, actor.ammo - cost_ammo)
	if resolved_consumes_action(actor):
		actor.action_spent = true
	t.result = float(actor.stamina)
	return t


## Build from one already composed definition dictionary. Production enumeration
## belongs to the injected content provider, never to this model class.
static func canonical_id_for_source(source_id: int,
		definitions: Dictionary) -> StringName:
	## Explicit content/import-boundary lookup; there is no model-global default.
	for canonical_id in definitions:
		var action := definitions[canonical_id] as Action
		if action != null and action.source_id == source_id:
			return StringName(canonical_id)
	return &""


func to_dict() -> Dictionary:
	var scale_pairs: Array = []
	for key in scales:
		scale_pairs.append([String(key), scales[key]])
	var data := {
		"id": String(id), "name": name, "source_id": source_id,
		"target": target, "cost_stamina": cost_stamina,
		"cost_ammo": cost_ammo, "consumes_action": consumes_action,
		"attack_surcharge": attack_surcharge,
		"free_action_for": free_action_for.duplicate(),
		"magnitude": magnitude, "is_attack": is_attack,
		"damage_scale": damage_scale, "suppresses": suppresses.duplicate(),
		"scales": scale_pairs, "excluded_targets": excluded_targets.duplicate(),
		"grants": grants.duplicate(true), "notes": notes,
	}
	if has_declarative_recipe():
		data["__validated_declarative_recipe"] = declarative_recipe()
	if declarative_recipe_error != "":
		data["__declarative_recipe_error"] = declarative_recipe_error
	return data


static func from_dict(d: Dictionary) -> Action:
	var a := Action.new()
	a.id = StringName(d.get("id", ""))
	a.name = String(d.get("name", ""))
	a.source_id = int(d.get("source_id", -1))
	var target_v: Variant = d.get("target", Target.SELF)
	if typeof(target_v) == TYPE_STRING:
		var target_key := String(target_v).to_upper()
		a.target = Target[target_key] if Target.has(target_key) else Target.SELF
	else:
		a.target = int(target_v)
	a.cost_stamina = int(d.get("cost_stamina", 0))
	a.cost_ammo = int(d.get("cost_ammo", 0))
	a.consumes_action = bool(d.get("consumes_action", true))
	a.attack_surcharge = bool(d.get("attack_surcharge", false))
	a.magnitude = int(d.get("magnitude", 0))
	a.is_attack = bool(d.get("is_attack", false))
	a.damage_scale = float(d.get("damage_scale", 1.0))
	a.notes = String(d.get("notes", ""))
	for s in d.get("free_action_for", []):
		a.free_action_for.append(StringName(s))
	for s in d.get("suppresses", []):
		a.suppresses.append(StringName(s))
	for s in d.get("excluded_targets", []):
		a.excluded_targets.append(StringName(s))
	for pair in d.get("scales", []):
		a.scales[StringName(pair[0])] = float(pair[1])
	a.grants = d.get("grants", [])
	var validated_recipe: Variant = d.get("__validated_declarative_recipe")
	if typeof(validated_recipe) == TYPE_DICTIONARY:
		a.set_declarative_recipe(validated_recipe)
	if d.has("__declarative_recipe_error"):
		a.set_declarative_recipe_error(String(d["__declarative_recipe_error"]))
	return a
