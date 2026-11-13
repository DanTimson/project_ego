extends Control

const Authored = preload("res://content/campaign/native_campaign.gd")
const MapView = preload("res://game/campaign/province_map.gd")
const BattleView = preload("res://game/campaign/strategic_battle.tscn")
const COMPANY_PORTRAIT = preload("res://game/presentation/art/company_portrait.svg")
const MENU := "res://game/demo/demo_main.tscn"
var sound: InteractionAudio
var service_feedback := ""
var row_feedback: Dictionary = {}
var campaign: StrategicCampaign
var store := CampaignCheckpointStore.new()
var battle: TacticalController
var map_view: Control
var screen: MarginContainer
var heading: Label
var roster_label: Label
var feedback: Label
var recovery_button: Button
var recruit_button: Button
var save_button: Button
var resume_button: Button
var new_button: Button
var resolver := TacticalAssetResolver.new()
var home_view: PanelContainer
var roster_rows: VBoxContainer
var roster_details: Label
var home_button: Button
var map_button: Button
var footer: PanelContainer
var context_panel: PanelContainer
var context_title: Label
var context_status: Label
var travel_button: Button
var services: VBoxContainer
var campaign_dialog: AcceptDialog
var inspected := "home"
var construction_button: Button
var recovery_reason: Label
var recruit_reason: Label
var objective_label: Label


func _ready() -> void:
	theme = PresentationTheme.create()
	resolver.configure()
	_build_screen()
	_refresh("Choose New Campaign or Resume Checkpoint. New runs save only when you press Save.")


func _build_screen() -> void:
	screen = MarginContainer.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 0)
	screen.add_child(layout)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 0)
	layout.add_child(columns)
	var field := Control.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(field)
	map_view = MapView.new()
	map_view.resolver = resolver
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field.add_child(map_view)
	map_view.province_inspected.connect(inspect_province)
	_build_home(field)
	feedback = _label(field, "", 14)
	feedback.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	feedback.offset_top = -52
	feedback.offset_left = 14
	feedback.offset_right = -14
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback.add_theme_color_override("font_shadow_color", Color.BLACK)
	feedback.add_theme_constant_override("shadow_offset_x", 2)
	feedback.add_theme_constant_override("shadow_offset_y", 2)
	context_panel = PanelContainer.new()
	columns.add_child(context_panel)
	resized.connect(_layout_context)
	_layout_context()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	context_panel.add_child(scroll)
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card)
	context_title = _label(card, "The road to Keep", 22)
	var portrait := TextureRect.new()
	portrait.texture = COMPANY_PORTRAIT
	portrait.custom_minimum_size.y = 58
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.add_child(portrait)
	context_status = _label(card, "Start or resume a campaign.", 15)
	travel_button = _button(card, "Travel", _travel_inspected)
	_build_services(card)
	roster_label = _label(card, "Company", 17)
	roster_rows = VBoxContainer.new()
	card.add_child(roster_rows)
	roster_details = _label(card, "Select a roster member to inspect persistent life.", 14)
	footer = PanelContainer.new()
	layout.add_child(footer)
	var strip := HBoxContainer.new()
	footer.add_child(strip)
	var gold_icon := _resource_icon(strip, "gold")
	gold_icon.tooltip_text = "Gold"
	heading = _label(strip, "Gold — • Turn —", 14)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	_resource_icon(strip, "crystal")
	strip.add_theme_constant_override("separation", 8)
	var crystal := _label(strip, "Crystals —", 14)
	crystal.autowrap_mode = TextServer.AUTOWRAP_OFF
	crystal.tooltip_text = "Unavailable: this campaign has no crystal resource."
	objective_label = _label(strip, "Objective: capture Keep", 14)
	objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	objective_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_button = _button(strip, "Map", show_map)
	home_button = _button(strip, "Home", show_home)
	for button in [map_button, home_button]:
		button.toggle_mode = true
	_button(strip, "Campaign", show_campaign_controls)
	campaign_dialog = AcceptDialog.new()
	campaign_dialog.title = "Campaign controls"
	add_child(campaign_dialog)
	var actions := VBoxContainer.new()
	campaign_dialog.add_child(actions)
	new_button = _button(actions, "New Campaign", new_campaign)
	resume_button = _button(actions, "Resume Checkpoint", resume_checkpoint)
	save_button = _button(actions, "Save checkpoint", save_checkpoint)
	_button(actions, "Main Menu", return_to_menu)
	sound = InteractionAudio.controls(actions)
	_label(actions, "Moves, resolved battles and paid services use one turn.\n"
		+ "Owned provinces then pay income. Save explicitly on the map.", 14)
	campaign_dialog.confirmed.connect(func() -> void: map_button.grab_focus())
	campaign_dialog.canceled.connect(func() -> void: map_button.grab_focus())
	show_map()


