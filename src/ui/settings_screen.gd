class_name BreakwaterSettingsScreen
extends BreakwaterUIScreen
## Complete settings surface with live application and input rebinding.

signal settings_saved

const CATEGORIES := ["AUDIO", "CONTROLS", "VIDEO", "GAMEPLAY"]
const REBIND_ACTIONS: Array[Dictionary] = [
	{"action": &"move_forward", "label": "Move forward"},
	{"action": &"move_back", "label": "Move back"},
	{"action": &"move_left", "label": "Move left"},
	{"action": &"move_right", "label": "Move right"},
	{"action": &"jump", "label": "Jump"},
	{"action": &"sprint", "label": "Sprint"},
	{"action": &"crouch", "label": "Crouch / slide"},
	{"action": &"fire", "label": "Fire"},
	{"action": &"aim", "label": "Aim down sights"},
	{"action": &"reload", "label": "Reload"},
	{"action": &"interact", "label": "Interact / pick up"},
	{"action": &"melee", "label": "Melee"},
	{"action": &"throw_frag", "label": "Throw lethal"},
	{"action": &"throw_tactical", "label": "Throw tactical"},
	{"action": &"swap_weapon", "label": "Swap weapon"},
	{"action": &"scoreboard", "label": "Scoreboard"},
	{"action": &"pause", "label": "Pause"},
]

var _settings_manager: BreakwaterSettingsManager
var _pages: Dictionary = {}
var _category_buttons: Dictionary = {}
var _binding_buttons: Dictionary = {}
var _current_category := "AUDIO"
var _capture_action: StringName = &""
var _capture_started_frame := -1
var _capture_prompt: Label
var _first_category_button: Button
var _refreshing := false


func build_screen() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 62)
	margin.add_theme_constant_override(&"margin_top", 42)
	margin.add_theme_constant_override(&"margin_right", 62)
	margin.add_theme_constant_override(&"margin_bottom", 42)
	content_root.add_child(margin)
	var root_row := HBoxContainer.new()
	root_row.add_theme_constant_override(&"separation", 34)
	margin.add_child(root_row)

	var rail := VBoxContainer.new()
	rail.custom_minimum_size.x = 300.0
	rail.add_theme_constant_override(&"separation", 8)
	root_row.add_child(rail)
	rail.add_child(BreakwaterUI.section_label("SYSTEM CONFIGURATION"))
	rail.add_child(BreakwaterUI.label("SETTINGS", &"HeadingLabel"))
	rail.add_child(BreakwaterUI.h_rule())
	for category: String in CATEGORIES:
		var category_button := BreakwaterUI.button(category, &"NavButton")
		category_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		category_button.pressed.connect(show_category.bind(category))
		rail.add_child(category_button)
		_category_buttons[category] = category_button
		if _first_category_button == null:
			_first_category_button = category_button
	var rail_flex := Control.new()
	rail_flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(rail_flex)
	var reset := BreakwaterUI.button("RESET DEFAULTS", &"DangerButton")
	reset.pressed.connect(_reset_defaults)
	rail.add_child(reset)
	var back := BreakwaterUI.button("SAVE + RETURN", &"PrimaryButton")
	back.pressed.connect(_save_and_return)
	rail.add_child(back)

	var page_panel := BreakwaterUI.panel(&"GlassPanel")
	page_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_row.add_child(page_panel)
	var pages_root := Control.new()
	pages_root.custom_minimum_size = Vector2(850.0, 740.0)
	page_panel.add_child(pages_root)
	_pages["AUDIO"] = _build_audio_page(pages_root)
	_pages["CONTROLS"] = _build_controls_page(pages_root)
	_pages["VIDEO"] = _build_video_page(pages_root)
	_pages["GAMEPLAY"] = _build_gameplay_page(pages_root)

	_capture_prompt = BreakwaterUI.data_label("")
	_capture_prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_capture_prompt.offset_top = -28.0
	_capture_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_capture_prompt.add_theme_color_override(&"font_color", BreakwaterUI.SUN_GOLD)
	page_panel.add_child(_capture_prompt)
	visibility_changed.connect(_on_visibility_changed)
	show_category(_current_category)
	call_deferred(&"_auto_bind_manager")


func bind_settings(manager: BreakwaterSettingsManager) -> void:
	_settings_manager = manager
	if not _settings_manager.bindings_changed.is_connected(_on_binding_changed):
		_settings_manager.bindings_changed.connect(_on_binding_changed)
	refresh_from_settings()


