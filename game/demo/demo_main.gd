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

var sound: InteractionAudio
var build_metadata: Dictionary = {}
var controls_dialog: AcceptDialog
var about_dialog: AcceptDialog
var options_dialog: AcceptDialog
var options_button: Button
var menu_chrome: Panel
var menu_buttons: VBoxContainer


func _ready() -> void:
	_present_menu()
	sound = InteractionAudio.controls(options_dialog)
	%PlayButton.pressed.connect(play_demo)
	%CampaignButton.pressed.connect(play_campaign)
	%StrategicButton.pressed.connect(play_strategic)
	%ControlsButton.pressed.connect(show_controls)
	%AboutButton.pressed.connect(show_about)
	%QuitButton.pressed.connect(quit_demo)
	%PlayButton.grab_focus()
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
	dialog.confirmed.connect(func() -> void:
		(%ControlsButton if dialog == controls_dialog else %AboutButton).grab_focus())
	dialog.canceled.connect(func() -> void:
		(%ControlsButton if dialog == controls_dialog else %AboutButton).grab_focus())


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
		+ "Legacy strategy/AI parity and broad content parity remain absent."
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
	landscape.anchor_bottom = 0.62
	add_child(landscape)
	move_child(landscape, 1)
	menu_chrome = Panel.new()
	menu_chrome.name = "LowerFrame"
	menu_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_chrome.anchor_top = 0.62
	menu_chrome.add_theme_stylebox_override("panel", PresentationTheme.frame(Color("491e1c")))
	add_child(menu_chrome)
	move_child(menu_chrome, 2)
	var frame_texture := resolver.texture_for_named("ui", "menu_frame")
	if frame_texture != null:
		var border := TextureRect.new()
		border.texture = PresentationTheme.crop(frame_texture, Rect2(0, 0, 1024, 24))
		border.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		border.offset_bottom = 10
		menu_chrome.add_child(border)
	var panel := get_node("Center/Panel") as PanelContainer
	panel.custom_minimum_size = Vector2.ZERO
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var margin := panel.get_node("Margin") as MarginContainer
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	menu_buttons = margin.get_node("Buttons") as VBoxContainer
	menu_buttons.add_theme_constant_override("separation", 3)
	var title := menu_buttons.get_node("Title") as Label
	title.reparent(self)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 22
	var subtitle := %Subtitle as Label
	subtitle.reparent(self)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	subtitle.position.y = 68
	var multiplayer := Button.new()
	multiplayer.text = "Multiplayer — unavailable"
	multiplayer.disabled = true
	multiplayer.tooltip_text = "Multiplayer is not implemented."
	menu_buttons.add_child(multiplayer)
	menu_buttons.move_child(multiplayer, 3)
	options_button = Button.new()
	options_button.name = "OptionsButton"
	options_button.text = "Options"
	menu_buttons.add_child(options_button)
	menu_buttons.move_child(options_button, 4)
	options_dialog = AcceptDialog.new()
	options_dialog.title = "Options • Sound"
	add_child(options_dialog)
	options_button.pressed.connect(show_options)
	options_dialog.confirmed.connect(func() -> void: options_button.grab_focus())
	options_dialog.canceled.connect(func() -> void: options_button.grab_focus())
	%AboutButton.text = "About"
	for button in [ %PlayButton, %CampaignButton, %StrategicButton,
		%ControlsButton, %AboutButton, %QuitButton, multiplayer, options_button ]:
		PresentationTheme.apply_menu_button(button, resolver)
		button.add_theme_font_size_override("font_size", 15)
		button.focus_entered.connect(func() -> void: sound.cue("select"))
		button.mouse_entered.connect(func() -> void: sound.cue("select"))
		button.button_down.connect(func() -> void: sound.cue("confirm"))
	var center := get_node("Center") as CenterContainer
	center.anchor_top = 0.62
	resized.connect(_layout_menu)
	_layout_menu.call_deferred()


func _layout_menu() -> void:
	var panel := get_node("Center/Panel") as PanelContainer
	panel.custom_minimum_size.x = roundf(size.x * 0.27)
	var row_height := floorf((size.y * 0.38 - 28) / 6)
	for child in menu_buttons.get_children():
		if child is Button:
			child.custom_minimum_size.y = row_height
		elif child is HBoxContainer:
			for button in child.get_children():
				button.custom_minimum_size.y = row_height


func show_options() -> void:
	options_dialog.popup_centered_clamped(Vector2i(320, 120), 0.85)
