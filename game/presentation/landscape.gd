class_name PresentationLandscape
extends Control

var resolver: TacticalAssetResolver
var mode := "menu"
var _menu_shade: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	var shade := Gradient.new()
	shade.offsets = PackedFloat32Array([0.0, 0.32, 1.0])
	shade.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0),
		Color(0.03, 0.025, 0.02, 0.64)])
	_menu_shade = GradientTexture2D.new()
	_menu_shade.gradient = shade
	_menu_shade.width = 256
	_menu_shade.height = 1


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color("131c22"))
	var texture: Texture2D
	if resolver != null:
		texture = resolver.texture_for_named(
			"ui", "home_background" if mode == "home" else "menu_panorama"
		)
	if texture != null:
		# Uniform cover: crop source rather than distorting the inspected panorama.
		var factor := maxf(size.x / texture.get_width(), size.y / texture.get_height())
		var source_size := size / factor
		var source := Rect2((texture.get_size() - source_size) * 0.5, source_size)
		draw_texture_rect_region(texture, bounds, source)
	else:
		_draw_authored_landscape()
	if mode == "menu":
		# Leave the illustration open on the left; darken the reading area on the right.
		draw_texture_rect(_menu_shade, bounds, false)


func _draw_authored_landscape() -> void:
	# Authored vector scenery; deterministic and independent of campaign state/RNG.
	for index in 24:
		var band := Color("263e48").lerp(Color("b49966"), index / 24.0)
		draw_rect(Rect2(0, size.y * index / 24.0, size.x, size.y / 24.0 + 1), band)
	draw_circle(size * Vector2(0.28, 0.26), size.y * 0.09, Color("dcc48b"))
	for layer in 4:
		var ridge := PackedVector2Array([Vector2(0, size.y)])
		for step in 25:
			var x := size.x * step / 24.0
			var y := size.y * (0.43 + layer * 0.13 + sin(step * 0.67 + layer) * 0.075)
			ridge.append(Vector2(x, y))
		ridge.append(size)
		draw_colored_polygon(ridge, Color("425f59").darkened(layer * 0.17))
	var keep := size * Vector2(0.24, 0.49)
	for tower in 3:
		var at := keep + Vector2(tower * 29, -tower % 2 * 16)
		draw_rect(Rect2(at, Vector2(23, 74)), Color("182b30"))
		draw_colored_polygon(
			PackedVector2Array([at + Vector2(-5, 0), at + Vector2(11, -28), at + Vector2(28, 0)]),
			Color("2f3432")
		)
	for index in 38:
		var at := Vector2(
			fmod(index * 137.0 + 25, size.x), size.y * (0.72 + fmod(index * 0.071, 0.26))
		)
		var h := 20 + index % 4 * 9
		draw_colored_polygon(
			PackedVector2Array([at, at + Vector2(12, -h), at + Vector2(24, 0)]), Color("142a24")
		)
