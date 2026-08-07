# gdlint: disable=max-returns
class_name TacticalAssetResolver
extends RefCounted

const DEFAULT_INDEX := "res://.local/eador_assets/index.json"
const DEFAULT_MAPPING := "res://.local/eador_assets/mapping.json"
const CATEGORY_UNITS := "units"
const CATEGORY_SHADOWS := "shadows"
const CATEGORY_PORTRAITS := "portraits"
const CATEGORY_TERRAIN := "terrain"
const CATEGORY_DECORATIONS := "decorations"
const CATEGORY_UI := "ui"
const IDENTITY_CATEGORIES := [CATEGORY_UNITS, CATEGORY_SHADOWS, CATEGORY_PORTRAITS]
const NAMED_CATEGORIES := [CATEGORY_TERRAIN, CATEGORY_DECORATIONS, CATEGORY_UI]

var index_path: String = ""
var mapping_path: String = ""
var paths_by_key: Dictionary = {}
var types_by_key: Dictionary = {}
# Slice-2 aliases remain available and always refer to the unit category.
var content_keys: Dictionary = {}
var instance_keys: Dictionary = {}
var content_keys_by_category: Dictionary = {}
var instance_keys_by_category: Dictionary = {}
var named_keys_by_category: Dictionary = {}
var status_messages: Array[String] = []
var _texture_cache: Dictionary = {}


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
		_clear_mapping()
	return loaded


func load_index(path: String) -> bool:
	index_path = ""
	paths_by_key.clear()
	types_by_key.clear()
	_texture_cache.clear()
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
	_clear_mapping()
	mapping_path = ""
	if not FileAccess.file_exists(path):
		_report("local tactical mapping absent; using placeholders: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_report("local tactical mapping is malformed or unsupported: %s" % path)
		return false
	var version := int(parsed.get("version", 0))
	var pending_content: Dictionary = {}
	var pending_instances: Dictionary = {}
	var pending_named: Dictionary = {}
	if version == 1:
		var legacy := _parse_identity_category(parsed)
		if not bool(legacy["ok"]):
			return _reject_mapping(String(legacy["reason"]))
		pending_content[CATEGORY_UNITS] = legacy["content"]
		pending_instances[CATEGORY_UNITS] = legacy["instances"]
	elif version == 2:
		for category in IDENTITY_CATEGORIES:
			var identity := _parse_identity_category(parsed.get(category))
			if not bool(identity["ok"]):
				return _reject_mapping("%s: %s" % [category, identity["reason"]])
			pending_content[category] = identity["content"]
			pending_instances[category] = identity["instances"]
		for category in NAMED_CATEGORIES:
			var named := _parse_named_category(parsed.get(category), category)
			if not bool(named["ok"]):
				return _reject_mapping("%s: %s" % [category, named["reason"]])
			pending_named[category] = named["values"]
	else:
		_report("local tactical mapping is malformed or unsupported: %s" % path)
		return false
	content_keys_by_category = pending_content
	instance_keys_by_category = pending_instances
	named_keys_by_category = pending_named
	content_keys = content_keys_by_category.get(CATEGORY_UNITS, {})
	instance_keys = instance_keys_by_category.get(CATEGORY_UNITS, {})
	mapping_path = path
	_report("loaded local tactical visual mapping version %d" % version)
	return true


func _parse_identity_category(section_v: Variant) -> Dictionary:
	if typeof(section_v) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "category must be an object"}
	var content := _mapping_section(section_v.get("content"), true)
	if not bool(content["ok"]):
		return content
	var instances := _mapping_section(section_v.get("instances"), false)
	if not bool(instances["ok"]):
		return instances
	return {"ok": true, "reason": "", "content": content["values"],
		"instances": instances["values"]}


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
		var asset_error := _mapped_image_error(asset)
		if asset_error != "":
			return {"ok": false, "reason": asset_error}
		values[id] = asset
	return {"ok": true, "reason": "", "values": values}


func _parse_named_category(section_v: Variant, _category: String) -> Dictionary:
	if typeof(section_v) != TYPE_ARRAY:
		return {"ok": false, "reason": "category must be an array"}
	var values: Dictionary = {}
	for entry_v in section_v:
		if typeof(entry_v) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "mapping entry is not an object"}
		var id := String(entry_v.get("id", ""))
		var asset := String(entry_v.get("asset", ""))
		if not _valid_named_id(id):
			return {"ok": false, "reason": "invalid visual slot: %s" % id}
		if values.has(id):
			return {"ok": false, "reason": "duplicate visual slot: %s" % id}
		var asset_error := _mapped_image_error(asset)
		if asset_error != "":
			return {"ok": false, "reason": asset_error}
		values[id] = asset
	return {"ok": true, "reason": "", "values": values}


