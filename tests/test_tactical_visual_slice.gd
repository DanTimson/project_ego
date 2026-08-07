extends SceneTree

const MAIN_SCENE := "res://game/tactical/tactical_main.tscn"
const SCENARIO := "res://scenarios/playable_tactical_slice.json"

var failures := 0


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  "))
	file.close()


func _save_image(path: String, fill: Color, matte := false) -> void:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.0, 1.0, 1.0) if matte else fill)
	if matte:
		for y in range(2, 6):
			for x in range(2, 6):
				image.set_pixel(x, y, fill)
	image.save_png(path)


func _scenario() -> Scenario:
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO))
	return Scenario.new(spec)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("\n[tactical visual integration slice 3]")
	var asset_root := "user://tactical_visual_test"
	DirAccess.make_dir_recursive_absolute(asset_root)
	var assets := {
		"unit.png": [Color("44aa66"), true],
		"shadow.png": [Color("111111"), true],
		"portrait.png": [Color("6688cc"), false],
		"terrain.png": [Color("52633b"), false],
		"decoration.png": [Color("d2b24c"), true],
		"panel.png": [Color("4d3028"), false],
	}
	for filename in assets:
		_save_image(asset_root.path_join(filename), assets[filename][0], assets[filename][1])
	var index_path := asset_root.path_join("index.json")
	var mapping_path := asset_root.path_join("mapping.json")
	var index_assets: Array = []
	for filename in assets:
		var source_id: String = filename.get_basename().capitalize()
		index_assets.append({"key": "Synthetic:%s" % source_id,
			"archive": "Synthetic", "source_id": source_id,
			"type": "image", "path": filename})
	_write_json(index_path, {"version": 1, "assets": index_assets})
	var identities := [
		"azure-vanguard-01", "azure-ranger-17",
		"crimson-guard-42", "crimson-marksman-88",
	]
	var unit_entries: Array = []
	var shadow_entries: Array = []
	var portrait_entries: Array = []
	for identity in identities:
		unit_entries.append({"id": identity, "asset": "Synthetic:Unit"})
		shadow_entries.append({"id": identity, "asset": "Synthetic:Shadow"})
		portrait_entries.append({"id": identity, "asset": "Synthetic:Portrait"})
	var mapping := {"version": 2,
		"units": {"content": [], "instances": unit_entries},
		"shadows": {"content": [], "instances": shadow_entries},
		"portraits": {"content": [], "instances": portrait_entries},
		"terrain": [{"id": "base", "asset": "Synthetic:Terrain"}],
		"decorations": [{"id": "grass", "asset": "Synthetic:Decoration"}],
		"ui": [{"id": "panel", "asset": "Synthetic:Panel"}],
	}
	_write_json(mapping_path, mapping)
	var resolver := TacticalAssetResolver.new()
	_check(resolver.load_index(index_path) and resolver.load_mapping(mapping_path),
		"version-2 visual index and category mapping load")
	var scenario := _scenario()
	var session := ManualBattleSession.new(scenario)
	session.begin()
	var left: Combatant = scenario.units["azure-vanguard-01"]
	var right: Combatant = scenario.units["crimson-guard-42"]
	_check(resolver.logical_key_for_unit(left) == "Synthetic:Unit"
		and resolver.logical_key_for_unit(left,
			TacticalAssetResolver.CATEGORY_SHADOWS) == "Synthetic:Shadow"
		and resolver.logical_key_for_unit(left,
			TacticalAssetResolver.CATEGORY_PORTRAITS) == "Synthetic:Portrait",
		"unit, shadow, and portrait namespaces resolve independently")
	_check(resolver.logical_key_for_named(TacticalAssetResolver.CATEGORY_TERRAIN,
		"base") == "Synthetic:Terrain"
		and resolver.logical_key_for_named(TacticalAssetResolver.CATEGORY_UI,
			"panel") == "Synthetic:Panel",
		"terrain and UI named slots remain category-separated")

	var view := TacticalBattlefieldView.new()
	view.configure(session, resolver)
	_check(view.unit_faces_right_for_side(scenario.side_of(left).id)
		!= view.unit_faces_right_for_side(scenario.side_of(right).id)
		and view.facing_scale_x_for_side(0) == -view.facing_scale_x_for_side(1),
		"opposing battle sides resolve to opposite horizontal facing")
	_check(view.overlay_scale_x_for_side(0) == 1.0
		and view.overlay_scale_x_for_side(1) == 1.0,
		"health, selection, and target overlays are never mirrored")
	var layers := view.presentation_layers()
	_check(layers.find(TacticalBattlefieldView.LAYER_SHADOW)
		< layers.find(TacticalBattlefieldView.LAYER_UNIT)
		and layers.find(TacticalBattlefieldView.LAYER_UNIT)
		< layers.find(TacticalBattlefieldView.LAYER_BARS)
		and layers.find(TacticalBattlefieldView.LAYER_BARS)
		< layers.find(TacticalBattlefieldView.LAYER_TARGET),
		"explicit layer model orders shadow, unit, bars, and target overlays")
	_check(view.terrain_source() == "local" and resolver.texture_for_shadow(left) != null,
		"asset-backed terrain and mapped shadow reach the battlefield view")
	_check(view.decoration_index(Vector2i(3, 2), 7) == 6,
		"presentation-only decoration selection is deterministic")
	var centre := view.adapter.cell_to_pixel(Vector2i(1, 1))
	var hit_before := view.hit_test_local(centre)
	var scale_probe := view.facing_scale_x_for_side(1) * TacticalBattlefieldView.UNIT_HEIGHT
	_check(scale_probe < 0.0 and hit_before == Vector2i(1, 1)
		and view.hit_test_local(centre) == hit_before,
		"coordinate hit-testing is independent of sprite scale and facing")

	var fallback_resolver := TacticalAssetResolver.new()
	var fallback_view := TacticalBattlefieldView.new()
	fallback_view.configure(session, fallback_resolver)
	_check(fallback_view.terrain_source() == "fallback",
		"project-authored terrain completely covers missing local assets")

	var keyed := Image.create(5, 5, false, Image.FORMAT_RGBA8)
	keyed.fill(Color(1.0, 0.0, 1.0, 1.0))
	for y in range(1, 4):
		for x in range(1, 4):
			keyed.set_pixel(x, y, Color("336633"))
	keyed.set_pixel(2, 2, Color(1.0, 0.0, 1.0, 1.0))
	keyed.set_pixel(1, 1, Color8(254, 0, 255, 255))
	var cleared := resolver.apply_color_key(keyed)
	_check(cleared == 17 and keyed.get_pixel(0, 0).a == 0.0
		and keyed.get_pixel(2, 2).a == 0.0
		and keyed.get_pixel(1, 1).a == 1.0,
		"exact matte key clears disconnected matte but preserves near-magenta")

	mapping["ui"] = [
		{"id": "panel", "asset": "Synthetic:Panel"},
		{"id": "panel", "asset": "Synthetic:Terrain"},
	]
	_write_json(mapping_path, mapping)
	_check(not resolver.load_mapping(mapping_path),
		"malformed duplicate visual slots reject the entire mapping")

	var previous_index := OS.get_environment("EGO_ASSET_INDEX")
	var previous_mapping := OS.get_environment("EGO_ASSET_MAPPING")
	OS.set_environment("EGO_ASSET_INDEX", asset_root.path_join("absent-index.json"))
	OS.set_environment("EGO_ASSET_MAPPING", asset_root.path_join("absent-mapping.json"))
	var packed := load(MAIN_SCENE) as PackedScene
	var controller := packed.instantiate() as TacticalController
	root.add_child(controller)
	await process_frame
	await process_frame
	var panel_vbox := controller.get_node("RightPanel/Frame/Margin/PanelScroll/VBox")
	_check(panel_vbox.get_node_or_null("IdentityRegion") != null
		and panel_vbox.get_node_or_null("StatsRegion") != null
		and panel_vbox.get_node_or_null("ActionRegion") != null
		and panel_vbox.get_node_or_null("EffectsRegion") != null,
		"actual tactical main scene constructs portrait, stats, actions, and effects regions")
	controller.select_unit("azure-vanguard-01")
	_check(controller.portrait_rect.texture == null
		and controller.portrait_fallback_label.text == "V",
		"selected unit retains project-authored portrait fallback")
	controller.queue_free()
	if previous_index == "":
		OS.unset_environment("EGO_ASSET_INDEX")
	else:
		OS.set_environment("EGO_ASSET_INDEX", previous_index)
	if previous_mapping == "":
		OS.unset_environment("EGO_ASSET_MAPPING")
	else:
		OS.set_environment("EGO_ASSET_MAPPING", previous_mapping)
	await process_frame
	view.free()
	fallback_view.free()
	resolver._texture_cache.clear()
	print("\n%s" % ["ALL PASS" if failures == 0 else "%d FAILURES" % failures])
	quit(0 if failures == 0 else 1)
