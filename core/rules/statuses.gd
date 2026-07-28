class_name Statuses
extends RefCounted

## Timed effects.
##
## Thirty-six abilities carry duration or stacking language, and between them
## they settle four things that could not be guessed:
##
##   DURATION IS REDUCED BY THE TARGET'S RESIST
##     «Сопротивление противника снижает время действия» — Сглаз, Окаменение,
##     Насылает гниение. The arithmetic is the documented spell formula.
##
##   STACKING IS PER-EFFECT, NOT GLOBAL
##     «кумулятивному воздействию» (Всплеск Тьмы) stacks, while «Способности
##     нескольких Оруженосцев НЕ СКЛАДЫВАЮТСЯ между собой, вместо этого
##     выбирается» the maximum. Both idioms appear.
##
##   DURATION IS REDUCIBLE FROM OUTSIDE
##     Разрушение заклинаний shortens enemy enchantments; Исцеление and
##     Излечение shorten hostile ones; Опытный лекарь shortens poison and
##     bleeding specifically.
##
##   SOME EFFECTS DECAY AGAINST THE TARGET'S OWN STATS
##     Паутина: «каждые 10 единиц атаки ... снижает длительность на 1».
##
## Effects carry Modifiers, so a status changing a number does it through the
## same pipeline as everything else. Nothing here recomputes damage.

enum Stacking {
	CUMULATIVE,   ## a separate instance each time — Всплеск Тьмы
	MAXIMUM,      ## only the strongest applies — Оруженосец, Мощь племени
	REFRESH,      ## reapplying resets the duration
	UNIQUE,       ## ignored entirely if already present
}

const PERMANENT := -1
const UNTIL_NEXT_TURN := 0   ## expires at the owner's next round start


class Effect extends RefCounted:
	var id: StringName = &""
	var name: String = ""
	var source: String = ""
	var duration: int = PERMANENT
	var power: int = 0
	## Modifiers contributed while active — they go through the normal Pipeline.
	var modifiers: Array = []
	## Per-round deltas applied at round start: {"life": -4, "stamina": -2}
	var tick: Dictionary = {}
	var stacking: Stacking = Stacking.REFRESH
	## «не может действовать» — Окаменение, Паутина
	var prevents_action: bool = false
	## What Разрушение заклинаний and the healing spells shorten
	var hostile: bool = false
	## For targeted removal: Опытный лекарь shortens poison and bleeding only
	var tags: Array[StringName] = []
	## ["attack_group", 10] for Паутина, or empty
	var decay_per: Array = []

	func describe() -> String:
		var label: String = name if name != "" else String(id)
		return label if duration == PERMANENT else "%s (%d)" % [label, duration]


## «Сила и длительность заклинаний», the documented form. DurationMod and
## ResistDuration are percentages PER POINT: 100 means one round per point of
## concentration, 200 two, 50 one per two. Thaumaturgy subtracts from the
## target's resist first.
##
## The page's worked example: conc 3, thaum 2, resist 7 -> effective 5;
## base 6 with both mods at 100 -> 6 + 3 - 5 = 4.
static func effective_duration(base: int, concentration: int = 0,
		duration_mod: int = 0, target_resist: int = 0,
		resist_duration: int = 0, thaumaturgy: int = 0) -> int:
	var effective_resist: int = maxi(0, target_resist - thaumaturgy)
	var gain: int = concentration * duration_mod / 100
	var loss: int = effective_resist * resist_duration / 100
	return maxi(0, base + gain - loss)


## Паутина's rule: the target's own numbers erode the effect. Per-effect rather
## than general — nothing else in the documentation works this way.
static func decay_from_stats(effect: Effect, unit: Combatant) -> int:
	if effect.decay_per.is_empty():
		return 0
	var stat_name := String(effect.decay_per[0])
	var per := int(effect.decay_per[1])
	if per == 0:
		return 0
	var value: int = 0
	if stat_name == "attack_group":
		# «атаки, контратаки или магической дистанционной атаки» — the BEST of
		# the three, not their sum.
		value = maxi(unit.attack, maxi(unit.counter_attack, unit.ranged_attack))
	else:
		value = int(unit.get(stat_name))
	return value / per


static func find(unit: Combatant, effect_id: StringName) -> Array:
	var out: Array = []
	for e in unit.statuses:
		if e.id == effect_id:
			out.append(e)
	return out


