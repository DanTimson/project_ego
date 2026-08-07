# gdlint: disable=max-returns
class_name TacticalAssetResolver
extends RefCounted

const DEFAULT_INDEX := "res://.local/eador_assets/index.json"
const DEFAULT_MAPPING := "res://.local/eador_assets/mapping.json"

var index_path: String = ""
var mapping_path: String = ""
var paths_by_key: Dictionary = {}
var types_by_key: Dictionary = {}
var content_keys: Dictionary = {}
var instance_keys: Dictionary = {}
var status_messages: Array[String] = []


func configure(p_index_path: String = "", p_mapping_path: String = "") -> bool:
	status_messages.clear()
	var requested_index := p_index_path
	if requested_index == "":
		requested_index = OS.get_environment("EGO_ASSET_INDEX")
	if requested_index == "":
		requested_index = DEFAULT_INDEX
	var loaded := load_index(requested_index)
	var requested_mapping := p_mapping_path
	if requested_mapping == "":
		requested_mapping = OS.get_environment("EGO_ASSET_MAPPING")
	if requested_mapping == "":
		requested_mapping = DEFAULT_MAPPING
	if loaded:
		load_mapping(requested_mapping)
	else:
		content_keys.clear()
		instance_keys.clear()
	return loaded


func load_index(path: String) -> bool:
	index_path = ""
	paths_by_key.clear()
	types_by_key.clear()
	if not FileAccess.file_exists(path):
		_report("local tactical asset index absent; using placeholders: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != 1:
		_report("local tactical asset index is malformed or unsupported: %s" % path)
		return false
	var assets_v: Variant = parsed.get("assets")
	if typeof(assets_v) != TYPE_ARRAY:
		_report("local tactical asset index has no assets array: %s" % path)
		return false
	var base := path.get_base_dir().simplify_path()
	var pending_paths: Dictionary = {}
	var pending_types: Dictionary = {}
	for entry_v in assets_v:
		if typeof(entry_v) != TYPE_DICTIONARY:
			return _reject_index(path, "asset entry is not an object")
		var entry: Dictionary = entry_v
		var key := String(entry.get("key", ""))
		var archive := String(entry.get("archive", ""))
		var source_id := String(entry.get("source_id", ""))
		var asset_type := String(entry.get("type", ""))
		var relative := _safe_relative(String(entry.get("path", "")))
		if not _valid_logical_key(key) or key != "%s:%s" % [archive, source_id]:
			return _reject_index(path, "invalid or inconsistent logical key")
		if pending_paths.has(key):
			return _reject_index(path, "duplicate logical key: %s" % key)
		if asset_type not in ["image", "raw"]:
			return _reject_index(path, "unsupported asset type for %s" % key)
		if relative == "":
			return _reject_index(path, "unsafe asset path for %s" % key)
		var resolved := base.path_join(relative).simplify_path()
		if not _inside(resolved, base) or not FileAccess.file_exists(resolved):
			return _reject_index(path, "missing or escaping asset file for %s" % key)
		pending_paths[key] = resolved
		pending_types[key] = asset_type
	paths_by_key = pending_paths
	types_by_key = pending_types
	index_path = path
	_report("loaded %d local tactical assets" % paths_by_key.size())
	return true


func load_mapping(path: String) -> bool:
	mapping_path = ""
	content_keys.clear()
	instance_keys.clear()
	if not FileAccess.file_exists(path):
		_report("local tactical mapping absent; using placeholders: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != 1:
		_report("local tactical mapping is malformed or unsupported: %s" % path)
		return false
	var content := _mapping_section(parsed.get("content"), true)
	if not bool(content["ok"]):
		_report("local tactical mapping rejected: %s" % content["reason"])
		return false
	var instances := _mapping_section(parsed.get("instances"), false)
	if not bool(instances["ok"]):
		_report("local tactical mapping rejected: %s" % instances["reason"])
		return false
	content_keys = content["values"]
	instance_keys = instances["values"]
	mapping_path = path
	_report("loaded %d content and %d instance tactical mappings" % [
		content_keys.size(), instance_keys.size()])
	return true


func _mapping_section(section_v: Variant, canonical: bool) -> Dictionary:
	if typeof(section_v) != TYPE_ARRAY:
		return {"ok": false, "reason": "%s must be an array" % [
			"content" if canonical else "instances"]}
	var values: Dictionary = {}
	for entry_v in section_v:
		if typeof(entry_v) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "mapping entry is not an object"}
		var id := String(entry_v.get("id", ""))
		var asset := String(entry_v.get("asset", ""))
		if not _valid_identity(id, canonical):
			return {"ok": false, "reason": "invalid mapping identity: %s" % id}
		if values.has(id):
			return {"ok": false, "reason": "duplicate mapping identity: %s" % id}
		if not _valid_logical_key(asset) or not paths_by_key.has(asset):
			return {"ok": false, "reason": "unknown asset reference: %s" % asset}
		if String(types_by_key[asset]) != "image":
			return {"ok": false, "reason": "mapped asset is not an image: %s" % asset}
		values[id] = asset
	return {"ok": true, "reason": "", "values": values}


func asset_path(logical_key: String) -> String:
	return String(paths_by_key.get(logical_key, ""))


func logical_key_for_unit(unit: Combatant) -> String:
	if unit.content_id != "" and content_keys.has(unit.content_id):
		return String(content_keys[unit.content_id])
	return String(instance_keys.get(unit.instance_id, ""))


func asset_source_for_unit(unit: Combatant) -> String:
	var key := logical_key_for_unit(unit)
	return "local:%s" % key if key != "" else "placeholder"


func texture_for_unit(unit: Combatant) -> Texture2D:
	var key := logical_key_for_unit(unit)
	return texture_for_key(key) if key != "" else null


func texture_for_key(logical_key: String) -> Texture2D:
	if String(types_by_key.get(logical_key, "")) != "image":
		return null
	var path := asset_path(logical_key)
	if path == "" or not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		_report("could not load local tactical image %s (error %d)" % [path, error])
		return null
	return ImageTexture.create_from_image(image)


func status_text() -> String:
	return " | ".join(status_messages)


func _safe_relative(raw: String) -> String:
	if raw == "":
		return ""
	var normalized := raw.replace("\\", "/")
	if normalized.begins_with("/") or normalized.contains("://"):
		return ""
	var drive := RegEx.new()
	drive.compile("^[A-Za-z]:/")
	if drive.search(normalized) != null:
		return ""
	var clean: Array[String] = []
	for component in normalized.split("/"):
		if component in ["", ".", ".."]:
			return ""
		clean.append(component)
	return "/".join(clean)


func _inside(path: String, root: String) -> bool:
	return path == root or path.begins_with(root.trim_suffix("/") + "/")


func _valid_logical_key(key: String) -> bool:
	var colon := key.find(":")
	if colon <= 0 or colon == key.length() - 1 or key.find(":", colon + 1) >= 0:
		return false
	var archive := key.left(colon)
	var archive_re := RegEx.new()
	archive_re.compile("^[A-Za-z0-9][A-Za-z0-9_.-]*$")
	if archive_re.search(archive) == null:
		return false
	var source := key.substr(colon + 1)
	return _safe_relative(source) == source


func _valid_identity(id: String, canonical: bool) -> bool:
	if canonical:
		var parsed := ContentId.parse(id)
		return parsed != null and parsed.kind == "unit"
	var instance_re := RegEx.new()
	instance_re.compile("^[A-Za-z0-9][A-Za-z0-9_.:-]*$")
	return instance_re.search(id) != null


func _reject_index(path: String, reason: String) -> bool:
	paths_by_key.clear()
	types_by_key.clear()
	_report("local tactical asset index rejected (%s): %s" % [path, reason])
	return false


func _report(message: String) -> void:
	status_messages.append(message)
	print("TacticalAssetResolver: %s" % message)
