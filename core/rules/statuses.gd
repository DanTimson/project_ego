class_name Statuses
extends RefCounted

## Stable status policy and explicit manipulation.
##
## Stacking is per effect, duration resistance uses the documented spell
## arithmetic, and status-owned modifiers remain ordinary later providers.
## No round/selection/activation hook advances duration here.

const PERMANENT := Status.PERMANENT


## «Сила и длительность заклинаний», the documented form. DurationMod and
## ResistDuration are percentages per point. A zero result means the application
## is resisted/rejected; it is not an UNTIL_NEXT_TURN lifecycle sentinel.
static func effective_duration(base: int, concentration: int = 0,
		duration_mod: int = 0, target_resist: int = 0,
		resist_duration: int = 0, thaumaturgy: int = 0) -> int:
	var effective_resist: int = maxi(0, target_resist - thaumaturgy)
	var gain: int = concentration * duration_mod / 100
	var loss: int = effective_resist * resist_duration / 100
	return maxi(0, base + gain - loss)


static func find(unit: Combatant, effect_id: StringName) -> Array[Status]:
	var out: Array[Status] = []
	for effect in unit.statuses:
		if effect.id == effect_id:
			out.append(effect)
	return out


## Add one runtime instance according to its per-effect stacking policy.
## A duration of zero is the stable fully-resisted result and leaves state intact.
static func apply(unit: Combatant, effect: Status) -> Trace:
	var trace := Trace.new("%s <- %s" % [unit.name, effect.describe()])
	if effect.duration == 0:
		trace.step("resisted", 0.0, 0.0, "effective duration is zero")
		return trace

	var existing := find(unit, effect.id)
	if existing.is_empty():
		unit.statuses.append(effect)
		trace.step("applied", 0.0, float(effect.duration), str(effect.stacking))
		return trace

	match effect.stacking:
		Status.Stacking.CUMULATIVE:
			unit.statuses.append(effect)
			trace.step("stacked", float(existing.size()),
				float(existing.size() + 1), "cumulative")
		Status.Stacking.MAXIMUM:
			var strongest: Status = existing[0]
			for current in existing:
				if current.power > strongest.power:
					strongest = current
			if effect.power > strongest.power:
				unit.statuses.erase(strongest)
				unit.statuses.append(effect)
				trace.step("replaced", float(strongest.power), float(effect.power),
					"stronger")
			else:
				trace.step("ignored", float(strongest.power), float(strongest.power),
					"maximum already active")
		Status.Stacking.REFRESH:
			var current: Status = existing[0]
			var before := current.duration
			current.duration = maxi(current.duration, effect.duration)
			current.power = maxi(current.power, effect.power)
			trace.step("refreshed", float(before), float(current.duration))
		_:
			trace.step("ignored", 1.0, 1.0, "already present")
	return trace


## Remove every instance sharing the established effect identity/group.
static func remove_on_damage(unit: Combatant) -> Array[Status]:
	## Explicit damage-boundary removal; no duration clock is involved.
	var removed: Array[Status] = []
	var kept: Array[Status] = []
	for effect in unit.statuses:
		if effect.remove_on_damage:
			removed.append(effect)
		else:
			kept.append(effect)
	unit.statuses = kept
	return removed


static func remove(unit: Combatant, effect_id: StringName) -> int:
	var before: int = unit.statuses.size()
	var kept: Array[Status] = []
	for effect in unit.statuses:
		if effect.id != effect_id:
			kept.append(effect)
	unit.statuses = kept
	return before - unit.statuses.size()


