# gdlint: disable=max-returns
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
	"instance_id": true, "content_id": true, "definition_id": true,
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
	"ammo_base": true, "tier": true,
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
var unit_catalogues: Dictionary = {}
var action_refusals: Dictionary = {}
var action_diagnostics: Array = []
var action_load_mode: String = ActionDefinitionComposer.STRICT
var _action_composition: Dictionary = {}
var _inline_action_ids: Dictionary = {}

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

var _content_provider: Variant = null

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
	var inline_instance_ids: Dictionary = {}
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
			var inline_id := String(unit.get("id", unit.get("name", "")))
			if inline_instance_ids.has(inline_id):
				return {"sides": [],
					"error": "duplicate unit instance id '%s'" % inline_id}
			inline_instance_ids[inline_id] = true
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
		and provider.has_method("resolve_definition") \
		and provider.has_method("compose_actions")
	if not provider_capable:
		return {"sides": [], "error": (
			"content provider must report provenance, resolve canonical definitions, and compose actions")}
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
	var seen_instance_ids: Dictionary = inline_instance_ids.duplicate()
	for side in prepared:
		var side_units: Array = side.get("units", [])
		for index in side_units.size():
			var unit: Dictionary = side_units[index]
			if not unit.has("def"):
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
				if field == "__scenario_action_grants":
					continue
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
	action_load_mode = String(spec.get("action_load_mode", ActionDefinitionComposer.STRICT))
	if action_load_mode != ActionDefinitionComposer.STRICT \
			and action_load_mode != ActionDefinitionComposer.PERMISSIVE:
		construction_error = "unknown action load mode '%s'" % action_load_mode
		push_error(construction_error)
		return
	if injected_content_provider != null \
			and typeof(injected_content_provider) == TYPE_OBJECT \
			and injected_content_provider.has_method("compose_actions"):
		_action_composition = injected_content_provider.call(
			"compose_actions", profile, action_load_mode)
	else:
		_action_composition = ActionDefinitionComposer.empty_result(profile, action_load_mode)
	action_diagnostics = _action_composition.get("diagnostics", []).duplicate(true)
	if not bool(_action_composition.get("ok", false)):
		var messages: PackedStringArray = []
		for diagnostic in action_diagnostics:
			messages.append(String(diagnostic.get("message", "action composition error")))
		construction_error = "action composition failed: %s" % "; ".join(messages)
		push_error(construction_error)
		return
	var prepared := prepare_content(spec, injected_content_provider)
	construction_error = String(prepared["error"])
	if construction_error != "":
		push_error(construction_error)
		return
	_side_specs = prepared["sides"]
	_content_provider = injected_content_provider
	# Provider-composed definitions are the production enumeration source.
	# Inline entries remain a self-contained fixture override layer.
	catalogue = (_action_composition.get("definitions", {}) as Dictionary).duplicate()
	for entry in spec.get("actions", []):
		var a := Action.from_dict(entry)
		catalogue[a.id] = a
		_inline_action_ids[a.id] = true
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
	var built := _build_sides(_side_specs)
	construction_error = String(built["error"])
	if construction_error != "":
		# _build_sides is transactional for indexes. Drop the staging field too,
		# so no occupied partial battlefield can be mistaken for a Scenario.
		field = null
		push_error(construction_error)
		return
	units = built["units"]
	var resolved_actions := _resolve_unit_actions(_side_specs)
	unit_catalogues = resolved_actions["catalogues"]
	action_refusals = resolved_actions["refusals"]
	if action_load_mode == ActionDefinitionComposer.STRICT:
		var malformed: Array = action_diagnostics.filter(
				func(d): return String(d.get("code", "")) == "malformed_grant")
		if not malformed.is_empty():
			var messages: PackedStringArray = []
			for diagnostic in malformed:
				messages.append(String(diagnostic.get("message", "malformed action grant")))
			construction_error = "action composition failed: %s" % "; ".join(messages)
			field = null
			units = {}
			unit_catalogues = {}
			action_refusals = {}
			push_error(construction_error)
			return
	state = RoundLoop.BattleState.new()
	state.sides = built["sides"]
	auras_by_source = _build_auras(_side_specs)


