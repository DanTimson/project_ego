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
##   Удар щитом            suppresses it from the action side
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
	SUPPRESSED,
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
	NoCounter.SUPPRESSED: "suppressed by the attacker's action",
}

## Attacker-side abilities that avoid retaliation entirely.
const EVASIVE: Array[StringName] = [&"Ловкость", &"Касание вампира"]

## «Не действует при контратаках» versus «атаки, контратаки и выстрелы»:
## whether an on-hit rider fires during a counter is a property of the rider.
const COUNTER_SUPPRESSED_RIDERS: Array[StringName] = [&"Смертельное касание"]


class Exchange extends RefCounted:
	var attack_damage: int = 0
	var counter_damage: int = 0
	var countered: bool = false
	var counter_first: bool = false
	var reason: int = NoCounter.NONE
	var attacker_died: bool = false
	var defender_died: bool = false
	var traces: Array = []
	var order: Array = []      ## [["attack"|"counter", damage], ...]


## Decidable before any dice are rolled.
static func why_no_counter(defender: Combatant, attacker: Combatant,
		kind: Combatant.AttackKind, action: Variant = null) -> int:
	if kind != Combatant.AttackKind.MELEE:
		return NoCounter.RANGED
	if not defender.alive or defender.life <= 0:
		return NoCounter.DEAD
	if defender.has_flag(&"Не сражается"):
		return NoCounter.CANNOT_FIGHT
	if defender.counter_attack <= 0:
		return NoCounter.NO_STAT
	if defender.stamina <= 0 and not defender.has_flag(&"Неутомимый"):
		return NoCounter.EXHAUSTED
	if defender.resting:
		return NoCounter.RESTING
	for f in EVASIVE:
		if attacker.has_flag(f):
			return NoCounter.EVADED
	if action != null and action.get("suppresses_counterattack") == true:
		return NoCounter.SUPPRESSED
	return NoCounter.NONE


static func will_counter(defender: Combatant, attacker: Combatant,
		kind: Combatant.AttackKind, action: Variant = null) -> bool:
	return why_no_counter(defender, attacker, kind, action) == NoCounter.NONE


## «Это правило не действует, если противник тоже обладает первым ударом.»
## Both having it is not a race — it cancels to the normal order.
static func strikes_first(defender: Combatant, attacker: Combatant) -> bool:
	return defender.has_flag(&"Первый удар") and not attacker.has_flag(&"Первый удар")


## Resolve an attack and any retaliation, in the correct order.
##
## ASSUMPTION (OPEN_QUESTIONS item 18): if a first-strike retaliation kills the
## attacker, the attack does NOT land. «Прежде, чем его ударит противник» says
## the retaliation precedes the blow, and a dead unit swinging seems the less
## likely reading — but the documentation does not settle it, and the difference
## shows only when the counter is lethal.
static func resolve(attacker: Combatant, defender: Combatant, rng: Rng,
		kind: Combatant.AttackKind = Combatant.AttackKind.MELEE,
		action: Variant = null, primary_melee_charge: Variant = null) -> Exchange:
	var ex := Exchange.new()
	ex.reason = why_no_counter(defender, attacker, kind, action)
	ex.countered = ex.reason == NoCounter.NONE
	ex.counter_first = ex.countered and strikes_first(defender, attacker)

	if ex.counter_first:
		_do_counter(ex, attacker, defender, rng)
		if not ex.attacker_died:
			_do_attack(ex, attacker, defender, rng, kind, primary_melee_charge)
	else:
		_do_attack(ex, attacker, defender, rng, kind, primary_melee_charge)
		if ex.countered and defender.alive:
			_do_counter(ex, attacker, defender, rng)
		elif ex.countered:
			ex.countered = false
			ex.reason = NoCounter.DEAD
	return ex


static func _do_attack(ex: Exchange, attacker: Combatant, defender: Combatant,
		rng: Rng, kind: Combatant.AttackKind,
		primary_melee_charge: Variant = null) -> void:
	# Resolve the ordinary strike completely before consuming R3 charge. The
	# combined capped value feeds the exchange accumulator/order before life
	# subtraction. Retaliation has its own charge-free path below.
	var result: Array = Damage.resolve_attack(attacker, defender, kind, rng)
	var ordinary_damage := int(result[0])
	var damage := ordinary_damage
	if kind == Combatant.AttackKind.MELEE and primary_melee_charge != null:
		var charge := maxi(0, int(primary_melee_charge))
		var combined := ordinary_damage + charge
		damage = mini(combined, maxi(0, defender.life))
		var combined_trace := Trace.new("primary melee combined damage")
		combined_trace.base = float(ordinary_damage)
		combined_trace.step("+ command-entry charge", float(ordinary_damage),
			float(combined), "flat post-defence, unrandomized, undefended")
		if damage != combined:
			combined_trace.step("target-life cap", float(combined), float(damage),
				"current target life")
		combined_trace.result = float(damage)
		result[1].append(combined_trace)
	ex.attack_damage = damage
	ex.traces.append_array(result[1])
	ex.order.append(["attack", damage])
	defender.life -= damage
	if defender.life <= 0 and defender.alive:
		defender.alive = false
		ex.defender_died = true


static func _do_counter(ex: Exchange, attacker: Combatant, defender: Combatant,
		rng: Rng) -> void:
	var result: Array = Damage.resolve_attack(
		defender, attacker, Combatant.AttackKind.COUNTER, rng)
	ex.counter_damage = int(result[0])
	ex.traces.append_array(result[1])
	ex.order.append(["counter", ex.counter_damage])
	attacker.life -= ex.counter_damage
	if attacker.life <= 0 and attacker.alive:
		attacker.alive = false
		ex.attacker_died = true


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
