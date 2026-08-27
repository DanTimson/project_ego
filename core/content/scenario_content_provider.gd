class_name ScenarioContentProvider
extends RefCounted

## Minimal scenario composition provider for synthetic definitions and callers.
## ContentDb implements the same two-method seam for locally loaded packs.

var pack_id: String = ""
var version: String = ""
var build: String = ""
var asserted_fingerprint: String = ""
## Last observed value, retained for fixture generation and diagnostics.
## content_provenance() always refreshes it from the current snapshot.
var fingerprint: String = ""
var _definitions: Dictionary = {}
var _action_overlay: Dictionary = {}


func _init(p_pack: String = "", p_definitions: Dictionary = {},
		p_version: String = "", p_build: String = "",
		p_fingerprint: String = "", p_action_overlay: Dictionary = {}) -> void:
	pack_id = p_pack
	version = p_version
	build = p_build
	_definitions = p_definitions.duplicate(true)
	asserted_fingerprint = p_fingerprint
	_action_overlay = p_action_overlay.duplicate(true)
	fingerprint = canonical_fingerprint(snapshot_payload())


func snapshot_payload() -> Dictionary:
	var payload := {
		"pack": pack_id,
		"version": version,
		"build": build,
		"definitions": _definitions,
	}
	if not _action_overlay.is_empty():
		payload["actions"] = _action_overlay
	return payload


static func _canonical_json_value(value: Variant) -> Variant:
	# Godot parses every JSON number as a float, while Python preserves integral
	# JSON numbers as ints. Normalize integral floats so both loaders hash the
	# same semantic snapshot. JSON object keys are strings in either runtime.
	match typeof(value):
		TYPE_DICTIONARY:
			var object: Dictionary = {}
			for key in value:
				object[str(key)] = _canonical_json_value(value[key])
			return object
		TYPE_ARRAY:
			var array: Array = []
			for item in value:
				array.append(_canonical_json_value(item))
			return array
		TYPE_FLOAT:
			var number: float = value
			if is_finite(number) and number == floor(number):
				return int(number)
	return value


static func canonical_fingerprint(value: Variant) -> String:
	# JSON sorts dictionary keys recursively, so insertion/enumeration order and
	# filesystem order cannot affect the digest.
	var normalized: Variant = _canonical_json_value(value)
	var encoded: PackedByteArray = JSON.stringify(normalized, "", true, true).to_utf8_buffer()
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(encoded)
	return "sha256:" + context.finish().hex_encode()


func content_provenance() -> Dictionary:
	var observed: String = canonical_fingerprint(snapshot_payload())
	fingerprint = observed
	var out: Dictionary = {"pack": pack_id, "fingerprint": observed}
	if version != "":
		out["version"] = version
	if build != "":
		out["build"] = build
	if asserted_fingerprint != "" and asserted_fingerprint != observed:
		out["error"] = (
			"content fingerprint assertion mismatch: expected '%s', observed '%s'"
			% [asserted_fingerprint, observed]
		)
	return out


func resolve_definition(content_id: String) -> Variant:
	var definition: Variant = _definitions.get(content_id)
	return definition.duplicate(true) if typeof(definition) == TYPE_DICTIONARY else null


func compose_actions(profile: String, mode: String = ActionDefinitionComposer.STRICT) -> Dictionary:
	return ActionDefinitionComposer.compose(pack_id, profile, _action_overlay, mode)
