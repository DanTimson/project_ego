class_name ContentPack
extends RefCounted

## Data tables plus an opcode->handler bindings manifest for one game build.
##
## The manifest exists because the opcode table is NOT stable between builds:
## opcode 30 is magic immunity in Genesis and armour-piercing strike in New
## Horizons. The mapping is content, so each pack carries its own file.
##
## Bindings are JSON, not TOML — Godot has no TOML parser, and a parser both
## languages must match byte for byte is exactly the sort of thing that silently
## diverges. Both parse JSON natively with zero code.

class Binding extends RefCounted:
	var opcode: int = 0
	var name: String = ""
	var hook: String = "UNCLASSIFIED"
	var handler: StringName = &""
	var params: Dictionary = {}
	var uses: int = 0

	func is_bound() -> bool:
		return handler != &""


## What the pack cannot do, split by cause. Conflating these would make the
## number comfortable and useless.
class LoadReport extends RefCounted:
	var pack_id: String = ""
	var total: int = 0
	var bound: int = 0
	var unbound: Array = []      # [[opcode, name, uses], ...]  work not started
	var missing: Array = []      # [[opcode, name, handler], ...] typo or rename
	var orphaned: Array = []     # handler names bound to nothing — dead code
	var errors: Array[String] = []

	func usable() -> int:
		return bound - missing.size()

	func ok() -> bool:
		return errors.is_empty() and unbound.is_empty() and missing.is_empty()

	func summary() -> String:
		return "%s: %d opcodes, %d usable, %d unbound, %d missing handlers, %d orphaned" % [
			pack_id, total, usable(), unbound.size(), missing.size(), orphaned.size()]

	func detail(limit: int = 20) -> String:
		var out: PackedStringArray = [summary()]
		if not errors.is_empty():
			out.append("  errors:")
			for e in errors:
				out.append("    %s" % e)
		if not missing.is_empty():
			out.append("  handlers named by the pack but not implemented:")
			for i in mini(limit, missing.size()):
				out.append("    %5d  %-28s -> %s" % [missing[i][0], missing[i][1], missing[i][2]])
		if not unbound.is_empty():
			var sorted_unbound := unbound.duplicate()
			sorted_unbound.sort_custom(func(a, b): return int(a[2]) > int(b[2]))
			out.append("  unbound, most-used first:")
			for i in mini(limit, sorted_unbound.size()):
				out.append("    %5d  %-28s  %d options"
					% [sorted_unbound[i][0], sorted_unbound[i][1], sorted_unbound[i][2]])
			if sorted_unbound.size() > limit:
				out.append("    ... and %d more" % (sorted_unbound.size() - limit))
		if not orphaned.is_empty():
			out.append("  implemented but bound to nothing: %s" % ", ".join(orphaned))
		return "\n".join(out)


var id: String = ""
var bindings: Dictionary = {}    # opcode:int -> Binding
var tables: Dictionary = {}      # table name -> {index:int -> record}
var loaded_from: String = ""
var version: String = ""
var build: String = ""
var declared_fingerprint: String = ""


func _init(p_id: String = "") -> void:
	id = p_id


## Returns an array of error strings; empty means clean.
func load_bindings(path: String) -> Array[String]:
	var errors: Array[String] = []
	if not FileAccess.file_exists(path):
		errors.append("bindings file not found: %s" % path)
		return errors
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("bindings unreadable: %s" % path)
		return errors
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("bindings malformed: %s" % path)
		return errors

	var payload: Dictionary = parsed
	if String(payload.get("pack", "")) != id:
		errors.append("bindings declare pack '%s', loaded as '%s'"
			% [payload.get("pack", ""), id])
	version = String(payload.get("version", ""))
	build = String(payload.get("build", ""))
	declared_fingerprint = String(payload.get("fingerprint", ""))

	var abilities: Dictionary = payload.get("abilities", {})
	for key in abilities:
		if not String(key).is_valid_int():
			errors.append("non-numeric opcode key '%s'" % key)
			continue
		var entry: Dictionary = abilities[key]
		var b := Binding.new()
		b.opcode = int(String(key))
		b.name = String(entry.get("name", ""))
		b.hook = String(entry.get("hook", "UNCLASSIFIED"))
		b.handler = StringName(String(entry.get("handler", "")))
		b.params = entry.get("params", {})
		b.uses = int(entry.get("uses", 0))
		bindings[b.opcode] = b
	loaded_from = path
	return errors


## Load one converted .var table — the JSON tools/var/eador_var.py emits.
func load_table(name: String, path: String) -> Array[String]:
	var errors: Array[String] = []
	if not FileAccess.file_exists(path):
		errors.append("table %s not found: %s" % [name, path])
		return errors
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("table %s malformed: %s" % [name, path])
		return errors
	var rows: Dictionary = {}
	for r in (parsed as Dictionary).get("records", []):
		rows[int(r["index"])] = r
	tables[name] = rows
	return errors


func report(registry: AbilityRegistry, errors: Array = []) -> LoadReport:
	var rep := LoadReport.new()
	rep.pack_id = id
	for e in errors:
		rep.errors.append(String(e))
	var used: Dictionary = {}
	var opcodes: Array = bindings.keys()
	opcodes.sort()
	for opcode in opcodes:
		var b: Binding = bindings[opcode]
		rep.total += 1
		if not b.is_bound():
			rep.unbound.append([opcode, b.name, b.uses])
			continue
		rep.bound += 1
		used[b.handler] = true
		if not registry.has(b.handler):
			rep.missing.append([opcode, b.name, String(b.handler)])
	for n in registry.names():
		if not used.has(n):
			rep.orphaned.append(String(n))
	rep.orphaned.sort()
	return rep


func snapshot_payload() -> Dictionary:
	var serialized_bindings: Dictionary = {}
	for opcode in bindings:
		var entry: Binding = bindings[opcode]
		serialized_bindings[str(opcode)] = {
			"name": entry.name,
			"hook": entry.hook,
			"handler": String(entry.handler),
			"params": entry.params,
			"uses": entry.uses,
		}
	return {
		"pack": id,
		"version": version,
		"build": build,
		"bindings": serialized_bindings,
		"tables": tables,
	}


func provenance() -> Dictionary:
	var observed := ScenarioContentProvider.canonical_fingerprint(snapshot_payload())
	var out := {"pack": id, "fingerprint": observed}
	if version != "":
		out["version"] = version
	if build != "":
		out["build"] = build
	if declared_fingerprint != "" and declared_fingerprint != observed:
		out["error"] = (
			"content pack fingerprint assertion mismatch: expected '%s', observed '%s'"
			% [declared_fingerprint, observed]
		)
	return out


func binding(opcode: int) -> Binding:
	return bindings.get(opcode)


func record(table: String, index: int) -> Variant:
	return (tables.get(table, {}) as Dictionary).get(index)
