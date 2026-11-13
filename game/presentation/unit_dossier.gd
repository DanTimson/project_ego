class_name UnitDossier
extends Control

# Inspected Battlefield:02Panel: portrait [9,18,64,80]; value cells at
# [78,18,55,24], [78,43,55,24], [78,69,55,24]. The remaining native
# panel is split into independently framed stat/action/effect groups.
var resolver: TacticalAssetResolver
var unit: Combatant


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if resolver == null:
		return
	var panel := resolver.texture_for_named("ui", "panel")
	if panel != null and panel.get_size() == Vector2(140, 768):
		draw_texture_rect_region(panel, Rect2(0, 0, 140, 120), Rect2(0, 0, 140, 120))
		var values := (
			[
				str(maxi(0, unit.life)),
				str(unit.stamina),
				str(unit.morale),
				str(unit.movement_remaining)
			]
			if unit != null
			else ["—", "—", "—", "—"]
		)
		for index in 4:
			# Bind known Ability icons explicitly instead of inferring panel glyph semantics.
			var at := Vector2(78, 18 + index * 25)
			if index < 3:
				draw_rect(Rect2(at, Vector2(55, 24)), Color("181710"))
				var icon := resolver.texture_for_named("ui", ["life", "stamina", "morale"][index])
				if icon != null:
					draw_texture_rect(icon, Rect2(at, Vector2(21, 21)), false)
			draw_string(
				ThemeDB.fallback_font,
				at + Vector2(25, 18),
				values[index],
				HORIZONTAL_ALIGNMENT_CENTER,
				29,
				13,
				Color("fff1c5")
			)
	else:
		# Authored portrait silhouette; the foreground texture takes precedence.
		draw_rect(Rect2(4, 4, 132, 112), Color("263530"))
		draw_circle(Vector2(70, 42), 21, Color("b8b6a0"))
		draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(40, 69),
					Vector2(70, 59),
					Vector2(100, 69),
					Vector2(112, 116),
					Vector2(28, 116)
				]
			),
			Color("657d84")
		)
		draw_rect(Rect2(54, 38, 32, 7), Color("28302e"))
		draw_line(Vector2(70, 27), Vector2(70, 57), Color("e3d1a3"), 2)