func _resolve_unit_actions(specs: Array) -> Dictionary:
	var catalogues: Dictionary = {}
	var refusals: Dictionary = {}
	var composed_grants: Dictionary = _action_composition.get("grants", {})
	var source_map: Dictionary = _action_composition.get("source_map", {})
	var composed_refusals: Dictionary = _action_composition.get("refusals", {})
	for side in specs:
		for unit_spec in side.get("units", []):
			var instance_id := String(unit_spec.get("id", unit_spec.get("name", "")))
			var content_id := String(unit_spec.get(RESOLVED_CONTENT_ID, ""))
			var available: Dictionary = {}
			for action_id in _inline_action_ids:
				available[action_id] = catalogue[action_id]
			var raw_grants: Array = composed_grants.get(content_id, []).duplicate(true)
			for raw_v in unit_spec.get("__scenario_action_grants", []):
				var raw: Dictionary = raw_v
				var source_id := int(raw.get("source_id", -1))
				if raw.has("error"):
					var candidate := String(source_map.get(source_id,
							ActionDefinitionComposer.namespace_id(
								String(_action_composition.get("pack", "")), source_id)))
					var message := String(raw["error"])
					if not refusals.has(instance_id):
						refusals[instance_id] = {}
					refusals[instance_id][candidate] = message
					action_diagnostics.append({
						"code": "malformed_grant",
						"message": message,
						"unit": content_id if content_id != "" else instance_id,
						"source_id": source_id,
						"canonical_id": candidate,
					})
					continue
				if not source_map.has(source_id):
					var candidate := ActionDefinitionComposer.namespace_id(
						String(_action_composition.get("pack", "")), source_id)
					var message := "unit '%s' has unresolved required action grant source %d" % [
						content_id if content_id != "" else instance_id, source_id]
					if not refusals.has(instance_id):
						refusals[instance_id] = {}
					refusals[instance_id][candidate] = message
					continue
				raw_grants.append({
					"canonical_id": String(source_map[source_id]),
					"overrides": raw.get("overrides", {}).duplicate(true),
				})
			for grant_v in raw_grants:
				var grant: Dictionary = grant_v
				var canonical_id := StringName(String(grant["canonical_id"]))
				if not catalogue.has(canonical_id):
					continue
				available[canonical_id] = ActionDefinitionComposer.resolve_grant(
					catalogue[canonical_id], grant.get("overrides", {}))
			catalogues[instance_id] = available
			if composed_refusals.has(content_id):
				if not refusals.has(instance_id):
					refusals[instance_id] = {}
				refusals[instance_id].merge(
					(composed_refusals[content_id] as Dictionary).duplicate(true), true)
	return {"catalogues": catalogues, "refusals": refusals}


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


func _build_sides(specs: Array) -> Dictionary:
	var out: Array = []
	var built_units: Dictionary = {}
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
						"statuses", "content_id", "instance_id", RESOLVED_CONTENT_ID,
						"__scenario_action_grants"]:
					continue
				if k == "damage_received":
					unit.damage_received.assign(u[key])
				else:
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
			for status_spec in u.get("statuses", []):
				Statuses.apply(unit, Status.from_dict(status_spec))
			for st in u.get("subtypes", []):
				unit.add_subtype(StringName(String(st)))
			if not u.has("life_base"):
				unit.life_base = unit.life
			if not u.has("stamina_base"):
				unit.stamina_base = unit.stamina
			if not u.has("morale_base"):
				unit.morale_base = unit.morale
			if not u.has("ammo_base"):
				unit.ammo_base = unit.ammo
			if not unit.original_definition.is_empty():
				unit.original_definition = DeathLifecycle.normalize_definition(
					unit.original_definition)
			if built_units.has(unit.instance_id):
				return {"sides": [], "units": {}, "error":
					"duplicate unit instance id '%s' — give each unit an explicit \"id\" when several share a display name"
					% unit.instance_id}
			var at: Array = u["at"]
			if not field.place(unit,
					Battlefield.offset_to_axial(int(at[0]), int(at[1]))):
				return {"sides": [], "units": {}, "error":
					"cannot place unit '%s' at %s" % [unit.instance_id, str(at)]}
			built_units[unit.instance_id] = unit
			side.units.append(unit)
		out.append(side)
	return {"sides": out, "units": built_units, "error": ""}


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


