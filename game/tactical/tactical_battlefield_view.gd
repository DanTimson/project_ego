class_name TacticalBattlefieldView
extends Node2D

signal cell_clicked(cell: Vector2i)
signal cancel_requested

const SIDE_COLORS := {
	0: Color("3b82f6"),
	1: Color("ef4444"),
}

var scenario: Scenario
var session: ManualBattleSession
var adapter := TacticalCoordinateAdapter.new(Vector2(52.0, 52.0), 34.0)
var asset_resolver: TacticalAssetResolver
var selected: Combatant
var reachable: Array[Vector2i] = []
var melee_targets: Array[Combatant] = []
var ranged_targets: Array[Combatant] = []
var hovered := Vector2i(-1, -1)
var _textures: Dictionary = {}


func configure(p_session: ManualBattleSession, p_resolver: TacticalAssetResolver) -> void:
	session = p_session
	scenario = session.scenario
	asset_resolver = p_resolver
	selected = null
	_textures.clear()
	refresh_highlights(null, [], [], [])


func refresh_highlights(p_selected: Combatant, p_reachable: Array[Vector2i],
		p_melee_targets: Array[Combatant], p_ranged_targets: Array[Combatant]) -> void:
	selected = p_selected
	reachable = p_reachable
	melee_targets = p_melee_targets
	ranged_targets = p_ranged_targets
	queue_redraw()


func _process(_delta: float) -> void:
	if scenario == null:
		return
	var next := adapter.pixel_to_cell(
		get_local_mouse_position(), scenario.field.width, scenario.field.height)
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
	for row in scenario.field.height:
		for col in scenario.field.width:
			var cell := Vector2i(col, row)
			var tile: Battlefield.Tile = scenario.field.tile(
				Battlefield.offset_to_axial(col, row))
			var fill := Color("263445") if tile.passable() else Color("111827")
			if reachable.has(cell):
				fill = Color("285943")
			draw_colored_polygon(adapter.cell_polygon(cell), fill)
			draw_polyline(adapter.cell_polygon(cell), Color("718096"), 2.0, true)
			if cell == hovered:
				draw_polyline(adapter.cell_polygon(cell), Color.WHITE, 3.0, true)
	for unit in session.living_units():
		_draw_unit(unit)


func _draw_unit(unit: Combatant) -> void:
	var cell := session.unit_position(unit)
	var centre := adapter.cell_to_pixel(cell)
	var side := scenario.side_of(unit)
	var color: Color = SIDE_COLORS.get(side.id, Color.GRAY)
	if melee_targets.has(unit):
		color = Color("f59e0b")
	elif ranged_targets.has(unit):
		color = Color("d946ef")
	if not _textures.has(unit.instance_id):
		_textures[unit.instance_id] = asset_resolver.texture_for_unit(unit)
	var texture: Texture2D = _textures[unit.instance_id]
	if texture != null:
		draw_texture_rect(texture, Rect2(centre - Vector2(23.0, 23.0), Vector2(46.0, 46.0)), false)
		draw_arc(centre, 25.0, 0.0, TAU, 32, color, 4.0, true)
	else:
		draw_circle(centre, 23.0, color)
		draw_circle(centre, 18.0, color.darkened(0.25), false, 3.0, true)
		var initial := unit.name.substr(0, 1).to_upper()
		draw_string(ThemeDB.fallback_font, centre + Vector2(-7.0, 7.0), initial,
			HORIZONTAL_ALIGNMENT_CENTER, 14.0, 18, Color.WHITE)
	if unit == selected:
		draw_arc(centre, 29.0, 0.0, TAU, 32, Color("67e8f9"), 4.0, true)
	var life_ratio := clampf(float(maxi(0, unit.life)) / float(unit.life_base), 0.0, 1.0)
	draw_rect(Rect2(centre + Vector2(-24.0, 27.0), Vector2(48.0, 5.0)), Color("111827"))
	draw_rect(Rect2(centre + Vector2(-24.0, 27.0), Vector2(48.0 * life_ratio, 5.0)), Color("22c55e"))
