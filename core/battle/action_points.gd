class_name ActionPoints
extends RefCounted

## Action points and per-round unit state.
##
## Activation is FREE and RE-ENTRANT: within its side's phase the player or AI
## picks any unit with resources left, spends some, and may yield and return to
## the same unit later in the same round. There is no queue and no per-unit turn
## boundary.
##
## Consequence, and the reason every reset below happens in begin_round() and
## nowhere else: anything reset per activation is farmable. Yield and reselect
## to collect a start-of-turn bonus twice, or to launder away the "moved this
## round" attack penalty.

enum Refusal { OK, NO_MOVEMENT, ACTION_SPENT, EXHAUSTED, NOT_YOUR_PHASE }


## Speed after the documented stamina penalty: -1 at stamina 3-4, -2 at 2 or
## below. Floors at 1. Returns [value: int, trace: Trace].
static func effective_speed(u: Combatant) -> Array:
	var t := Trace.new("%s.speed" % u.name)
	t.base = float(u.speed)
	var value: int = u.speed
	if not u.has_flag(&"Неутомимый") and u.stamina <= 4:
		var penalty: int = -1 if u.stamina >= 3 else -2
		t.step("stamina %d" % u.stamina, float(value), float(value + penalty))
		value += penalty
	if value < 1:
		t.step("floor", float(value), 1.0, "speed never drops below 1")
		value = 1
	t.result = float(value)
	return [value, t]


## Reset per-round state. THE ONLY place these are cleared.
static func begin_round(u: Combatant) -> void:
	u.movement_remaining = effective_speed(u)[0]
	u.steps_this_round = 0
	u.action_spent = false
	u.resting = false
	# «в свой следующий ход принудительно выполняет команду Отдых»
	if u.forced_rest:
		rest(u)
		u.forced_rest = false
		u.movement_remaining = 0
		u.action_spent = true


static func can_move(u: Combatant, tiles: int = 1) -> Refusal:
	return Refusal.OK if u.movement_remaining >= tiles else Refusal.NO_MOVEMENT


## Move `tiles` steps. `stamina_cost` is the terrain drain the caller has already
## resolved from bf_object — hills and swamp cost 1 unless the unit has the
## matching Знание; flyers pay nothing.
##
## Steps ACCUMULATE as path length. A unit pacing back to its starting tile has
## still moved, for both charge distance and the attack stamina discriminator.
static func spend_move(u: Combatant, tiles: int = 1, stamina_cost: int = 0) -> Trace:
	var t := Trace.new("%s.move" % u.name)
	t.base = float(u.movement_remaining)
	u.movement_remaining -= tiles
	t.step("-%d tiles" % tiles, t.base, float(u.movement_remaining))

	var before_steps: int = u.steps_this_round
	u.steps_this_round += tiles
	t.step("steps_this_round", float(before_steps), float(u.steps_this_round),
		"cumulative path length")

	var extra: int = tiles if int(effective_speed(u)[0]) <= 0 else 0
	var total: int = stamina_cost + extra
	if total > 0 and not u.has_flag(&"Неутомимый"):
		var before: int = u.stamina
		u.stamina = maxi(0, u.stamina - total)
		t.step("stamina", float(before), float(u.stamina), "terrain")
	t.result = float(u.movement_remaining)
	return t


## -2 if the unit moved at any point this round, -1 otherwise. The test is
## `steps_this_round > 0`, NOT a position comparison.
static func attack_stamina_cost(u: Combatant) -> int:
	return 2 if u.moved_this_round() else 1


static func spend_attack(u: Combatant) -> Trace:
	var t := Trace.new("%s.attack_cost" % u.name)
	var cost: int = attack_stamina_cost(u)
	t.base = float(u.stamina)
	if not u.has_flag(&"Неутомимый"):
		u.stamina = maxi(0, u.stamina - cost)
		t.step("-%d stamina" % cost, t.base, float(u.stamina),
			"moved this round" if u.moved_this_round() else "attacked in place")
	u.action_spent = true
	if u.stamina <= 0 and not u.has_flag(&"Неутомимый"):
		u.forced_rest = true
		t.step("exhausted", float(u.stamina), float(u.stamina), "forced Rest next round")
	t.result = float(u.stamina)
	return t


## Rest or skip: +(2 + Восстановление сил), capped at base. Under Зуд the
## recovery bonus is 0 regardless of its value. Resting forgoes counterattacks.
static func rest(u: Combatant) -> Trace:
	var t := Trace.new("%s.rest" % u.name)
	t.base = float(u.stamina)
	var gain: int = 2
	var note: String = "2 + %d recovery" % u.stamina_recovery
	if u.has_flag(&"Зуд"):
		note = "Зуд suppresses the recovery bonus"
	else:
		gain += u.stamina_recovery
	u.stamina = mini(u.stamina_base, u.stamina + gain)
	t.step("+%d" % gain, t.base, float(u.stamina), note)
	u.resting = true
	u.action_spent = true
	u.movement_remaining = 0
	t.result = float(u.stamina)
	return t


## Can this unit still do anything at all this round?
static func has_resources(u: Combatant) -> bool:
	if not u.alive:
		return false
	return u.movement_remaining > 0 or not u.action_spent
