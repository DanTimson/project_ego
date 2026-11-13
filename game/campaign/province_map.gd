extends Control

signal destination_chosen(id: String)

const LOCATIONS := {
	"home": Vector2(0.0, 0.5),
	"ford": Vector2(0.33, 0.15),
	"quarry": Vector2(0.33, 0.85),
	"watchpost": Vector2(0.67, 0.15),
	"mill": Vector2(0.67, 0.85),
	"keep": Vector2(1.0, 0.5),
}
var buttons: Dictionary = {}
var resolver: TacticalAssetResolver
var _content: Dictionary = {}
var _state: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(580, 300)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	for id in LOCATIONS:
		var button := Button.new()
		button.name = id.capitalize()
		button.size = Vector2(114, 110)
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_color_override("font_disabled_color", Color("e1d9bd"))
		for state in ["normal", "disabled"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.add_theme_stylebox_override(
			"hover", PresentationTheme.frame(Color(0.9, 0.8, 0.5, 0.13))
		)
		button.add_theme_stylebox_override("pressed", PresentationTheme.frame(Color(0, 0, 0, 0.2)))
		button.pressed.connect(func() -> void: destination_chosen.emit(id))
		add_child(button)
		buttons[id] = button
	resized.connect(_layout)
	_layout()


func display(campaign: StrategicCampaign) -> void:
	_content = campaign.content()
	_state = campaign.snapshot()
	for id in buttons:
		var province: Dictionary = _content.provinces[id]

		var query := campaign.query("travel", id)
		buttons[id].disabled = not query.ok
		buttons[id].tooltip_text = (
			("You are here. " if id == _state.position else "")
			+ (
				("Travel to " if id in _state.owned else "Battle for ") + province.name
				if query.ok
				else query.reason
			)
		)
	queue_redraw()


func _layout() -> void:
	for id in buttons:
		buttons[id].position = Vector2(10, 8) + LOCATIONS[id] * (size - Vector2(134, 126))
	queue_redraw()


func _art(slot: String, at: Vector2, extent: Vector2) -> bool:
	var texture := resolver.texture_for_named("ui", slot) if resolver != null else null
	if texture == null:
		return false
	var drawn := (
		texture.get_size() * minf(extent.x / texture.get_width(), extent.y / texture.get_height())
	)
	draw_texture_rect(texture, Rect2(at - drawn * 0.5, drawn), false)
	return true


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("43513a"))
	var grass := resolver.texture_for_named("ui", "map_grass") if resolver != null else null
	if grass != null:
		draw_texture_rect(grass, Rect2(Vector2.ZERO, size), true, Color("c5c7a3"))
	var river := PackedVector2Array()
	for step in 33:
		var y := size.y * step / 32.0
		river.append(Vector2(size.x * 0.36 + sin(y * 0.027) * 17, y))
	draw_polyline(river, Color("3c4633"), 21, true)
	draw_polyline(river, Color("6c9693"), 12, true)
	for index in 70:
		var at := Vector2(fmod(index * 97.0 + 48, size.x), fmod(index * 71.0 + 30, size.y))
		var clear := true
		for button in buttons.values():
			if button.get_rect().grow(12).has_point(at):
				clear = false
		if clear and not _art("map_tree", at, Vector2(35, 46)):
			draw_colored_polygon(
				PackedVector2Array(
					[at + Vector2(-12, 10), at + Vector2(0, -23), at + Vector2(12, 10)]
				),
				Color("243d2c")
			)
	_art("map_mountain", Vector2(size.x * 0.5, size.y * 0.5), Vector2(130, 85))
	if _content.is_empty():
		return
	for id in buttons:
		for neighbor in _content.provinces[id].links:
			if id < neighbor:
				var start: Vector2 = buttons[id].position + Vector2(57, 42)
				var end: Vector2 = buttons[neighbor].position + Vector2(57, 42)
				draw_line(start, end, Color("233428"), 7, true)
				draw_dashed_line(start, end, Color("cdb983"), 2, 7, true)
				if id == _state.position or neighbor == _state.position:
					_art("route_marker", start.lerp(end, 0.5), Vector2(22, 12))
	for id in buttons:
		var centre: Vector2 = buttons[id].position + Vector2(57, 35)
		draw_rect(Rect2(centre + Vector2(-57, 26), Vector2(114, 49)), Color(0.06, 0.09, 0.06, 0.85))
		if id == _state.position:
			if not _art("position_ring", centre + Vector2(0, 22), Vector2(90, 30)):
				draw_arc(centre + Vector2(0, 16), 35, 0, TAU, 36, Color("ffe9a4"), 4, true)
			draw_string(
				ThemeDB.fallback_font,
				centre + Vector2(-24, -31),
				"HERE",
				0,
				-1,
				12,
				Color("fff1b9")
			)
		if not _art("map_" + id, centre, Vector2(63, 62)):
			_draw_landmark(centre, id)
		var owned: bool = id in _state.owned
		var province: Dictionary = _content.provinces[id]
		var title: String = province.name + (" ★" if id == "keep" else "")
		draw_string(
			ThemeDB.fallback_font,
			centre + Vector2(-57, 43),
			title,
			HORIZONTAL_ALIGNMENT_CENTER,
			114,
			16,
			Color("fff0c7")
		)
		draw_string(
			ThemeDB.fallback_font,
			centre + Vector2(-57, 63),
			"%s • +%dg" % ["Allied" if owned else "Hostile", province.income],
			HORIZONTAL_ALIGNMENT_CENTER,
			114,
			13,
			Color("eee0bd")
		)
		if not _art(
			"owner_friendly" if owned else "owner_hostile",
			centre + Vector2(35, -10),
			Vector2(21, 25)
		):
			var shield := centre + Vector2(25, -22)
			draw_colored_polygon(
				PackedVector2Array(
					[
						shield,
						shield + Vector2(19, 0),
						shield + Vector2(19, 17),
						shield + Vector2(9, 25),
						shield + Vector2(0, 17)
					]
				),
				Color("437bb2") if owned else Color("a84939")
			)
			draw_string(
				ThemeDB.fallback_font, shield + Vector2(4, 15), "+" if owned else "!", 0, -1, 13
			)
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color("bc9c60"), false, 2)