func show_category(category: String) -> void:
	if not _pages.has(category):
		return
	_current_category = category
	for category_name: Variant in _pages.keys():
		(_pages[category_name] as Control).visible = category_name == category
		(_category_buttons[category_name] as Button).modulate = BreakwaterUI.MIST if category_name == category else Color(BreakwaterUI.MIST, 0.58)


func refresh_from_settings() -> void:
	if _settings_manager == null:
		return
	_refreshing = true
	for node: Node in get_tree().get_nodes_in_group(&"settings_widget"):
		if not is_ancestor_of(node):
			continue
		var section := StringName(node.get_meta(&"section"))
		var key := StringName(node.get_meta(&"key"))
		var value: Variant = _settings_manager.get_value(section, key)
		if node is Range:
			node.value = float(value)
		if node is BaseButton and not node is OptionButton:
			node.button_pressed = bool(value)
		if node is OptionButton:
			_select_option_value(node, value)
	_refreshing = false
	_refresh_binding_labels()


func focus_default() -> void:
	_first_category_button.grab_focus()


func _input(event: InputEvent) -> void:
	# Capture before Control nodes consume ui_accept/ui_cancel or D-pad input.
	# Rebinding through _unhandled_input misses precisely the controller and
	# keyboard events most likely to be interpreted by the focused GUI button.
	if _capture_action.is_empty() or not visible:
		return
	if Engine.get_process_frames() <= _capture_started_frame:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_binding_capture()
		get_viewport().set_input_as_handled()
		return
	var accepted := false
	var binding_event := event
	if event is InputEventKey:
		accepted = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		accepted = event.pressed
	elif event is InputEventJoypadButton:
		accepted = event.pressed
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= 0.65:
		var axis_event := InputEventJoypadMotion.new()
		axis_event.device = event.device
		axis_event.axis = event.axis
		axis_event.axis_value = signf(event.axis_value)
		binding_event = axis_event
		accepted = true
	if not accepted:
		return
	if _settings_manager != null:
		_settings_manager.rebind_action(_capture_action, binding_event, true, true)
	_cancel_binding_capture()
	get_viewport().set_input_as_handled()


func _build_audio_page(parent: Control) -> Control:
	var page := _new_page(parent, "AUDIO MIX", "Tune the station mix. Changes apply immediately.")
	var stack: VBoxContainer = page.get_meta(&"stack")
	stack.add_child(_slider_setting("Master volume", "All game audio", &"audio", &"master_volume", 0.0, 1.0, 0.01, true))
	stack.add_child(_slider_setting("Music volume", "Menu and match score", &"audio", &"music_volume", 0.0, 1.0, 0.01, true))
	stack.add_child(_slider_setting("Effects volume", "Weapons, movement, and environment", &"audio", &"sfx_volume", 0.0, 1.0, 0.01, true))
	stack.add_child(_slider_setting("Interface volume", "Navigation and match feedback", &"audio", &"ui_volume", 0.0, 1.0, 0.01, true))
	return page


func _build_controls_page(parent: Control) -> Control:
	var page := _new_page(parent, "CONTROLS", "Mouse and controller response, plus keyboard, mouse, and gamepad bindings.")
	var stack: VBoxContainer = page.get_meta(&"stack")
	stack.add_child(_slider_setting("Mouse sensitivity", "Look response", &"controls", &"mouse_sensitivity", 0.05, 0.5, 0.01))
	stack.add_child(_slider_setting("ADS multiplier", "Sensitivity while aiming", &"controls", &"ads_sensitivity", 0.25, 1.0, 0.01))
	stack.add_child(_slider_setting("Controller sensitivity", "Right-stick look speed", &"controls", &"controller_sensitivity", 0.5, 6.0, 0.1))
	stack.add_child(_slider_setting("Controller dead zone", "Minimum stick input", &"controls", &"controller_deadzone", 0.05, 0.35, 0.01))
	stack.add_child(_toggle_setting("Invert vertical look", "Reverse pitch input", &"controls", &"invert_y"))
	stack.add_child(_toggle_setting("Controller vibration", "Weapon and damage feedback", &"controls", &"vibration"))
	stack.add_child(BreakwaterUI.h_rule())
	stack.add_child(BreakwaterUI.section_label("INPUT BINDINGS"))
	for binding: Dictionary in REBIND_ACTIONS:
		stack.add_child(_binding_row(String(binding.label), StringName(binding.action)))
	return page


