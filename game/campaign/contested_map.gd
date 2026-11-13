extends Control

signal inspected(id: String)
var model: ContestedCampaign
var selected := ""
var resolver: TacticalAssetResolver
var buttons: Dictionary = {}


func display(campaign: ContestedCampaign, province: String) -> void:
	model = campaign
	selected = province
	if buttons.is_empty():
		for id in model.content().provinces:
			var button := Button.new()
			button.custom_minimum_size = Vector2(126, 72)
			button.add_theme_font_size_override("font_size", 13)
			button.pressed.connect(func() -> void: inspected.emit(id))
			add_child(button)
			buttons[id] = button
	if not resized.is_connected(_layout):
		resized.connect(_layout)
	var s := model.snapshot()
	var c := model.content()
	for id in buttons:
		var army := model.field_at(id)
		var position := "Garrison %d" % model.members("", id).size()
		if army != "":
			position += " • Move %d" % s.armies[army].moves
		buttons[id].text = "%s\n%s • +%dg\n%s" % [c.provinces[id].name,
			s.provinces[id].owner.capitalize() if s.provinces[id].owner != "" else "Neutral",
			model.province_income(id, true), position]
		buttons[id].tooltip_text = "Next payout +%dg • %s" % [model.province_income(id, true), army]
		buttons[id].modulate = Color("badbff") if s.provinces[id].owner == c.player \
			else Color("ffceba") if s.provinces[id].owner != "" else Color.WHITE
	_layout()


func _layout() -> void:
	if model == null:
		return
	var c := model.content()
	for id in buttons:
		var point: Array = c.provinces[id].point
		buttons[id].position = Vector2(12, 16) + Vector2(point[0], point[1]) \
			* (size - Vector2(150, 110))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("43513a"))
	var grass := resolver.texture_for_named("ui", "map_grass") if resolver != null else null
	if grass != null:
		draw_texture_rect(grass, Rect2(Vector2.ZERO, size), true, Color("c5c7a3"))
	if model == null:
		return
	for id in buttons:
		for other in model.content().provinces[id].links:
			if id < other:
				draw_line(buttons[id].position + Vector2(63, 36),
					buttons[other].position + Vector2(63, 36), Color("ddc792"), 3, true)
	if buttons.has(selected):
		draw_rect(buttons[selected].get_rect().grow(4), Color("ffe0a0"), false, 2)
