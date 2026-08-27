class_name Roster
extends RefCounted

## Turn a unit.var record into a live Combatant.
##
## This closes the last link in the chain. Everything before it was engine
## machinery with hand-written test units; this is where the unit corpus becomes
## something the battle loop can fight with.
##
## THE RESOLUTION CHAIN, and every hop can fail independently:
##
##   unit.var "Abilityes"  ->  unit_upg INDEX          (a curried modifier)
##   unit_upg "Upg Type"   ->  ability_num Number      (the opcode)
##   unit_upg "Quantity"   ->  the modifier's power    (the magnitude)
##   bindings[opcode]      ->  handler name + params   (per content pack)
##   registry[handler]     ->  the engine function
##
## Recall the trap from the format work: unit.var's `Abilityes` block references
## unit_upg by INDEX, while item/spell/medal `Effects` reference ability_num by
## NUMBER. Both are dense integer spaces, so resolving against the wrong table
## succeeds about 97% of the time and returns silent nonsense.
##
## WHAT IT REFUSES TO DO. A unit whose abilities are unbound still builds, with
## those abilities recorded as unresolved rather than dropped. Silently building
## a Мечник without his Парирование would produce a unit that fights wrong and
## looks fine.

## unit.var column -> Combatant property. Only combat-relevant columns; the
## economic (GoldPrice) and presentation (SoundHit, Missile) ones are
## deliberately not carried into the battle model.
const STAT_COLUMNS: Dictionary = {
	"Life": "life",
	"Attack": "attack",
	"CounterAttack": "counter_attack",
	"Defence": "defence",
	"RangedDefence": "ranged_defence",
	"Resist": "resist",
	"Speed": "speed",
	"RangedAttack": "ranged_attack",
	"ShootingRange": "shooting_range",
	"Ammo": "ammo",
	"Stamina": "stamina",
	"Morale": "morale",
}


class Unresolved extends RefCounted:
	var upgrade_index: int = 0
	var upgrade_name: String = ""
	var opcode: int = -1
	var ability_name: String = ""
	var reason: String = ""

	func _to_string() -> String:
		var head := "upg/%d %s" % [upgrade_index,
			upgrade_name if upgrade_name != "" else "?"]
		if opcode >= 0:
			head += " -> opcode %d %s" % [opcode, ability_name]
		return "%s: %s" % [head, reason]


class Built extends RefCounted:
	var unit: Combatant
	var resolved: Array = []      ## [[opcode, name], ...]
	var unresolved: Array = []    ## [Unresolved, ...]
	var action_grants: Array = [] ## raw source grants for Scenario composition

	func complete() -> bool:
		return unresolved.is_empty()

	func summary() -> String:
		return "%s: %d abilities resolved, %d unresolved" % [
			unit.name, resolved.size(), unresolved.size()]


var db: ContentDb
var units: Dictionary = {}
var upgrades: Dictionary = {}
var abilities: Dictionary = {}
var by_number: Dictionary = {}


func _init(p_db: ContentDb) -> void:
	db = p_db
	units = db.pack.tables.get("unit", {})
	upgrades = db.pack.tables.get("unit_upg", {})
	abilities = db.pack.tables.get("ability_num", {})
	# ability_num is indexed by RECORD, but bindings are keyed by the `Number`
	# column — the same distinction that makes the two-namespace trap possible.
	for key in abilities:
		var rec: Dictionary = abilities[key]
		if rec.get("Number") != null:
			by_number[int(rec["Number"])] = rec


## Canonical unit ids, sorted. This is the addressing mode callers should use.
func ids() -> Array:
	var out: Array = []
	for key in units:
		out.append(ContentId.make(db.pack.id, "unit", int(key)))
	out.sort()
	return out


## Record for a canonical id.
func by_id(content_id: String) -> Variant:
	var cid := ContentId.parse(content_id)
	if cid == null or cid.pack != db.pack.id or cid.kind != "unit":
		return null
	return units.get(cid.number)


