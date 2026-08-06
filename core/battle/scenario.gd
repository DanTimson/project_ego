# core/battle/scenario.gd
class_name Scenario
extends RefCounted

## Deterministic battles as data.
##
## A scenario is a seed, a battlefield, two sides, and a command list. Running it
## produces a LOG: an ordered list of plain strings, compared line for line
## against the Python oracle.
##
## WHY A LOG AND NOT A FINAL STATE. A final state can match while the route to it
## differs — two implementations that disagree about pathfinding tie-breaks, or
## about when stamina is charged, can still land the same unit on the same hex
## with the same HP. The log catches the divergence at the step where it happens.
##
## THIS IS THE INTEGRATION POINT. Pathfinding updates live capacity and
## command-entry coordinates; the composed profile rule resolves primary-melee
## charge; stamina scales the ordinary attack; the RNG rolls it; defence reduces
## it; then charge is added. Reproduction is evidence the whole chain agrees.

const PROFILE_GENESIS := "genesis"
const PROFILE_NEW_HORIZONS := "new_horizons"
const PROFILE_NATIVE := "native"
const PROFILE_REQUIRED := "scenario configuration requires explicit \"profile\"; the omitted-profile native fallback was removed"
const RNG_REMOVED := "scenario configuration key \"rng\" was removed; use explicit \"profile\" (\"genesis\" for LegacyRng or \"native\" for named streams)"
const NEW_HORIZONS_INCOMPLETE := "scenario profile \"new_horizons\" is incomplete: minimum rules assignment is not defined"
const CANONICAL_UNIT_KEYS := {"id": true, "def": true, "at": true, "overrides": true}
const RESOLVED_CONTENT_ID := "__scenario_resolved_content_id"
const SERIALIZED_IDENTITY_FIELDS := {
	"content_id": true, "instance_id": true,
	"__scenario_resolved_content_id": true,
}
const FORBIDDEN_OVERRIDE_FIELDS := {
	"id": true, "def": true, "at": true, "overrides": true,
	"instance_id": true, "content_id": true,
	"__scenario_resolved_content_id": true, "content": true,
	"pack": true, "version": true, "build": true, "fingerprint": true,
	"provenance": true,
}
const SETTABLE_UNIT_FIELDS := {
	"name": true, "attack": true, "counter_attack": true,
	"ranged_attack": true, "shooting_range": true, "defence": true,
	"ranged_defence": true, "resist": true, "life_base": true,
	"life": true, "stamina_base": true, "stamina": true,
	"morale_base": true, "morale": true, "speed": true,
	"attack_bonus": true, "defence_bonus": true, "conditional_bonus": true,
	"modifiers": true, "flags": true, "subtypes": true, "auras": true,
	"ammo": true, "action_spent": true, "movement_remaining": true,
	"forced_rest": true, "resting": true, "stamina_recovery": true,
	"alive": true, "once_per_round": true, "steps_this_round": true,
}

var spec: Dictionary = {}
var scenario_name: String = "unnamed"
var seed_value: int = 0
## Normalized rules-profile identity selected at this composition root.
var profile: String = ""
var construction_error: String = ""
var log: Array[String] = []
## Either Rng (named streams) or LegacyRng (Genesis compatibility).
var catalogue: Dictionary = {}

var rng: Variant
## Profile-composed primary-melee charge. Ordinary damage rules never receive
## it and never branch on profile identity.
var _attack_command_charge: Callable
var field: Battlefield
var units: Dictionary = {}          ## name -> Combatant
var state: RoundLoop.BattleState
## unit -> its projected auras. Passive, so built once; which units an aura
## REACHES is recomputed on every query.
var auras_by_source: Dictionary = {}
var _side_specs: Array = []


static func profile_configuration(p_spec: Dictionary) -> Dictionary:
	# Serialized configuration is strict. The constructor's injected_rng
	# argument remains a separate dependency-injection seam for tests.
	if p_spec.has("rng"):
		return {"profile": "", "error": RNG_REMOVED}
	if not p_spec.has("profile"):
		return {"profile": "", "error": PROFILE_REQUIRED}

	var normalized := String(p_spec["profile"]).strip_edges().to_lower()
	if normalized != PROFILE_GENESIS \
			and normalized != PROFILE_NEW_HORIZONS \
			and normalized != PROFILE_NATIVE:
		var unknown_profile := 'unknown scenario profile "%s"' % normalized
		return {"profile": "", "error": unknown_profile}

	if normalized == PROFILE_NEW_HORIZONS:
		return {"profile": normalized, "error": NEW_HORIZONS_INCOMPLETE}
	return {"profile": normalized, "error": ""}

