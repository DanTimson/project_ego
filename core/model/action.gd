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
## «в полтора раза большие повреждения» = 1.5.
## OPEN: whether this scales the attack value before the roll or the final
## damage after defence. Those differ — the roll is integer and defence is
## subtracted afterwards.
var damage_scale: float = 1.0
var suppresses: Array[StringName] = []
## ability name -> factor, applied for the duration of this action
var scales: Dictionary = {}
var excluded_targets: Array[StringName] = []
## [ability_name, magnitude_or_null, duration]
var grants: Array = []
var suppresses_counterattack: bool = false
var notes: String = ""


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
func availability(actor: Combatant) -> Refusal:
	if actor.action_spent and resolved_consumes_action(actor):
		return Refusal.ACTION_SPENT
	# At 0 stamina the unit is forced to Rest — «в свой следующий ход
	# принудительно выполняет команду Отдых» — so nothing else is available.
	if actor.stamina <= 0 and not actor.has_flag(&"Неутомимый"):
		return Refusal.EXHAUSTED
	var need: int = resolved_stamina()
	if need > 0 and not actor.has_flag(&"Неутомимый") and actor.stamina < need:
		return Refusal.NO_STAMINA
	if cost_ammo > 0 and actor.ammo < cost_ammo:
		return Refusal.NO_AMMO
	return Refusal.OK


func is_available(actor: Combatant) -> bool:
	return availability(actor) == Refusal.OK


func pay(actor: Combatant) -> void:
	if not actor.has_flag(&"Неутомимый"):
		actor.stamina = maxi(0, actor.stamina - resolved_stamina())
	actor.ammo = maxi(0, actor.ammo - cost_ammo)
	if resolved_consumes_action(actor):
		actor.action_spent = true


## Build from a pack definition dictionary. Actions are CONTENT: which exist and
## what they cost differs between the genesis and new_horizons packs, so this
## must be data-driven rather than a hardcoded catalogue.
## Actions available to the running game.
##
## Loaded from data rather than hardcoded, mirroring the oracle's module-level
## CATALOGUE. A scenario may declare its own entries so a committed scenario file
## is self-contained and both implementations build the same catalogue from the
## same bytes.
static var CATALOGUE: Dictionary = {}


## Merge `entries` (an Array of Dictionaries) into the catalogue.
static func load_catalogue(entries: Array) -> void:
	for d in entries:
		var a := Action.from_dict(d)
		CATALOGUE[a.id] = a


static func from_dict(d: Dictionary) -> Action:
	var a := Action.new()
	a.id = StringName(d.get("id", ""))
	a.name = String(d.get("name", ""))
	a.target = int(d.get("target", Target.SELF))
	a.cost_stamina = int(d.get("cost_stamina", 0))
	a.cost_ammo = int(d.get("cost_ammo", 0))
	a.consumes_action = bool(d.get("consumes_action", true))
	a.attack_surcharge = bool(d.get("attack_surcharge", false))
	a.magnitude = int(d.get("magnitude", 0))
	a.is_attack = bool(d.get("is_attack", false))
	a.damage_scale = float(d.get("damage_scale", 1.0))
	a.suppresses_counterattack = bool(d.get("suppresses_counterattack", false))
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
	return a
