extends "res://game/campaign/contested_main.gd"

const ProvinceContent = preload("res://content/campaign/province_campaign.gd")
const ProvinceMap = preload("res://game/campaign/exploration_map.gd")
var explore_button: Button
var site_button: Button
var choice_panel: VBoxContainer
var choice_text: Label
var fight_button: Button
var withdraw_button: Button
var negotiate_button: Button
var pages: TabContainer
var districts: VBoxContainer
var heroes_panel: VBoxContainer


func _campaign_definition() -> Dictionary:
	return ProvinceContent.definition(graph_picker.selected == 1)


func _build() -> void:
	super._build()
	store = CampaignCheckpointStore.new("user://province_campaign.json")
	var columns := map_view.get_parent()
	columns.remove_child(map_view)
	map_view.queue_free()
	pages = TabContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(pages)
	columns.move_child(pages, 0)
	map_view = ProvinceMap.new()
	map_view.name = "Province map"
	map_view.resolver = resolver
	map_view.inspected.connect(inspect)
	pages.add_child(map_view)
	districts = _page("Settlement districts")
	heroes_panel = _page("Hero and army")
	var card := details.get_parent()
	explore_button = _button(
		card,
		"Explore current province",
		func() -> void: issue({"op": "explore", "army": selected_army})
	)
	card.move_child(explore_button, 4)
	site_button = _button(
		card,
		"Inspect discovered site",
		func() -> void: issue({"op": "site", "army": selected_army})
	)
	card.move_child(site_button, 5)
	choice_panel = VBoxContainer.new()
	card.add_child(choice_panel)
	card.move_child(choice_panel, 6)
	choice_text = _label(choice_panel, "")
	fight_button = _button(choice_panel, "Fight", func() -> void: _choose("fight"))
	withdraw_button = _button(choice_panel, "Withdraw", func() -> void: _choose("withdraw"))
	negotiate_button = _button(choice_panel, "Negotiate", func() -> void: _choose("negotiate"))
	recovery_button.text = "Recover wounded local survivors"
	for child in card.get_children():
		if child is Label and child.text.begins_with("Home services"):
			child.text = "Settlement services • one paid service per faction round"


func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return rows


func new_campaign() -> void:
	super.new_campaign()
	_refresh("Explore the frontier. End Turn resolves rivals and pays owned provinces.")


func _refresh(message: String) -> void:
	if model == null or explore_button == null:
		return
	var s := model.snapshot()
	var view: Dictionary = model.faction_view(definition.player)
	if not view.armies.has(selected_army):
		selected_army = ""
	army_picker.clear()
	for id in view.armies:
		if selected_army == "":
			selected_army = id
		var a: Dictionary = view.armies[id]
		army_picker.add_item("%s • %s • move %d" % [id, view.provinces[a.province].name, a.moves])
		var index := army_picker.item_count - 1
		army_picker.set_item_metadata(index, id)
		if id == selected_army:
			army_picker.select(index)
	heading.text = (
		"Round %d/%d • %s • %dg / %dc • %s"
		% [
			s.round,
			definition.round_limit,
			definition.factions[definition.player].name,
			view.treasury.gold,
			view.treasury.crystals,
			s.status
		]
	)
	map_view.display(model, selected_province)
	var p: Dictionary = view.provinces[selected_province]
	if p.knowledge != "known":
		details.text = (
			"Unexplored space" if p.knowledge == "unknown" else "Frontier • reachable route"
		)
		details.text += "\nTerrain, income, defenders and discoveries unknown."
	else:
		details.text = (
			"%s • %s\n%s • %s • exploration %d%%\n%s • stability %d (+%d/owned round)"
			% [
				p.name,
				p.visibility,
				p.terrain,
				p.owner if p.owner != "" else "Neutral",
				p.progress,
				p.tier,
				p.stability,
				p.recovery
			]
		)
		details.text += (
			"\nBase %dg / %dc • next payout %dg / %dc\nGarrison %d/%d"
			% [
				p.base.gold,
				p.base.crystals,
				p.payout.gold,
				p.payout.crystals,
				p.garrison,
				definition.garrison_cap
			]
		)
		details.text += (
			"\nResource: "
			+ (
				"undiscovered"
				if p.resource.is_empty()
				else (
					"%s (+%dg / %dc before stability)"
					% [p.resource.name, p.resource.gold, p.resource.crystals]
				)
			)
		)
		details.text += (
			"\nSite: "
			+ ("undiscovered" if p.site.is_empty() else p.site_name + " • " + p.site.status)
		)
	for pair in [
		[travel_button, {"op": "travel", "army": selected_army, "to": selected_province}],
		[explore_button, {"op": "explore", "army": selected_army}],
		[site_button, {"op": "site", "army": selected_army}],
		[end_button, {"op": "end_turn"}],
		[form_button, {"op": "form", "province": selected_province, "units": _formation_units()}],
		[recovery_button, {"op": "recover", "units": _wounded(), "province": selected_province}]
	]:
		_set_query(pair[0], pair[1])
	save_button.disabled = not model.checkpoint().ok
	defend_button.visible = model.in_battle() and model.contest().defense
	concede_button.visible = defend_button.visible
	if defend_button.visible:
		details.text += "\nDefend " + definition.provinces[model.contest().to].name
	_refresh_choice()
	# Public trace excerpts must not disclose hidden rival discoveries or payments.
	rival_feedback.text = "Rivals acted through the same command rules." if s.completed > 0 else ""
	_clear(roster_rows)
	for u in view.units.values():
		if u.province == selected_province:
			if s.heroes.has(u.id):
				_label(
					roster_rows,
					"%s • leader %d life" % [definition.definitions[u.def].name, u.life]
				)
			else:
				_troop_row(u)
	for dead in s.casualties.values():
		if dead.faction == definition.player:
			_label(roster_rows, "%s • casualty" % dead.id)
	_refresh_service()
	_refresh_district(p)
	_refresh_heroes(view)
	feedback.text = message
	feedback.tooltip_text = ""


