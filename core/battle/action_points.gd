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
	# Recovered effective-speed form (R8):
	#     if stamina < 5 and speed > 1: speed -= 1
	#     if stamina < 3 and speed > 1: speed -= 1
	#     return max(speed, 1)
	# Two guarded decrements rather than one banded penalty. Numerically
	# identical for every reachable input, but this is what the binary does.
	#
	# ONE BEHAVIOURAL CHANGE: the «Неутомимый» exemption is removed. The recovered effective-speed rule
	# has no modifier 0x12 check; the exemption was inferred from "such a unit
	# never loses stamina", which fails when an effect sets stamina directly.
	# Modifier 0x12 suppresses stamina DEDUCTIONS, not the speed penalty.
	var value: int = u.speed
	if u.stamina < 5 and value > 1:
		t.step("stamina %d < 5" % u.stamina, float(value), float(value - 1))
		value -= 1
	if u.stamina < 3 and value > 1:
		t.step("stamina %d < 3" % u.stamina, float(value), float(value - 1))
		value -= 1
	if value < 1:
		t.step("floor", float(value), 1.0, "speed never drops below 1")
		value = 1
	t.result = float(value)
	return [value, t]


# ---------------------------------------------------------------------------
# Round start vs. extra turns
#
# Eleven documented effects grant a unit a SECOND TURN inside the same round:
#
#   single target   Рывок, Всплеск Хаоса (demon), Стрекало (animal),
#                   Руна обновления (mechanism)
#   filtered group  Искажение Хаоса (all friendly demons),
#                   Клич некроманта (all friendly undead EXCEPT слуги Смерти),
#                   Стимул (several kobold slaves, +1 speed until end of turn)
#   with a rider    Слово вождя (5 damage, then a second turn),
#                   Ментальный резонанс (magic boost, then a second turn)
#   self, on kill   Кровавое безумие (melee kill: -2 stamina, act again),
#                   Азарт Охотника (ranged kill: act again)
#
# So refreshing a unit and starting a round are DIFFERENT operations, and both
# are needed. begin_round is the true round boundary; refresh_for_extra_turn
# hands back resources without it.
#
# THE LIMITER MATTERS MOST. Кровавое безумие and Азарт Охотника are both
# «только один раз за ход». If an extra turn reset that counter they would chain
# without bound: kill -> extra action -> kill -> extra action. So once_per_round
# is cleared by begin_round and by NOTHING else.
# ---------------------------------------------------------------------------

## True round boundary. THE ONLY place once-per-round limiters are cleared.
static func begin_round(u: Combatant) -> Trace:
	var t := Trace.new("%s.begin_round" % u.name)
	u.movement_remaining = effective_speed(u)[0]
	u.steps_this_round = 0
	u.action_spent = false
	u.resting = false
	u.once_per_round.clear()
	t.step("refresh", 0.0, float(u.movement_remaining),
		"movement, steps, action, limiters")
	# «в свой следующий ход принудительно выполняет команду Отдых»
	if u.forced_rest:
		rest(u)
		u.forced_rest = false
		u.movement_remaining = 0
		u.action_spent = true
		t.step("forced rest", 0.0, float(u.stamina), "round consumed")
	t.result = float(u.movement_remaining)
	return t


## Hand a unit its movement and action back inside the current round.
##
## `fire_round_start` — whether the grant also triggers "в начале хода" effects.
## Both variants exist among the spells, so it is a parameter rather than a
## decision. When true this also serves a pending forced rest, so such a spell
## can rescue an exhausted unit.
##
## `reset_steps` is retained for callers that explicitly need to clear the
## diagnostic path counter. It defaults false because an extra turn is not a
## round boundary. Genesis charge recomputes from each command's entry coordinates.
##
## Never clears once_per_round, and never clears `resting`: a rest already taken
## is not undone by being handed another turn.
static func refresh_for_extra_turn(u: Combatant, fire_round_start: bool = false,
		reset_steps: bool = false) -> Trace:
	var t := Trace.new("%s.extra_turn" % u.name)
	t.base = float(u.movement_remaining)
	u.movement_remaining = effective_speed(u)[0]
	u.action_spent = false
	if reset_steps:
		t.step("steps reset", float(u.steps_this_round), 0.0)
		u.steps_this_round = 0
	t.step("refresh", t.base, float(u.movement_remaining),
		"with round-start effects" if fire_round_start else "movement and action only")
	if fire_round_start and u.forced_rest:
		rest(u)
		u.forced_rest = false
		u.movement_remaining = 0
		u.action_spent = true
		t.step("forced rest served", 0.0, float(u.stamina), "round-start effects fired")
	t.result = float(u.movement_remaining)
	return t


## For «только один раз за ход» effects. Survives extra turns by design.
static func may_trigger_once(u: Combatant, source: StringName) -> bool:
	return not u.once_per_round.has(source)


static func mark_triggered(u: Combatant, source: StringName) -> void:
	u.once_per_round[source] = true


## Returns [granted: bool, trace: Trace].
static func grant_extra_turn(u: Combatant, source: StringName = &"",
		once_per_round: bool = false, fire_round_start: bool = false,
		reset_steps: bool = false) -> Array:
	if not u.alive:
		return [false, Trace.new("%s.extra_turn refused: dead" % u.name)]
	if once_per_round and not may_trigger_once(u, source):
		var t := Trace.new("%s.extra_turn" % u.name)
		t.step("refused", 0.0, 0.0, "%s already triggered this round" % source)
		return [false, t]
	if once_per_round:
		mark_triggered(u, source)
	return [true, refresh_for_extra_turn(u, fire_round_start, reset_steps)]