## Explicit duration manipulation used by shortening/cleanup consumers. This is
## caller-driven and deliberately has no relationship to a battle-time clock.
static func reduce_duration(unit: Combatant, amount: int,
		hostile_only: bool = true, tags: Array = []) -> Trace:
	var trace := Trace.new("%s: shorten effects" % unit.name)
	var shortened: int = 0
	var reduction := maxi(0, amount)
	for effect in unit.statuses.duplicate():
		if hostile_only and not effect.hostile:
			continue
		if not tags.is_empty():
			var matched := false
			for tag in tags:
				if effect.tags.has(StringName(String(tag))):
					matched = true
			if not matched:
				continue
		if effect.duration == PERMANENT:
			continue
		var before: int = effect.duration
		effect.duration = maxi(0, effect.duration - reduction)
		trace.step(effect.name if effect.name != "" else String(effect.id),
			float(before), float(effect.duration))
		shortened += 1
		if effect.duration == 0:
			unit.statuses.erase(effect)
			trace.step(effect.name if effect.name != "" else String(effect.id),
				0.0, 0.0, "removed")
	if shortened == 0:
		trace.step("nothing to shorten", 0.0, 0.0)
	return trace


## Pre-existing explicit reference-model lifecycle step. It is intentionally not
## called by Scenario, RoundLoop, selection, activation or extra-turn code. Its
## event boundary and tick/expiry ordering are provisional pending R13; stable
## CX-010 coverage must use explicit reduce_duration/remove instead.
static func tick_round(unit: Combatant) -> Trace:
	var trace := Trace.new("%s: statuses" % unit.name)
	for effect in unit.statuses.duplicate():
		for stat in effect.tick:
			var key := String(stat)
			var before := int(unit.get(key))
			var after := before + int(effect.tick[stat])
			match key:
				"life":
					after = mini(after, unit.life_base)
				"stamina":
					after = maxi(0, mini(after, unit.stamina_base))
				"morale":
					after = maxi(0, mini(after, unit.morale_base))
			unit.set(key, after)
			trace.step("%s: %s" % [effect.name if effect.name != "" else String(effect.id), key],
				float(before), float(after))
		if unit.life <= 0 and unit.alive:
			unit.alive = false
			trace.step("died", 0.0, 0.0,
				"killed by %s" % (effect.name if effect.name != "" else String(effect.id)))

	for effect in unit.statuses.duplicate():
		if effect.duration == PERMANENT:
			continue
		var before: int = effect.duration
		effect.duration -= 1 + decay_from_stats(effect, unit)
		if effect.duration != before - 1:
			trace.step("%s decays faster" % (effect.name if effect.name != "" else String(effect.id)),
				float(before), float(maxi(0, effect.duration)),
				"eroded by the target's own stats")
		if effect.duration <= 0:
			unit.statuses.erase(effect)
			trace.step(effect.name if effect.name != "" else String(effect.id),
				float(before), 0.0, "expired in provisional explicit step")
	return trace


static func decay_from_stats(effect: Status, unit: Combatant) -> int:
	if effect.decay_per.is_empty():
		return 0
	var stat_name := String(effect.decay_per[0])
	var per := int(effect.decay_per[1])
	if per == 0:
		return 0
	var value: int
	if stat_name == "attack_group":
		value = maxi(unit.attack, maxi(unit.counter_attack, unit.ranged_attack))
	else:
		value = int(unit.get(stat_name))
	return value / per


static func describe_all(unit: Combatant) -> String:
	var descriptions: Array[String] = []
	for status in unit.statuses:
		descriptions.append(status.describe())
	return ", ".join(descriptions)


static func serialize(unit: Combatant) -> Array:
	var out: Array = []
	for status in unit.statuses:
		out.append(status.to_dict())
	return out


static func active_modifiers(unit: Combatant) -> Array[Modifier]:
	var out: Array[Modifier] = []
	for effect in unit.statuses:
		out.append_array(effect.modifiers)
	return out


## «не может действовать» — existing stable query, not an action executor.
static func can_act(unit: Combatant) -> Array:
	for effect in unit.statuses:
		if effect.prevents_action:
			return [false, effect.name if effect.name != "" else String(effect.id)]
	return [true, ""]