func _refresh_choice() -> void:
	var d: Dictionary = model.encounter_choice()
	choice_panel.visible = not d.is_empty()
	if d.is_empty():
		return
	var known: Dictionary = d.known
	var title: String = known.get("name", "Unknown frontier")
	choice_text.text = "%s • %s encounter\nWithdraw keeps position and movement." % [title, d.kind]
	if d.kind == "site":
		choice_text.text += (
			"\n" + known.site_name + " • guard survivors " + str(known.site.guards.size())
		)
	elif known.has("garrison"):
		choice_text.text += "\nKnown garrison: " + str(known.garrison)
	else:
		choice_text.text += "\nOpposition unknown."
	choice_text.text += "\nFight spends movement on resolution."
	if d.kind == "site":
		choice_text.text += "\nWin reward %dg / %dc" % [d.reward.gold, d.reward.crystals]
	if d.negotiate:
		choice_text.text += (
			"\nTribute resolves access; no reward or XP."
			if d.kind == "site"
			else "\nTribute grants control and spends movement."
		)
	negotiate_button.visible = d.negotiate
	negotiate_button.text = (
		"Negotiate • %dg / %dc" % [d.price.get("gold", 0), d.price.get("crystals", 0)]
	)
	for pair in [
		[fight_button, "fight"], [withdraw_button, "withdraw"], [negotiate_button, "negotiate"]
	]:
		_set_query(pair[0], {"op": "decide", "choice": pair[1], "token": d.token})


func _choose(choice: String) -> void:
	var d: Dictionary = model.encounter_choice()
	if not d.is_empty():
		issue({"op": "decide", "choice": choice, "token": d.token})


func _wounded() -> Array:
	var result: Array = []
	if model == null:
		return result
	for u in model.faction_view(definition.player).units.values():
		if u.province == selected_province and u.life < definition.definitions[u.def].life:
			result.append(u.id)
	return result


func _buy_service() -> void:
	if service_picker.selected >= 0:
		var command: Dictionary = _choices[service_picker.selected].duplicate(true)
		command["province"] = selected_province
		issue(command)


func _refresh_service() -> void:
	if model == null or service_picker.selected < 0:
		return
	var command: Dictionary = _choices[service_picker.selected].duplicate(true)
	command["province"] = selected_province
	var q := model.query(command)
	service_button.disabled = not q.ok
	var price: Dictionary = model._price(command)
	service_reason.text = (
		"Target %s • %dg / %dc\n%s"
		% [
			selected_province,
			price.gold,
			price.get("crystals", 0),
			q.reason if not q.ok else "One shared faction service slot available."
		]
	)