## Existing aura upkeep. Status duration is intentionally absent: its automatic
## lifecycle clock and ordering remain unresolved pending R13 observation.
func _round_upkeep() -> void:
	for side in state.sides:
		# A battle-owned final death may erase itself from this roster.
		for unit in side.units.duplicate():
			DeathLifecycle.apply_aura_upkeep(unit, auras_by_source, field,
				Callable(self, "side_of"), Callable(self, "_resolve_fatal_event"),
				Callable(self, "_fell"), Callable(self, "emit"))

# -- helpers -----------------------------------------------------------------

func _at(unit: Combatant) -> String:
	return DeathLifecycle.scenario_position(unit, field)


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
		target_xy: Vector2i, movement_requested: bool) -> Dictionary:
	return ScenarioNumericOrdering.genesis_charge(
		unit, attacker_xy, target_xy, movement_requested)


# -- authoritative manual-command boundary -----------------------------------

## Validate a one-at-a-time presentation command against the current model.
## This is also the execution gate used by execute_command(); presentation may
## use it for advisory highlights but may not treat a prior query as authority.
func query_command(command: Dictionary) -> Dictionary:
	var op := String(command.get("op", ""))
	var command_name := _command_name(op)
	if op == "end_phase":
		return _command_query(true, command_name)
	if op not in ["move", "attack", "shoot", "rest", "action"]:
		return _command_query(false, command_name,
			"unknown command '%s'" % op)
	var unit: Combatant = units.get(String(command.get("unit", "")))
	if unit == null:
		return _command_query(false, command_name,
			"unknown unit '%s'" % command.get("unit", ""))
	if not unit.alive:
		return _command_query(false, command_name,
			"%s is down and cannot act" % unit.label())
	var side := side_of(unit)
	if side == null or side.id != state.active_side:
		return _command_query(false, command_name,
			"%s is not in the active side's phase" % unit.label())
	if unit.action_spent:
		return _command_query(false, command_name,
			"%s has already acted" % unit.label())
	if not ActionPoints.has_resources(unit):
		return _command_query(false, command_name,
			"%s has no resources left this activation" % unit.label())
	if op == "action":
		return _query_action_command(unit, command, command_name)
	if op == "move":
		var destination_v: Variant = command.get("to")
		if typeof(destination_v) != TYPE_ARRAY or destination_v.size() != 2:
			return _command_query(false, command_name,
				"movement destination is malformed")
		var plan := movement_plan(unit, int(destination_v[0]), int(destination_v[1]))
		return _command_query(bool(plan["ok"]), command_name,
			String(plan.get("reason", "")))
	if op == "rest":
		return _command_query(not unit.action_spent, command_name,
			"%s has already acted" % unit.label() if unit.action_spent else "")
	var target: Combatant = units.get(String(command.get("target", "")))
	if target == null:
		return _command_query(false, command_name,
			"unknown target '%s'" % command.get("target", ""))
	if not target.alive:
		return _command_query(false, command_name,
			"%s is down and cannot be targeted" % target.label())
	if side_of(target) == side:
		return _command_query(false, command_name,
			"%s is on the same side as %s" % [target.label(), unit.label()])
	if op == "attack":
		var approach := _approach_plan(unit, target)
		return _command_query(bool(approach["ok"]), command_name,
			"%s cannot reach %s" % [unit.label(), target.label()]
			if not bool(approach["ok"]) else "")
	if unit.ammo <= 0:
		return _command_query(false, command_name,
			"%s is out of ammunition" % unit.label())
	if unit.shooting_range <= 0:
		return _command_query(false, command_name,
			"%s cannot make ranged attacks" % unit.label())
	var distance := Battlefield.distance(field.find_unit(unit), field.find_unit(target))
	if distance > unit.shooting_range:
		return _command_query(false, command_name,
			"%s is out of range of %s (%d > %d)" % [
				target.label(), unit.label(), distance, unit.shooting_range])
	return _command_query(true, command_name)


## Decide and apply a manual command through one authoritative core path.
func execute_command(command: Dictionary) -> Dictionary:
	var before_log := log.size()
	var query := query_command(command)
	if not bool(query["accepted"]):
		return _command_result(false, String(query["command"]),
			String(query["reason"]), [], false)
	var before_state := _command_state()
	var op := String(command.get("op", ""))
	if op == "end_phase":
		cmd_end_phase()
	else:
		var unit: Combatant = units[String(command["unit"])]
		match op:
			"move":
				var destination: Array = command["to"]
				cmd_move(unit, int(destination[0]), int(destination[1]))
			"attack":
				cmd_attack(unit, units[String(command["target"])])
			"shoot":
				cmd_shoot(unit, units[String(command["target"])])
			"action":
				cmd_action(unit, String(command.get("action", "")),
					units.get(String(command.get("target", ""))))
			"rest":
				cmd_rest(unit)
	if RoundLoop.battle_over(state):
		emit("== battle over ==")
	elif op != "end_phase":
		_auto_end_phase()
	var events: Array = log.slice(before_log)
	return _command_result(true, String(query["command"]), "", events,
		before_state != _command_state())