## Transitional pack-scoped name lookup. Prefer canonical ids.
##
## Returns null when the name is AMBIGUOUS rather than returning the first
## match: New Horizons uses 11 names for more than one record, and silently
## picking one is how a wrong unit reaches the battlefield looking correct.
## `ambiguous_names()` lists them.
func find(unit_name: String) -> Variant:
	var hits: Array = []
	for key in units:
		if String((units[key] as Dictionary).get("Name", "")) == unit_name:
			hits.append(units[key])
	if hits.size() == 1:
		return hits[0]
	if hits.size() > 1:
		push_error("ambiguous unit name '%s': %d records in pack '%s' — use a canonical id"
			% [unit_name, hits.size(), db.pack.id])
	return null


## Canonical id for a display name, or "" when absent or ambiguous.
func id_for_name(unit_name: String) -> String:
	var found: Array = []
	for key in units:
		if String((units[key] as Dictionary).get("Name", "")) == unit_name:
			found.append(int(key))
	if found.size() == 1:
		return ContentId.make(db.pack.id, "unit", found[0])
	return ""


## Display names used by more than one record in this pack.
func ambiguous_names() -> Array:
	var counts: Dictionary = {}
	for key in units:
		var n := String((units[key] as Dictionary).get("Name", ""))
		if n != "" and n != "Пусто":
			counts[n] = int(counts.get(n, 0)) + 1
	var out: Array = []
	for n in counts:
		if int(counts[n]) > 1:
			out.append(n)
	out.sort()
	return out


func names() -> Array:
	var out: Array = []
	for key in units:
		var n := String((units[key] as Dictionary).get("Name", ""))
		if n != "" and n != "Пусто":
			out.append(n)
	out.sort()
	return out


## Build by canonical id or, transitionally, by display name.
func build(reference: String) -> Built:
	var record: Variant = by_id(reference) if ContentId.is_canonical(reference) \
		else find(reference)
	if record == null:
		return null
	var rec: Dictionary = record

	var unit := Combatant.new()
	unit.content_id = ContentId.make(db.pack.id, "unit", int(rec.get("index", -1)))
	unit.name = String(rec.get("Name", "?"))
	for column in STAT_COLUMNS:
		var value: Variant = rec.get(column)
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			unit.set(String(STAT_COLUMNS[column]), int(value))
	# Base values are what the multipliers and caps measure against, and the
	# tables carry only the current figure.
	unit.life_base = unit.life
	unit.stamina_base = unit.stamina
	unit.morale_base = unit.morale

	var subtypes: Variant = rec.get("Subtype")
	if typeof(subtypes) == TYPE_ARRAY:
		for s in subtypes:
			if int(s) != 0:
				unit.add_subtype(StringName(str(s)))
	elif typeof(subtypes) == TYPE_FLOAT or typeof(subtypes) == TYPE_INT:
		if int(subtypes) != 0:
			unit.add_subtype(StringName(str(int(subtypes))))

	var built := Built.new()
	built.unit = unit
	for entry in rec.get("Abilityes", []):
		_resolve_ability(entry, built)
	return built


func _resolve_ability(entry: Variant, built: Built) -> void:
	var ref: int = 0
	if typeof(entry) == TYPE_DICTIONARY:
		ref = int((entry as Dictionary).get("ref", 0))
	else:
		ref = int(entry)
	if ref == 0:
		return   # /0 is the reserved empty entry, not a real ability

	var upgrade: Variant = upgrades.get(ref)
	if upgrade == null:
		var u := Unresolved.new()
		u.upgrade_index = ref
		u.reason = "no unit_upg record — the reference is dangling"
		built.unresolved.append(u)
		return

	var up: Dictionary = upgrade
	var upgrade_name := String(up.get("Name", ""))

	# COMPOUND ROWS. `Upg Type` and `Quantity` are PARALLEL LISTS when one
	# upgrade grants several abilities at once — Здоровье +1 is [1, 11] / [1, 1]
	# (Life and Stamina together), Младшая нежить is [13, 19, 18, 42].
	# 10 of 153 vanilla rows and 212 of 868 NH rows are like this.
	#
	# Treating Upg Type as a scalar silently drops every ability after the
	# first, which would build a unit that fights wrong and looks fine.
	var opcodes: Variant = up.get("Upg Type")
	var powers: Variant = up.get("Quantity", 0)
	if typeof(opcodes) == TYPE_ARRAY:
		var power_list: Array = []
		if typeof(powers) == TYPE_ARRAY:
			power_list = powers
		else:
			for i in (opcodes as Array).size():
				power_list.append(powers)
		if power_list.size() != (opcodes as Array).size():
			var u := Unresolved.new()
			u.upgrade_index = ref
			u.upgrade_name = upgrade_name
			u.reason = "Upg Type and Quantity lists differ in length (%d vs %d)" % [
				(opcodes as Array).size(), power_list.size()]
			built.unresolved.append(u)
			return
		for i in (opcodes as Array).size():
			_resolve_one(ref, upgrade_name, opcodes[i], power_list[i], built)
		return
	_resolve_one(ref, upgrade_name, opcodes, powers, built)


