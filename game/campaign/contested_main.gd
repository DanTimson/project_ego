extends Control

const Authored = preload("res://content/campaign/contested_campaign.gd")
const Map = preload("res://game/campaign/contested_map.gd")
const Battle = preload("res://game/campaign/strategic_battle.tscn")
var model: ContestedCampaign
var definition: Dictionary
var store := CampaignCheckpointStore.new("user://contested_campaign.json")
var selected_army := ""
var selected_province := ""
var screen: VBoxContainer
var map_view: Control
var heading: Label
var feedback: Label
var details: Label
var army_picker: OptionButton
var graph_picker: OptionButton
var travel_button: Button
var end_button: Button
var save_button: Button
var defend_button: Button
var concede_button: Button
var roster_rows: VBoxContainer
var service_rows: VBoxContainer
var service_picker: OptionButton
var service_button: Button
var service_reason: Label
var form_button: Button
var recovery_button: Button
var rival_feedback: Label
var battle: TacticalController
var resolver := TacticalAssetResolver.new()
var sound: InteractionAudio
var _choices: Array = []
var _formation_selection: Array = []


func _ready() -> void:
	theme = PresentationTheme.create()
	resolver.configure()
	_build()
	new_campaign()


func _build() -> void:
	screen = VBoxContainer.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var bar := HBoxContainer.new()
	screen.add_child(bar)
	_button(bar, "New", new_campaign)
	graph_picker = OptionButton.new()
	graph_picker.add_item("Six provinces")
	graph_picker.add_item("Coast graph")
	bar.add_child(graph_picker)
	_button(bar, "Resume contested", resume_checkpoint)
	save_button = _button(bar, "Save", save_checkpoint)
	end_button = _button(bar, "End Turn", func() -> void: issue({"op": "end_turn"}))
	_button(bar, "Native campaign", func() -> void:
		get_tree().change_scene_to_file("res://game/campaign/strategic_main.tscn"))
	_button(bar, "Menu", func() -> void:
		get_tree().change_scene_to_file("res://game/demo/demo_main.tscn"))
	heading = _label(screen, "")
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.add_child(columns)
	map_view = Map.new()
	map_view.resolver = resolver
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.inspected.connect(inspect)
	columns.add_child(map_view)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 310
	columns.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card)
	details = _label(card, "")
	rival_feedback = _label(card, "")
	rival_feedback.max_lines_visible = 7
	army_picker = OptionButton.new()
	army_picker.item_selected.connect(func(index: int) -> void:
		selected_army = army_picker.get_item_metadata(index)
		_refresh("Army selected; no action spent."))
	card.add_child(army_picker)
	travel_button = _button(card, "Travel", func() -> void:
		issue({"op": "travel", "army": selected_army, "to": selected_province}))
	defend_button = _button(card, "Defend province", defend)
	concede_button = _button(card, "Concede province and defenders", concede)
	_label(card, "Troops here • select individual transfers")
	roster_rows = VBoxContainer.new()
	card.add_child(roster_rows)
	form_button = _button(card, "Form army from garrison", form_army)
	_label(card, "Home services • one paid service per round")
	service_picker = OptionButton.new()
	card.add_child(service_picker)
	service_picker.item_selected.connect(func(_index: int) -> void: _refresh_service())
	service_button = _button(card, "Buy selected service", _buy_service)
	service_reason = _label(card, "")
	recovery_button = _button(card, "Recover wounded troops at Home", func() -> void:
		issue({"op": "recover", "units": _wounded()}))
	service_rows = VBoxContainer.new()
	card.add_child(service_rows)
	feedback = _label(screen, "")
	feedback.custom_minimum_size.y = 42
	feedback.max_lines_visible = 3
	sound = InteractionAudio.controls(bar)