## Add an effect, honouring its stacking policy.
static func apply(unit: Combatant, effect: Effect) -> Trace:
	var t := Trace.new("%s <- %s" % [unit.name, effect.describe()])
	var existing := find(unit, effect.id)

	if existing.is_empty():
		unit.statuses.append(effect)
		t.step("applied", 0.0, float(effect.duration), str(effect.stacking))
		return t

	match effect.stacking:
		Stacking.CUMULATIVE:
			unit.statuses.append(effect)
			t.step("stacked", float(existing.size()),
				float(existing.size() + 1), "cumulative")
		Stacking.MAXIMUM:
			var strongest: Effect = existing[0]
			for e in existing:
				if e.power > strongest.power:
					strongest = e
			if effect.power > strongest.power:
				unit.statuses.erase(strongest)
				unit.statuses.append(effect)
				t.step("replaced", float(strongest.power), float(effect.power),
					"stronger")
			else:
				t.step("ignored", float(strongest.power), float(strongest.power),
					"«не складываются, вместо этого выбирается» the maximum")
		Stacking.REFRESH:
			var current: Effect = existing[0]
			var before := current.duration
			current.duration = maxi(current.duration, effect.duration)
			current.power = maxi(current.power, effect.power)
			t.step("refreshed", float(before), float(current.duration))
		_:
			t.step("ignored", 1.0, 1.0, "already present")
	return t


static func remove(unit: Combatant, effect_id: StringName) -> int:
	var before: int = unit.statuses.size()
	var kept: Array = []
	for e in unit.statuses:
		if e.id != effect_id:
			kept.append(e)
	unit.statuses = kept
	return before - unit.statuses.size()


## Разрушение заклинаний, Исцеление, Излечение, Опытный лекарь.
## `tags` narrows it: Опытный лекарь shortens poison and bleeding, not
## every hostile effect.
static func reduce_duration(unit: Combatant, amount: int,
		hostile_only: bool = true, tags: Array = []) -> Trace:
	var t := Trace.new("%s: shorten effects" % unit.name)
	var shortened: int = 0
	for e in unit.statuses.duplicate():
		if hostile_only and not e.hostile:
			continue
		if not tags.is_empty():
			var matched := false
			for tag in tags:
				if e.tags.has(StringName(String(tag))):
					matched = true
			if not matched:
				continue
		if e.duration == PERMANENT:
			continue
		var before := e.duration
		e.duration = maxi(0, e.duration - amount)
		t.step(e.name if e.name != "" else String(e.id),
			float(before), float(e.duration))
		shortened += 1
		if e.duration == 0:
			unit.statuses.erase(e)
			t.step(e.name if e.name != "" else String(e.id), 0.0, 0.0, "expired")
	if shortened == 0:
		t.step("nothing to shorten", 0.0, 0.0)
	return t


## Apply per-round deltas, then age every effect by one round.
##
## ORDER MATTERS AND IS NOT ARBITRARY: an effect that deals damage on the round
## it expires should still deal it. Ageing first would silently drop the last
## tick of every damage-over-time effect, which looks like a balance problem
## rather than a bug.
static func tick_round(unit: Combatant) -> Trace:
	var t := Trace.new("%s: statuses" % unit.name)

	for e in unit.statuses.duplicate():
		for stat in e.tick:
			var key := String(stat)
			var before := int(unit.get(key))
			var after := before + int(e.tick[stat])
			match key:
				"life":
					after = mini(after, unit.life_base)
				"stamina":
					after = maxi(0, mini(after, unit.stamina_base))
				"morale":
					after = maxi(0, mini(after, unit.morale_base))
			unit.set(key, after)
			t.step("%s: %s" % [e.name if e.name != "" else String(e.id), key],
				float(before), float(after))
		if unit.life <= 0 and unit.alive:
			unit.alive = false
			t.step("died", 0.0, 0.0,
				"killed by %s" % (e.name if e.name != "" else String(e.id)))

	for e in unit.statuses.duplicate():
		if e.duration == PERMANENT:
			continue
		var before := e.duration
		e.duration -= 1 + decay_from_stats(e, unit)
		if e.duration != before - 1:
			t.step("%s decays faster" % (e.name if e.name != "" else String(e.id)),
				float(before), float(maxi(0, e.duration)),
				"eroded by the target's own stats")
		if e.duration <= 0:
			unit.statuses.erase(e)
			t.step(e.name if e.name != "" else String(e.id),
				float(before), 0.0, "expired")
	return t


## Every Modifier contributed by active effects, for the Pipeline.
static func active_modifiers(unit: Combatant) -> Array:
	var out: Array = []
	for e in unit.statuses:
		out.append_array(e.modifiers)
	return out


## «не может действовать» — Окаменение, Паутина. Returns [can_act, reason].
static func can_act(unit: Combatant) -> Array:
	for e in unit.statuses:
		if e.prevents_action:
			return [false, e.name if e.name != "" else String(e.id)]
	return [true, ""]