static func prepare_content(p_spec: Dictionary, provider: Variant = null) -> Dictionary:
	var sides: Array = p_spec.get("sides", [])
	var has_references := false
	for side in sides:
		for unit in side.get("units", []):
			if unit.has("def"):
				has_references = true
				continue
			for field in SERIALIZED_IDENTITY_FIELDS:
				if unit.has(field):
					return {"sides": [], "error":
						"inline unit '%s' cannot contain serialized identity field: %s"
						% [unit.get("id", unit.get("name", "?")), field]}
	if not has_references:
		return {"sides": sides, "error": ""}

	var declaration: Variant = p_spec.get("content")
	if typeof(declaration) != TYPE_DICTIONARY:
		return {"sides": [],
			"error": 'scenario units using "def" require a scenario-level "content" object'}
	var declared: Dictionary = declaration
	for key in declared:
		if String(key) not in ["pack", "version", "build", "fingerprint"]:
			return {"sides": [], "error": "unknown scenario content provenance field: %s" % key}
	var pack_v: Variant = declared.get("pack")
	if typeof(pack_v) != TYPE_STRING or String(pack_v) == "":
		return {"sides": [], "error": 'scenario content provenance requires non-empty "pack"'}
	var pack := String(pack_v)
	var discriminators: Array[String] = []
	for key in ["version", "build", "fingerprint"]:
		if declared.get(key) != null and String(declared.get(key)) != "":
			if typeof(declared[key]) != TYPE_STRING:
				return {"sides": [], "error": 'scenario content provenance field "%s" must be a string' % key}
			discriminators.append(key)
	if discriminators.is_empty():
		return {"sides": [],
			"error": "scenario content provenance requires version, build, and/or fingerprint"}
	if "fingerprint" in discriminators:
		var fingerprint_re := RegEx.new()
		fingerprint_re.compile("^sha256:[0-9a-f]{64}$")
		if fingerprint_re.search(String(declared["fingerprint"])) == null:
			return {"sides": [],
				"error": 'scenario content fingerprint must use "sha256:" plus 64 lowercase hex digits'}
	if provider == null:
		return {"sides": [],
			"error": "scenario canonical definitions require an injected content provider"}
	if typeof(provider) != TYPE_OBJECT:
		return {"sides": [], "error": "content provider must be an object"}
	var provider_capable: bool = provider.has_method("content_provenance") \
		and provider.has_method("resolve_definition")
	if not provider_capable:
		return {"sides": [],
			"error": "content provider must report provenance and resolve canonical definitions"}
	var observed_v: Variant = provider.call("content_provenance")
	if typeof(observed_v) != TYPE_DICTIONARY:
		return {"sides": [], "error": "content provider returned malformed provenance"}
	var observed: Dictionary = observed_v
	if String(observed.get("error", "")) != "":
		return {"sides": [], "error": "content provider provenance error: %s"
			% observed["error"]}
	var verified: Array[String] = ["pack"]
	verified.append_array(discriminators)
	for key in verified:
		var expected := String(declared.get(key, ""))
		var actual := String(observed.get(key, ""))
		if actual != expected:
			if actual == "":
				actual = "<missing>"
			return {"sides": [], "error":
				"content provenance mismatch for %s: expected '%s', observed '%s'"
				% [key, expected, actual]}

	var prepared: Array = sides.duplicate(true)
	var seen_instance_ids: Dictionary = {}
	for side in prepared:
		var side_units: Array = side.get("units", [])
		for index in side_units.size():
			var unit: Dictionary = side_units[index]
			if not unit.has("def"):
				var inline_id := String(unit.get("id", unit.get("name", "")))
				if seen_instance_ids.has(inline_id):
					return {"sides": [], "error": "duplicate unit instance id '%s'" % inline_id}
				seen_instance_ids[inline_id] = true
				continue
			for key in unit:
				if not CANONICAL_UNIT_KEYS.has(String(key)):
					return {"sides": [], "error":
						"canonical unit '%s' mixes undeclared inline field '%s'; use overrides"
						% [unit.get("id", "?"), key]}
			var instance_v: Variant = unit.get("id")
			if typeof(instance_v) != TYPE_STRING or String(instance_v) == "":
				return {"sides": [], "error": 'canonical unit requires a non-empty battle-instance "id"'}
			var instance_id := String(instance_v)
			if seen_instance_ids.has(instance_id):
				return {"sides": [], "error": "duplicate unit instance id '%s'" % instance_id}
			seen_instance_ids[instance_id] = true
			var content_id := String(unit.get("def", ""))
			var cid := ContentId.parse(content_id)
			if cid == null or cid.kind != "unit":
				return {"sides": [], "error": "canonical unit definition id is malformed: '%s'" % content_id}
			if cid.pack != pack:
				return {"sides": [], "error":
					"canonical definition namespace mismatch: '%s' uses pack '%s', scenario declares '%s'"
					% [content_id, cid.pack, pack]}
			var at: Variant = unit.get("at")
			if typeof(at) != TYPE_ARRAY or (at as Array).size() != 2:
				return {"sides": [], "error":
					'canonical unit "%s" requires battle placement "at"' % instance_id}
			var overrides_v: Variant = unit.get("overrides", {})
			if typeof(overrides_v) != TYPE_DICTIONARY:
				return {"sides": [], "error": "canonical unit '%s' overrides must be an object" % instance_id}
			var overrides: Dictionary = overrides_v
			for key in overrides:
				var field := String(key)
				if FORBIDDEN_OVERRIDE_FIELDS.has(field):
					return {"sides": [], "error":
						"canonical unit '%s' overrides forbidden field: %s"
						% [instance_id, field]}
				if not SETTABLE_UNIT_FIELDS.has(field):
					return {"sides": [], "error":
						"canonical unit '%s' overrides unknown or non-settable field: %s"
						% [instance_id, field]}
			var definition_v: Variant = provider.call("resolve_definition", content_id)
			if definition_v == null:
				return {"sides": [], "error":
					"canonical definition '%s' was not found in content pack '%s'"
					% [content_id, pack]}
			if typeof(definition_v) != TYPE_DICTIONARY:
				return {"sides": [], "error":
					"canonical definition '%s' did not resolve to an object" % content_id}
			var definition: Dictionary = definition_v.duplicate(true)
			for key in definition:
				var field := String(key)
				if FORBIDDEN_OVERRIDE_FIELDS.has(field):
					return {"sides": [], "error":
						"canonical definition '%s' contains scenario-owned field: %s"
						% [content_id, field]}
				if not SETTABLE_UNIT_FIELDS.has(field):
					return {"sides": [], "error":
						"canonical definition '%s' contains unknown construction field: %s"
						% [content_id, field]}
			for key in overrides:
				var override_value: Variant = overrides[key]
				definition[key] = override_value.duplicate(true) \
					if typeof(override_value) in [TYPE_ARRAY, TYPE_DICTIONARY] \
					else override_value
			if typeof(definition.get("name")) != TYPE_STRING or String(definition.get("name")) == "":
				return {"sides": [], "error": "canonical definition '%s' has no display name" % content_id}
			definition["id"] = instance_id
			definition["at"] = (at as Array).duplicate(true)
			definition[RESOLVED_CONTENT_ID] = content_id
			side_units[index] = definition
		# Preserve replacement if a caller supplied a non-reference Array.
		side["units"] = side_units
	return {"sides": prepared, "error": ""}