func new_campaign() -> void:
	if model != null and (model.in_battle() or model.snapshot().phase == "rival"):
		_refresh("Resolve or concede the defense first.")
		return
	definition = _campaign_definition()
	model = ContestedCampaign.create(definition)
	selected_province = definition.factions[definition.player].home
	selected_army = ""
	for child in map_view.get_children():
		map_view.remove_child(child)
		child.queue_free()
	map_view.buttons.clear()
	_choices.clear()
	_formation_selection.clear()
	service_picker.clear()
	for id in definition.buildings:
		var b: Dictionary = definition.buildings[id]
		_choices.append({"op": "build", "id": id})
		service_picker.add_item("Build %s • %dg" % [b.name, b.cost])
	for id in definition.recruits:
		_choices.append({"op": "recruit", "id": id})
		service_picker.add_item("Recruit %s • %dg" % [definition.definitions[id].name,
			definition.recruits[id].cost])
	_refresh("New contested run. End Turn advances rivals and income. Save explicitly.")


func _campaign_definition() -> Dictionary:
	return Authored.definition() if graph_picker.selected == 0 else Authored.alternate()


func inspect(province: String) -> void:
	selected_province = province
	_formation_selection.clear()
	_refresh("Province selected; no action spent.")


func issue(command: Dictionary) -> Dictionary:
	var result := model.execute(command)
	_refresh(result.reason)
	sound.cue("confirm" if result.ok else "refuse")
	if result.ok and model.in_battle() and not model.contest().defense:
		_open_battle()
	elif model.in_battle() and model.contest().defense:
		defend_button.grab_focus()
	else:
		army_picker.grab_focus()
	return result


func form_army() -> void:
	var ids := _formation_units()
	var result := issue({"op": "form", "province": selected_province, "units": ids})
	if result.ok:
		selected_army = model.field_at(selected_province)
		_refresh(result.reason)
		army_picker.grab_focus()


func defend() -> void:
	if model.in_battle() and model.contest().defense:
		_open_battle()


func concede() -> void:
	var result := model.concede()
	_refresh(result.reason)


func _open_battle() -> void:
	battle = Battle.instantiate()
	battle.campaign = model
	battle.encounter = model.pending_encounter()
	battle.destination = model.contest().to
	battle.army_id = model.contest().army
	battle.map_requested.connect(return_from_battle)
	screen.hide()
	add_child(battle)


func return_from_battle(commit: bool) -> Dictionary:
	var result: Dictionary
	if commit:
		result = model.finish(battle.encounter)
	elif model.contest().defense:
		result = model.concede()
	else:
		result = model.abandon(battle.encounter)
	if result.ok:
		battle.playback.cancel()
		battle.session.end()
		battle.queue_free()
		battle = null
		screen.show()
	_refresh(result.reason)
	return result


func save_checkpoint() -> Dictionary:
	var result := store.save_campaign(model)
	_refresh(result.reason)
	return result


func resume_checkpoint() -> Dictionary:
	if model.in_battle() or model.snapshot().phase == "rival":
		return {"ok": false, "reason": "Resolve the rival phase first."}
	var result := store.load_campaign(definition, true)
	if result.ok:
		model = result.campaign
	_refresh(result.get("reason", "Contested checkpoint resumed."))
	return result


