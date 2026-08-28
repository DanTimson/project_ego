class_name GenesisDeathReplacementResolver
extends RefCounted

## Profile/content-qualified Genesis death replacement (CX-016).
## The marker and recovered exact source-record edge remain behind this resolver.

const PROFILE_GENESIS := "genesis"
const COMPATIBILITY_GENESIS := "genesis"
const COMPATIBILITY_NEW_HORIZONS := "new_horizons"
const COMPATIBILITY_UNSPECIFIED := "unspecified"
const STRICT := "strict"
const PERMISSIVE := "permissive"
# RECOVERED Genesis-only applicability marker; no NH meaning is asserted.
const GENESIS_REPLACEMENT_MARKER := 0x5B
const GENESIS_SOURCE_BY_TIER := {1: 21, 2: 37, 3: 56, 4: 65}

var profile: String = ""
var provider: Variant = null
var mode: String = STRICT
var diagnostics: Array = []
var compatibility: String = COMPATIBILITY_UNSPECIFIED
var compatibility_source: String = "unspecified"
var compatibility_override: bool = false
var configuration_error: String = ""
var _resolved: Dictionary = {}


func _init(p_profile: String, p_provider: Variant = null,
		p_compatibility_override: String = "", p_mode: String = STRICT) -> void:
	profile = p_profile
	provider = p_provider
	mode = p_mode
	if mode not in [STRICT, PERMISSIVE]:
		configuration_error = "unknown death replacement load mode '%s'" % mode
		return
	_normalize_compatibility(p_compatibility_override)
	if profile == PROFILE_GENESIS:
		_validate_genesis_configuration()
	if mode == STRICT:
		var errors: Array = diagnostics.filter(
			func(item): return String(item.get("severity", "")) == "error")
		if not errors.is_empty():
			var messages: PackedStringArray = []
			for item in errors:
				messages.append(String(item.get("message", "configuration error")))
			configuration_error = "death replacement composition failed: %s" % "; ".join(messages)


static func source_record_for_tier(tier: int) -> int:
	return int(GENESIS_SOURCE_BY_TIER.get(tier, -1))


