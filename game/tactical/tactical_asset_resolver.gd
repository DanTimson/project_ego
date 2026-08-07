class_name TacticalAssetResolver
extends RefCounted

const DEFAULT_MANIFEST := "res://local_assets/egograbber/manifest.json"
const DEFAULT_UNIT_MAP := "res://local_assets/egograbber/unit_asset_map.json"

var manifest_path: String = ""
var paths_by_key: Dictionary = {}
var unit_keys: Dictionary = {}


func configure(p_manifest_path: String = "", p_unit_map_path: String = "") -> bool:
	var requested_manifest := p_manifest_path
	if requested_manifest == "":
		requested_manifest = OS.get_environment("EGO_ASSET_MANIFEST")
	if requested_manifest == "":
		requested_manifest = DEFAULT_MANIFEST
	var loaded := load_manifest(requested_manifest)
	var requested_map := p_unit_map_path
	if requested_map == "":
		requested_map = OS.get_environment("EGO_ASSET_UNIT_MAP")
	if requested_map == "":
		requested_map = DEFAULT_UNIT_MAP
	load_unit_map(requested_map)
	return loaded


func load_manifest(path: String) -> bool:
	manifest_path = ""
	paths_by_key.clear()
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != 1:
		return false
	var assets_v: Variant = parsed.get("assets", [])
	if typeof(assets_v) != TYPE_ARRAY:
		return false
	var assets: Array = assets_v.duplicate(true)
	assets.sort_custom(func(a: Dictionary, b: Dictionary):
		var a_key := "%s\n%s" % [a.get("id", ""), a.get("path", "")]
		var b_key := "%s\n%s" % [b.get("id", ""), b.get("path", "")]
		return a_key < b_key)
	var base := path.get_base_dir()
	for entry_v in assets:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		var key := String(entry.get("id", ""))
		var relative_path := String(entry.get("path", ""))
		if key == "" or relative_path == "" or paths_by_key.has(key):
			continue
		paths_by_key[key] = base.path_join(relative_path).simplify_path()
	manifest_path = path
	return true


func load_unit_map(path: String) -> bool:
	unit_keys.clear()
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != 1:
		return false
	var units_v: Variant = parsed.get("units", {})
	if typeof(units_v) != TYPE_DICTIONARY:
		return false
	var ids: Array = units_v.keys()
	ids.sort()
	for instance_id in ids:
		var key := String(units_v[instance_id])
		if key != "":
			unit_keys[String(instance_id)] = key
	return true


func asset_path(logical_key: String) -> String:
	return String(paths_by_key.get(logical_key, ""))


func logical_key_for_unit(unit: Combatant) -> String:
	return String(unit_keys.get(unit.instance_id, ""))


func texture_for_unit(unit: Combatant) -> Texture2D:
	var key := logical_key_for_unit(unit)
	return texture_for_key(key) if key != "" else null


func texture_for_key(logical_key: String) -> Texture2D:
	var path := asset_path(logical_key)
	if path == "" or not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)
