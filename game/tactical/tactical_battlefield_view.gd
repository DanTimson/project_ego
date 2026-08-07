class_name TacticalBattlefieldView
extends Node2D

signal cell_clicked(cell: Vector2i)
signal cancel_requested

const SIDE_COLORS := {0: Color("4f8fd8"), 1: Color("c84b45")}
const LAYER_TERRAIN := 0
const LAYER_VARIATION := 10
const LAYER_DECORATION := 20
const LAYER_GRID := 30
const LAYER_SHADOW := 40
const LAYER_UNIT := 50
const LAYER_BARS := 60
const LAYER_TARGET := 70
const LAYER_UI := 100
const FIELD_RECT := Rect2(Vector2(-8.0, -8.0), Vector2(848.0, 736.0))
const UNIT_HEIGHT := 94.0
const UNIT_FOOT_Y := 39.0

var scenario: Scenario
var session: ManualBattleSession
var adapter := TacticalCoordinateAdapter.new(Vector2(58.0, 174.0), 50.0)
var asset_resolver: TacticalAssetResolver
var selected: Combatant
var reachable: Array[Vector2i] = []
var melee_targets: Array[Combatant] = []
var ranged_targets: Array[Combatant] = []
var hovered := Vector2i(-1, -1)
var _textures: Dictionary = {}
var _shadow_textures: Dictionary = {}
var _terrain_texture: Texture2D
var _variation_textures: Array[Texture2D] = []
var _decoration_textures: Array[Texture2D] = []


func configure(p_session: ManualBattleSession, p_resolver: TacticalAssetResolver) -> void:
	session = p_session
	scenario = session.scenario
	asset_resolver = p_resolver
	selected = null
	_textures.clear()
	_shadow_textures.clear()
	_variation_textures.clear()
	_decoration_textures.clear()
	_terrain_texture = asset_resolver.texture_for_named(
		TacticalAssetResolver.CATEGORY_TERRAIN, "base")
	for index in 4:
		var variation := asset_resolver.texture_for_named(
			TacticalAssetResolver.CATEGORY_TERRAIN, "variation_%d" % index)
		if variation != null:
			_variation_textures.append(variation)
	for key in asset_resolver.logical_keys_for_category(
		TacticalAssetResolver.CATEGORY_DECORATIONS):
		var decoration := asset_resolver.texture_for_key(key)
		if decoration != null:
			_decoration_textures.append(decoration)
	refresh_highlights(null, [], [], [])


func refresh_highlights(p_selected: Combatant, p_reachable: Array[Vector2i],
		p_melee_targets: Array[Combatant], p_ranged_targets: Array[Combatant]) -> void:
	selected = p_selected
	reachable = p_reachable
	melee_targets = p_melee_targets
	ranged_targets = p_ranged_targets
	queue_redraw()


func presentation_layers() -> Array[int]:
	return [LAYER_TERRAIN, LAYER_VARIATION, LAYER_DECORATION, LAYER_GRID,
		LAYER_SHADOW, LAYER_UNIT, LAYER_BARS, LAYER_TARGET, LAYER_UI]


func unit_faces_right_for_side(side_id: int) -> bool:
	# Inspected Units.dat figures naturally face screen-right.  The synthetic
	# left deployment is side 0, so it keeps that facing; side 1 is mirrored.
	return side_id == 0


func facing_scale_x_for_side(side_id: int) -> float:
	return 1.0 if unit_faces_right_for_side(side_id) else -1.0


func overlay_scale_x_for_side(_side_id: int) -> float:
	return 1.0


func hit_test_local(pixel: Vector2) -> Vector2i:
	if scenario == null:
		return Vector2i(-1, -1)
	return adapter.pixel_to_cell(pixel, scenario.field.width, scenario.field.height)


func terrain_source() -> String:
	return "local" if _terrain_texture != null else "fallback"


func decoration_index(cell: Vector2i, count: int) -> int:
	if count <= 0:
		return -1
	return posmod(cell.x * 37 + cell.y * 71 + 19, count)


func should_decorate(cell: Vector2i) -> bool:
	return posmod(cell.x * 17 + cell.y * 29 + 7, 5) in [0, 2]


func sprite_rect(texture: Texture2D) -> Rect2:
	var source_size := texture.get_size()
	var aspect := source_size.x / maxf(1.0, source_size.y)
	var size := Vector2(UNIT_HEIGHT * aspect, UNIT_HEIGHT)
	return Rect2(Vector2(-size.x * 0.5, -UNIT_HEIGHT + UNIT_FOOT_Y), size)


func _process(_delta: float) -> void:
	if scenario == null:
		return
	var next := hit_test_local(get_local_mouse_position())
	if next != hovered:
		hovered = next
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and hovered.x >= 0:
			cell_clicked.emit(hovered)
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if scenario == null:
		return
	_draw_base_terrain()
	_draw_tile_variation_and_decoration()
	_draw_grid()
	for unit in session.living_units():
		_draw_unit_shadow(unit)
	for unit in session.living_units():
		_draw_unit_sprite(unit)
	for unit in session.living_units():
		_draw_unit_overlays(unit)


func _draw_base_terrain() -> void:
	if _terrain_texture != null:
		draw_texture_rect(_terrain_texture, FIELD_RECT, true,
			Color(0.78, 0.78, 0.72, 1.0))
		return
	draw_rect(FIELD_RECT, Color("31402f"))
	# Project-authored deterministic fallback texture keeps the full field usable.
	for y in range(-8, 728, 32):
		for x in range(-8, 840, 32):
			var alternate := posmod((x + 8) / 32 + (y + 8) / 32, 2) == 0
			var color := Color("40533a") if alternate else Color("374832")
			draw_rect(Rect2(Vector2(x, y), Vector2(32.0, 32.0)), color)