func _mapped_image_error(asset: String) -> String:
	if not _valid_logical_key(asset) or not paths_by_key.has(asset):
		return "unknown asset reference: %s" % asset
	if String(types_by_key[asset]) != "image":
		return "mapped asset is not an image: %s" % asset
	return ""


func asset_path(logical_key: String) -> String:
	return String(paths_by_key.get(logical_key, ""))


func logical_key_for_unit(unit: Combatant, category: String = CATEGORY_UNITS) -> String:
	var category_content: Dictionary = content_keys_by_category.get(category, {})
	if unit.content_id != "" and category_content.has(unit.content_id):
		return String(category_content[unit.content_id])
	var category_instances: Dictionary = instance_keys_by_category.get(category, {})
	return String(category_instances.get(unit.instance_id, ""))


func logical_key_for_named(category: String, id: String) -> String:
	var category_values: Dictionary = named_keys_by_category.get(category, {})
	return String(category_values.get(id, ""))


func logical_keys_for_category(category: String) -> Array[String]:
	var values: Dictionary = named_keys_by_category.get(category, {})
	var ids: Array = values.keys()
	ids.sort()
	var result: Array[String] = []
	for id in ids:
		result.append(String(values[id]))
	return result


func asset_source_for_unit(unit: Combatant, category: String = CATEGORY_UNITS) -> String:
	var key := logical_key_for_unit(unit, category)
	return "local:%s" % key if key != "" else "placeholder"


func texture_for_unit(unit: Combatant) -> Texture2D:
	return texture_for_unit_category(unit, CATEGORY_UNITS)


func texture_for_shadow(unit: Combatant) -> Texture2D:
	return texture_for_unit_category(unit, CATEGORY_SHADOWS)


func texture_for_portrait(unit: Combatant) -> Texture2D:
	return texture_for_unit_category(unit, CATEGORY_PORTRAITS)


func texture_for_unit_category(unit: Combatant, category: String) -> Texture2D:
	var key := logical_key_for_unit(unit, category)
	return texture_for_key(key) if key != "" else null


func texture_for_named(category: String, id: String) -> Texture2D:
	var key := logical_key_for_named(category, id)
	return texture_for_key(key) if key != "" else null


func texture_for_key(logical_key: String) -> Texture2D:
	if _texture_cache.has(logical_key):
		return _texture_cache[logical_key]
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
	apply_color_key(image)
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[logical_key] = texture
	return texture


func apply_color_key(image: Image) -> int:
	# Direct inspection found an exact RGB(255, 0, 255) reserved matte across
	# sprites, both shadow families, and keyed terrain/decorations.  Clear only
	# that exact value; near-magenta artwork and every other interior color stay.
	if image.is_empty():
		return 0
	image.convert(Image.FORMAT_RGBA8)
	var cleared := 0
	for y in image.get_height():
		for x in image.get_width():
			var point := Vector2i(x, y)
			if _is_exact_matte(image.get_pixelv(point)):
				image.set_pixelv(point, Color(1.0, 0.0, 1.0, 0.0))
				cleared += 1
	return cleared


func _is_exact_matte(color: Color) -> bool:
	return color.r8 == 255 and color.g8 == 0 and color.b8 == 255


func status_text() -> String:
	return " | ".join(status_messages)


func _clear_mapping() -> void:
	content_keys.clear()
	instance_keys.clear()
	content_keys_by_category.clear()
	instance_keys_by_category.clear()
	named_keys_by_category.clear()


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
	return _valid_named_id(id)


func _valid_named_id(id: String) -> bool:
	var instance_re := RegEx.new()
	instance_re.compile("^[A-Za-z0-9][A-Za-z0-9_.:-]*$")
	return instance_re.search(id) != null


func _reject_index(path: String, reason: String) -> bool:
	paths_by_key.clear()
	types_by_key.clear()
	_texture_cache.clear()
	_report("local tactical asset index rejected (%s): %s" % [path, reason])
	return false


func _reject_mapping(reason: String) -> bool:
	_clear_mapping()
	_report("local tactical mapping rejected: %s" % reason)
	return false


func _report(message: String) -> void:
	status_messages.append(message)
	print("TacticalAssetResolver: %s" % message)
