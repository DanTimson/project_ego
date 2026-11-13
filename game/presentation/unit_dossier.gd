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