func _draw_tile_variation_and_decoration() -> void:
	for row in scenario.field.height:
		for col in scenario.field.width:
			var cell := Vector2i(col, row)
			var centre := adapter.cell_to_pixel(cell)
			if not _variation_textures.is_empty():
				var variation_index := decoration_index(cell, _variation_textures.size())
				var variation := _variation_textures[variation_index]
				draw_texture_rect(variation,
					Rect2(centre - Vector2(50.0, 50.0), Vector2(100.0, 100.0)),
					false, Color(1.0, 1.0, 1.0, 0.28))
			if should_decorate(cell) and not _decoration_textures.is_empty():
				var index := decoration_index(cell, _decoration_textures.size())
				var texture := _decoration_textures[index]
				var size := texture.get_size()
				var scale := minf(1.0, 56.0 / maxf(size.x, size.y))
				var drawn_size := size * scale
				draw_texture_rect(texture, Rect2(
					centre + Vector2(-drawn_size.x * 0.5, 14.0 - drawn_size.y),
					drawn_size), false, Color(1.0, 1.0, 1.0, 0.82))


func _draw_grid() -> void:
	for row in scenario.field.height:
		for col in scenario.field.width:
			var cell := Vector2i(col, row)
			var tile: Battlefield.Tile = scenario.field.tile(
				Battlefield.offset_to_axial(col, row))
			var fill := Color(0.09, 0.14, 0.12, 0.10)
			if not tile.passable():
				fill = Color(0.08, 0.09, 0.08, 0.58)
			if reachable.has(cell):
				fill = Color(0.12, 0.48, 0.27, 0.45)
			draw_colored_polygon(adapter.cell_polygon(cell), fill)
			draw_polyline(adapter.cell_polygon(cell), Color(0.78, 0.72, 0.48, 0.72),
				2.0, true)
			if cell == hovered:
				draw_polyline(adapter.cell_polygon(cell), Color.WHITE, 3.0, true)


func _draw_unit_shadow(unit: Combatant) -> void:
	if not _shadow_textures.has(unit.instance_id):
		_shadow_textures[unit.instance_id] = asset_resolver.texture_for_shadow(unit)
	var texture: Texture2D = _shadow_textures[unit.instance_id]
	if texture == null:
		return
	var centre := adapter.cell_to_pixel(session.unit_position(unit))
	var side_id := scenario.side_of(unit).id
	draw_set_transform(centre, 0.0, Vector2(facing_scale_x_for_side(side_id), 1.0))
	draw_texture_rect(texture, sprite_rect(texture), false,
		Color(1.0, 1.0, 1.0, 0.42))
	draw_set_transform(Vector2.ZERO)


func _draw_unit_sprite(unit: Combatant) -> void:
	if not _textures.has(unit.instance_id):
		_textures[unit.instance_id] = asset_resolver.texture_for_unit(unit)
	var texture: Texture2D = _textures[unit.instance_id]
	var centre := adapter.cell_to_pixel(session.unit_position(unit))
	var side_id := scenario.side_of(unit).id
	if texture != null:
		draw_set_transform(centre, 0.0, Vector2(facing_scale_x_for_side(side_id), 1.0))
		draw_texture_rect(texture, sprite_rect(texture), false)
		draw_set_transform(Vector2.ZERO)
	else:
		_draw_placeholder_unit(unit, centre, side_id)


func _draw_placeholder_unit(unit: Combatant, centre: Vector2, side_id: int) -> void:
	var direction := facing_scale_x_for_side(side_id)
	var color: Color = SIDE_COLORS.get(side_id, Color.GRAY)
	var body := PackedVector2Array([
		centre + Vector2(-20.0 * direction, -27.0),
		centre + Vector2(23.0 * direction, 0.0),
		centre + Vector2(-20.0 * direction, 27.0),
	])
	draw_colored_polygon(body, color.darkened(0.2))
	draw_polyline(body, color.lightened(0.25), 3.0, true)
	draw_circle(centre + Vector2(-5.0 * direction, -3.0), 15.0, color)
	draw_string(ThemeDB.fallback_font, centre + Vector2(-7.0, 6.0),
		unit.name.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
		14.0, 17, Color.WHITE)


func _draw_unit_overlays(unit: Combatant) -> void:
	var centre := adapter.cell_to_pixel(session.unit_position(unit))
	var side_id := scenario.side_of(unit).id
	var color: Color = SIDE_COLORS.get(side_id, Color.GRAY)
	if melee_targets.has(unit):
		color = Color("f5a524")
	elif ranged_targets.has(unit):
		color = Color("d75bdc")
	draw_arc(centre + Vector2(0.0, 30.0), 27.0, 0.0, TAU, 32, color, 3.0, true)
	var life_ratio := clampf(float(maxi(0, unit.life)) / float(unit.life_base), 0.0, 1.0)
	var bar_position := centre + Vector2(-25.0, 43.0)
	draw_rect(Rect2(bar_position, Vector2(50.0, 7.0)), Color("17130f"))
	draw_rect(Rect2(bar_position + Vector2(1.0, 1.0),
		Vector2(48.0 * life_ratio, 5.0)), Color("51b847"))
	if unit == selected:
		draw_arc(centre + Vector2(0.0, 30.0), 32.0, 0.0, TAU, 32,
			Color("70e6ef"), 4.0, true)
