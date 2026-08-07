class_name DemoMain
extends Control

const TACTICAL_SCENE := "res://game/tactical/tactical_main.tscn"
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
	build_metadata = load_build_metadata()
	%PlayButton.pressed.connect(play_demo)
	%ControlsButton.pressed.connect(show_controls)
	%AboutButton.pressed.connect(show_about)
	%QuitButton.pressed.connect(quit_demo)
	controls_dialog = %ControlsDialog
	about_dialog = %AboutDialog
	_prepare_dialog(controls_dialog)
	_prepare_dialog(about_dialog)
	controls_dialog.dialog_text = controls_text()
	about_dialog.dialog_text = about_text(build_metadata)
	if OS.get_cmdline_user_args().has("--demo-smoke"):
		_run_export_smoke.call_deferred()


func play_demo() -> Error:
	return get_tree().change_scene_to_file(TACTICAL_SCENE)


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
	return ("Select an active-side unit with the mouse.\n"
		+ "Green hex: move. Orange unit: melee.\n"
		+ "R or Ranged button: ranged mode; click a magenta target.\n"
		+ "Space or Pass button: end the side's phase.\n"
		+ "Escape or Cancel button: clear the selection.")


func about_text(metadata: Dictionary) -> String:
	return ("Project EGO — Tactical Prototype, Milestone %s\n\n"
		+ "Incomplete engine reimplementation prototype. This build includes a "
		+ "playable deterministic hot-seat tactical battle, movement, melee, ranged "
		+ "attacks, turn passing, and authored fallback presentation. Strategy play, "
		+ "AI, saving, audio, animation, and broad content parity are visibly absent."
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
