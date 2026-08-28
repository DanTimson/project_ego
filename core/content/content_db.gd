class_name ContentDb
extends RefCounted

## A CONSTRUCTED instance, never a singleton. The simulation takes one as an
## argument; game/autoload/app.gd may hold the currently active one for the UI,
## and that is all an autoload is for. The moment the rules can only run inside a
## live scene tree the headless harness dies, and differential testing with it.

var pack: ContentPack
var registry: AbilityRegistry
var report: ContentPack.LoadReport
var _active_action_composition: Dictionary = {}


func _init(p_pack: ContentPack, p_registry: AbilityRegistry,
		p_report: ContentPack.LoadReport) -> void:
	pack = p_pack
	registry = p_registry
	report = p_report


## `tables` maps a table name to its filename under <pack_dir>/data/.
static func load_pack(pack_id: String, pack_dir: String, registry: AbilityRegistry,
		tables: Dictionary = {}, legacy_profile: String = "") -> ContentDb:
	var p := ContentPack.new(pack_id)
	var errors: Array[String] = p.load_bindings(pack_dir.path_join("bindings.json"))
	for name in tables:
		errors.append_array(
			p.load_table(String(name), pack_dir.path_join("data").path_join(String(tables[name]))))
	var inherited := legacy_profile.strip_edges().to_lower()
	if inherited != "":
		if inherited not in ["genesis", "new_horizons"]:
			errors.append("unsupported legacy compatibility profile '%s'" % inherited)
		elif p.compatibility_source == "unspecified":
			p.compatibility = inherited
			p.compatibility_source = "legacy_profile"
	return ContentDb.new(p, registry, p.report(registry, errors))


## Returns [handler: StringName, params: Dictionary]. handler is &"" when the
## opcode is unbound, names a handler we do not implement, or does not exist.
func resolve(opcode: int) -> Array:
	var b: ContentPack.Binding = pack.binding(opcode)
	if b == null or not b.is_bound() or not registry.has(b.handler):
		return [&"", {}]
	return [b.handler, b.params]


func resolve_semantics(opcode: int) -> Array[int]:
	## Resolve only this pack-qualified binding's semantic dimension.
	var b: ContentPack.Binding = pack.binding(opcode)
	if b == null:
		return []
	return b.semantics.duplicate()


## Scenario composition seam.  This adapts the existing pack and roster loader;
## rules never load or branch on pack identity.
func content_provenance() -> Dictionary:
	return pack.provenance()


func content_compatibility() -> Dictionary:
	return {"identity": pack.compatibility, "source": pack.compatibility_source}


func resolve_source_definition(kind: String, source_record: int) -> Variant:
	var canonical_id := "%s:%s/%d" % [pack.id, kind, source_record]
	var definition: Variant = resolve_definition(canonical_id)
	if typeof(definition) != TYPE_DICTIONARY:
		return null
	return {"content_id": canonical_id, "definition": definition}


func compose_actions(profile: String,
		mode: String = ActionDefinitionComposer.STRICT) -> Dictionary:
	_active_action_composition = ActionDefinitionComposer.compose(
		pack.id, profile, pack.action_overlay, mode)
	return _active_action_composition


func resolve_action_grant(source_id: int, magnitude: Variant) -> Variant:
	var source_map: Dictionary = _active_action_composition.get("source_map", {})
	if not source_map.has(source_id):
		return null
	var canonical_id := String(source_map[source_id])
	if canonical_id == "shield_bash" and typeof(magnitude) != TYPE_INT:
		return {
			"source_id": source_id,
			"error": "action grant source %d (%s) requires integer Quantity" % [
				source_id, canonical_id],
		}
	var overrides := {"magnitude": magnitude} if canonical_id == "shield_bash" else {}
	return {"source_id": source_id, "overrides": overrides}


func resolve_definition(content_id: String) -> Variant:
	var built: Roster.Built = Roster.new(self).build(content_id)
	if built == null:
		return null
	if not built.complete():
		var reasons: PackedStringArray = []
		for unresolved in built.unresolved.slice(0, 3):
			reasons.append(str(unresolved))
		push_error("canonical definition '%s' is incomplete: %s"
			% [content_id, "; ".join(reasons)])
		return null
	var unit := built.unit
	var modifiers: Array = []
	for modifier in unit.modifiers:
		var serialized := {
			"ability": modifier.ability,
			"handler": String(modifier.handler),
			"hook": Modifier.Hook.keys()[modifier.hook],
			"power": modifier.power,
			"params": modifier.params.duplicate(true),
			"source": modifier.source,
		}
		if not modifier.semantics.is_empty():
			serialized["semantics"] = modifier.semantic_names()
		modifiers.append(serialized)
	return {
		"name": unit.name,
		"attack": unit.attack,
		"counter_attack": unit.counter_attack,
		"ranged_attack": unit.ranged_attack,
		"shooting_range": unit.shooting_range,
		"defence": unit.defence,
		"ranged_defence": unit.ranged_defence,
		"resist": unit.resist,
		"life": unit.life,
		"life_base": unit.life_base,
		"stamina": unit.stamina,
		"stamina_base": unit.stamina_base,
		"morale": unit.morale,
		"morale_base": unit.morale_base,
		"speed": unit.speed,
		"ammo": unit.ammo,
		"attack_bonus": unit.attack_bonus,
		"defence_bonus": unit.defence_bonus,
		"conditional_bonus": unit.conditional_bonus,
		"flags": unit.flags.keys(),
		"subtypes": unit.subtypes.keys(),
		"__scenario_action_grants": built.action_grants.duplicate(true),
		"modifiers": modifiers,
	}.duplicate(true)