## Group grants: Искажение Хаоса (all friendly demons), Клич некроманта (all
## friendly undead EXCEPT слуги Смерти), Стимул (several kobold slaves).
##
## `exclude` covers both the documented content exclusion and the common
## caster-excluded pattern; `subtype` covers the filter. Rider effects — Стимул's
## +1 speed, Слово вождя's 5 damage — are applied by the CALLER. They belong to
## the spell, not to the turn system.
static func grant_extra_turn_to(units: Array, exclude: Array = [],
		subtype: StringName = &"", source: StringName = &"",
		once_per_round: bool = false, fire_round_start: bool = false) -> Array:
	var traces: Array[Trace] = []
	for u in units:
		if exclude.has(u):
			continue
		if subtype != &"" and not u.has_subtype(subtype):
			continue
		var r: Array = grant_extra_turn(u, source, once_per_round, fire_round_start)
		if r[0]:
			traces.append(r[1])
	return traces


static func can_move(u: Combatant, tiles: int = 1) -> Refusal:
	return Refusal.OK if u.movement_remaining >= tiles else Refusal.NO_MOVEMENT


static func _modifier_0x12_suppresses(u: Combatant,
		resolved_effective_modifier: bool = false) -> bool:
	return (resolved_effective_modifier or u.has_modifier_id(0x12)
		or u.has_flag(&"Неутомимый"))


## Move `tiles` steps. `stamina_cost` is the terrain drain the caller has already
## resolved from bf_object — hills and swamp cost 1 unless the unit has the
## matching Знание; flyers pay nothing.
##
## Steps ACCUMULATE as trace-visible path history. A unit pacing back to its
## starting tile still records every step, but neither Genesis charge nor the R8
## attack stamina cost consumes this counter.
static func spend_move(u: Combatant, tiles: int = 1, stamina_cost: int = 0,
		modifier_0x12_effective: bool = false) -> Trace:
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
	if total > 0:
		if _modifier_0x12_suppresses(u, modifier_0x12_effective):
			t.step("modifier 0x12 stamina mutation suppression",
				float(u.stamina), float(u.stamina),
				"movement requested stamina cost %d" % total)
		else:
			var before: int = u.stamina
			u.stamina = maxi(0, u.stamina - total)
			t.step("movement stamina mutation", float(before), float(u.stamina),
				"terrain")
	t.result = float(u.movement_remaining)
	return t


## 2 when live remaining capacity is BELOW effective speed, else 1 (R8).
##
## The recovered ranged executor compares live remaining capacity against
## effective speed, with a STRICT less-than, so
## equality and temporary over-capacity both select 1.
##
## This is NOT `steps_this_round > 0`, which is what this used before. The two
## agree on the common path and diverge whenever capacity is restored: effect
## type 7 can raise `+0x04` back to effective speed, and a non-movement command
## increments it by one, while ordinary selection and reselection do not touch it
## at all. `steps_this_round` remains available as diagnostic movement history.
static func attack_stamina_cost(u: Combatant) -> int:
	return 2 if u.movement_remaining < int(effective_speed(u)[0]) else 1


static func _spend_attack(u: Combatant, ranged_executor: bool,
		modifier_0x12_effective: bool = false) -> Trace:
	var label := "ranged_attack_cost" if ranged_executor else "attack_cost"
	var t := Trace.new("%s.%s" % [u.name, label])
	var speed := int(effective_speed(u)[0])
	var capacity := u.movement_remaining
	var cost: int = 2 if capacity < speed else 1
	t.base = float(u.stamina)
	t.step("live-capacity stamina discriminator", float(capacity), float(cost),
		"effective speed %d; strict capacity < speed is %s; selected base cost %d"
		% [speed, str(capacity < speed), cost])
	if _modifier_0x12_suppresses(u, modifier_0x12_effective):
		t.step("modifier 0x12 stamina mutation suppression", t.base, t.base,
			"requested attack stamina cost %d" % cost)
	else:
		u.stamina = maxi(0, u.stamina - cost)
		t.step("attack stamina mutation", t.base, float(u.stamina),
			"selected base cost %d" % cost)
	u.action_spent = true
	if ranged_executor:
		var before_capacity := u.movement_remaining
		u.movement_remaining = 0
		t.step("ranged activation capacity clear", float(before_capacity), 0.0,
			"ranged executor ends activation")
	if u.stamina <= 0 and not _modifier_0x12_suppresses(
			u, modifier_0x12_effective):
		u.forced_rest = true
		t.step("exhausted", float(u.stamina), float(u.stamina),
			"forced Rest next round")
	t.result = float(u.stamina)
	return t


static func spend_attack(u: Combatant,
		modifier_0x12_effective: bool = false) -> Trace:
	# Existing non-ranged callers retain their established executor boundary.
	return _spend_attack(u, false, modifier_0x12_effective)


static func spend_ranged_attack(u: Combatant,
		modifier_0x12_effective: bool = false) -> Trace:
	return _spend_attack(u, true, modifier_0x12_effective)


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