static func _diagnostic(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var out := {"code": code, "severity": "error", "message": message}
	out.merge(details, true)
	return out


func _normalize_compatibility(override_value: String) -> void:
	var normalized := override_value.strip_edges().to_lower()
	if normalized != "":
		if normalized != COMPATIBILITY_GENESIS:
			configuration_error = "unknown content compatibility override '%s'" % normalized
			return
		compatibility = COMPATIBILITY_GENESIS
		compatibility_source = "load_override"
		compatibility_override = true
		diagnostics.append({
			"code": "explicit_compatibility_override", "severity": "info",
			"message": "content compatibility explicitly overridden to genesis",
			"compatibility": COMPATIBILITY_GENESIS, "source": "load_override",
		})
		return
	var raw: Variant = (
		provider.call("content_compatibility")
		if provider != null and provider.has_method("content_compatibility")
		else {}
	)
	if typeof(raw) != TYPE_DICTIONARY:
		raw = {}
	compatibility = String(raw.get("identity", COMPATIBILITY_UNSPECIFIED)).strip_edges().to_lower()
	compatibility_source = String(raw.get("source", "unspecified"))
	if compatibility not in [COMPATIBILITY_GENESIS, COMPATIBILITY_NEW_HORIZONS,
			COMPATIBILITY_UNSPECIFIED]:
		diagnostics.append(_diagnostic("malformed_compatibility_contract",
			"content compatibility identity '%s' is not supported" % compatibility,
			{"compatibility": compatibility, "source": compatibility_source}))
		compatibility = COMPATIBILITY_UNSPECIFIED


func normalized_state() -> Dictionary:
	return {
		"profile": profile, "mode": mode,
		"content_compatibility": compatibility,
		"compatibility_source": compatibility_source,
		"compatibility_override": compatibility_override,
		"diagnostics": diagnostics.duplicate(true),
	}


func _validate_genesis_configuration() -> void:
	if compatibility != COMPATIBILITY_GENESIS:
		diagnostics.append(_diagnostic("genesis_content_compatibility_mismatch",
			"Genesis rules require Genesis-compatible content; got %s" % compatibility,
			{"compatibility": compatibility,
			"compatibility_source": compatibility_source}))
		return
	if provider == null or not provider.has_method("resolve_source_definition"):
		diagnostics.append(_diagnostic("missing_source_definition_provider",
			"Genesis-compatible content provider cannot resolve qualified source records"))
		return
	for tier in GENESIS_SOURCE_BY_TIER:
		var source_record := int(GENESIS_SOURCE_BY_TIER[tier])
		var resolved: Variant = provider.call(
			"resolve_source_definition", "unit", source_record)
		if typeof(resolved) != TYPE_DICTIONARY:
			diagnostics.append(_diagnostic("unresolved_genesis_replacement_target",
				"Genesis replacement source record %d (tier %d) did not resolve"
				% [source_record, tier],
				{"tier": tier, "source_record": source_record}))
			continue
		var canonical_id: Variant = resolved.get("content_id")
		var definition_v: Variant = resolved.get("definition")
		if (typeof(canonical_id) != TYPE_STRING or String(canonical_id) == ""
				or typeof(definition_v) != TYPE_DICTIONARY):
			diagnostics.append(_diagnostic("malformed_genesis_replacement_target",
				"Genesis replacement source record %d (tier %d) resolved malformed data"
				% [source_record, tier],
				{"tier": tier, "source_record": source_record}))
			continue
		var definition: Dictionary = definition_v.duplicate(true)
		if (typeof(definition.get("name")) != TYPE_STRING
				or String(definition.get("name")) == ""):
			diagnostics.append(_diagnostic("malformed_genesis_replacement_target",
				"Genesis replacement source record %d (tier %d) has no display name"
				% [source_record, tier],
				{"tier": tier, "source_record": source_record}))
			continue
		var built_modifiers: Array = []
		var malformed := false
		for modifier_v in definition.get("modifiers", []):
			if modifier_v is Modifier:
				built_modifiers.append(modifier_v)
			elif (typeof(modifier_v) == TYPE_DICTIONARY
					and (modifier_v as Dictionary).has("handler")):
				var modifier: Dictionary = modifier_v
				var hook_name := String(modifier.get("hook", "STAT_PASSIVE"))
				if not Modifier.Hook.has(hook_name):
					malformed = true
					break
				built_modifiers.append(Modifier.make(
					int(modifier.get("ability", 0)),
					StringName(String(modifier["handler"])),
					Modifier.Hook[hook_name], int(modifier.get("power", 0)),
					modifier.get("params", {}).duplicate(true),
					String(modifier.get("source", modifier["handler"]))))
			else:
				malformed = true
				break
		if malformed:
			diagnostics.append(_diagnostic("malformed_genesis_replacement_target",
				"Genesis replacement source record %d (tier %d) is malformed"
				% [source_record, tier],
				{"tier": tier, "source_record": source_record}))
			continue
		definition["modifiers"] = built_modifiers
		definition["content_id"] = String(canonical_id)
		definition["definition_id"] = source_record
		_resolved[tier] = definition


static func _has_marker(unit: Combatant) -> bool:
	for effect in unit.statuses:
		for modifier in effect.modifiers:
			if int(modifier.ability) == GENESIS_REPLACEMENT_MARKER:
				return true
	return false


func decision_for(unit: Combatant) -> Dictionary:
	if profile != PROFILE_GENESIS or not _has_marker(unit):
		return {"status": "not_applicable"}
	var tier := int(unit.original_definition.get("tier", unit.tier))
	var source_record := source_record_for_tier(tier)
	if source_record < 0:
		return {"status": "unresolved",
			"error": "Genesis death replacement requires original tier 1..4"}
	if not _resolved.has(tier):
		return {"status": "unresolved",
			"error": "Genesis replacement source record %d for tier %d is unresolved"
				% [source_record, tier],
			"tier": tier, "source_record": source_record}
	return {"status": "resolved", "definition": _resolved[tier].duplicate(true),
		"definition_id": source_record, "tier": tier}