func _refresh_district(p: Dictionary) -> void:
	_clear(districts)
	_label(districts, "Settlement • " + p.get("name", "Unknown"))
	if p.knowledge != "known":
		return
	_label(districts, "%s • %s" % [p.tier, p.visibility])
	if p.visibility != "current" or p.owner != definition.player:
		_label(districts, "Services require current control.")
	for id in definition.buildings:
		var b: Dictionary = definition.buildings[id]
		if (b.district == "capital") != (p.tier == "capital"):
			continue
		var panel := PanelContainer.new()
		districts.add_child(panel)
		var row := VBoxContainer.new()
		panel.add_child(row)
		_label(
			row,
			"%s district • %s • %dg / %dc" % [b.district.capitalize(), b.name, b.cost, b.crystals]
		)
		var requirements: Array = []
		for required in b.requires:
			requirements.append(definition.buildings[required].name)
		var effect: String = (
			("Unlocks " + definition.definitions[b.value].name)
			if b.effect == "recruit"
			else "+%d %s; +%dc output" % [b.value, b.effect, b.crystal_yield]
		)
		_label(
			row,
			(
				"%s\nRequires: %s\n%s"
				% [
					effect,
					", ".join(requirements) if not requirements.is_empty() else "None",
					"Built round %d" % p.buildings[id] if p.buildings.has(id) else "Unbuilt"
				]
			)
		)
		var command := {"op": "build", "id": id, "province": selected_province}
		var button := _button(row, "Build", func() -> void: issue(command))
		_set_query(button, command)
		_label(row, button.tooltip_text)
	for id in definition.recruits:
		var r: Dictionary = definition.recruits[id]
		var command := {"op": "recruit", "id": id, "province": selected_province}
		var button := _button(
			districts,
			(
				"Recruit %s • %dg / %dc"
				% [definition.definitions[id].name, r.cost, r.get("crystals", 0)]
			),
			func() -> void: issue(command)
		)
		_set_query(button, command)
		_label(districts, button.tooltip_text)


func _refresh_heroes(view: Dictionary) -> void:
	_clear(heroes_panel)
	_label(heroes_panel, "Leader, equipment, army slots and local garrison")
	var s := model.snapshot()
	for role in definition.heroes:
		var h: Dictionary = definition.heroes[role]
		var command := {"op": "hire", "id": role, "province": selected_province}
		var button := _button(
			heroes_panel,
			"Hire %s • %dg / %dc" % [h.name, h.gold, h.crystals],
			func() -> void: issue(command)
		)
		_set_query(button, command)
		_label(heroes_panel, button.tooltip_text)
	for hero in s.heroes:
		if not view.units.has(hero):
			continue
		var u: Dictionary = view.units[hero]
		var stats: Dictionary = model.hero_stats(hero)
		_label(
			heroes_panel,
			(
				"%s • %s • life %d/%d • level %d • XP %d"
				% [
					hero,
					u.army if u.army != "" else "At settlement " + u.province,
					u.life,
					stats.base.life,
					stats.progress.level,
					stats.progress.xp
				]
			)
		)
		_label(
			heroes_panel,
			(
				"Attack base %d / effective %d • Defence base %d / effective %d"
				% [
					stats.base.attack,
					stats.effective.attack,
					stats.base.get("defence", 0),
					stats.effective.get("defence", 0)
				]
			)
		)
		var panes := HBoxContainer.new()
		heroes_panel.add_child(panes)
		var gear := VBoxContainer.new()
		gear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panes.add_child(gear)
		var army := VBoxContainer.new()
		army.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panes.add_child(army)
		_label(gear, "Equipment")
		for type in definition.equipment:
			var e: Dictionary = definition.equipment[type]
			_label(gear, "%s • %s • +%d %s" % [e.name, e.slot, e.value, e.stat])
			var item: String = hero + ":" + type
			var cmd := {"op": "buy", "id": type, "hero": hero, "province": selected_province}
			var title: String = "Buy %s (%dg/%dc)" % [e.name, e.gold, e.crystals]
			if s.inventory.has(item):
				var equipped: bool = s.inventory[item].equipped
				cmd = (
					{"op": "unequip", "hero": hero, "slot": e.slot}
					if equipped
					else {"op": "equip", "hero": hero, "item": item}
				)
				title = ("Unequip " if equipped else "Equip ") + e.name
			var button := _button(gear, title, func() -> void: issue(cmd))
			_set_query(button, cmd)
		_label(army, "Leader assignment")
		for destination in [selected_army, ""]:
			var cmd := {"op": "assign", "hero": hero, "army": destination}
			var button := _button(
				army,
				"Assign selected army" if destination != "" else "Withdraw leader",
				func() -> void: issue(cmd)
			)
			_set_query(button, cmd)
	_label(heroes_panel, "Deployment order • first slot is the first tactical placement")
	if view.armies.has(selected_army):
		var ids := model.members(selected_army)
		for index in ids.size():
			_label(heroes_panel, "Slot %d: %s" % [index + 1, ids[index]])
			if index > 0:
				var reordered := ids.duplicate()
				reordered.remove_at(index)
				reordered.push_front(ids[index])
				var cmd := {"op": "order", "army": selected_army, "units": reordered}
				var button := _button(
					heroes_panel, "Move to first slot", func() -> void: issue(cmd)
				)
				_set_query(button, cmd)
	_label(heroes_panel, "Garrison • use individual transfers in the right pane")
	for u in view.units.values():
		if u.province == selected_province and u.army == "":
			_label(heroes_panel, "%s • %d life" % [u.id, u.life])


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