func _build_video_page(parent: Control) -> Control:
	var page := _new_page(parent, "DISPLAY + GRAPHICS", "Image quality and performance controls.")
	var stack: VBoxContainer = page.get_meta(&"stack")
	stack.add_child(_slider_setting("Field of view", "Vertical camera angle", &"video", &"fov", 70.0, 110.0, 1.0, false, "°"))
	stack.add_child(_option_setting("Window mode", "Choose desktop presentation", &"video", &"window_mode", [
		{"label": "EXCLUSIVE FULLSCREEN", "value": "fullscreen"},
		{"label": "BORDERLESS", "value": "borderless"},
		{"label": "WINDOWED", "value": "windowed"},
	]))
	stack.add_child(_option_setting("Window resolution", "Applied in windowed mode", &"video", &"resolution", [
		{"label": "1280 × 720", "value": Vector2i(1280, 720)},
		{"label": "1600 × 900", "value": Vector2i(1600, 900)},
		{"label": "1920 × 1080", "value": Vector2i(1920, 1080)},
		{"label": "2560 × 1440", "value": Vector2i(2560, 1440)},
	]))
	stack.add_child(_slider_setting("3D render scale", "Internal scene resolution", &"video", &"render_scale", 0.5, 1.25, 0.05, true))
	stack.add_child(_option_setting("Graphics preset", "Anti-aliasing and scene quality", &"video", &"quality", [
		{"label": "LOW", "value": "low"},
		{"label": "MEDIUM", "value": "medium"},
		{"label": "HIGH", "value": "high"},
	]))
	stack.add_child(_toggle_setting("Vertical sync", "Prevent visible frame tearing", &"video", &"vsync"))
	return page


func _build_gameplay_page(parent: Control) -> Control:
	var page := _new_page(parent, "COMBAT FEEDBACK", "Control how strongly the game communicates hits and movement.")
	var stack: VBoxContainer = page.get_meta(&"stack")
	stack.add_child(_slider_setting("Camera shake", "Weapon, blast, and impact motion", &"gameplay", &"camera_shake", 0.0, 1.0, 0.05, true))
	stack.add_child(_toggle_setting("Hit markers", "Confirm successful weapon impacts", &"gameplay", &"hit_markers"))
	stack.add_child(_toggle_setting("Crosshair", "Show the hip-fire reticle", &"gameplay", &"crosshair"))
	stack.add_child(_option_setting("Crosshair color", "Select a high-contrast reticle color", &"gameplay", &"crosshair_color", [
		{"label": "MIST WHITE", "value": Color("dce8eb")},
		{"label": "SEA GLASS", "value": Color("5ed3c6")},
		{"label": "SIGNAL GOLD", "value": Color("f2c14e")},
	]))
	return page


func _new_page(parent: Control, title_text: String, description: String) -> ScrollContainer:
	var page := ScrollContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(page)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override(&"separation", 15)
	page.add_child(stack)
	stack.add_child(BreakwaterUI.section_label("BREAKWATER SYSTEMS"))
	stack.add_child(BreakwaterUI.label(title_text, &"HeadingLabel"))
	var description_label := BreakwaterUI.label(description)
	description_label.modulate = Color(BreakwaterUI.MIST, 0.74)
	stack.add_child(description_label)
	stack.add_child(BreakwaterUI.h_rule())
	page.set_meta(&"stack", stack)
	return page


func _slider_setting(
		title: String,
		description: String,
		section: StringName,
		key: StringName,
		minimum: float,
		maximum: float,
		step: float,
		as_percent := false,
		suffix := ""
	) -> Control:
	var row := _setting_row(title, description)
	var value_label := BreakwaterUI.data_label("")
	value_label.custom_minimum_size.x = 70.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size = Vector2(280.0, 38.0)
	slider.set_meta(&"section", section)
	slider.set_meta(&"key", key)
	slider.add_to_group(&"settings_widget")
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = ("%d%%" % roundi(value * 100.0)) if as_percent else ("%d%s" % [roundi(value), suffix] if step >= 1.0 else "%.2f%s" % [value, suffix])
		_write_setting(section, key, value)
	)
	(row.get_meta(&"controls") as HBoxContainer).add_child(value_label)
	(row.get_meta(&"controls") as HBoxContainer).add_child(slider)
	return row


