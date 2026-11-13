extends Control

## Authored layout, optional inspected sprites. Positions make no legacy layout claim.
var resolver: TacticalAssetResolver
var buildings: Array = []
var catalogue_size := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var row_count := maxi(1, ceili(catalogue_size / 3.0))
	for building in buildings:
		var slot: int = building.settlement_slot
		@warning_ignore("integer_division")
		var row := slot / 3
		var centre := Vector2(size.x * (0.22 + (slot % 3) * 0.27),
			size.y * (0.59 + row * 0.44 / row_count))
		var texture := resolver.texture_for_named("ui", "castle_" + building.id)
		if texture != null:
			var factor := minf(100.0 / texture.get_width(), 90.0 / texture.get_height())
			var extent := texture.get_size() * factor
			draw_texture_rect(texture, Rect2(centre - extent * Vector2(0.5, 1), extent), false)
		else:
			draw_rect(Rect2(centre - Vector2(32, 40), Vector2(64, 40)), Color("b59a72"))
			draw_colored_polygon(PackedVector2Array([
				centre + Vector2(-40, -40), centre + Vector2(0, -66),
				centre + Vector2(40, -40)]), Color("703c31"))
			draw_rect(Rect2(centre - Vector2(8, 24), Vector2(16, 24)), Color("33312c"))
		draw_rect(Rect2(centre + Vector2(-72, 3), Vector2(144, 22)), Color(0.08, 0.1, 0.1, 0.9))
		draw_string(ThemeDB.fallback_font, centre + Vector2(-70, 19), building.name,
			HORIZONTAL_ALIGNMENT_CENTER, 140, 14, Color("fff0c7"))
