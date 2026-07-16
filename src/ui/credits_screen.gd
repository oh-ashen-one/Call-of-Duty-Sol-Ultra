class_name BreakwaterCreditsScreen
extends BreakwaterUIScreen
## Credits and asset-origin disclosure.

var _back_button: Button


func build_screen() -> void:
	var layout := make_page_layout("Credits + provenance", "BREAKWATER SYSTEMS / MANIFEST")
	var stack: VBoxContainer = layout.stack
	var panel := BreakwaterUI.panel(&"GlassPanel")
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override(&"separation", 18)
	scroll.add_child(copy)
	_add_credit(copy, "PROJECT BREAKWATER", "An original offline arena FPS training simulation.")
	_add_credit(copy, "DESIGN + ENGINEERING", "Built in Godot with original systems, layouts, names, and game rules.")
	_add_credit(copy, "BREAKWATER STATION", "Original coastal research-base environment designed for eight-combatant free-for-all.")
	_add_credit(copy, "VISUAL LANGUAGE", "Maritime-industrial interface using procedurally drawn controls and macOS system typography fallbacks.")
	_add_credit(copy, "ASSET POLICY", "Only original, procedural, AI-generated, or redistributable free assets may ship. See ATTRIBUTIONS.md in the repository for the authoritative manifest.")
	_add_credit(copy, "TRADEMARK NOTICE", "Project Breakwater is an original work and is not affiliated with or endorsed by any other game publisher or franchise.")
	copy.add_child(BreakwaterUI.h_rule())
	copy.add_child(BreakwaterUI.data_label("ENGINE  GODOT 4.7  •  MODE  OFFLINE PRACTICE  •  TARGET  macOS"))
	_back_button = BreakwaterUI.button("BACK", &"PrimaryButton")
	_back_button.pressed.connect(back_requested.emit)
	stack.add_child(_back_button)


func focus_default() -> void:
	_back_button.grab_focus()


func _add_credit(parent: VBoxContainer, heading: String, body: String) -> void:
	parent.add_child(BreakwaterUI.section_label(heading))
	var body_label := BreakwaterUI.label(body)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(body_label)