func movement_plan(unit: Combatant, col: int, row: int) -> Dictionary:
	var start := field.find_unit(unit)
	var goal := Battlefield.offset_to_axial(col, row)
	var path := [] if unit.action_spent else field.path(start, goal, false, unit.movement_remaining)
	if path.is_empty():
		return {"ok": false, "reason": "%s cannot reach %d,%d" % [
			unit.label(), col, row]}
	var cost := _path_cost(path)
	if cost > unit.movement_remaining:
		return {"ok": false, "reason": "%s lacks movement for %d,%d" % [
			unit.label(), col, row]}
	return {"ok": true, "reason": "", "start": start, "goal": goal,
		"path": path, "cost": cost, "stamina_cost": _path_stamina(path)}


func _resolve_action_command(unit: Combatant, action_id: String,
		target: Combatant) -> Dictionary:
	var unit_refusals: Dictionary = action_refusals.get(unit.instance_id, {})
	if unit_refusals.has(action_id):
		return {"reason": "unresolved action grant: %s" % unit_refusals[action_id],
			"refusal": "validation"}
	var available: Dictionary = unit_catalogues.get(unit.instance_id, {})
	if not available.has(StringName(action_id)):
		if catalogue.has(StringName(action_id)):
			return {"reason": "action is not granted", "refusal": "validation"}
		return {"reason": "unknown action '%s'" % action_id,
			"refusal": "unknown"}
	var action: Action = available[StringName(action_id)]
	var resolution := ActionRecipeResolver.resolve(action)
	if not resolution.supported:
		return {"reason": "action %s is known but unsupported" % action.id,
			"refusal": "unsupported"}
	var refusal := action.availability(unit,
		Damage.has_effective_modifier(unit, 0x12))
	if refusal != Action.Refusal.OK:
		return {"reason": Action.REFUSAL_TEXT[refusal]}
	if target == null:
		return {"reason": "requires an existing target"}
	if not target.alive or target.life <= 0:
		return {"reason": "%s is down and cannot be targeted" % target.label()}
	if side_of(target) == side_of(unit):
		return {"reason": "%s is on the same side as %s" % [
			target.label(), unit.label()]}
	if Battlefield.distance(field.find_unit(unit), field.find_unit(target)) != 1:
		return {"reason": "%s is not adjacent to %s" % [
			target.label(), unit.label()]}
	for excluded in action.excluded_targets:
		if target.has_flag(excluded) or target.has_subtype(excluded):
			return {"reason": "%s is excluded by %s" % [
				target.label(), action.id]}
	return {"reason": "", "action": action, "plan": resolution.plan}


func _query_action_command(unit: Combatant, command: Dictionary,
		command_name: String) -> Dictionary:
	var prepared := _resolve_action_command(unit,
		String(command.get("action", "")),
		units.get(String(command.get("target", ""))))
	var reason := String(prepared["reason"])
	return _command_query(reason == "", command_name, reason)

func _command_name(op: String) -> String:
	return {"attack": "melee", "shoot": "ranged", "end_phase": "pass"}.get(op, op)


func _command_query(accepted: bool, command: String,
		reason: String = "") -> Dictionary:
	return {"accepted": accepted, "command": command, "reason": reason}


func _command_result(accepted: bool, command: String, reason: String,
		events: Array, state_changed: bool) -> Dictionary:
	var message := reason
	if accepted and not events.is_empty():
		message = " | ".join(events)
	return {
		"accepted": accepted,
		"command": command,
		"reason": reason,
		"events": events,
		"state_changed": state_changed,
		# Backward-compatible aliases for Slice 1 callers.
		"ok": accepted,
		"message": message,
		"log": events,
	}


