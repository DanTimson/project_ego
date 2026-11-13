extends Control

const Authored = preload("res://content/campaign/native_campaign.gd")
const MapView = preload("res://game/campaign/province_map.gd")
const BattleView = preload("res://game/campaign/strategic_battle.tscn")
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


func _ready() -> void:
	theme = PresentationTheme.create()
	resolver.configure()
	_build_screen()
	_refresh("Choose New Campaign or Resume Checkpoint. New runs save only when you press Save.")


func _build_screen() -> void:
	var background := ColorRect.new()
	background.color = Color("161c19")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	screen = MarginContainer.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		screen.add_theme_constant_override("margin_" + side, 16)
	add_child(screen)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	scroll.add_child(columns)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(main)
	var title_row := HBoxContainer.new()
	main.add_child(title_row)
	var gold_icon := TextureRect.new()
	gold_icon.texture = resolver.texture_for_named("ui", "gold")
	if gold_icon.texture == null:
		gold_icon.texture = preload("res://game/presentation/art/gold.svg")
	gold_icon.custom_minimum_size = Vector2(28, 28)
	gold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_row.add_child(gold_icon)
	heading = _label(title_row, "The road to Keep", 22)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(main, "Objective: capture Keep. Links allow travel in both directions.", 16)
	map_view = MapView.new()
	map_view.resolver = resolver
	main.add_child(map_view)
	map_view.destination_chosen.connect(travel)
	var tabs := HBoxContainer.new()
	main.add_child(tabs)
	_button(tabs, "Province Map", show_map)
	home_button = _button(tabs, "Home • Roster & services", show_home)
	_build_home(main)
	feedback = _label(main, "", 16)
	feedback.custom_minimum_size.y = 56
	var actions := HBoxContainer.new()
	main.add_child(actions)
	save_button = _button(actions, "Save checkpoint", save_checkpoint)
	_label(
		main,
		(
			"Each move, resolved battle or paid service costs one turn, "
			+ "then all owned provinces pay income.\nBattles deploy survivors only. "
			+ "Casualties remain on your roster. Recovery and recruitment: Home only."
		),
		14
	)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 286
	columns.add_child(sidebar)
	sound = InteractionAudio.controls(sidebar)
	_label(sidebar, "Campaign", 22)
	new_button = _button(sidebar, "New Campaign", new_campaign)
	resume_button = _button(sidebar, "Resume Checkpoint", resume_checkpoint)
	_button(sidebar, "Main Menu", return_to_menu)
	_label(sidebar, "Roster • persistent life", 20)
	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(roster_scroll)
	roster_rows = VBoxContainer.new()
	roster_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(roster_rows)
	roster_label = _label(roster_rows, "Start or resume a campaign.", 14)
	roster_details = _label(
		sidebar, "Select a roster row to inspect.\nLife persists between battles.", 14
	)


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
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func new_campaign() -> void:
	if battle != null:
		return
	row_feedback = {}
	campaign = StrategicCampaign.create(Authored.definition())
	_refresh("New run. An existing checkpoint stays unchanged until you explicitly save.")


func resume_checkpoint() -> Dictionary:
	if battle != null:
		return {"ok": false, "reason": "Return to the map first."}
	var loaded := store.load_campaign(Authored.definition())
	if loaded.ok:
		row_feedback = {}
		campaign = loaded.campaign
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
	map_view.visible = campaign != null and not home_view.visible
	save_button.disabled = campaign == null or campaign.in_battle()
	recovery_button.disabled = campaign == null or not campaign.query("recover").ok
	recruit_button.disabled = campaign == null or not campaign.query("recruit").ok
	if campaign == null:
		return
	var state := campaign.snapshot()
	var content := campaign.content()
	heading.text = (
		"%s • %s\nGold %d • Turns %d / %d"
		% [
			content.provinces[state.position].name,
			state.status.capitalize(),
			state.gold,
			state.turn,
			content.turn_limit
		]
	)
	recovery_button.text = "Recover +%d (%dg)" % [content.recovery_life, content.recovery_cost]
	recruit_button.text = "Recruit (%dg)" % content.recruit_cost
	recovery_button.tooltip_text = campaign.query("recover").reason
	recruit_button.tooltip_text = campaign.query("recruit").reason
	for child in roster_rows.get_children():
		if child != roster_label:
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
	map_view.display(campaign)


func _build_home(parent: Control) -> void:
	home_view = PanelContainer.new()
	home_view.custom_minimum_size = Vector2(580, 300)
	home_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(home_view)
	home_view.hide()
	var backdrop := PresentationLandscape.new()
	backdrop.mode = "home"
	backdrop.resolver = resolver
	home_view.add_child(backdrop)
	var columns := HBoxContainer.new()
	home_view.add_child(columns)
	var estate := TextureRect.new()
	estate.custom_minimum_size = Vector2(180, 160)
	estate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	estate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	estate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	estate.texture = resolver.texture_for_named("ui", "home_estate")
	columns.add_child(estate)
	var service_frame := PanelContainer.new()
	service_frame.add_theme_stylebox_override(
		"panel", PresentationTheme.frame(Color(0.08, 0.07, 0.05, 0.93))
	)
	columns.add_child(service_frame)
	var services := VBoxContainer.new()
	services.custom_minimum_size.x = 280
	service_frame.add_child(services)
	_label(services, "HOME", 26)
	_label(services, "Recovery & recruitment", 20)
	_label(services, "Care for wounded survivors.\nCasualties cannot be revived.", 15)
	recovery_button = _button(services, "Recover", recover)
	recovery_button.icon = resolver.texture_for_named("ui", "home_recovery")
	recovery_button.add_theme_constant_override("icon_max_width", 38)
	recovery_button.expand_icon = true
	var content := Authored.definition()
	var recruit_definition: Dictionary = content.definitions[content.recruit_def]
	_label(
		services,
		(
			"Recruit a %s • full life %d/%d\nMaximum %d living company members."
			% [
				recruit_definition.name,
				recruit_definition.life,
				recruit_definition.life,
				content.living_cap
			]
		),
		15
	)
	recruit_button = _button(services, "Recruit", recruit)
	recruit_button.icon = resolver.texture_for_named("ui", "home_recruit")
	recruit_button.add_theme_constant_override("icon_max_width", 38)
	recruit_button.expand_icon = true
	_label(services, "Each service uses one turn.\nAvailable while stationed at Home.", 14)


func show_home() -> void:
	home_view.show()
	map_view.hide()


func show_map() -> void:
	home_view.hide()
	map_view.visible = campaign != null


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
	row.custom_minimum_size.y = 82
	row.add_theme_font_size_override("font_size", 15)
	var key: String = resolver.content_keys_by_category.get("portraits", {}).get(member.def, "")
	row.icon = resolver.texture_for_key(key)
	if row.icon == null:
		row.icon = preload("res://game/presentation/art/company_portrait.svg")
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
