class_name BreakwaterUI
extends RefCounted
## Shared maritime-industrial visual tokens and programmatic control builders.

const DEEP_NAVY := Color("07131f")
const ABYSS := Color("040b12")
const SLATE := Color("142635")
const SLATE_LIGHT := Color("203a4c")
const SEA_GLASS := Color("5ed3c6")
const SAFETY_CORAL := Color("ff6b4a")
const MIST := Color("dce8eb")
const FOG := Color("8ea7ad")
const SUN_GOLD := Color("f2c14e")
const INK := Color("091017")

const DISPLAY_FONTS := ["Avenir Next Condensed", "Arial Narrow", "Helvetica Neue"]
const BODY_FONTS := ["Avenir Next", "Helvetica Neue", "Arial"]
const DATA_FONTS := ["SF Mono", "Menlo", "Courier New"]


static func create_theme() -> Theme:
	var theme := Theme.new()
	var display := _system_font(DISPLAY_FONTS, 700)
	var body := _system_font(BODY_FONTS, 500)
	var data := _system_font(DATA_FONTS, 600)

	theme.default_font = body
	theme.default_font_size = 17
	theme.set_font(&"font", &"Label", body)
	theme.set_font_size(&"font_size", &"Label", 17)
	theme.set_color(&"font_color", &"Label", MIST)
	theme.set_color(&"font_shadow_color", &"Label", Color(0.0, 0.0, 0.0, 0.36))
	theme.set_constant(&"shadow_offset_x", &"Label", 1)
	theme.set_constant(&"shadow_offset_y", &"Label", 2)

	theme.set_font(&"font", &"Button", display)
	theme.set_font_size(&"font_size", &"Button", 18)
	theme.set_color(&"font_color", &"Button", MIST)
	theme.set_color(&"font_hover_color", &"Button", DEEP_NAVY)
	theme.set_color(&"font_pressed_color", &"Button", DEEP_NAVY)
	theme.set_color(&"font_focus_color", &"Button", MIST)
	theme.set_color(&"font_disabled_color", &"Button", FOG.darkened(0.35))
	theme.set_constant(&"outline_size", &"Button", 0)
	theme.set_stylebox(&"normal", &"Button", panel_style(Color(SLATE, 0.82), Color(SLATE_LIGHT, 0.7), 1, 7, 14))
	theme.set_stylebox(&"hover", &"Button", panel_style(SEA_GLASS, SEA_GLASS, 1, 7, 14))
	theme.set_stylebox(&"pressed", &"Button", panel_style(SEA_GLASS.darkened(0.12), MIST, 2, 7, 14))
	theme.set_stylebox(&"focus", &"Button", panel_style(Color.TRANSPARENT, SUN_GOLD, 2, 7, 14))
	theme.set_stylebox(&"disabled", &"Button", panel_style(Color(SLATE, 0.45), Color(SLATE_LIGHT, 0.25), 1, 7, 14))

	theme.set_type_variation(&"NavButton", &"Button")
	theme.set_font_size(&"font_size", &"NavButton", 21)
	theme.set_color(&"font_hover_color", &"NavButton", MIST)
	theme.set_color(&"font_pressed_color", &"NavButton", MIST)
	theme.set_stylebox(&"normal", &"NavButton", panel_style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 2, 15))
	theme.set_stylebox(&"hover", &"NavButton", panel_style(Color(SEA_GLASS, 0.12), SEA_GLASS, 0, 2, 15, 4))
	theme.set_stylebox(&"pressed", &"NavButton", panel_style(Color(SEA_GLASS, 0.2), SEA_GLASS, 0, 2, 15, 4))
	theme.set_stylebox(&"focus", &"NavButton", panel_style(Color.TRANSPARENT, SUN_GOLD, 1, 2, 15))

	theme.set_type_variation(&"PrimaryButton", &"Button")
	theme.set_color(&"font_color", &"PrimaryButton", DEEP_NAVY)
	theme.set_color(&"font_hover_color", &"PrimaryButton", DEEP_NAVY)
	theme.set_stylebox(&"normal", &"PrimaryButton", panel_style(SEA_GLASS, SEA_GLASS, 1, 7, 16))
	theme.set_stylebox(&"hover", &"PrimaryButton", panel_style(SEA_GLASS.lightened(0.12), MIST, 1, 7, 16))
	theme.set_stylebox(&"pressed", &"PrimaryButton", panel_style(SEA_GLASS.darkened(0.15), MIST, 2, 7, 16))

	theme.set_type_variation(&"DangerButton", &"Button")
	theme.set_stylebox(&"hover", &"DangerButton", panel_style(SAFETY_CORAL, SAFETY_CORAL, 1, 7, 14))
	theme.set_stylebox(&"pressed", &"DangerButton", panel_style(SAFETY_CORAL.darkened(0.14), MIST, 2, 7, 14))

	theme.set_type_variation(&"DisplayLabel", &"Label")
	theme.set_font(&"font", &"DisplayLabel", display)
	theme.set_font_size(&"font_size", &"DisplayLabel", 62)
	theme.set_color(&"font_color", &"DisplayLabel", MIST)
	theme.set_constant(&"outline_size", &"DisplayLabel", 5)
	theme.set_color(&"font_outline_color", &"DisplayLabel", Color(DEEP_NAVY, 0.72))

	theme.set_type_variation(&"HeadingLabel", &"Label")
	theme.set_font(&"font", &"HeadingLabel", display)
	theme.set_font_size(&"font_size", &"HeadingLabel", 34)
	theme.set_color(&"font_color", &"HeadingLabel", MIST)

	theme.set_type_variation(&"SectionLabel", &"Label")
	theme.set_font(&"font", &"SectionLabel", display)
	theme.set_font_size(&"font_size", &"SectionLabel", 15)
	theme.set_color(&"font_color", &"SectionLabel", SEA_GLASS)

	theme.set_type_variation(&"DataLabel", &"Label")
	theme.set_font(&"font", &"DataLabel", data)
	theme.set_font_size(&"font_size", &"DataLabel", 14)
	theme.set_color(&"font_color", &"DataLabel", FOG)

	theme.set_type_variation(&"ScoreLabel", &"Label")
	theme.set_font(&"font", &"ScoreLabel", data)
	theme.set_font_size(&"font_size", &"ScoreLabel", 28)
	theme.set_color(&"font_color", &"ScoreLabel", MIST)

	theme.set_stylebox(&"panel", &"PanelContainer", panel_style(Color(SLATE, 0.88), Color(SLATE_LIGHT, 0.75), 1, 10, 22))
	theme.set_type_variation(&"GlassPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"GlassPanel", panel_style(Color(DEEP_NAVY, 0.84), Color(SEA_GLASS, 0.32), 1, 8, 22))
	theme.set_type_variation(&"CoralPanel", &"PanelContainer")
	theme.set_stylebox(&"panel", &"CoralPanel", panel_style(Color(SLATE, 0.94), SAFETY_CORAL, 2, 8, 22, 4))

	_style_ranges(theme)
	_style_options(theme)
	return theme


static func panel_style(
		background: Color,
		border: Color,
		border_width := 1,
		corner_radius := 8,
		content_padding := 16,
		left_accent := 0
	) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = maxi(border_width, left_accent)
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.content_margin_left = float(content_padding + left_accent)
	style.content_margin_top = float(content_padding)
	style.content_margin_right = float(content_padding)
	style.content_margin_bottom = float(content_padding)
	return style


static func label(text_value: String, variation := &"", alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text_value
	node.horizontal_alignment = alignment
	if not variation.is_empty():
		node.theme_type_variation = variation
	return node


static func button(text_value: String, variation := &"Button") -> Button:
	var node := Button.new()
	node.text = text_value
	node.theme_type_variation = variation
	node.focus_mode = Control.FOCUS_ALL
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.custom_minimum_size = Vector2(236.0, 54.0)
	return node


static func section_label(text_value: String) -> Label:
	var node := label(text_value.to_upper(), &"SectionLabel")
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return node


static func data_label(text_value: String, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return label(text_value.to_upper(), &"DataLabel", alignment)


static func panel(variation := &"PanelContainer") -> PanelContainer:
	var node := PanelContainer.new()
	node.theme_type_variation = variation
	return node


static func h_rule(color := Color(SEA_GLASS, 0.25)) -> HSeparator:
	var separator := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_top = 1.0
	separator.add_theme_stylebox_override(&"separator", style)
	return separator


static func make_backdrop() -> ColorRect:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = DEEP_NAVY
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return backdrop


static func _system_font(names: Array, weight: int) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(names)
	font.font_weight = weight
	return font


static func _style_ranges(theme: Theme) -> void:
	theme.set_color(&"font_color", &"CheckButton", MIST)
	theme.set_color(&"font_hover_color", &"CheckButton", SEA_GLASS)
	theme.set_font_size(&"font_size", &"CheckButton", 16)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = SLATE_LIGHT
	slider_bg.corner_radius_top_left = 3
	slider_bg.corner_radius_top_right = 3
	slider_bg.corner_radius_bottom_left = 3
	slider_bg.corner_radius_bottom_right = 3
	slider_bg.content_margin_top = 3.0
	slider_bg.content_margin_bottom = 3.0
	var slider_fill := slider_bg.duplicate() as StyleBoxFlat
	slider_fill.bg_color = SEA_GLASS
	theme.set_stylebox(&"slider", &"HSlider", slider_bg)
	theme.set_stylebox(&"grabber_area", &"HSlider", slider_fill)
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", slider_fill)
	var grabber := GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([MIST, SEA_GLASS])
	grabber.gradient = gradient
	grabber.width = 14
	grabber.height = 14
	theme.set_icon(&"grabber", &"HSlider", grabber)
	theme.set_icon(&"grabber_highlight", &"HSlider", grabber)


static func _style_options(theme: Theme) -> void:
	theme.set_font_size(&"font_size", &"OptionButton", 16)
	theme.set_color(&"font_color", &"OptionButton", MIST)
	theme.set_color(&"font_hover_color", &"OptionButton", DEEP_NAVY)
	theme.set_stylebox(&"normal", &"OptionButton", panel_style(Color(SLATE, 0.9), SLATE_LIGHT, 1, 6, 12))
	theme.set_stylebox(&"hover", &"OptionButton", panel_style(SEA_GLASS, SEA_GLASS, 1, 6, 12))
	theme.set_stylebox(&"focus", &"OptionButton", panel_style(Color.TRANSPARENT, SUN_GOLD, 2, 6, 12))
	theme.set_color(&"font_color", &"LineEdit", MIST)
	theme.set_color(&"caret_color", &"LineEdit", SEA_GLASS)
	theme.set_stylebox(&"normal", &"LineEdit", panel_style(Color(SLATE, 0.86), SLATE_LIGHT, 1, 5, 10))
	theme.set_stylebox(&"focus", &"LineEdit", panel_style(Color(SLATE, 0.96), SEA_GLASS, 2, 5, 10))