func _command_state() -> Dictionary:
	var snapshot := {
		"round": state.round_number,
		"active_side": state.active_side,
		"units": {},
	}
	var ids: Array = units.keys()
	ids.sort()
	for id in ids:
		var unit: Combatant = units[id]
		snapshot["units"][id] = {
			"alive": unit.alive,
			"life": unit.life,
			"stamina": unit.stamina,
			"ammo": unit.ammo,
			"action_spent": unit.action_spent,
			"movement_remaining": unit.movement_remaining,
			"steps_this_round": unit.steps_this_round,
			"position": unit_position_offset(unit),
		}
	return snapshot


func unit_position_offset(unit: Combatant) -> Vector2i:
	var axial := field.find_unit(unit)
	return Battlefield.axial_to_offset(axial) if field.contains(axial) \
		else Vector2i(-1, -1)


# -- commands ----------------------------------------------------------------

func cmd_move(unit: Combatant, col: int, row: int) -> void:
	var plan := movement_plan(unit, col, row)
	if not bool(plan["ok"]):
		emit(String(plan["reason"]))
		return
	var start: Vector2i = plan["start"]
	var goal: Vector2i = plan["goal"]
	var path: Array = plan["path"]
	var cost := int(plan["cost"])
	field.remove_occupant(start)
	field.place(unit, goal)
	var move_trace := ActionPoints.spend_move(unit, cost,
		int(plan["stamina_cost"]), Damage.has_effective_modifier(unit, 0x12))
	ScenarioNumericOrdering.append_traces(log, [move_trace])
	emit("%s moves to %s (%d steps, %d total this round)"
		% [unit.label(), _at(unit), path.size(), unit.steps_this_round])


## Attack commands carry an implicit move: issuing an attack against a reachable
## target auto-paths the unit into contact, drawing from the same pool.
func _approach_plan(unit: Combatant, target: Combatant) -> Dictionary:
	var here := field.find_unit(unit)
	var there := field.find_unit(target)
	if Battlefield.distance(here, there) == 1:
		return {"ok": true, "already_adjacent": true}
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
		return {"ok": false}
	return {
		"ok": true,
		"already_adjacent": false,
		"cost": best_cost,
		"destination": best_dest,
		"path": best_path,
	}


func _approach(unit: Combatant, target: Combatant) -> bool:
	var plan := _approach_plan(unit, target)
	if not bool(plan["ok"]):
		return false
	if bool(plan["already_adjacent"]):
		return true
	var here := field.find_unit(unit)
	var destination: Vector2i = plan["destination"]
	var path: Array = plan["path"]
	var cost := int(plan["cost"])
	field.remove_occupant(here)
	field.place(unit, destination)
	var move_trace := ActionPoints.spend_move(unit, cost, _path_stamina(path),
		Damage.has_effective_modifier(unit, 0x12))
	ScenarioNumericOrdering.append_traces(log, [move_trace])
	emit("%s closes to %s (%d steps)" % [unit.label(), _at(unit), path.size()])
	return true

func _resolve_fatal_event(unit: Combatant) -> Dictionary:
	return DeathLifecycle.resolve_for_scenario(unit, field, state.sides, _content_provider, log)

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
		attack_context: Variant = null, primary_melee_charge: Variant = null,
		spend_attack_cost: bool = true) -> Counterattack.Exchange:
	Counterattack.bind_death_resolver(Callable(self, "_resolve_fatal_event"))
	var ex := ScenarioNumericOrdering.resolve_exchange(
		log, unit, target, rng, kind, attack_context, primary_melee_charge,
		spend_attack_cost)
	Counterattack.bind_death_resolver(Callable())

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
	return ex


func _primary_melee_charge_at_command_entry(unit: Combatant,
		target: Combatant, movement_requested: bool) -> Variant:
	var attacker_entry := Battlefield.axial_to_offset(field.find_unit(unit))
	var target_entry := Battlefield.axial_to_offset(field.find_unit(target))
	var charge_decision: Variant = _attack_command_charge.call(
		unit, attacker_entry, target_entry, movement_requested)
	return ScenarioNumericOrdering.charge_value(
		log, charge_decision, attacker_entry, target_entry, movement_requested)


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
	var movement_requested := Battlefield.distance(
		attacker_entry_h, target_entry_h) != 1
	var primary_melee_charge: Variant = _primary_melee_charge_at_command_entry(
		unit, target, movement_requested)
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
	if unit.action_spent:
		emit("%s has already acted" % unit.label())
		return
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


