class_name Counterattack
extends RefCounted

## Melee retaliation.
##
## Twenty-three abilities in the documentation touch this, and between them they
## pin the rules down further than any single one does:
##
##   Контратака            «сколько повреждений воин наносит атаковавшему его
##                         противнику» — a SEPARATE stat, not a copy of Attack
##   Первый удар           «наносит ответный удар ПРЕЖДЕ, чем его ударит
##                         противник ... не действует, если противник тоже
##                         обладает первым ударом»
##   Ловкость              «атаковать врукопашную, ИЗБЕГАЯ ответных ударов»
##   Не сражается          «не может атаковать и контратаковать»
##   Касание вампира       «не получать контратаки»
##   Смертельное касание   «не действует при контратаках»
##   Парализующее касание  «атаки, контратаки и выстрелы» — so rider suppression
##                         is per-ability, not a blanket rule
##   Жажда крови           a kill by counter is worth HALF the morale
##
## RANGED ATTACKS DO NOT PROVOKE. Every rule above says «врукопашную». A shot is
## answered by nothing, which is most of why archers earn their cost.
##
## FIRST STRIKE IS A REORDERING, NOT AN EXTRA BLOW. It moves the retaliation
## ahead of the attack that caused it, so a defender can kill an attacker before
## the attack lands. Two units that both have it cancel to the normal order.

## Why a counterattack did not happen. Distinct values because the combat log
## should say which, and the AI needs to know whether it can be arranged again.
enum NoCounter {
	NONE,           ## it happened
	DEAD,
	RANGED,
	NO_STAT,
	EXHAUSTED,
	RESTING,
	CANNOT_FIGHT,
	EVADED,
}

const REASON_TEXT: Dictionary = {
	NoCounter.NONE: "counterattacked",
	NoCounter.DEAD: "defender is down",
	NoCounter.RANGED: "ranged attacks are not answered",
	NoCounter.NO_STAT: "no counterattack value",
	NoCounter.EXHAUSTED: "at 0 stamina a unit does not counterattack",
	NoCounter.RESTING: "resting forgoes counterattacks",
	NoCounter.CANNOT_FIGHT: "Не сражается",
	NoCounter.EVADED: "the attacker avoided it",
}

## Attacker-side abilities that avoid retaliation entirely.
const EVASIVE: Array[StringName] = [&"Ловкость", &"Касание вампира"]

## «Не действует при контратаках» versus «атаки, контратаки и выстрелы»:
## whether an on-hit rider fires during a counter is a property of the rider.
const COUNTER_SUPPRESSED_RIDERS: Array[StringName] = [&"Смертельное касание"]

## Scoped by Scenario around one exchange, matching Damage's existing battle
## pipeline/environment bindings. Direct handler tests may leave it invalid.
static var _death_resolver: Callable = Callable()


static func bind_death_resolver(resolver: Callable) -> void:
	_death_resolver = resolver


class Exchange extends RefCounted:
	var attack_damage: int = 0
	var ordinary_attack_damage: int = 0
	var primary_melee_charge: Variant = null
	var counter_damage: int = 0
	var countered: bool = false
	var counter_first: bool = false
	var reason: int = NoCounter.NONE
	var attacker_fatal_event: bool = false
	var defender_fatal_event: bool = false
	## Final post-lifecycle death, deliberately distinct from fatal_event.
	var attacker_died: bool = false
	var defender_died: bool = false
	var traces: Array = []
	var order: Array = []      ## [["attack"|"counter", damage], ...]


## Decidable before any dice are rolled.
static func why_no_counter(defender: Combatant, attacker: Combatant,
		kind: Combatant.AttackKind) -> int:
	if kind != Combatant.AttackKind.MELEE:
		return NoCounter.RANGED
	if not defender.alive or defender.life <= 0:
		return NoCounter.DEAD
	if Damage.has_effective_modifier(defender, 0x26) \
			or defender.has_flag(&"Не сражается"):
		return NoCounter.CANNOT_FIGHT
	if defender.counter_attack <= 0:
		return NoCounter.NO_STAT
	if defender.stamina <= 0:
		return NoCounter.EXHAUSTED
	if defender.resting:
		return NoCounter.RESTING
	for f in EVASIVE:
		if attacker.has_flag(f):
			return NoCounter.EVADED
	return NoCounter.NONE


static func will_counter(defender: Combatant, attacker: Combatant,
		kind: Combatant.AttackKind) -> bool:
	return why_no_counter(defender, attacker, kind) == NoCounter.NONE


## «Это правило не действует, если противник тоже обладает первым ударом.»
## Both having it is not a race — it cancels to the normal order.
static func strikes_first(defender: Combatant, attacker: Combatant) -> bool:
	return defender.has_flag(&"Первый удар") and not attacker.has_flag(&"Первый удар")


