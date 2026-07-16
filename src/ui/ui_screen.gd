class_name BreakwaterUIScreen
extends Control
## Base class for full-screen programmatic menus.

signal screen_requested(screen_id: StringName)
signal back_requested

var content_root: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = BreakwaterUI.create_theme()
	_build_once()


func _build_once() -> void:
	if content_root != null:
		return
	add_child(BreakwaterUI.make_backdrop())
	content_root = Control.new()
	content_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content_root)
	build_screen()


func build_screen() -> void:
	pass


func focus_default() -> void:
	pass


func open() -> void:
	show()
	focus_default()


func close() -> void:
	hide()


func make_page_layout(title_text: String, eyebrow: String) -> Dictionary:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 72)
	margin.add_theme_constant_override(&"margin_top", 50)
	margin.add_theme_constant_override(&"margin_right", 72)
	margin.add_theme_constant_override(&"margin_bottom", 48)
	content_root.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override(&"separation", 11)
	margin.add_child(stack)
	stack.add_child(BreakwaterUI.section_label(eyebrow))
	stack.add_child(BreakwaterUI.label(title_text.to_upper(), &"HeadingLabel"))
	stack.add_child(BreakwaterUI.h_rule())
	return {"margin": margin, "stack": stack}


func make_footer_hint(text_value: String) -> Label:
	var hint := BreakwaterUI.data_label(text_value)
	hint.modulate = Color(BreakwaterUI.FOG, 0.84)
	return hint