func _init(p_spec: Dictionary, injected_rng: Variant = null,
		injected_content_provider: Variant = null) -> void:
	spec = p_spec
	scenario_name = String(spec.get("name", "unnamed"))
	seed_value = int(spec.get("seed", 0))
	var profile_config := profile_configuration(spec)
	profile = String(profile_config["profile"])
	var profile_error := String(profile_config["error"])
	assert(profile_error == "", profile_error)
	# Assertions are omitted from release builds; keep invalid configuration
	# from falling through to battle construction there.
	if profile_error != "":
		construction_error = profile_error
		push_error(profile_error)
		return
	var prepared := prepare_content(spec, injected_content_provider)
	construction_error = String(prepared["error"])
	assert(construction_error == "", construction_error)
	if construction_error != "":
		push_error(construction_error)
		return
	_side_specs = prepared["sides"]
	# Actions available in this battle. A scenario may declare its own so the
	# file is self-contained; see Action.CATALOGUE.
	catalogue = Action.CATALOGUE.duplicate()
	for entry in spec.get("actions", []):
		var a := Action.from_dict(entry)
		catalogue[a.id] = a
	# THE randomness boundary. Rules never choose a generator and never branch on
	# profile — they receive whatever is injected here and call roll(x, stream).
	# Genesis compatibility needs ONE shared LegacyRng because the original
	# advances a single CRT state across every consumer; native keeps
	# per-subsystem streams so adding a roll in one place does not invalidate
	# every stored replay. Those requirements are irreconcilable, which is why
	# this composition-root seam exists and why it is the only general seam in
	# the engine.
	if injected_rng != null:
		rng = injected_rng
	elif profile == PROFILE_GENESIS:
		rng = LegacyRng.new(seed_value)
	else:
		rng = Rng.new(seed_value)
	# Resolve the charge policy once at the same composition seam as RNG. Native
	# injects no R3 consumer so established zero-charge/overkill behaviour remains
	# untouched; New Horizons was rejected before construction reached this point.
	if profile == PROFILE_GENESIS:
		_attack_command_charge = Callable(self, "_genesis_attack_command_charge")
	else:
		_attack_command_charge = Callable(self, "_no_attack_command_charge")
	field = _build_field(spec.get("battlefield", {}))
	state = RoundLoop.BattleState.new()
	state.sides = _build_sides(_side_specs)
	auras_by_source = _build_auras(_side_specs)