## Resolve an attack and any retaliation, in the correct order.
##
## EXP-CI11 distinguishes fatal_event from final post-lifecycle alive state:
## a first-strike survivor still attacks, while a fatal initiating primary
## suppresses ordinary retaliation even if its target survives the lifecycle.
static func resolve(attacker: Combatant, defender: Combatant, rng: Variant,
		kind: Combatant.AttackKind = Combatant.AttackKind.MELEE,
		action: Variant = null, primary_melee_charge: Variant = null) -> Exchange:
	var ex := Exchange.new()
	ex.reason = why_no_counter(defender, attacker, kind)
	ex.countered = ex.reason == NoCounter.NONE
	ex.counter_first = ex.countered and strikes_first(defender, attacker)

	if ex.counter_first:
		_do_counter(ex, attacker, defender, rng)
		## First-strike continuation uses final post-lifecycle alive state.
		if attacker.alive and attacker.life > 0:
			_do_attack(ex, attacker, defender, rng, kind, action, primary_melee_charge)
	else:
		_do_attack(ex, attacker, defender, rng, kind, action, primary_melee_charge)
		## A fatal primary stays on the fatal-event branch even after survival.
		if ex.countered and not ex.defender_fatal_event and defender.alive:
			_do_counter(ex, attacker, defender, rng)
		elif ex.countered:
			ex.countered = false
			ex.reason = NoCounter.DEAD
	return ex


static func _do_attack(ex: Exchange, attacker: Combatant, defender: Combatant,
		rng: Variant, kind: Combatant.AttackKind, action: Variant = null,
		primary_melee_charge: Variant = null) -> void:
	# Resolve the ordinary strike completely before consuming R3 charge. The
	# combined capped value feeds the exchange accumulator/order before life
	# subtraction. Retaliation has its own charge-free path below.
	var scale_numerator := 1
	var scale_denominator := 1
	if action != null and action.get("initiating_attack_scale_numerator") != null:
		scale_numerator = int(action.get("initiating_attack_scale_numerator"))
		scale_denominator = int(action.get("initiating_attack_scale_denominator"))
	var result: Array
	var ranged_channel := 0
	if kind == Combatant.AttackKind.RANGED:
		result = Damage.resolve_ranged_attack(attacker, defender, rng)
		ranged_channel = int(result[2])
	else:
		result = Damage.resolve_attack(
			attacker, defender, kind, rng, false,
			scale_numerator, scale_denominator)
	var ordinary_damage := int(result[0])
	ex.ordinary_attack_damage = ordinary_damage
	var damage := ordinary_damage
	if kind == Combatant.AttackKind.MELEE and primary_melee_charge != null:
		var charge := maxi(0, int(primary_melee_charge))
		ex.primary_melee_charge = charge
		var combined := ordinary_damage + charge
		damage = mini(combined, maxi(0, defender.life))
		var combined_trace := Trace.new("primary melee combined damage")
		combined_trace.base = float(ordinary_damage)
		combined_trace.step("command-entry charge consumption", float(ordinary_damage),
			float(combined), "initiating primary melee; flat, unrandomized, undefended")
		if damage != combined:
			combined_trace.step("target-life cap", float(combined), float(damage),
				"current target life")
		combined_trace.result = float(damage)
		result[1].append(combined_trace)
	ex.attack_damage = damage
	ex.traces.append_array(result[1])
	ex.order.append(["attack", damage])
	var outcome := Damage.apply_received_damage(
		defender, damage,
		ranged_channel if kind == Combatant.AttackKind.RANGED else 0,
		_death_resolver)
	ex.defender_fatal_event = bool(outcome["fatal_event"])
	ex.defender_died = bool(outcome["final_death"])


static func _do_counter(ex: Exchange, attacker: Combatant, defender: Combatant,
		rng: Variant) -> void:
	var result: Array = Damage.resolve_attack(
		defender, attacker, Combatant.AttackKind.COUNTER, rng)
	ex.counter_damage = int(result[0])
	ex.traces.append_array(result[1])
	ex.order.append(["counter", ex.counter_damage])
	var outcome := Damage.apply_received_damage(
		attacker, ex.counter_damage, 0, _death_resolver)
	ex.attacker_fatal_event = bool(outcome["fatal_event"])
	ex.attacker_died = bool(outcome["final_death"])


## «При убийстве противника контратакой или выстрелом воин дополнительно
## получит только половину этого значения.»
static func morale_kill_share(kind: Combatant.AttackKind) -> float:
	return 1.0 if kind == Combatant.AttackKind.MELEE else 0.5


static func rider_fires(ability_name: StringName,
		kind: Combatant.AttackKind) -> bool:
	if kind == Combatant.AttackKind.COUNTER \
			and COUNTER_SUPPRESSED_RIDERS.has(ability_name):
		return false
	return true
