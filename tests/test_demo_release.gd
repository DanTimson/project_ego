extends SceneTree

const DEMO_SCENE := "res://game/demo/demo_main.tscn"

var failures := 0


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("\n[milestone demo shell]")
	var packed := load(DEMO_SCENE) as PackedScene
	_check(packed != null, "demo main scene resource loads")
	var menu: Control = packed.instantiate() as Control
	root.add_child(menu)
	await process_frame
	var button_root := "Center/Panel/Margin/Buttons/"
	_check(menu != null
		and menu.get_node_or_null(button_root + "PlayButton") != null
		and menu.get_node_or_null(button_root + "ControlsButton") != null
		and menu.get_node_or_null(button_root + "AboutButton") != null
		and menu.get_node_or_null(button_root + "QuitButton") != null,
		"demo menu constructs its four obvious actions")
	_check(menu.controls_text().contains("Ranged")
		and menu.controls_text().contains("Space")
		and menu.controls_text().contains("Escape"),
		"controls describe implemented tactical inputs")
	menu.show_controls()
	await process_frame
	var controls_opened: bool = menu.controls_dialog.visible
	menu.controls_dialog.hide()
	menu.show_about()
	await process_frame
	_check(controls_opened and menu.about_dialog.visible,
		"Controls and About actions open their dialogs")
	_check(menu.about_dialog.dialog_text.contains("Incomplete engine reimplementation")
		and menu.about_dialog.dialog_text.contains("Strategy play"),
		"About states the implemented and absent prototype boundary")

	var metadata_path := "user://demo_build_metadata.json"
	var metadata_file := FileAccess.open(metadata_path, FileAccess.WRITE)
	metadata_file.store_string(JSON.stringify({
		"project": "Project EGO", "milestone": "0.1", "commit": "abc123",
		"godot_version": "4.3.test", "mode": "public", "built_at": "test-time",
	}))
	metadata_file.close()
	var parsed: Dictionary = menu.load_build_metadata(metadata_path)
	_check(parsed["commit"] == "abc123" and parsed["mode"] == "public",
		"valid external build metadata parses")
	var missing: Dictionary = menu.load_build_metadata("user://missing-build-metadata.json")
	_check(missing["mode"] == "development" and missing["commit"] == "unavailable",
		"missing build metadata has a development fallback")

	var resolver := TacticalAssetResolver.new()
	_check(resolver.runtime_asset_root("C:/Demo/Project EGO.exe", true)
		== "C:/Demo/local_assets",
		"exported discovery uses executable-adjacent local_assets")
	_check(resolver.runtime_asset_root("", false) == TacticalAssetResolver.DEVELOPMENT_ROOT,
		"development discovery retains the ignored local root")
	var saved_root := OS.get_environment("EGO_ASSET_ROOT")
	var saved_index := OS.get_environment("EGO_ASSET_INDEX")
	var saved_mapping := OS.get_environment("EGO_ASSET_MAPPING")
	OS.set_environment("EGO_ASSET_ROOT", "C:/ExplicitAssets")
	OS.set_environment("EGO_ASSET_INDEX", "")
	OS.set_environment("EGO_ASSET_MAPPING", "")
	var configured_paths := resolver.discovery_paths()
	_check(configured_paths["index"] == "C:/ExplicitAssets/index.json"
		and configured_paths["mapping"] == "C:/ExplicitAssets/mapping.json",
		"explicit configured root has priority over runtime discovery")
	OS.set_environment("EGO_ASSET_ROOT", saved_root)
	OS.set_environment("EGO_ASSET_INDEX", saved_index)
	OS.set_environment("EGO_ASSET_MAPPING", saved_mapping)
	var absent_paths := resolver.discovery_paths(
		"user://definitely-absent/index.json", "user://definitely-absent/mapping.json")
	_check(not resolver.configure(absent_paths["index"], absent_paths["mapping"])
		and resolver.paths_by_key.is_empty(),
		"no local assets remains a normal authored-fallback path")

	menu.controls_dialog.hide()
	menu.about_dialog.hide()
	var transition: Error = menu.play_demo()
	_check(transition == OK, "Play Demo requests the tactical scene transition")
	await process_frame
	await process_frame
	_check(current_scene is TacticalController
		and (current_scene as TacticalController).scenario != null,
		"Play Demo enters the existing initialized tactical scene")
	if current_scene != null:
		current_scene.queue_free()
	menu.queue_free()
	await process_frame
	print("\n%s" % ["ALL PASS" if failures == 0 else "%d FAILURES" % failures])
	quit(0 if failures == 0 else 1)
