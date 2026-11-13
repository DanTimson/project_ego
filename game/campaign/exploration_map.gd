extends "res://game/campaign/contested_map.gd"

var view: Dictionary = {}


func display(campaign: ContestedCampaign, province: String) -> void:
	model = campaign
	selected = province
	view = model.faction_view(model.content().player)
	if buttons.is_empty():
		for id in view.provinces:
			var button := Button.new()
			button.custom_minimum_size = Vector2(126, 72)
			button.add_theme_font_size_override("font_size", 13)
			button.pressed.connect(func() -> void: inspected.emit(id))
			add_child(button)
			buttons[id] = button
	if not resized.is_connected(_layout):
		resized.connect(_layout)
	for id in buttons:
		var p: Dictionary = view.provinces[id]
		if p.knowledge != "known":
			buttons[id].text = (
				"Unexplored space" if p.knowledge == "unknown" else "Frontier\nReachable route"
			)
			buttons[id].modulate = Color("777b86") if p.knowledge == "unknown" else Color("c1b18b")
			buttons[id].tooltip_text = "No province details discovered."
		else:
			buttons[id].text = (
				"%s • %d%%\n%s • %s\n%dg / %dc • %s"
				% [
					p.name,
					p.progress,
					p.terrain,
					p.owner if p.owner != "" else "Neutral",
					p.payout.gold,
					p.payout.crystals,
					p.visibility
				]
			)
			buttons[id].tooltip_text = "%s • Stability %d" % [p.visibility, p.stability]
			buttons[id].modulate = (
				Color("badbff")
				if p.owner == model.content().player
				else Color("ffceba") if p.owner != "" else Color.WHITE
			)
	_layout()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("202631"))
	if model == null:
		return
	for id in buttons:
		var p: Dictionary = view.provinces[id]
		var rect: Rect2 = buttons[id].get_rect().grow(18)
		if p.knowledge == "known":
			var grass := resolver.texture_for_named("ui", "map_grass") if resolver != null else null
			draw_rect(rect, Color("4b6042") if p.terrain == "Woodland" else Color("77734b"))
			if grass != null:
				draw_texture_rect(grass, rect, true, Color(1, 1, 1, 0.4))
			# Authored landmark: castle towers or village roof, independent of private art.
			var center: Vector2 = rect.position + Vector2(rect.size.x / 2, -8)
			if p.tier == "capital":
				for offset in [-15, 0, 15]:
					draw_rect(Rect2(center + Vector2(offset, -12), Vector2(8, 14)), Color("c6b78b"))
			else:
				draw_colored_polygon(
					PackedVector2Array(
						[
							center + Vector2(-12, 0),
							center + Vector2(0, -12),
							center + Vector2(12, 0)
						]
					),
					Color("b69765")
				)
		for other in p.links:
			if id < other:
				draw_line(
					buttons[id].position + Vector2(63, 36),
					buttons[other].position + Vector2(63, 36),
					Color("c6ae7b"),
					3,
					true
				)
	if buttons.has(selected):
		draw_rect(buttons[selected].get_rect().grow(4), Color("ffe0a0"), false, 2)