## Execute validated typed operations through existing battle primitives.
## Recipe selection remains pure; command ownership stays in Scenario.
func _execute_action_attack(operation: ActionExecutionPlan.AttackOp,
		unit: Combatant, target: Combatant) -> Counterattack.Exchange:
	var charge_value: Variant = _primary_melee_charge_at_command_entry(
		unit, target, false)
	return _strike(unit, target, Combatant.AttackKind.MELEE, operation,
		charge_value, false)


func _execute_action_resource_delta(
		operation: ActionExecutionPlan.ResourceDeltaOp,
		target: Combatant) -> Trace:
	assert(operation.target == ActionExecutionPlan.OperationTarget.SELECTED_ENEMY
		and operation.resource == ActionExecutionPlan.ResourceKind.STAMINA
		and operation.amount <= 0,
		"unsupported internal ResourceDeltaOp parameters")
	var trace := Stamina.apply_tactical_drain(target, operation.amount,
		Damage.has_effective_modifier(target, 0x12))
	ScenarioNumericOrdering.append_traces(log, [trace])
	return trace


func cmd_action(unit: Combatant, action_id: String,
		target: Combatant = null) -> void:
	var prepared := _resolve_action_command(unit, action_id, target)
	var reason := String(prepared["reason"])
	if reason != "":
		match String(prepared.get("refusal", "validation")):
			"unknown":
				emit(reason)
			"unsupported":
				emit("%s: %s" % [unit.label(), reason])
			_:
				emit("%s cannot use %s: %s" % [
					unit.label(), action_id, reason])
		return

	var action: Action = prepared["action"]
	var plan: ActionExecutionPlan = prepared["plan"]
	var operation_names: Array[String] = []
	for operation in plan.operations():
		operation_names.append(String(operation.kind))
	var before_stamina := unit.stamina
	emit("%s requests action %s" % [unit.label(), action.id])
	emit("  [action] %s resolved plan [%s]" % [
		action.id, ", ".join(operation_names)])
	var action_cost_trace := action.pay(unit,
		Damage.has_effective_modifier(unit, 0x12))
	ScenarioNumericOrdering.append_traces(log, [action_cost_trace])
	emit("  [action] %s payment stamina %d -> %d; spent %s" % [
		action.id, before_stamina, unit.stamina, str(unit.action_spent)])

	var attack := func(operation: ActionExecutionPlan.AttackOp) -> Variant:
		emit("  [action] operation AttackOp melee scale %d/%d" % [
			operation.initiating_attack_scale_numerator,
			operation.initiating_attack_scale_denominator])
		return _execute_action_attack(operation, unit, target)
	var resource_delta := func(
			operation: ActionExecutionPlan.ResourceDeltaOp) -> Variant:
		var before := target.stamina
		emit("  [action] operation ResourceDeltaOp selected_enemy stamina %+d"
			% operation.amount)
		var trace := _execute_action_resource_delta(operation, target)
		emit("  [action] resource result %s stamina %d -> %d" % [
			target.label(), before, target.stamina])
		return trace
	ActionExecutionPlan.Executor.execute(plan, attack, resource_delta)
	emit("  [action] %s result target life %d stamina %d" % [
		action.id, maxi(0, target.life), target.stamina])
	emit("  [action] %s terminal actor spent %s" % [
		action.id, str(unit.action_spent)])


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
	var status_units: Array = units.keys()
	status_units.sort()
	for unit_id in status_units:
		var status_unit: Combatant = units[unit_id]
		if not status_unit.statuses.is_empty():
			emit("  %s: statuses [%s]" % [
				status_unit.label(), Statuses.describe_all(status_unit)])

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
				cmd_action(unit, String(c.get("action", "")),
					units.get(String(c.get("target", ""))))
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
		var unit_state := {
			"alive": u.alive, "life": maxi(0, u.life), "stamina": u.stamina,
			"at": _at(u), "steps_this_round": u.steps_this_round,
			"action_spent": u.action_spent,
			"movement_remaining": u.movement_remaining,
			"ammo": u.ammo, "damage_received": u.damage_received.duplicate(),
		}
		if not u.statuses.is_empty():
			unit_state["statuses"] = Statuses.serialize(u)
		if DeathLifecycle.has_scenario_final_details(u):
			unit_state.merge(DeathLifecycle.scenario_final_details(u, _side_of(u)))
		out[n] = unit_state
	return out
