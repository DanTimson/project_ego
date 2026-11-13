class_name DemoMain
extends Control

const TACTICAL_SCENE := "res://game/tactical/tactical_vs_crimson.tscn"
const CAMPAIGN_SCENE := "res://game/demo/campaign_demo.tscn"
const STRATEGIC_SCENE := "res://game/campaign/strategic_main.tscn"
const DEVELOPMENT_METADATA := {
	"project": "Project EGO",
	"milestone": "development",
	"commit": "unavailable",
	"godot_version": "development editor",
	"mode": "development",
	"built_at": "not a packaged build",
}

var build_metadata: Dictionary = {}
var controls_dialog: AcceptDialog
var about_dialog: AcceptDialog


func _ready() -> void:
	_present_menu()
	%PlayButton.pressed.connect(play_demo)
	%CampaignButton.pressed.connect(play_campaign)
	%StrategicButton.pressed.connect(play_strategic)
	%ControlsButton.pressed.connect(show_controls)
	%AboutButton.pressed.connect(show_about)
	%QuitButton.pressed.connect(quit_demo)
	controls_dialog = %ControlsDialog
	about_dialog = %AboutDialog
	_prepare_dialog(controls_dialog)
	_prepare_dialog(about_dialog)
	controls_dialog.dialog_text = controls_text()
	apply_build_metadata(load_build_metadata())
	if OS.get_cmdline_user_args().has("--demo-smoke"):
		_run_export_smoke.call_deferred()


func play_demo() -> Error:
	return get_tree().change_scene_to_file(TACTICAL_SCENE)


func play_campaign() -> Error:
	return get_tree().change_scene_to_file(CAMPAIGN_SCENE)


func play_strategic() -> Error:
	return get_tree().change_scene_to_file(STRATEGIC_SCENE)


func _prepare_dialog(dialog: AcceptDialog) -> void:
	var message := dialog.get_label()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func show_controls() -> void:
	controls_dialog.popup_centered_clamped(Vector2i(660, 360), 0.85)


func show_about() -> void:
	about_dialog.popup_centered_clamped(Vector2i(700, 430), 0.85)


func quit_demo() -> void:
	get_tree().quit()


func controls_text() -> String:
	return ("You control Azure; Crimson acts automatically. Select an Azure unit.\n"
		+ "Green hex: move. Orange unit: melee.\n"
		+ "R or Ranged button: ranged mode; click a magenta target.\n"
		+ "Space or Pass button: end the side's phase.\n"
		+ "Escape or Cancel button: clear the selection.\n"
		+ "Campaign Demo: win Ford, then continue to Watchpost with the surviving roster.\n"
		+ "Strategic Campaign: choose adjacent provinces, capture Keep, and save on the map.")


func milestone_subtitle(metadata: Dictionary) -> String:
	var milestone := String(metadata.get("milestone", "development"))
	if milestone == "development":
		return "Tactical Prototype — Development Build"
	return "Tactical Prototype — Milestone %s" % milestone


func apply_build_metadata(metadata: Dictionary) -> void:
	build_metadata = metadata.duplicate(true)
	%Subtitle.text = milestone_subtitle(build_metadata)
	if about_dialog != null:
		about_dialog.dialog_text = about_text(build_metadata)


func about_text(metadata: Dictionary) -> String:
	return ("Project EGO — Tactical Prototype, Milestone %s\n\n"
		+ "Incomplete engine reimplementation prototype. This build includes a "
		+ "standalone tactical battle, a short campaign and a native six-province campaign "
		+ "against Crimson, "
		+ "movement, melee, ranged "
		+ "attacks, turn passing, map checkpoints, and authored fallback presentation. "
		+ "Legacy strategy/AI parity, audio, animation, and broad content parity remain absent."
		+ "\n\nCommit: %s\nGodot: %s\nMode: %s\nBuild: %s") % [
		String(metadata.get("milestone", "unknown")),
		String(metadata.get("commit", "unknown")),
		String(metadata.get("godot_version", "unknown")),
		String(metadata.get("mode", "unknown")),
		String(metadata.get("built_at", "unknown")),
	]


func load_build_metadata(path: String = "") -> Dictionary:
	var requested := path
	if requested == "":
		if OS.has_feature("editor"):
			requested = "res://BUILD.json"
		else:
			requested = OS.get_executable_path().get_base_dir().path_join("BUILD.json")
	if not FileAccess.file_exists(requested):
		return DEVELOPMENT_METADATA.duplicate(true)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(requested))
	if typeof(parsed) != TYPE_DICTIONARY:
		return DEVELOPMENT_METADATA.duplicate(true)
	var required := ["project", "milestone", "commit", "godot_version", "mode", "built_at"]
	for key in required:
		if typeof(parsed.get(key)) != TYPE_STRING or String(parsed[key]) == "":
			return DEVELOPMENT_METADATA.duplicate(true)
	return (parsed as Dictionary).duplicate(true)


func _run_export_smoke() -> void:
	var packed := load(TACTICAL_SCENE) as PackedScene
	if packed == null:
		push_error("DEMO_SMOKE tactical scene failed to load")
		get_tree().quit(1)
		return
	var tactical := packed.instantiate()
	get_tree().root.add_child(tactical)
	await get_tree().process_frame
	await get_tree().process_frame
	if tactical is TacticalController and tactical.scenario != null:
		print("DEMO_SMOKE PASS menu and tactical scene")
		tactical.queue_free()
		get_tree().quit(0)
		return
	push_error("DEMO_SMOKE tactical scene failed to initialize")
	get_tree().quit(1)


func _present_menu() -> void:
	theme = PresentationTheme.create()
	var resolver := TacticalAssetResolver.new()
	resolver.configure()
	var landscape := PresentationLandscape.new()
	landscape.resolver = resolver
	landscape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(landscape)
	move_child(landscape, 1)
	var panel := get_node("Center/Panel") as PanelContainer
	panel.add_theme_stylebox_override("panel", PresentationTheme.frame(Color(0.08, 0.06, 0.045, 0.93)))
	for id in ["PlayButton", "CampaignButton", "StrategicButton",
		"ControlsButton", "AboutButton", "QuitButton"]:
		PresentationTheme.apply_menu_button(get_node("%" + id), resolver)
	var frame_texture := resolver.texture_for_named("ui", "menu_frame")
	if frame_texture != null:
		var border := TextureRect.new()
		border.texture = PresentationTheme.crop(frame_texture, Rect2(0, 0, 1024, 82))
		border.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		border.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		border.offset_bottom = 48
		add_child(border)
	%PlayButton.grab_focus()
