class_name ContentDb
extends RefCounted

## A CONSTRUCTED instance, never a singleton. The simulation takes one as an
## argument; game/autoload/app.gd may hold the currently active one for the UI,
## and that is all an autoload is for. The moment the rules can only run inside a
## live scene tree the headless harness dies, and differential testing with it.

var pack: ContentPack
var registry: AbilityRegistry
var report: ContentPack.LoadReport


func _init(p_pack: ContentPack, p_registry: AbilityRegistry,
		p_report: ContentPack.LoadReport) -> void:
	pack = p_pack
	registry = p_registry
	report = p_report


## `tables` maps a table name to its filename under <pack_dir>/data/.
static func load_pack(pack_id: String, pack_dir: String, registry: AbilityRegistry,
		tables: Dictionary = {}) -> ContentDb:
	var p := ContentPack.new(pack_id)
	var errors: Array[String] = p.load_bindings(pack_dir.path_join("bindings.json"))
	for name in tables:
		errors.append_array(
			p.load_table(String(name), pack_dir.path_join("data").path_join(String(tables[name]))))
	return ContentDb.new(p, registry, p.report(registry, errors))


## Returns [handler: StringName, params: Dictionary]. handler is &"" when the
## opcode is unbound, names a handler we do not implement, or does not exist.
func resolve(opcode: int) -> Array:
	var b: ContentPack.Binding = pack.binding(opcode)
	if b == null or not b.is_bound() or not registry.has(b.handler):
		return [&"", {}]
	return [b.handler, b.params]