func _draw_landmark(at: Vector2, id: String) -> void:
	if id == "quarry":
		draw_colored_polygon(
			PackedVector2Array(
				[
					at + Vector2(-28, 20),
					at + Vector2(-7, -23),
					at + Vector2(13, -10),
					at + Vector2(31, 20)
				]
			),
			Color("929384")
		)
		return
	if id == "ford":
		draw_line(at + Vector2(-29, 4), at + Vector2(29, 4), Color("d0bd8f"), 18, true)
		for offset in [-8, 15]:
			draw_line(at + Vector2(-29, offset), at + Vector2(29, offset), Color("4c3c27"), 3)
		return
	if id == "keep":
		for offset in [-29, 13]:
			draw_rect(Rect2(at + Vector2(offset, -24), Vector2(16, 44)), Color("b0ad91"))
			for tooth in 3:
				draw_rect(
					Rect2(at + Vector2(offset + tooth * 6, -30), Vector2(4, 8)), Color("b0ad91")
				)
	var height := 45 if id in ["keep", "watchpost"] else 28
	draw_rect(Rect2(at + Vector2(-20, 20 - height), Vector2(40, height)), Color("ada27e"))
	draw_colored_polygon(
		PackedVector2Array(
			[
				at + Vector2(-27, 20 - height),
				at + Vector2(0, -height),
				at + Vector2(27, 20 - height)
			]
		),
		Color("5f4332")
	)
	draw_rect(Rect2(at + Vector2(-5, 2), Vector2(10, 18)), Color("30291e"))
	if id == "mill":
		for direction in [Vector2(25, 25), Vector2(25, -25)]:
			draw_line(at - direction, at + direction, Color("e2d3a5"), 5, true)
