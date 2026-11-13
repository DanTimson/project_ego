class_name PresentationTheme
extends RefCounted


static func frame(fill := Color("251e19"), border := Color("92764a")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


static func create() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.default_font = ThemeDB.get_default_theme().get_font("font", "Label")
	result.set_color("font_color", "Label", Color("eee1bf"))
	result.set_color("default_color", "RichTextLabel", Color("e3d5b4"))
	result.set_stylebox("panel", "PanelContainer", frame())
	result.set_stylebox("normal", "Button", frame(Color("302820")))
	result.set_stylebox("hover", "Button", frame(Color("51412b"), Color("e2c47b")))
	result.set_stylebox("pressed", "Button", frame(Color("181e1b"), Color("e2c47b")))
	result.set_stylebox("disabled", "Button", frame(Color("242321"), Color("534c3d")))
	var focus := frame(Color(0, 0, 0, 0), Color("ffe5a1"))
	focus.set_border_width_all(2)
	result.set_stylebox("focus", "Button", focus)
	result.set_color("font_color", "Button", Color("f4e6c3"))
	result.set_color("font_disabled_color", "Button", Color("999387"))
	return result


static func crop(texture: Texture2D, region: Rect2) -> Texture2D:
	if texture == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	return atlas


static func textured(texture: Texture2D, border := 5) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, border)
		style.set_content_margin(side, border + 3)
	return style


static func apply_menu_button(button: Button, resolver: TacticalAssetResolver) -> void:
	var ink := Color("26190c")
	var normal := resolver.texture_for_named("ui", "menu_normal")
	if normal != null:
		button.add_theme_stylebox_override("normal", textured(normal, 10))
		button.add_theme_color_override("font_color", ink)
		button.add_theme_color_override("font_focus_color", ink)
	var hover := resolver.texture_for_named("ui", "menu_hover")
	if hover != null:
		button.add_theme_stylebox_override("hover", textured(hover, 10))
		button.add_theme_stylebox_override("pressed", textured(hover, 10))
		for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(state, ink)