func _build_field(s: Dictionary) -> Battlefield:
	var bf := Battlefield.new(int(s.get("width", 7)), int(s.get("height", 7)))
	for t in s.get("tiles", []):
		var h := Battlefield.offset_to_axial(int(t["col"]), int(t["row"]))
		var tile: Battlefield.Tile = bf.tile(h)
		if tile == null:
			continue
		if t.has("bf_object"):
			tile.bf_object = int(t["bf_object"])
		if t.has("move_cost"):
			tile.move_cost = int(t["move_cost"])
		if t.has("stam_cost"):
			tile.stam_cost = int(t["stam_cost"])
	return bf


func _build_sides(specs: Array) -> Array:
	var out: Array = []
	for s in specs:
		var side := RoundLoop.Side.new()
		side.id = int(s["id"])
		side.name = String(s.get("name", str(s["id"])))
		side.leader_initiative = int(s.get("leader_initiative", 0))
		side.is_attacker = bool(s.get("is_attacker", false))
		for u in s.get("units", []):
			var unit := Combatant.new()
			unit.name = String(u["name"])
			# Battle-instance identity, distinct from the display name; defaults
			# to the name so existing scenarios are unaffected.
			unit.instance_id = String(u.get("id", u["name"]))
			for key in u:
				var k := String(key)
				if k == "id":
					continue
				if k in ["name", "at", "flags", "subtypes", "modifiers", "auras",
						"content_id", "instance_id", RESOLVED_CONTENT_ID]:
					continue
				unit.set(k, u[key])
			unit.content_id = String(u.get(RESOLVED_CONTENT_ID, ""))
			for f in u.get("flags", []):
				unit.set_flag(StringName(String(f)))
			for m in u.get("modifiers", []):
				unit.modifiers.append(Modifier.make(
					int(m.get("ability", 0)), StringName(String(m["handler"])),
					Modifier.Hook[String(m.get("hook", "STAT_PASSIVE"))],
					int(m.get("power", 0)), m.get("params", {}),
					String(m.get("source", m["handler"]))))
			for st in u.get("subtypes", []):
				unit.add_subtype(StringName(String(st)))
			if not u.has("life_base"):
				unit.life_base = unit.life
			if not u.has("stamina_base"):
				unit.stamina_base = unit.stamina
			if not u.has("morale_base"):
				unit.morale_base = unit.morale
			var at: Array = u["at"]
			field.place(unit, Battlefield.offset_to_axial(int(at[0]), int(at[1])))
			if units.has(unit.instance_id):
				push_error("duplicate unit instance id '%s' — give each unit an explicit \"id\" when several share a display name" % unit.instance_id)
			units[unit.instance_id] = unit
			side.units.append(unit)
		out.append(side)
	return out


