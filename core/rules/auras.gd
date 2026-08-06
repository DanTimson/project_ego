# core/rules/auras.gd
class_name Auras
extends RefCounted

## Continuous area effects.
##
## SCOPING THIS RIGHT MATTERED MORE THAN BUILDING IT. Sixty-six abilities use
## radius or area language, which looks like a large aura system. It is not:
## 264 of them are `Заклятье "X"` spells applying an effect once when cast,
## 5 are ranged attacks that spread damage around their target, and only
## **10 are persistent auras**. Those three mechanisms share the word "radius"
## and nothing else, so one "area effects" module would have fitted none of them.
## Spell AoE belongs to casting; attack spread belongs to the attack path; this
## file is the ten.
##
## AURAS ARE DERIVED, NEVER APPLIED. An aura depends on where units stand and on
## its source still being alive, both of which change constantly. Applying one as
## a status on entry would need removal on every move, death and expiry — the
## bookkeeping that flags avoided by deriving. So modifiers_for() recomputes from
## the battlefield each time, exactly as Combatant.has_flag walks its sources.
##
## WHAT THE TEN ABILITIES DECLARE THEMSELVES:
##
##   scope     «все союзники НА ПОЛЕ БОЯ» (Вдохновляющее присутствие, Гнетущее
##             присутствие) versus «ВОКРУГ воина» / «РЯДОМ с воином» (Аура
##             доблести, жизни, смерти, бодрости, увядания). Battlefield-wide and
##             adjacent-only, with no radii between
##   stacking  «эффекты всех лидеров СКЛАДЫВАЮТСЯ» versus «действует только САМАЯ
##             СИЛЬНАЯ аура» — stated per-ability, the same split status effects showed
##   side      Аура жизни helps allies; Аура увядания drains enemies; but Аура
##             смерти drains ALL «живые войска» regardless of side
##   subtypes  Аура жизни reaches «смертные, демоны и герои», not undead.
##             Аура смерти spares «Привратников Смерти»

enum Scope {
	ADJACENT,     ## «вокруг воина» / «рядом с воином»
	BATTLEFIELD,  ## «все союзники на поле боя»
	SELF,
}

enum Side { ALLY, ENEMY, ALL }

enum Stacking {
	CUMULATIVE,   ## «эффекты всех лидеров складываются»
	MAXIMUM,      ## «действует только самая сильная аура»
}


class Aura extends RefCounted:
	var id: StringName = &""
	var name: String = ""
	var scope: Auras.Scope = Auras.Scope.ADJACENT
	var affects: Auras.Side = Auras.Side.ALLY
	var stacking: Auras.Stacking = Auras.Stacking.MAXIMUM
	var power: int = 0
	## Modifiers granted to each affected unit.
	var modifiers: Array = []
	## Per-round deltas: {"life": 2} for Аура жизни, {"stamina": -1} for увядания.
	var tick: Dictionary = {}
	## Only these subtypes are affected, if given.
	var only_subtypes: Array[StringName] = []
	## These subtypes are spared even if otherwise eligible.
	var except_subtypes: Array[StringName] = []
	## The unit projecting it. A dead source projects nothing.
	var source: Combatant = null

	func reaches(target: Combatant, source_hex: Vector2i, target_hex: Vector2i,
			field: Battlefield) -> bool:
		if source != null and not source.alive:
			return false
		if target == source and scope != Auras.Scope.SELF:
			# «все дружественные воины ВОКРУГ» — the projector is not in its own
			# adjacency. Whether it benefits from its own battlefield-wide aura is
			# not stated; excluded for consistency. OPEN_QUESTIONS item 19.
			return false
		if not only_subtypes.is_empty():
			var matched := false
			for s in only_subtypes:
				if target.has_subtype(s):
					matched = true
			if not matched:
				return false
		for s in except_subtypes:
			if target.has_subtype(s):
				return false
		if scope == Auras.Scope.BATTLEFIELD:
			return true
		if scope == Auras.Scope.SELF:
			return target == source
		if field == null or not field.contains(source_hex) \
				or not field.contains(target_hex):
			return false
		return Battlefield.distance(source_hex, target_hex) == 1


