extends Control

const Authored = preload("res://content/campaign/native_campaign.gd")
const MapView = preload("res://game/campaign/province_map.gd")
const BattleView = preload("res://game/campaign/strategic_battle.tscn")
const MENU := "res://game/demo/demo_main.tscn"
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


func _ready() -> void:
	_build_screen()
	_refresh("Choose New Campaign or Resume Checkpoint. New runs save only when you press Save.")


func _build_screen() -> void:
	var background := ColorRect.new()
	background.color = Color(0.055, 0.073, 0.086)
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
	heading = _label(main, "Native Strategic Campaign", 24)
	_label(main, "Objective: capture Keep. Links allow travel in both directions.", 16)
	map_view = MapView.new()
	main.add_child(map_view)
	map_view.destination_chosen.connect(travel)
	feedback = _label(main, "", 16)
	feedback.custom_minimum_size.y = 56
	var actions := HBoxContainer.new()
	main.add_child(actions)
	recovery_button = _button(actions, "Recover", recover)
	recruit_button = _button(actions, "Recruit", recruit)
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
	sidebar.custom_minimum_size.x = 290
	columns.add_child(sidebar)
	_label(sidebar, "Campaign", 22)
	new_button = _button(sidebar, "New Campaign", new_campaign)
	resume_button = _button(sidebar, "Resume Checkpoint", resume_checkpoint)
	_button(sidebar, "Main Menu", return_to_menu)
	_label(sidebar, "Roster • persistent life", 20)
	var roster_scroll := ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(roster_scroll)
	roster_label = _label(roster_scroll, "Start or resume a campaign.", 16)
	roster_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL


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
	campaign = StrategicCampaign.create(Authored.definition())
	_refresh("New run. An existing checkpoint stays unchanged until you explicitly save.")


func resume_checkpoint() -> Dictionary:
	if battle != null:
		return {"ok": false, "reason": "Return to the map first."}
	var loaded := store.load_campaign(Authored.definition())
	if loaded.ok:
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
	var result := campaign.travel(destination)
	_refresh(result.reason)
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
	var result := (
		campaign.finish(battle.encounter) if commit else campaign.abandon(battle.encounter)
	)
	if result.ok:
		battle.session.end()
		battle.queue_free()
		battle = null
		screen.show()
	_refresh(result.reason)
	return result


func recover() -> Dictionary:
	if campaign == null:
		return {"ok": false, "reason": "Start a campaign first."}
	var result := campaign.recover()
	_refresh(result.reason)
	return result


func recruit() -> Dictionary:
	if campaign == null:
		return {"ok": false, "reason": "Start a campaign first."}
	var result := campaign.recruit()
	_refresh(result.reason)
	return result


func return_to_menu() -> void:
	get_tree().change_scene_to_file(MENU)


func _refresh(message: String) -> void:
	feedback.text = message
	map_view.visible = campaign != null
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
	roster_label.text = "\n\n".join(rows)
	map_view.display(campaign)