func _build_auras(specs: Array) -> Dictionary:
	var out: Dictionary = {}
	for side_spec in specs:
		for u in side_spec.get("units", []):
			var declared: Array = u.get("auras", [])
			if declared.is_empty():
				continue
			var unit: Combatant = units[String(u.get("id", u["name"]))]
			var built: Array = []
			for a in declared:
				var aura := Auras.Aura.new()
				aura.id = StringName(String(a["id"]))
				aura.name = String(a.get("name", a["id"]))
				aura.scope = Auras.Scope[String(a.get("scope", "ADJACENT"))]
				aura.affects = Auras.Side[String(a.get("affects", "ALLY"))]
				aura.stacking = Auras.Stacking[String(a.get("stacking", "MAXIMUM"))]
				aura.power = int(a.get("power", 0))
				aura.tick = a.get("tick", {})
				for st in a.get("only_subtypes", []):
					aura.only_subtypes.append(StringName(String(st)))
				for st in a.get("except_subtypes", []):
					aura.except_subtypes.append(StringName(String(st)))
				aura.source = unit
				for m in a.get("modifiers", []):
					aura.modifiers.append(Modifier.make(
						int(m.get("ability", 0)),
						StringName(String(m["handler"])),
						Modifier.Hook[String(m.get("hook", "STAT_PASSIVE"))],
						int(m.get("power", a.get("power", 0))),
						m.get("params", {}), aura.name))
				built.append(aura)
			out[unit] = built
	return out


func side_of(unit: Combatant) -> RoundLoop.Side:
	return _side_of(unit)


## Modifiers from the unit's surroundings — the auras reaching it now.
func environment(unit: Combatant) -> Array:
	return Auras.modifiers_for(unit, auras_by_source, field,
		Callable(self, "side_of"))


## Statuses and auras, at the top of each round.
##
## ORDER: auras first, then statuses. An aura is a continuous drain from a living
## source; a status is a stored effect that ages. Ticking statuses first would let
## an effect expire before an aura that might have killed its source resolves.
## Nothing documents the order — OPEN_QUESTIONS item 20.
func _round_upkeep() -> void:
	for side in state.sides:
		for unit in side.units.duplicate():
			if not unit.alive:
				continue
			var result: Array = Auras.tick_for(unit, auras_by_source, field,
				Callable(self, "side_of"))
			var totals: Dictionary = result[0]
			if not totals.is_empty():
				Auras.apply_tick(unit, totals)
				var parts: Array = []
				var keys: Array = totals.keys()
				keys.sort()
				for k in keys:
					parts.append("%s %+d" % [String(k), int(totals[k])])
				emit("  %s: auras (%s)" % [unit.label(), ", ".join(parts)])
				if not unit.alive:
					_fell(unit)
					continue
			if not unit.statuses.is_empty():
				var names: Array = []
				for e in unit.statuses:
					names.append(e.describe())
				Statuses.tick_round(unit)
				emit("  %s: %s" % [unit.label(), ", ".join(names)])
				if not unit.alive:
					_fell(unit)


# -- helpers -----------------------------------------------------------------

func _at(unit: Combatant) -> String:
	var h := field.find_unit(unit)
	if not field.contains(h):
		return "-"
	var o := Battlefield.axial_to_offset(h)
	return "%d,%d" % [o.x, o.y]


func emit(line: String) -> void:
	log.append(line)


func _side_of(unit: Combatant) -> RoundLoop.Side:
	for s in state.sides:
		if s.units.has(unit):
			return s
	return null


func _path_cost(path: Array) -> int:
	var c := 0
	for h in path:
		c += (field.tile(h) as Battlefield.Tile).move_cost
	return c


