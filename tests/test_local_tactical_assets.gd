# gdlint: disable=max-returns
extends SceneTree

const INDEX := "res://.local/eador_assets/index.json"
const MAPPING := "res://.local/eador_assets/mapping.json"
const SCENARIO := "res://scenarios/playable_tactical_slice.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not FileAccess.file_exists(INDEX):
		print("SKIP local-real-assets: .local/eador_assets/index.json is absent")
		quit(0)
		return
	var resolver := TacticalAssetResolver.new()
	if not resolver.load_index(INDEX):
		print("FAIL local real asset index rejected: %s" % resolver.status_text())
		quit(1)
		return
	if not FileAccess.file_exists(MAPPING):
		print("SKIP local-real-assets: index exists but mapping.json is absent")
		quit(0)
		return
	if not resolver.load_mapping(MAPPING):
		print("FAIL local real asset mapping rejected: %s" % resolver.status_text())
		quit(1)
		return
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO))
	if typeof(spec) != TYPE_DICTIONARY:
		print("FAIL playable scenario is malformed")
		quit(1)
		return
	var scenario := Scenario.new(spec)
	var loaded := 0
	var shadow_loaded := 0
	var portrait_loaded := 0
	for unit in scenario.units.values():
		var key := resolver.logical_key_for_unit(unit)
		if key == "":
			continue
		var texture := resolver.texture_for_unit(unit)
		if texture == null:
			print("FAIL mapped local texture did not load: %s -> %s" % [
				unit.instance_id, key])
			quit(1)
			return
		loaded += 1
		if resolver.texture_for_shadow(unit) != null:
			shadow_loaded += 1
		if resolver.texture_for_portrait(unit) != null:
			portrait_loaded += 1
	if loaded == 0:
		print("FAIL local mapping contains no playable battle instance/content mapping")
		quit(1)
		return
	if shadow_loaded == 0:
		print("FAIL no mapped real shadow loads for a playable unit")
		quit(1)
		return
	var packed := load("res://game/tactical/tactical_main.tscn") as PackedScene
	var controller := packed.instantiate() as TacticalController
	root.add_child(controller)
	await process_frame
	await process_frame
	var displayed := 0
	for texture in controller.battlefield_view._textures.values():
		if texture != null:
			displayed += 1
	if displayed == 0:
		print("FAIL playable battlefield did not route mapped textures into unit drawing")
		controller.queue_free()
		quit(1)
		return
	if controller.battlefield_view.facing_scale_x_for_side(0) \
			== controller.battlefield_view.facing_scale_x_for_side(1):
		print("FAIL opposing side facing is not mirrored")
		controller.queue_free()
		quit(1)
		return
	if controller.battlefield_view.terrain_source() != "local" \
			or controller.battlefield_view._decoration_textures.is_empty():
		print("FAIL real terrain/decoration did not reach battlefield rendering")
		controller.queue_free()
		quit(1)
		return
	controller.select_unit("azure-vanguard-01")
	if controller.panel_texture.texture == null and controller.portrait_rect.texture == null:
		print("FAIL no mapped real interface or portrait reached the right panel")
		controller.queue_free()
		quit(1)
		return
	print(("PASS local-real-assets: units=%d displayed=%d shadows=%d portraits=%d; "
		+ "terrain/decor and right-panel visual reached the playable scene") % [
		loaded, displayed, shadow_loaded, portrait_loaded])
	controller.queue_free()
	quit(0)