func _layout_context() -> void:
	context_panel.custom_minimum_size.x = clampf(size.x * 0.24, 264, 320)


func show_campaign_controls() -> void:
	campaign_dialog.popup_centered_clamped(Vector2i(420, 340), 0.85)


func inspect_province(id: String) -> void:
	inspected = id
	map_view.inspected = id
	map_view.queue_redraw()
	if campaign == null:
		return
	var state := campaign.snapshot()
	var province: Dictionary = campaign.content().provinces[id]
	context_title.text = province.name + " • inspected"
	objective_label.text = province.name + " • Objective: Keep"
	context_status.text = "%s • Income +%dg\nArmy at %s\n%s" % [
		"Allied" if id in state.owned else "Hostile", province.income,
		campaign.content().provinces[state.position].name, campaign.query("travel", id).reason]
	travel_button.text = ("Travel to " if id in state.owned else "Battle for ") + province.name
	travel_button.disabled = not campaign.query("travel", id).ok
	travel_button.tooltip_text = campaign.query("travel", id).reason


func _travel_inspected() -> void:
	travel(inspected)


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 32
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func new_campaign() -> void:
	if battle != null:
		return
	row_feedback = {}
	service_feedback = ""
	inspected = "home"
	campaign = StrategicCampaign.create(Authored.definition())
	_refresh("New run. An existing checkpoint stays unchanged until you explicitly save.")


func resume_checkpoint() -> Dictionary:
	if battle != null:
		return {"ok": false, "reason": "Return to the map first."}
	var loaded := store.load_campaign(Authored.definition())
	if loaded.ok:
		row_feedback = {}
		campaign = loaded.campaign
		service_feedback = ""
		inspected = campaign.snapshot().position
	_refresh("Checkpoint resumed." if loaded.ok else loaded.reason)
	return loaded


func save_checkpoint() -> Dictionary:
	if campaign == null:
		return {"ok": false, "reason": "Start a campaign first."}
	var saved := store.save_campaign(campaign)
	_refresh(saved.reason)
	return saved


func travel(destination: String) -> Dictionary:
	if campaign == null:
		return {"ok": false, "reason": "Start a campaign first."}
	inspected = destination
	map_view.mark(destination, "Selected")
	sound.cue("select")
	var result := campaign.travel(destination)
	_refresh(result.reason)
	sound.cue("movement" if result.ok else "refuse")
	map_view.mark(destination, "Travel" if result.ok else "Refused")
	if result.ok and result.has("encounter"):
		battle = BattleView.instantiate()
		battle.campaign = campaign
		battle.encounter = result.encounter
		battle.destination = destination
		battle.map_requested.connect(return_from_battle)
		screen.hide()
		add_child(battle)
	return result