func _path_stamina(path: Array) -> int:
	var c := 0
	for h in path:
		c += (field.tile(h) as Battlefield.Tile).stam_cost
	return c


# -- profile-composed primary-melee charge -----------------------------------

func _no_attack_command_charge(_unit: Combatant, _attacker_xy: Vector2i,
		_target_xy: Vector2i, _movement_requested: bool) -> Variant:
	return null


func _genesis_attack_command_charge(unit: Combatant, attacker_xy: Vector2i,
		target_xy: Vector2i, movement_requested: bool) -> int:
	# 0x25 is the accepted Genesis evidence identity. Query it at the battle
	# seam rather than teaching Damage about a profile or pack opcode.
	for modifier in Damage.effective_modifiers(unit):
		if (modifier as Modifier).ability == 0x25:
			return Charge.command_entry_charge(
				attacker_xy, target_xy, movement_requested)
	return 0


# -- commands ----------------------------------------------------------------

func cmd_move(unit: Combatant, col: int, row: int) -> void:
	var start := field.find_unit(unit)
	var goal := Battlefield.offset_to_axial(col, row)
	var path := field.path(start, goal, false, unit.movement_remaining)
	if path.is_empty():
		emit("%s cannot reach %d,%d" % [unit.label(), col, row])
		return
	var cost := _path_cost(path)
	if cost > unit.movement_remaining:
		emit("%s lacks movement for %d,%d" % [unit.label(), col, row])
		return
	field.remove_occupant(start)
	field.place(unit, goal)
	ActionPoints.spend_move(unit, cost, _path_stamina(path))
	emit("%s moves to %s (%d steps, %d total this round)"
		% [unit.label(), _at(unit), path.size(), unit.steps_this_round])


## Attack commands carry an implicit move: issuing an attack against a reachable
## target auto-paths the unit into contact, drawing from the same pool.
func _approach(unit: Combatant, target: Combatant) -> bool:
	var here := field.find_unit(unit)
	var there := field.find_unit(target)
	if Battlefield.distance(here, there) == 1:
		return true
	var best_cost := 1 << 30
	var best_dest := Vector2i.ZERO
	var best_path: Array[Vector2i] = []
	for h in field.neighbours(there):
		if not (field.tile(h) as Battlefield.Tile).is_free():
			continue
		var p := field.path(here, h, false, unit.movement_remaining)
		if p.is_empty():
			continue
		var cost := _path_cost(p)
		if cost > unit.movement_remaining or cost >= best_cost:
			continue
		best_cost = cost
		best_dest = h
		best_path = p
	if best_path.is_empty():
		return false
	field.remove_occupant(here)
	field.place(unit, best_dest)
	ActionPoints.spend_move(unit, best_cost, _path_stamina(best_path))
	emit("%s closes to %s (%d steps)" % [unit.label(), _at(unit), best_path.size()])
	return true


func _fell(unit: Combatant) -> void:
	var h := field.find_unit(unit)
	if field.contains(h):
		field.remove_occupant(h)
	emit("%s falls" % unit.label())


## One exchange: the attack and any retaliation, in the right order.
##
## Melee is answered; a shot is not. Первый удар moves the retaliation ahead of
## the blow that caused it, so a defender can kill an attacker before the attack
## lands.
func _strike(unit: Combatant, target: Combatant, kind: Combatant.AttackKind,
		action: Variant = null, primary_melee_charge: Variant = null) -> void:
	var ex := Counterattack.resolve(
		unit, target, rng, kind, action, primary_melee_charge)
	ActionPoints.spend_attack(unit)

	for entry in ex.order:
		if String(entry[0]) == "attack":
			emit("%s hits %s for %d (%s at %d/%d, stamina %d)"
				% [unit.label(), target.label(), int(entry[1]), target.label(),
					maxi(0, target.life), target.life_base, unit.stamina])
		else:
			emit("%s counters%s for %d (%s at %d/%d)"
				% [target.label(), " first" if ex.counter_first else "",
					int(entry[1]), unit.label(),
					maxi(0, unit.life), unit.life_base])
	if ex.defender_died:
		_fell(target)
	if ex.attacker_died:
		_fell(unit)
	if not ex.countered and ex.reason != Counterattack.NoCounter.RANGED \
			and ex.reason != Counterattack.NoCounter.DEAD:
		emit("  (%s does not counter: %s)"
			% [target.label(), Counterattack.REASON_TEXT[ex.reason]])