func _resolve_one(ref: int, upgrade_name: String, opcode_v: Variant,
		power_v: Variant, built: Built) -> void:
	if typeof(opcode_v) != TYPE_INT and typeof(opcode_v) != TYPE_FLOAT:
		var u := Unresolved.new()
		u.upgrade_index = ref
		u.upgrade_name = upgrade_name
		u.reason = "unit_upg row has no usable Upg Type"
		built.unresolved.append(u)
		return
	var opcode := int(opcode_v)

	var ability: Variant = by_number.get(opcode)
	var ability_name := String((ability as Dictionary).get("Name", "")) \
		if ability != null else ""

	# Classify action grants before coercing Quantity for passive modifiers.
	# Malformed action data must not become magnitude 0 or passive behavior.
	var action_grant: Variant = db.resolve_action_grant(opcode, power_v)
	if action_grant != null:
		built.action_grants.append(action_grant)
		built.resolved.append([opcode, upgrade_name if upgrade_name != "" else ability_name])
		return

	var power := int(power_v) if typeof(power_v) != TYPE_ARRAY else 0
	var resolved: Array = db.resolve(opcode)
	var handler: StringName = resolved[0]
	if handler == &"":
		var binding: ContentPack.Binding = db.pack.binding(opcode)
		var reason := "opcode is in no binding table"
		if binding != null:
			if not binding.is_bound():
				reason = "unbound in %s" % db.pack.id
			else:
				reason = "handler '%s' is not implemented" % binding.handler
		var u := Unresolved.new()
		u.upgrade_index = ref
		u.upgrade_name = upgrade_name
		u.opcode = opcode
		u.ability_name = ability_name
		u.reason = reason
		built.unresolved.append(u)
		return

	var binding: ContentPack.Binding = db.pack.binding(opcode)
	var hook: int = Modifier.Hook.STAT_PASSIVE
	if binding != null and Modifier.Hook.has(binding.hook):
		hook = Modifier.Hook[binding.hook]

	var source := upgrade_name
	if source == "":
		source = ability_name if ability_name != "" else "opcode %d" % opcode
	built.unit.modifiers.append(Modifier.make(
		opcode, handler, hook, power, resolved[1], source))
	built.resolved.append([opcode, source])


## How much of the roster builds cleanly.
##
## This is the content-side counterpart to the load report: that one counts
## OPCODES, this one counts UNITS, which is what a player would notice. A pack
## can bind most of its opcodes and still have most of its units incomplete,
## because the unbound ones cluster on the interesting abilities.
func coverage(limit: int = 0) -> Dictionary:
	# Iterate canonical ids, not display names: NH uses 11 names for more than
	# one record, so a name-driven sweep both mis-attributes and under-counts.
	# /0 is the reserved empty record in every .var table, not a unit.
	var all_ids: Array = []
	for cid in ids():
		var rec: Variant = by_id(String(cid))
		if rec == null:
			continue
		var n := String((rec as Dictionary).get("Name", ""))
		if n != "" and n != "Пусто":
			all_ids.append(cid)
	if limit > 0:
		all_ids = all_ids.slice(0, limit)
	var complete: int = 0
	var partial: int = 0
	var missing: Dictionary = {}
	for cid in all_ids:
		var built := build(String(cid))
		if built == null:
			continue
		if built.complete():
			complete += 1
		else:
			partial += 1
		for u in built.unresolved:
			var key := "%d|%s" % [u.opcode,
				u.ability_name if u.ability_name != "" else u.upgrade_name]
			missing[key] = int(missing.get(key, 0)) + 1
	var blockers: Array = []
	for key in missing:
		blockers.append([key, missing[key]])
	blockers.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	return {"units": all_ids.size(), "complete": complete,
			"partial": partial, "blockers": blockers}