func _toggle_setting(title: String, description: String, section: StringName, key: StringName) -> Control:
	var row := _setting_row(title, description)
	var toggle := CheckButton.new()
	toggle.text = "ON"
	toggle.set_meta(&"section", section)
	toggle.set_meta(&"key", key)
	toggle.add_to_group(&"settings_widget")
	toggle.toggled.connect(func(enabled: bool) -> void:
		toggle.text = "ON" if enabled else "OFF"
		_write_setting(section, key, enabled)
	)
	(row.get_meta(&"controls") as HBoxContainer).add_child(toggle)
	return row


func _option_setting(title: String, description: String, section: StringName, key: StringName, entries: Array[Dictionary]) -> Control:
	var row := _setting_row(title, description)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(300.0, 46.0)
	option.set_meta(&"section", section)
	option.set_meta(&"key", key)
	option.add_to_group(&"settings_widget")
	for entry: Dictionary in entries:
		option.add_item(String(entry.label))
		option.set_item_metadata(option.item_count - 1, entry.value)
	option.item_selected.connect(func(index: int) -> void: _write_setting(section, key, option.get_item_metadata(index)))
	(row.get_meta(&"controls") as HBoxContainer).add_child(option)
	return row


func _setting_row(title: String, description: String) -> PanelContainer:
	var panel := BreakwaterUI.panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	panel.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	copy.add_child(BreakwaterUI.label(title.to_upper()))
	var description_label := BreakwaterUI.data_label(description)
	description_label.modulate = Color(BreakwaterUI.FOG, 0.82)
	copy.add_child(description_label)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_END
	controls.add_theme_constant_override(&"separation", 10)
	row.add_child(controls)
	panel.set_meta(&"controls", controls)
	return panel


func _binding_row(title: String, action: StringName) -> Control:
	var row := _setting_row(title, String(action).replace("_", " "))
	var button := BreakwaterUI.button("UNBOUND")
	button.custom_minimum_size = Vector2(240.0, 44.0)
	button.pressed.connect(_begin_binding_capture.bind(action))
	(row.get_meta(&"controls") as HBoxContainer).add_child(button)
	_binding_buttons[action] = button
	return row


func _write_setting(section: StringName, key: StringName, value: Variant) -> void:
	if _refreshing or _settings_manager == null:
		return
	_settings_manager.set_value(section, key, value, true)


func _select_option_value(option: OptionButton, value: Variant) -> void:
	for index in option.item_count:
		if option.get_item_metadata(index) == value:
			option.select(index)
			return


func _begin_binding_capture(action: StringName) -> void:
	_capture_action = action
	_capture_started_frame = Engine.get_process_frames()
	_capture_prompt.text = "PRESS A KEY, MOUSE, OR GAMEPAD CONTROL  /  ESC TO CANCEL"
	for button: Variant in _binding_buttons.values():
		(button as Button).disabled = true



func _cancel_binding_capture(restore_focus := true) -> void:
	var focus_target := _binding_buttons.get(_capture_action) as Button
	_capture_action = &""
	_capture_started_frame = -1
	_capture_prompt.text = ""
	for button: Variant in _binding_buttons.values():
		(button as Button).disabled = false
	if restore_focus and is_instance_valid(focus_target) and visible:
		focus_target.grab_focus()


func _on_visibility_changed() -> void:
	if not visible and not _capture_action.is_empty():
		_cancel_binding_capture(false)


func _refresh_binding_labels() -> void:
	if _settings_manager == null:
		return
	for action: Variant in _binding_buttons.keys():
		(_binding_buttons[action] as Button).text = _settings_manager.action_display_name(StringName(action)).to_upper()


func _on_binding_changed(_action: StringName) -> void:
	_refresh_binding_labels()


func _reset_defaults() -> void:
	if _settings_manager != null:
		_settings_manager.reset_to_defaults(true)
		refresh_from_settings()


func _save_and_return() -> void:
	_cancel_binding_capture(false)
	if _settings_manager != null:
		_settings_manager.save_settings()
	settings_saved.emit()
	back_requested.emit()


func _auto_bind_manager() -> void:
	if _settings_manager != null:
		return
	var candidate := get_node_or_null("/root/SettingsManager")
	if candidate is BreakwaterSettingsManager:
		bind_settings(candidate)