func cmd_attack(unit: Combatant, target: Combatant) -> void:
	if not target.alive:
		emit("%s has no target: %s is down" % [unit.label(), target.label()])
		return
	if unit.action_spent:
		emit("%s has already acted" % unit.label())
		return
	# Resolve both R3 applicability and distance before automatic approach
	# mutates battlefield occupancy or the environment-derived modifier set.
	var attacker_entry_h := field.find_unit(unit)
	var target_entry_h := field.find_unit(target)
	var attacker_entry := Battlefield.axial_to_offset(attacker_entry_h)
	var target_entry := Battlefield.axial_to_offset(target_entry_h)
	var movement_requested := Battlefield.distance(
		attacker_entry_h, target_entry_h) != 1
	var primary_melee_charge: Variant = _attack_command_charge.call(
		unit, attacker_entry, target_entry, movement_requested)
	if not _approach(unit, target):
		emit("%s cannot reach %s" % [unit.label(), target.label()])
		return
	_strike(unit, target, Combatant.AttackKind.MELEE, null,
		primary_melee_charge)


func cmd_shoot(unit: Combatant, target: Combatant) -> void:
	if not target.alive:
		emit("%s has no target: %s is down" % [unit.label(), target.label()])
		return
	if unit.action_spent:
		emit("%s has already acted" % unit.label())
		return
	if unit.ammo <= 0:
		emit("%s is out of ammunition" % unit.label())
		return
	var dist := Battlefield.distance(field.find_unit(unit), field.find_unit(target))
	if dist > unit.shooting_range:
		emit("%s is out of range of %s (%d > %d)"
			% [target.label(), unit.label(), dist, unit.shooting_range])
		return
	unit.ammo -= 1
	_strike(unit, target, Combatant.AttackKind.RANGED)


func cmd_rest(unit: Combatant) -> void:
	ActionPoints.rest(unit)
	emit("%s rests (stamina %d)" % [unit.label(), unit.stamina])


func cmd_extra_turn(unit: Combatant, c: Dictionary) -> void:
	var r: Array = ActionPoints.grant_extra_turn(
		unit, StringName(String(c.get("source", ""))),
		bool(c.get("once_per_round", false)),
		bool(c.get("fire_round_start", false)))
	emit("%s %s an extra turn (movement %d, steps %d)"
		% [unit.label(), "receives" if bool(r[0]) else "is refused",
			unit.movement_remaining, unit.steps_this_round])


## Invoke a catalogued action.
##
## Executes what the Action model declares — `grants`, applied as timed statuses
## through the normal status machinery. Everything else is REFUSED EXPLICITLY
## rather than silently doing nothing, because an action that appears to succeed
## and changes nothing is worse than one that reports it cannot run yet:
##
##   - `is_attack` actions need the attack pipeline plus `damage_scale`, whose
##     insertion point is an open question (FORMULAS §1.1);
##   - target-consuming effects need magnitudes from `unit_upg.Quantity`, which
##     are not yet carried into Action instances.
##
## Log strings mirror oracle/scenario.py exactly; the scenario fixture compares
## them line for line.
func cmd_action(unit: Combatant, action_id: String) -> void:
	if not catalogue.has(StringName(action_id)):
		emit("unknown action '%s'" % action_id)
		return
	var action: Action = catalogue[StringName(action_id)]

	var refusal: int = action.availability(unit)
	if refusal != Action.Refusal.OK:
		emit("%s cannot use %s: %s"
			% [unit.label(), action.name, Action.REFUSAL_TEXT[refusal]])
		return

	if action.is_attack:
		emit("%s: %s is an attack-replacing action and is not executable yet"
			% [unit.label(), action.name])
		return
	if action.grants.is_empty():
		emit("%s: %s has no executable effect yet (magnitudes are not loaded from unit_upg)"
			% [unit.label(), action.name])
		return

	action.pay(unit)
	var applied: Array = []
	for g in action.grants:
		var ability := String(g[0])
		var magnitude: int = int(g[1]) if g[1] != null else 0
		var duration: int = int(g[2]) if g.size() > 2 and g[2] != null else Statuses.PERMANENT
		var effect := Statuses.Effect.new()
		effect.id = StringName("%s:%s" % [action.id, ability])
		effect.name = ability
		effect.source = action.name
		effect.duration = duration
		effect.power = magnitude
		Statuses.apply(unit, effect)
		applied.append(ability)
	emit("%s uses %s (%s; stamina %d)"
		% [unit.label(), action.name, ", ".join(applied), unit.stamina])