func return_from_battle(commit: bool) -> Dictionary:
	if battle == null:
		return {"ok": false, "reason": "No active battle."}
	var captured: bool = commit and battle.session.winning_side_id() == 0
	var result := (
		campaign.finish(battle.encounter) if commit else campaign.abandon(battle.encounter)
	)
	if result.ok:
		var marker := "Captured" if captured else ("Defeated" if commit else "Returned")
		map_view.mark(battle.destination, marker)
		sound.cue("capture" if captured else ("refuse" if commit else "confirm"))
		battle.playback.cancel()
		battle.session.end()
		battle.queue_free()
		battle = null
		screen.show()
	_refresh(result.reason)
	return result


func recover() -> Dictionary:
	if campaign == null:
		return {"ok": false, "reason": "Start a campaign first."}
	var before: Dictionary = campaign.snapshot().roster.entries
	var result := campaign.recover()
	_record_roster_feedback(before)
	service_feedback = "Recovered" if result.ok else "Refused"
	sound.cue("confirm" if result.ok else "refuse")
	_refresh(result.reason)
	map_view.mark("home", service_feedback)
	roster_details.text = service_feedback + " • " + result.reason
	return result


func recruit() -> Dictionary:
	if campaign == null:
		return {"ok": false, "reason": "Start a campaign first."}
	var before: Dictionary = campaign.snapshot().roster.entries
	var result := campaign.recruit()
	_record_roster_feedback(before)
	service_feedback = "Recruited" if result.ok else "Refused"
	sound.cue("confirm" if result.ok else "refuse")
	_refresh(result.reason)
	map_view.mark("home", service_feedback)
	roster_details.text = service_feedback + " • " + result.reason
	return result


func return_to_menu() -> void:
	get_tree().change_scene_to_file(MENU)


func _refresh(message: String) -> void:
	feedback.text = message
	map_view.visible = not home_view.visible
	travel_button.disabled = campaign == null
	save_button.disabled = campaign == null or campaign.in_battle()
	recovery_button.disabled = campaign == null or not campaign.query("recover").ok
	recruit_button.disabled = campaign == null or not campaign.query("recruit").ok
	if campaign == null:
		return
	var state := campaign.snapshot()
	var content := campaign.content()
	heading.text = "Gold %d • Turn %d / %d" % [state.gold, state.turn, content.turn_limit]
	if home_view.visible:
		context_title.text = "Home • Company"
		objective_label.text = "Home • Objective: Keep"
		context_status.text = "Army at %s • %s" % [
			content.provinces[state.position].name, state.status.capitalize()]
	else:
		inspect_province(inspected)
	recovery_button.text = "Recover +%d (%dg)" % [content.recovery_life, content.recovery_cost]
	recruit_button.text = "Recruit (%dg)" % content.recruit_cost
	recovery_button.tooltip_text = campaign.query("recover").reason
	recovery_reason.text = recovery_button.tooltip_text
	recruit_button.tooltip_text = campaign.query("recruit").reason
	recruit_reason.text = recruit_button.tooltip_text
	for child in roster_rows.get_children():
		roster_rows.remove_child(child)
		child.queue_free()
	var rows: PackedStringArray = []
	for member in state.roster.entries.values():
		rows.append(
			(
				"%s\n%s\n%d / %d life%s"
				% [
					member.definition.name,
					member.id,
					member.life,
					member.definition.get("life_base", member.definition.life),
					" • CASUALTY" if member.life == 0 else ""
				]
			)
		)
		_add_roster_row(member)
	roster_label.text = (
		"Company • %d records%s"
		% [rows.size(), " • CASUALTY recorded" if "CASUALTY" in " ".join(rows) else ""]
	)
	if state.status != "active":
		objective_label.text = "%s • %s" % [
			state.status.capitalize(), content.provinces[state.position].name]
	map_view.display(campaign)


