class_name ActionDefinitionComposer
extends RefCounted

## Production action-definition composition. Raw source identities stop here;
## runtime recipes receive only canonical IDs.

const STRICT := "strict"
const PERMISSIVE := "permissive"
const GRANT_OVERRIDE_FIELDS := {"magnitude": true}
const SHARED_IDS := {"crushing_blow": true, "shield_bash": true}
const DEFINITION_FIELDS := {
	"source_id": true, "shared_id": true, "canonical_id": true, "name": true,
	"target": true, "cost_stamina": true, "cost_ammo": true,
	"consumes_action": true, "attack_surcharge": true, "free_action_for": true,
	"magnitude": true, "is_attack": true, "damage_scale": true,
	"suppresses": true, "scales": true, "excluded_targets": true,
	"grants": true, "notes": true, "replace": true, "recipe": true,
}
const GENESIS_DEFAULTS := [
	{"source_id": 59, "shared_id": "crushing_blow", "name": "Crushing Blow",
		"target": "enemy_melee", "cost_stamina": 0, "attack_surcharge": true,
		"is_attack": true, "damage_scale": 1.5},
	{"source_id": 388, "shared_id": "shield_bash", "name": "Shield Bash",
		"target": "enemy_melee", "cost_stamina": 1, "attack_surcharge": true,
		"is_attack": true, "damage_scale": 0.0,
		"excluded_targets": ["Бестелесный"]},
]


static func namespace_id(pack: String, source_id: int) -> String:
	return "%s:action/%d" % [pack, source_id]


static func empty_result(profile: String, mode: String) -> Dictionary:
	return {"pack": "", "profile": profile, "mode": mode, "ok": true,
		"definitions": {}, "source_map": {}, "grants": {}, "refusals": {},
		"diagnostics": []}


static func _diagnostic(out: Dictionary, code: String, message: String,
		context: Dictionary = {}) -> void:
	var item := {"code": code, "message": message}
	item.merge(context, true)
	out["diagnostics"].append(item)


static func _is_int_value(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT
		and is_finite(float(value)) and float(value) == floor(float(value)))


static func _definition_shape_error(entry: Dictionary) -> String:
	for key in entry:
		if not DEFINITION_FIELDS.has(String(key)):
			return "unknown field: %s" % key
	for key in ["free_action_for", "suppresses", "scales", "excluded_targets", "grants"]:
		if entry.has(key) and typeof(entry[key]) != TYPE_ARRAY:
			return "%s must be a list" % key
	for pair in entry.get("scales", []):
		if typeof(pair) != TYPE_ARRAY or (pair as Array).size() != 2 \
				or typeof(pair[1]) not in [TYPE_INT, TYPE_FLOAT]:
			return "scales entries must be [identity, numeric factor]"
	for key in ["cost_stamina", "cost_ammo", "magnitude"]:
		if entry.has(key) and not _is_int_value(entry[key]):
			return "%s must be an integer" % key
	for key in ["consumes_action", "attack_surcharge", "is_attack", "replace"]:
		if entry.has(key) and typeof(entry[key]) != TYPE_BOOL:
			return "%s must be a boolean" % key
	if entry.has("damage_scale") and typeof(entry["damage_scale"]) not in [TYPE_INT, TYPE_FLOAT]:
		return "damage_scale must be numeric"
	if entry.has("notes") and typeof(entry["notes"]) != TYPE_STRING:
		return "notes must be a string"
	return ""


static func _canonical_id(pack: String, entry: Dictionary,
		source_id: int) -> String:
	if entry.has("shared_id"):
		var shared: Variant = entry["shared_id"]
		if typeof(shared) != TYPE_STRING or not SHARED_IDS.has(String(shared)):
			return ""
		return String(shared)
	if entry.has("canonical_id"):
		var supplied: Variant = entry["canonical_id"]
		var prefix := "%s:action/" % pack
		if typeof(supplied) != TYPE_STRING or not String(supplied).begins_with(prefix):
			return ""
		return String(supplied)
	return namespace_id(pack, source_id)