func cmd_end_phase() -> void:
	if RoundLoop.end_phase(state):
		emit("-- round %d, side %d first --" % [state.round_number, state.active_side])
		_round_upkeep()
	else:
		emit("-- side %d --" % state.active_side)


## R7: exhaustion hands control over just like an explicit pass. Check after
## every unit command, matching the oracle and the recovered roster scan.
func _auto_end_phase() -> void:
	while not RoundLoop.battle_over(state) \
			and RoundLoop.phase_done(state, state.active_side):
		var before: int = state.round_number
		var new_round: bool = RoundLoop.end_phase(state)
		if new_round:
			emit("-- round %d, side %d first (both sides exhausted) --"
				% [state.round_number, state.active_side])
			_round_upkeep()
		else:
			emit("-- side %d takes over (no units left to act) --"
				% state.active_side)
		if state.round_number == before and not new_round \
				and not RoundLoop.phase_done(state, state.active_side):
			break


# -- run ---------------------------------------------------------------------

## Install the pipeline AND the environment, then run.
##
## Both are needed and forgetting either is silent. Without a pipeline,
## Damage._run_hook returns immediately and NO modifier applies — innate
## abilities, statuses and auras alike. Without an environment, auras alone
## vanish. The first version of this bound only the environment, so a scenario
## ran with every modifier inert while looking entirely healthy.
func run() -> Dictionary:
	var registry := AbilityRegistry.new()
	Handlers.register_all(registry)
	Damage.bind_pipeline(Pipeline.new(registry))
	Damage.bind_environment(Callable(self, "environment"))
	var result := _run()
	Damage.bind_environment(Callable())
	Damage.bind_pipeline(null)
	return result


func _run() -> Dictionary:
	RoundLoop.begin_battle(state)
	emit("== %s (seed %d) ==" % [scenario_name, seed_value])
	emit("-- round %d, side %d first --" % [state.round_number, state.active_side])

	for c in spec.get("commands", []):
		var op := String(c["op"])
		if op == "end_phase":
			cmd_end_phase()
			continue
		var unit: Combatant = units.get(String(c.get("unit", "")))
		if unit == null:
			emit("unknown unit '%s'" % c.get("unit", ""))
			continue
		if not unit.alive:
			emit("%s is down and cannot act" % unit.label())
			continue
		var side := _side_of(unit)
		if side != null and side.id != state.active_side:
			emit("%s is not in the active side's phase" % unit.label())
			continue
		match op:
			"move":
				cmd_move(unit, int(c["to"][0]), int(c["to"][1]))
			"attack":
				cmd_attack(unit, units[String(c["target"])])
			"shoot":
				cmd_shoot(unit, units[String(c["target"])])
			"rest":
				cmd_rest(unit)
			"action":
				cmd_action(unit, String(c.get("action", "")))
			"extra_turn":
				cmd_extra_turn(unit, c)
			_:
				emit("unknown command '%s'" % op)
		if RoundLoop.battle_over(state):
			emit("== battle over ==")
			break
		_auto_end_phase()

	return {"name": scenario_name, "seed": seed_value,
			"log": log, "final": final_state()}


func final_state() -> Dictionary:
	var out: Dictionary = {}
	var names: Array = units.keys()
	names.sort()
	for n in names:
		var u: Combatant = units[n]
		out[n] = {
			"alive": u.alive, "life": maxi(0, u.life), "stamina": u.stamina,
			"at": _at(u), "steps_this_round": u.steps_this_round,
			"action_spent": u.action_spent,
			"movement_remaining": u.movement_remaining,
		}
	return out
