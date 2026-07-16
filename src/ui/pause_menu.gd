class_name BreakwaterPauseMenu
extends Control
## In-match pause overlay. Add to a CanvasLayer above the HUD.

signal resume_requested
signal restart_requested
signal settings_requested
signal quit_to_menu_requested

var _resume_button: Button
var _resume_hint: Label
var _settings_manager: BreakwaterSettingsManager
var _owns_tree_pause := false
var _opened_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = BreakwaterUI.create_theme()
	_build_ui()
	hide()
	call_deferred(&"_auto_bind_manager")


func bind_settings(manager: BreakwaterSettingsManager) -> void:
	_settings_manager = manager
	if not manager.bindings_changed.is_connected(_on_binding_changed):
		manager.bindings_changed.connect(_on_binding_changed)
	_refresh_resume_hint()


func open_pause(pause_tree := true) -> void:
	_owns_tree_pause = pause_tree
	_opened_frame = Engine.get_process_frames()
	if pause_tree:
		get_tree().paused = true
	show()
	_resume_button.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_pause(unpause_tree := true) -> void:
	hide()
	if unpause_tree and _owns_tree_pause:
		get_tree().paused = false
	_owns_tree_pause = false


func restore_pause_view() -> void:
	show()
	_resume_button.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed(&"pause"):
		_on_resume()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(BreakwaterUI.ABYSS, 0.78)
	add_child(dim)

	var rail := PanelContainer.new()
	rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rail.offset_right = 480.0
	rail.add_theme_stylebox_override(&"panel", BreakwaterUI.panel_style(Color(BreakwaterUI.DEEP_NAVY, 0.96), Color(BreakwaterUI.SEA_GLASS, 0.42), 1, 0, 48, 5))
	add_child(rail)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override(&"separation", 9)
	rail.add_child(stack)
	stack.add_child(BreakwaterUI.section_label("SIMULATION SUSPENDED"))
	stack.add_child(BreakwaterUI.label("PAUSED", &"HeadingLabel"))
	stack.add_child(BreakwaterUI.h_rule())
	_resume_button = _pause_button("RESUME", &"PrimaryButton", _on_resume)
	stack.add_child(_resume_button)
	stack.add_child(_pause_button("RESTART MATCH", &"Button", restart_requested.emit))
	stack.add_child(_pause_button("SETTINGS + CONTROLS", &"Button", settings_requested.emit))
	stack.add_child(_pause_button("LEAVE PRACTICE", &"DangerButton", quit_to_menu_requested.emit))
	_resume_hint = BreakwaterUI.data_label("ESC / PAD START  •  RESUME")
	stack.add_child(_resume_hint)


func _pause_button(text_value: String, variation: StringName, callback: Callable) -> Button:
	var node := BreakwaterUI.button(text_value, variation)
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.pressed.connect(callback)
	return node


func _on_resume() -> void:
	close_pause(true)
	resume_requested.emit()


func _on_binding_changed(action: StringName) -> void:
	if action == &"pause":
		_refresh_resume_hint()


func _refresh_resume_hint() -> void:
	if _resume_hint == null:
		return
	var hint := "ESC / PAD START"
	if _settings_manager != null:
		hint = _settings_manager.action_display_name(&"pause").to_upper()
	_resume_hint.text = "%s  •  RESUME" % hint


func _auto_bind_manager() -> void:
	if _settings_manager != null:
		return
	var candidate := get_node_or_null("/root/SettingsManager")
	if candidate is BreakwaterSettingsManager:
		bind_settings(candidate)