static func compose(pack: String, profile: String, overlay_v: Variant = {},
		mode: String = STRICT) -> Dictionary:
	var out := {"pack": pack, "profile": profile, "mode": mode, "ok": true,
		"definitions": {}, "source_map": {}, "grants": {}, "refusals": {},
		"diagnostics": []}
	if mode != STRICT and mode != PERMISSIVE:
		_diagnostic(out, "malformed_binding", "unknown action load mode '%s'" % mode)
		out["ok"] = false
		return out
	var overlay: Dictionary = {}
	if typeof(overlay_v) != TYPE_DICTIONARY:
		_diagnostic(out, "malformed_binding", "action overlay must be an object")
	else:
		overlay = (overlay_v as Dictionary).duplicate(true)
	var raw_definitions: Array = GENESIS_DEFAULTS.duplicate(true) 		if profile == "genesis" else []
	var supplied: Variant = overlay.get("definitions", [])
	if typeof(supplied) != TYPE_ARRAY:
		_diagnostic(out, "malformed_binding", "action definitions must be a list")
	else:
		raw_definitions.append_array(supplied)
	var owner_by_canonical: Dictionary = {}
	for position in raw_definitions.size():
		var raw_v: Variant = raw_definitions[position]
		if typeof(raw_v) != TYPE_DICTIONARY:
			_diagnostic(out, "malformed_binding",
				"action definition %d must be an object" % position,
				{"position": position})
			continue
		var raw: Dictionary = raw_v
		var shape_error := _definition_shape_error(raw)
		if shape_error != "":
			_diagnostic(out, "malformed_binding",
				"action definition %d is malformed: %s" % [position, shape_error],
				{"position": position})
			continue
		var source_v: Variant = raw.get("source_id")
		if not _is_int_value(source_v) or int(source_v) < 0:
			_diagnostic(out, "malformed_binding",
				"action definition %d requires a non-negative integer source_id" % position,
				{"position": position})
			continue
		var source_id := int(source_v)
		var canonical_id := _canonical_id(pack, raw, source_id)
		if canonical_id == "":
			_diagnostic(out, "malformed_binding",
				"action source %d has an invalid shared or canonical identity" % source_id,
				{"source_id": source_id})
			continue
		if typeof(raw.get("name")) != TYPE_STRING or String(raw.get("name")) == "":
			_diagnostic(out, "malformed_binding",
				"action source %d requires a non-empty name" % source_id,
				{"source_id": source_id})
			continue
		# Declarative pack data cannot replace either engine-owned shared recipe.
		# In permissive Genesis composition, preserve the installed default.
		var raw_for_action: Dictionary = raw
		if SHARED_IDS.has(canonical_id) and raw.has("recipe"):
			_diagnostic(out, "shared_recipe_override",
				"action '%s' cannot attach or replace its engine-owned recipe" % canonical_id,
				{"source_id": source_id, "canonical_id": canonical_id})
			if owner_by_canonical.has(canonical_id):
				continue
			raw_for_action = raw.duplicate(true)
			raw_for_action.erase("recipe")
		if out["source_map"].has(source_id):
			var old_canonical := String(out["source_map"][source_id])
			if raw_for_action.get("replace") == true:
				out["definitions"].erase(StringName(old_canonical))
				owner_by_canonical.erase(old_canonical)
				out["source_map"].erase(source_id)
			else:
				_diagnostic(out, "identity_collision",
					"source action %d is bound more than once" % source_id,
					{"source_id": source_id})
				out["definitions"].erase(StringName(old_canonical))
				owner_by_canonical.erase(old_canonical)
				out["source_map"].erase(source_id)
				continue
		if owner_by_canonical.has(canonical_id):
			var other := int(owner_by_canonical[canonical_id])
			_diagnostic(out, "identity_collision",
				"canonical action '%s' is claimed by source %d and %d" % [
					canonical_id, other, source_id],
				{"canonical_id": canonical_id, "source_ids": [other, source_id]})
			out["definitions"].erase(StringName(canonical_id))
			out["source_map"].erase(other)
			owner_by_canonical.erase(canonical_id)
			continue
		var target_v: Variant = raw_for_action.get("target", "self")
		if typeof(target_v) == TYPE_STRING:
			var target_key := String(target_v).to_upper()
			if not Action.Target.has(target_key):
				_diagnostic(out, "malformed_binding",
					"action source %d has an invalid target" % source_id,
					{"source_id": source_id})
				continue
		elif not _is_int_value(target_v) or int(target_v) < 0 \
				or int(target_v) >= Action.Target.size():
			_diagnostic(out, "malformed_binding",
				"action source %d has an invalid target" % source_id,
				{"source_id": source_id})
			continue
		var data := raw_for_action.duplicate(true)
		data.erase("shared_id")
		data.erase("canonical_id")
		data.erase("replace")
		data.erase("recipe")
		data["id"] = canonical_id
		var action := Action.from_dict(data)
		if raw_for_action.has("recipe"):
			var validated := DeclarativeActionRecipe.validate(
				raw_for_action["recipe"], action.magnitude)
			if validated["ok"]:
				action.set_declarative_recipe(validated["recipe"])
			else:
				var recipe_message := "action '%s' has invalid declarative recipe: %s" % [
					canonical_id, validated["error"]]
				_diagnostic(out, "invalid_declarative_recipe", recipe_message,
					{"source_id": source_id, "canonical_id": canonical_id})
				action.set_declarative_recipe_error(String(validated["error"]))
		out["definitions"][action.id] = action
		out["source_map"][source_id] = canonical_id
		owner_by_canonical[canonical_id] = source_id

	var required: Variant = overlay.get("required_source_ids", [])
	if typeof(required) != TYPE_ARRAY:
		_diagnostic(out, "malformed_binding", "required_source_ids must be a list")
	else:
		for source_v in required:
			if not _is_int_value(source_v):
				_diagnostic(out, "malformed_binding",
					"required action source identity must be an integer")
			elif not out["source_map"].has(int(source_v)):
				_diagnostic(out, "missing_binding",
					"required action source %d has no unambiguous binding" % int(source_v),
					{"source_id": int(source_v)})

	var grants_v: Variant = overlay.get("grants", {})
	if typeof(grants_v) != TYPE_DICTIONARY:
		_diagnostic(out, "malformed_binding", "action grants must be an object")
		grants_v = {}
	for unit_key in grants_v:
		var unit_id := String(unit_key)
		if not unit_id.begins_with(pack + ":unit/"):
			_diagnostic(out, "malformed_binding",
				"action grant unit '%s' is outside pack '%s'" % [unit_id, pack],
				{"unit": unit_id})
			continue
		var raw_grants: Variant = grants_v[unit_key]
		if typeof(raw_grants) != TYPE_ARRAY:
			_diagnostic(out, "malformed_binding",
				"action grants for '%s' must be a list" % unit_id, {"unit": unit_id})
			continue
		for position in raw_grants.size():
			var grant_v: Variant = raw_grants[position]
			if typeof(grant_v) != TYPE_DICTIONARY:
				_diagnostic(out, "malformed_binding",
					"action grant %d for '%s' must be an object" % [position, unit_id],
					{"unit": unit_id, "position": position})
				continue
			var grant: Dictionary = grant_v
			var source_v: Variant = grant.get("source_id")
			if not _is_int_value(source_v) or int(source_v) < 0:
				_diagnostic(out, "malformed_binding",
					"action grant %d for '%s' requires an integer source_id" % [
						position, unit_id], {"unit": unit_id, "position": position})
				continue
			var source_id := int(source_v)
			var overrides_v: Variant = grant.get("overrides", {})
			if typeof(overrides_v) != TYPE_DICTIONARY:
				_diagnostic(out, "malformed_binding",
					"action grant for '%s' source %d has malformed overrides" % [
						unit_id, source_id], {"unit": unit_id, "source_id": source_id})
				continue
			var overrides: Dictionary = overrides_v
			var forbidden: Array[String] = []
			for key in overrides:
				if not GRANT_OVERRIDE_FIELDS.has(String(key)):
					forbidden.append(String(key))
			forbidden.sort()
			if not forbidden.is_empty():
				_diagnostic(out, "forbidden_override",
					"action grant for '%s' source %d overrides forbidden fields: %s" % [
						unit_id, source_id, ", ".join(forbidden)],
					{"unit": unit_id, "source_id": source_id, "fields": forbidden})
				continue
			if overrides.has("magnitude") and not _is_int_value(overrides["magnitude"]):
				_diagnostic(out, "malformed_binding",
					"action grant magnitude for '%s' source %d must be an integer" % [
						unit_id, source_id], {"unit": unit_id, "source_id": source_id})
				continue
			if not out["source_map"].has(source_id):
				var candidate := namespace_id(pack, source_id)
				var message := "unit '%s' has unresolved required action grant source %d" % [
					unit_id, source_id]
				_diagnostic(out, "unresolved_grant", message,
					{"unit": unit_id, "source_id": source_id,
					 "canonical_id": candidate})
				if not out["refusals"].has(unit_id):
					out["refusals"][unit_id] = {}
				out["refusals"][unit_id][candidate] = message
				continue
			var resolved_canonical := String(out["source_map"][source_id])
			var definition: Action = out["definitions"][StringName(resolved_canonical)]
			var resolved_magnitude := int(overrides.get("magnitude", definition.magnitude))
			if definition.has_declarative_recipe() \
					and DeclarativeActionRecipe.uses_action_magnitude(
						definition.declarative_recipe()) \
					and resolved_magnitude < 0:
				var recipe_message := ("action grant for '%s' source %d makes "
					+ "declarative stamina delta positive") % [unit_id, source_id]
				_diagnostic(out, "invalid_declarative_recipe", recipe_message,
					{"unit": unit_id, "source_id": source_id,
					 "canonical_id": resolved_canonical})
				if not out["refusals"].has(unit_id):
					out["refusals"][unit_id] = {}
				out["refusals"][unit_id][resolved_canonical] = recipe_message
				continue
			if not out["grants"].has(unit_id):
				out["grants"][unit_id] = []
			out["grants"][unit_id].append({
				"canonical_id": resolved_canonical,
				"overrides": overrides.duplicate(true),
			})
	out["ok"] = out["diagnostics"].is_empty() or mode == PERMISSIVE
	return out


static func resolve_grant(definition: Action, overrides: Dictionary) -> Action:
	var data := definition.to_dict()
	for key in overrides:
		data[key] = overrides[key]
	return Action.from_dict(data)