func _build_home(parent: Control) -> void:
	home_view = PanelContainer.new()
	home_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(home_view)
	home_view.hide()
	var backdrop := PresentationLandscape.new()
	backdrop.mode = "home"
	backdrop.resolver = resolver
	home_view.add_child(backdrop)
	var estate_texture := resolver.texture_for_named("ui", "home_estate")
	if estate_texture != null:
		var composition := CenterContainer.new()
		composition.mouse_filter = Control.MOUSE_FILTER_IGNORE
		home_view.add_child(composition)
		var estate := TextureRect.new()
		estate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		estate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		estate.texture = estate_texture
		# Preserve the small sprite's proportions and leave the settlement visible.
		estate.custom_minimum_size = estate_texture.get_size() * 2.0
		estate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		composition.add_child(estate)


func _build_services(parent: Control) -> void:
	services = VBoxContainer.new()
	parent.add_child(services)
	_label(services, "Recovery & recruitment", 17)
	_label(services, "Wounded survivors only. Casualties cannot be revived.", 14)
	recovery_button = _button(services, "Recover", recover)
	recovery_reason = _label(services, "Start a campaign first.", 13)
	var content := Authored.definition()
	var definition: Dictionary = content.definitions[content.recruit_def]
	_label(services, "Recruit %s • %d/%d life. Maximum %d living members." % [
		definition.name, definition.life, definition.life, content.living_cap], 14)
	recruit_button = _button(services, "Recruit", recruit)
	recruit_reason = _label(services, "Start a campaign first.", 13)
	_label(services, "Each service uses one turn. Available while stationed at Home.", 14)
	construction_button = _button(services, "Construction — unavailable", func() -> void: pass)
	construction_button.disabled = true
	_label(services, "Construction is not implemented.", 14)


func show_home() -> void:
	home_view.show()
	map_view.hide()
	services.show()
	travel_button.hide()
	home_button.set_pressed_no_signal(true)
	map_button.set_pressed_no_signal(false)
	_refresh(service_feedback)


func show_map() -> void:
	home_view.hide()
	map_view.show()
	services.hide()
	travel_button.show()
	home_button.set_pressed_no_signal(false)
	map_button.set_pressed_no_signal(true)
	_refresh(service_feedback)


func _add_roster_row(member: Dictionary) -> void:
	var row := Button.new()
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text = (
		"%s\n%d / %d life • %s"
		% [
			member.definition.name,
			member.life,
			member.definition.get("life_base", member.definition.life),
			(
				"CASUALTY"
				if member.life == 0
				else "Ready" if member.life == member.definition.life else "Wounded"
			)
		]
	)
	if row_feedback.has(member.id):
		row.text += "\n" + String(row_feedback[member.id])
	row.custom_minimum_size.y = 60
	row.add_theme_font_size_override("font_size", 14)
	var key: String = resolver.content_keys_by_category.get("portraits", {}).get(member.def, "")
	row.icon = resolver.texture_for_key(key)
	if row.icon == null:
		row.icon = COMPANY_PORTRAIT
	row.add_theme_constant_override("icon_max_width", 48)
	row.expand_icon = true
	row.tooltip_text = (
		"%s • Attack %d • Life %d/%d"
		% [
			member.definition.name,
			member.definition.get("attack", 0),
			member.life,
			member.definition.life
		]
	)
	row.pressed.connect(func() -> void:
		roster_details.text = row.tooltip_text
		sound.cue("select"))
	row.focus_entered.connect(func() -> void: roster_details.text = row.tooltip_text)
	roster_rows.add_child(row)


func _record_roster_feedback(before: Dictionary) -> void:
	row_feedback = {}
	for id in campaign.snapshot().roster.entries:
		var member: Dictionary = campaign.snapshot().roster.entries[id]
		if not before.has(id):
			row_feedback[id] = "Recruited"
		elif member.life > before[id].life:
			row_feedback[id] = "Recovered +%d life" % (member.life - before[id].life)


func _resource_icon(parent: Control, slot: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = resolver.texture_for_named("ui", slot)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if icon.texture == null and slot == "gold":
		icon.texture = preload("res://game/presentation/art/gold.svg")
	parent.add_child(icon)
	return icon