func _refresh(message: String) -> void:
	if model == null:
		return
	var s := model.snapshot()
	if not s.armies.has(selected_army):
		selected_army = ""
	army_picker.clear()
	for id in s.armies:
		if s.armies[id].faction != definition.player:
			continue
		if selected_army == "":
			selected_army = id
		army_picker.add_item("%s • %s • move %d" % [id,
			definition.provinces[s.armies[id].province].name, s.armies[id].moves])
		var index := army_picker.item_count - 1
		army_picker.set_item_metadata(index, id)
		if id == selected_army:
			army_picker.select(index)
	var money: Array = []
	for id in s.factions:
		money.append("%s %dg" % [definition.factions[id].name, s.factions[id].gold])
	heading.text = "Round %d/%d • %s • %s • %s • Objective: %s" % [
		s.round, definition.round_limit, model.active_faction().capitalize(), s.status,
		" / ".join(money), definition.provinces[definition.objective].name]
	map_view.display(model, selected_province)
	var p: Dictionary = s.provinces[selected_province]
	var occupant := model.field_at(selected_province)
	details.text = "%s • %s\nGarrison %d • Field: %s\nSelected army: %s" % [
		definition.provinces[selected_province].name, p.owner if p.owner != "" else "Neutral",
		model.members("", selected_province).size(), occupant if occupant != "" else "none",
		selected_army if selected_army != "" else "none"]
	details.text += "\nNext payout +%dg • Later effective +%dg" % [
		model.province_income(selected_province, true), model.province_income(selected_province)]
	_set_query(travel_button, {"op": "travel", "army": selected_army, "to": selected_province})
	_set_query(end_button, {"op": "end_turn"})
	save_button.disabled = not model.checkpoint().ok
	defend_button.visible = model.in_battle() and model.contest().defense
	concede_button.visible = defend_button.visible
	if defend_button.visible:
		details.text += "\nRival attack at " + definition.provinces[model.contest().to].name
	var reports: Array = s.trace.filter(func(line: String) -> bool:
		return not line.begins_with(definition.player) and not line.begins_with("Player round"))
	rival_feedback.text = "\n".join(reports.slice(maxi(0, reports.size() - 4)))
	_set_query(form_button, {"op": "form", "province": selected_province,
		"units": _formation_units()})
	for child in roster_rows.get_children():
		roster_rows.remove_child(child)
		child.queue_free()
	for u in s.units.values():
		if u.province == selected_province:
			_troop_row(u)
	_label(roster_rows, "%d persistent casualties" % s.casualties.size())
	for dead in s.casualties.values():
		_label(roster_rows, "%s • %s • casualty" % [dead.id,
			definition.definitions[dead.def].name])
	_refresh_service()
	_set_query(recovery_button, {"op": "recover", "units": _wounded()})
	for child in service_rows.get_children():
		service_rows.remove_child(child)
		child.queue_free()
	var home: String = definition.factions[definition.player].home
	var built: Array = []
	for id in s.provinces[home].buildings:
		built.append(definition.buildings[id].name)
	_label(service_rows, "Home built: " + (", ".join(built) if not built.is_empty() else "none"))
	feedback.text = message
	if s.trace.size() > 0:
		feedback.tooltip_text = "\n".join(s.trace.slice(maxi(0, s.trace.size() - 16)))


func _troop_row(unit: Dictionary) -> void:
	var text := "%s • %s %d/%d • %s" % [unit.id, definition.definitions[unit.def].name,
		unit.life, definition.definitions[unit.def].get("life_base",
			definition.definitions[unit.def].life),
		unit.army if unit.army != "" else "garrison"]
	_label(roster_rows, text)
	if unit.faction != definition.player:
		return
	if unit.army == "":
		var choice := CheckButton.new()
		choice.text = "Include in new army"
		choice.set_meta("unit", unit.id)
		choice.button_pressed = unit.id in _formation_selection
		choice.toggled.connect(func(checked: bool) -> void:
			if checked:
				_formation_selection.append(unit.id)
			else:
				_formation_selection.erase(unit.id)
			_set_query(form_button, {"op": "form", "province": selected_province,
				"units": _formation_units()}))
		roster_rows.add_child(choice)
	var destination: String = "" if unit.army != "" else model.field_at(unit.province)
	var command := {"op": "transfer", "unit": unit.id, "army": destination}
	var button := _button(roster_rows, "Station in garrison" if unit.army != "" \
		else "Withdraw to stationed army", func() -> void: issue(command))
	_set_query(button, command)


func _wounded() -> Array:
	var result: Array = []
	if model == null:
		return result
	var home: String = definition.factions[definition.player].home
	for u in model.snapshot().units.values():
		if u.faction == definition.player and u.province == home \
				and u.life < definition.definitions[u.def].get("life_base",
					definition.definitions[u.def].life):
			result.append(u.id)
	return result


func _formation_units() -> Array:
	var available := model.members("", selected_province)
	return _formation_selection.filter(func(id: String) -> bool: return id in available)


func _buy_service() -> void:
	if service_picker.selected >= 0:
		issue(_choices[service_picker.selected])


func _refresh_service() -> void:
	if model == null or service_picker.selected < 0:
		return
	var query := model.query(_choices[service_picker.selected])
	service_button.disabled = not query.ok
	service_reason.text = query.reason if not query.ok \
		else "Available at your Home; price paid before income."


func _set_query(button: Button, command: Dictionary) -> void:
	var query := model.query(command)
	button.disabled = not query.ok
	button.tooltip_text = query.reason


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 30
	button.pressed.connect(action)
	parent.add_child(button)
	return button
