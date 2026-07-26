extends Node

var _root_res: String = "" # always res://...
var _assets := {} # id -> {type, path, res_path}

func load_manifest(manifest_res_path: String) -> void:
	_assets.clear()

	if not manifest_res_path.begins_with("res://"):
		push_error("VFS: manifest must be res:// path, got: " + manifest_res_path)
		return

	var f := FileAccess.open(manifest_res_path, FileAccess.READ)
	if f == null:
		push_error("VFS: cannot open manifest: " + manifest_res_path)
		return

	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("VFS: invalid JSON: " + manifest_res_path)
		return

	var root := str(parsed.get("root", "")).replace("\\", "/")
	if root.is_empty():
		push_error("VFS: manifest missing root")
		return

	_root_res = root if root.begins_with("res://") else ("res://".path_join(root))
	if not _root_res.ends_with("/"):
		_root_res += "/"

	var arr = parsed.get("assets", [])
	if typeof(arr) != TYPE_ARRAY:
		push_error("VFS: manifest assets must be array")
		return

	for a in arr:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var id := str(a.get("id", ""))
		var typ := str(a.get("type", ""))
		var rel := str(a.get("path", "")).replace("\\", "/")
		if id.is_empty() or typ.is_empty() or rel.is_empty():
			continue

		var res_path := _root_res.path_join(rel)
		_assets[id] = {"type": typ, "path": rel, "res_path": res_path}

func list_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in _assets.keys():
		ids.append(k)
	ids.sort()
	return ids

func get_asset(id: String) -> Dictionary:
	return _assets.get(id, {})

func resolve_res_path(id: String) -> String:
	return str(get_asset(id).get("res_path", ""))