static func _side_matches(aura: Aura, source_side: Variant,
		target_side: Variant) -> bool:
	if aura.affects == Auras.Side.ALL:
		return true
	var same: bool = source_side != null and source_side == target_side
	return same if aura.affects == Auras.Side.ALLY else not same


## Every aura reaching `unit` right now.
##
## `auras_by_source` maps a projecting unit to its auras; `side_of` is a Callable
## answering which side a unit belongs to. Both are passed in so this module needs
## no knowledge of BattleState.
static func collect(unit: Combatant, auras_by_source: Dictionary,
		field: Battlefield, side_of: Callable) -> Array:
	var target_hex: Vector2i = field.find_unit(unit) if field != null \
		else Vector2i(1 << 30, 1 << 30)
	var out: Array = []
	for source in auras_by_source:
		var source_hex: Vector2i = field.find_unit(source) if field != null \
			else Vector2i(1 << 30, 1 << 30)
		for aura in auras_by_source[source]:
			if aura.source == null:
				aura.source = source
			if not _side_matches(aura, side_of.call(source), side_of.call(unit)):
				continue
			if aura.reaches(unit, source_hex, target_hex, field):
				out.append(aura)
	return out


## «действует только самая сильная аура» versus «складываются».
##
## Grouped by aura id, because the rule is a property of the ABILITY: two
## Аура доблести sources give the stronger only, while two Вдохновляющее
## присутствие sources add up.
static func _resolve_stacking(list: Array) -> Array:
	var by_id: Dictionary = {}
	for a in list:
		if not by_id.has(a.id):
			by_id[a.id] = []
		by_id[a.id].append(a)
	var out: Array = []
	for key in by_id:
		var group: Array = by_id[key]
		if group[0].stacking == Auras.Stacking.CUMULATIVE:
			out.append_array(group)
		else:
			var strongest: Aura = group[0]
			for a in group:
				if a.power > strongest.power:
					strongest = a
			out.append(strongest)
	return out


static func active_for(unit: Combatant, auras_by_source: Dictionary,
		field: Battlefield, side_of: Callable) -> Array:
	return _resolve_stacking(collect(unit, auras_by_source, field, side_of))


## Modifiers to hand the Pipeline. Recomputed on every call by design.
static func modifiers_for(unit: Combatant, auras_by_source: Dictionary,
		field: Battlefield, side_of: Callable) -> Array:
	var out: Array = []
	for aura in active_for(unit, auras_by_source, field, side_of):
		out.append_array(aura.modifiers)
	return out


## Per-round deltas from every aura reaching this unit.
##
## Аура жизни and Аура смерти can both reach the same unit — one restoring and
## one draining — so the deltas are SUMMED rather than resolved by precedence.
## Nothing in the documentation suggests one wins.
## Returns [totals: Dictionary, trace: Trace].
static func tick_for(unit: Combatant, auras_by_source: Dictionary,
		field: Battlefield, side_of: Callable) -> Array:
	var t := Trace.new("%s: auras" % unit.name)
	var totals: Dictionary = {}
	for aura in active_for(unit, auras_by_source, field, side_of):
		for stat in aura.tick:
			var before: int = int(totals.get(stat, 0))
			totals[stat] = before + int(aura.tick[stat])
			t.step("%s: %s" % [aura.name if aura.name != "" else String(aura.id),
				String(stat)], float(before), float(totals[stat]))
	var sum := 0
	for stat in totals:
		sum += int(totals[stat])
	t.result = float(sum)
	return [totals, t]


## Apply summed aura deltas, respecting the unit's caps.
static func apply_tick(unit: Combatant, totals: Dictionary) -> Trace:
	var t := Trace.new("%s: aura tick" % unit.name)
	var keys: Array = totals.keys()
	keys.sort()
	for stat in keys:
		var delta := int(totals[stat])
		if delta == 0:
			continue
		var key := String(stat)
		var before := int(unit.get(key))
		var after := before + delta
		match key:
			"life":
				after = mini(after, unit.life_base)
			"stamina":
				after = maxi(0, mini(after, unit.stamina_base))
			"morale":
				after = maxi(0, mini(after, unit.morale_base))
		unit.set(key, after)
		t.step(key, float(before), float(after))
	if unit.life <= 0 and unit.alive:
		unit.alive = false
		t.step("died", 0.0, 0.0, "killed by an aura")
	return t
