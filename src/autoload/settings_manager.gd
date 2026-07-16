class_name BreakwaterSettingsManager
extends Node
## Persistent, runtime-applied settings for Project Breakwater.
## Register this script as the `SettingsManager` autoload.

signal settings_loaded
signal setting_changed(section: StringName, key: StringName, value: Variant)
signal settings_applied
signal bindings_changed(action: StringName)

const SETTINGS_PATH := "user://breakwater_settings.cfg"
const SETTINGS_VERSION := 1

const DEFAULTS: Dictionary = {
	"audio": {
		"master_volume": 0.85,
		"music_volume": 0.65,
		"sfx_volume": 0.85,
		"ui_volume": 0.75,
	},
	"controls": {
		"mouse_sensitivity": 0.18,
		"ads_sensitivity": 0.72,
		"controller_sensitivity": 2.6,
		"controller_deadzone": 0.16,
		"invert_y": false,
		"vibration": true,
	},
	"video": {
		"fov": 90.0,
		"window_mode": "fullscreen",
		"resolution": Vector2i(1920, 1080),
		"render_scale": 1.0,
		"quality": "high",
		"vsync": true,
	},
	"gameplay": {
		"camera_shake": 0.75,
		"hit_markers": true,
		"crosshair": true,
		"crosshair_color": Color("dce8eb"),
	},
}

const DEFAULT_BINDINGS: Dictionary = {
	"move_forward": [{"type": "key", "code": KEY_W}, {"type": "joy_axis", "axis": JOY_AXIS_LEFT_Y, "value": -1.0}],
	"move_back": [{"type": "key", "code": KEY_S}, {"type": "joy_axis", "axis": JOY_AXIS_LEFT_Y, "value": 1.0}],
	"move_left": [{"type": "key", "code": KEY_A}, {"type": "joy_axis", "axis": JOY_AXIS_LEFT_X, "value": -1.0}],
	"move_right": [{"type": "key", "code": KEY_D}, {"type": "joy_axis", "axis": JOY_AXIS_LEFT_X, "value": 1.0}],
	"jump": [{"type": "key", "code": KEY_SPACE}, {"type": "joy_button", "button": JOY_BUTTON_A}],
	"sprint": [{"type": "key", "code": KEY_SHIFT}, {"type": "joy_button", "button": JOY_BUTTON_LEFT_STICK}],
	"crouch": [{"type": "key", "code": KEY_CTRL}, {"type": "joy_button", "button": JOY_BUTTON_B}],
	"fire": [{"type": "mouse", "button": MOUSE_BUTTON_LEFT}, {"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "value": 1.0}],
	"aim": [{"type": "mouse", "button": MOUSE_BUTTON_RIGHT}, {"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_LEFT, "value": 1.0}],
	"reload": [{"type": "key", "code": KEY_R}, {"type": "joy_button", "button": JOY_BUTTON_X}],
	"interact": [{"type": "key", "code": KEY_E}, {"type": "joy_button", "button": JOY_BUTTON_X}],
	"melee": [{"type": "key", "code": KEY_V}, {"type": "joy_button", "button": JOY_BUTTON_RIGHT_STICK}],
	"throw_frag": [{"type": "key", "code": KEY_G}, {"type": "joy_button", "button": JOY_BUTTON_RIGHT_SHOULDER}],
	"throw_tactical": [{"type": "key", "code": KEY_Q}, {"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER}],
	"swap_weapon": [{"type": "key", "code": KEY_1}, {"type": "joy_button", "button": JOY_BUTTON_Y}],
	"scoreboard": [{"type": "key", "code": KEY_TAB}, {"type": "joy_button", "button": JOY_BUTTON_BACK}],
	"pause": [{"type": "key", "code": KEY_ESCAPE}, {"type": "joy_button", "button": JOY_BUTTON_START}],
}

var _settings: Dictionary = {}
var _bound_cameras: Array[Camera3D] = []
var _loaded := false
var settings_path: String = SETTINGS_PATH


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	_settings = DEFAULTS.duplicate(true)
	var config := ConfigFile.new()
	var error := config.load(settings_path)
	if error == OK:
		for section_key: Variant in DEFAULTS.keys():
			var section := StringName(section_key)
			var defaults_for_section: Dictionary = DEFAULTS[section_key]
			for setting_key: Variant in defaults_for_section.keys():
				var key := StringName(setting_key)
				_settings[section_key][setting_key] = config.get_value(section, key, defaults_for_section[setting_key])
		_load_bindings(config)
	else:
		reset_bindings(false)
	_loaded = true
	apply_all()
	settings_loaded.emit()


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", SETTINGS_VERSION)
	for section_key: Variant in _settings.keys():
		var values: Dictionary = _settings[section_key]
		for setting_key: Variant in values.keys():
			config.set_value(String(section_key), String(setting_key), values[setting_key])
	_save_bindings(config)
	return config.save(settings_path)


func is_loaded() -> bool:
	return _loaded


func get_value(section: StringName, key: StringName, fallback: Variant = null) -> Variant:
	if not _settings.has(section):
		return fallback
	var values: Dictionary = _settings[section]
	return values.get(key, fallback)


func set_value(section: StringName, key: StringName, value: Variant, persist := true) -> void:
	if not _settings.has(section):
		_settings[section] = {}
	_settings[section][key] = value
	_apply_setting(section, key, value)
	setting_changed.emit(section, key, value)
	if persist:
		save_settings()


func reset_to_defaults(persist := true) -> void:
	_settings = DEFAULTS.duplicate(true)
	reset_bindings(false)
	apply_all()
	for section_key: Variant in _settings.keys():
		for setting_key: Variant in (_settings[section_key] as Dictionary).keys():
			setting_changed.emit(StringName(section_key), StringName(setting_key), _settings[section_key][setting_key])
	if persist:
		save_settings()


func get_settings_snapshot() -> Dictionary:
	return _settings.duplicate(true)


func apply_all() -> void:
	for section_key: Variant in _settings.keys():
		var values: Dictionary = _settings[section_key]
		for setting_key: Variant in values.keys():
			_apply_setting(StringName(section_key), StringName(setting_key), values[setting_key])
	_apply_camera_settings()
	settings_applied.emit()


func apply_scene_quality() -> void:
	_apply_quality(String(get_value(&"video", &"quality", "high")))


func bind_camera(camera: Camera3D) -> void:
	if not is_instance_valid(camera) or _bound_cameras.has(camera):
		return
	_bound_cameras.append(camera)
	camera.fov = float(get_value("video", "fov", 90.0))


func unbind_camera(camera: Camera3D) -> void:
	_bound_cameras.erase(camera)


func rebind_action(action: StringName, event: InputEvent, replace_existing := true, persist := true) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if replace_existing:
		var preserved_events: Array[InputEvent] = []
		var replacing_controller := event is InputEventJoypadButton or event is InputEventJoypadMotion
		for existing: InputEvent in InputMap.action_get_events(action):
			var existing_is_controller := existing is InputEventJoypadButton or existing is InputEventJoypadMotion
			if existing_is_controller != replacing_controller:
				preserved_events.append(existing)
		InputMap.action_erase_events(action)
		for preserved_event: InputEvent in preserved_events:
			InputMap.action_add_event(action, preserved_event)
	_remove_binding_conflicts(action, event)
	InputMap.action_add_event(action, event)
	bindings_changed.emit(action)
	if persist:
		save_settings()


func clear_action_binding(action: StringName, persist := true) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	bindings_changed.emit(action)
	if persist:
		save_settings()


func reset_bindings(persist := true) -> void:
	for action_key: Variant in DEFAULT_BINDINGS.keys():
		var action := StringName(action_key)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var definitions: Array = DEFAULT_BINDINGS[action_key]
		for definition: Dictionary in definitions:
			var event := _event_from_definition(definition)
			if event != null:
				InputMap.action_add_event(action, event)
		bindings_changed.emit(action)
	if persist:
		save_settings()


func action_display_name(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "Unbound"
	var desktop_name := ""
	var controller_name := ""
	for event: InputEvent in InputMap.action_get_events(action):
		if desktop_name.is_empty() and (event is InputEventKey or event is InputEventMouseButton):
			desktop_name = event.as_text().trim_suffix(" (Physical)")
		elif controller_name.is_empty() and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			controller_name = _controller_event_name(event)
	if not desktop_name.is_empty() and not controller_name.is_empty():
		return "%s / %s" % [desktop_name, controller_name]
	return desktop_name if not desktop_name.is_empty() else (controller_name if not controller_name.is_empty() else "Unbound")


func _controller_event_name(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		var button_names := {
			JOY_BUTTON_A: "PAD A", JOY_BUTTON_B: "PAD B", JOY_BUTTON_X: "PAD X", JOY_BUTTON_Y: "PAD Y",
			JOY_BUTTON_LEFT_SHOULDER: "PAD LB", JOY_BUTTON_RIGHT_SHOULDER: "PAD RB",
			JOY_BUTTON_LEFT_STICK: "PAD L3", JOY_BUTTON_RIGHT_STICK: "PAD R3",
			JOY_BUTTON_BACK: "PAD BACK", JOY_BUTTON_START: "PAD START",
			JOY_BUTTON_DPAD_UP: "D-PAD UP", JOY_BUTTON_DPAD_DOWN: "D-PAD DOWN",
			JOY_BUTTON_DPAD_LEFT: "D-PAD LEFT", JOY_BUTTON_DPAD_RIGHT: "D-PAD RIGHT",
		}
		return String(button_names.get(event.button_index, "PAD BUTTON %d" % event.button_index))
	if event is InputEventJoypadMotion:
		var axis_names := {
			JOY_AXIS_LEFT_X: "LEFT STICK X", JOY_AXIS_LEFT_Y: "LEFT STICK Y",
			JOY_AXIS_RIGHT_X: "RIGHT STICK X", JOY_AXIS_RIGHT_Y: "RIGHT STICK Y",
			JOY_AXIS_TRIGGER_LEFT: "LEFT TRIGGER", JOY_AXIS_TRIGGER_RIGHT: "RIGHT TRIGGER",
		}
		return String(axis_names.get(event.axis, "PAD AXIS %d" % event.axis))
	return "GAMEPAD"


func _remove_binding_conflicts(target_action: StringName, event: InputEvent) -> void:
	for action_key: Variant in DEFAULT_BINDINGS.keys():
		var other_action := StringName(action_key)
		if other_action == target_action or _actions_may_share_binding(target_action, other_action):
			continue
		var removed := false
		for existing: InputEvent in InputMap.action_get_events(other_action):
			if _binding_events_match(existing, event):
				InputMap.action_erase_event(other_action, existing)
				removed = true
		if removed:
			bindings_changed.emit(other_action)


func _actions_may_share_binding(first: StringName, second: StringName) -> bool:
	return (first == &"reload" and second == &"interact") \
		or (first == &"interact" and second == &"reload")


func _binding_events_match(first: InputEvent, second: InputEvent) -> bool:
	if first.get_class() != second.get_class():
		return false
	if first is InputEventKey and second is InputEventKey:
		var first_code: int = int(first.physical_keycode if first.physical_keycode != 0 else first.keycode)
		var second_code: int = int(second.physical_keycode if second.physical_keycode != 0 else second.keycode)
		return first_code == second_code and _modifier_mask(first) == _modifier_mask(second)
	if first is InputEventMouseButton and second is InputEventMouseButton:
		return first.button_index == second.button_index and _modifier_mask(first) == _modifier_mask(second)
	if first is InputEventJoypadButton and second is InputEventJoypadButton:
		return first.button_index == second.button_index
	if first is InputEventJoypadMotion and second is InputEventJoypadMotion:
		return first.axis == second.axis and signf(first.axis_value) == signf(second.axis_value)
	return false


func _apply_setting(section: StringName, key: StringName, value: Variant) -> void:
	match section:
		&"audio":
			var bus_name := _bus_name_for_key(key)
			if not bus_name.is_empty():
				_set_bus_linear_volume(bus_name, float(value))
		&"video":
			match key:
				&"fov":
					_apply_camera_settings()
				&"window_mode":
					_apply_window_mode(String(value))
				&"resolution":
					if value is Vector2i and String(get_value("video", "window_mode", "fullscreen")) == "windowed":
						DisplayServer.window_set_size(value)
				&"render_scale":
					if is_inside_tree():
						get_tree().root.scaling_3d_scale = clampf(float(value), 0.5, 1.5)
				&"quality":
					_apply_quality(String(value))
				&"vsync":
					DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(value) else DisplayServer.VSYNC_DISABLED)


func _apply_camera_settings() -> void:
	var fov := float(get_value("video", "fov", 90.0))
	var valid_cameras: Array[Camera3D] = []
	for camera: Camera3D in _bound_cameras:
		if is_instance_valid(camera):
			camera.fov = fov
			valid_cameras.append(camera)
	_bound_cameras = valid_cameras


func _apply_window_mode(mode: String) -> void:
	match mode:
		"windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size: Variant = get_value("video", "resolution", Vector2i(1920, 1080))
			if size is Vector2i:
				DisplayServer.window_set_size(size)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func _apply_quality(quality: String) -> void:
	if not is_inside_tree():
		return
	var rendering_method := String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility"))
	var supports_screen_space_aa := rendering_method != "gl_compatibility"
	match quality:
		"low":
			get_tree().root.msaa_3d = Viewport.MSAA_DISABLED
			if supports_screen_space_aa:
				get_tree().root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"medium":
			get_tree().root.msaa_3d = Viewport.MSAA_2X
			if supports_screen_space_aa:
				get_tree().root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_:
			get_tree().root.msaa_3d = Viewport.MSAA_4X
			if supports_screen_space_aa:
				get_tree().root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var detail_enabled := quality != "low"
	for node in get_tree().get_nodes_in_group(&"quality_shadow_light"):
		if node is DirectionalLight3D:
			(node as DirectionalLight3D).shadow_enabled = detail_enabled
	for node in get_tree().get_nodes_in_group(&"quality_environment"):
		if node is WorldEnvironment and (node as WorldEnvironment).environment != null:
			(node as WorldEnvironment).environment.fog_enabled = detail_enabled
	for node in get_tree().get_nodes_in_group(&"quality_reflection"):
		if node is Node3D:
			(node as Node3D).visible = quality == "high"
	for node in get_tree().get_nodes_in_group(&"quality_detail"):
		if node is Node3D:
			(node as Node3D).visible = detail_enabled
	for node in get_tree().get_nodes_in_group(&"quality_vfx"):
		if node.has_method(&"set_quality"):
			node.call(&"set_quality", quality)


func _bus_name_for_key(key: StringName) -> StringName:
	match key:
		&"master_volume": return &"Master"
		&"music_volume": return &"Music"
		&"sfx_volume": return &"SFX"
		&"ui_volume": return &"UI"
	return &""


func _set_bus_linear_volume(bus_name: StringName, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
	AudioServer.set_bus_mute(index, value <= 0.0001)


func _save_bindings(config: ConfigFile) -> void:
	for action_key: Variant in DEFAULT_BINDINGS.keys():
		var action := StringName(action_key)
		var serialized: Array[Dictionary] = []
		if InputMap.has_action(action):
			for event: InputEvent in InputMap.action_get_events(action):
				var definition := _definition_from_event(event)
				if not definition.is_empty():
					serialized.append(definition)
		config.set_value("bindings", String(action), serialized)


func _load_bindings(config: ConfigFile) -> void:
	for action_key: Variant in DEFAULT_BINDINGS.keys():
		var action := StringName(action_key)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var definitions: Array = config.get_value("bindings", String(action), DEFAULT_BINDINGS[action_key])
		for definition: Dictionary in definitions:
			var event := _event_from_definition(definition)
			if event != null:
				InputMap.action_add_event(action, event)


func _event_from_definition(definition: Dictionary) -> InputEvent:
	match String(definition.get("type", "")):
		"key":
			var key_event := InputEventKey.new()
			key_event.physical_keycode = int(definition.get("physical_code", definition.get("code", 0))) as Key
			key_event.keycode = int(definition.get("keycode", 0)) as Key
			_apply_serialized_modifiers(key_event, definition)
			return key_event
		"mouse":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = int(definition.get("button", MOUSE_BUTTON_LEFT)) as MouseButton
			_apply_serialized_modifiers(mouse_event, definition)
			return mouse_event
		"joy_button":
			var button_event := InputEventJoypadButton.new()
			button_event.button_index = int(definition.get("button", JOY_BUTTON_A)) as JoyButton
			return button_event
		"joy_axis":
			var axis_event := InputEventJoypadMotion.new()
			axis_event.axis = int(definition.get("axis", JOY_AXIS_LEFT_X)) as JoyAxis
			axis_event.axis_value = float(definition.get("value", 1.0))
			return axis_event
	return null


func _definition_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return _with_serialized_modifiers({
			"type": "key",
			"physical_code": key_event.physical_keycode,
			"keycode": key_event.keycode,
		}, key_event)
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return _with_serialized_modifiers({"type": "mouse", "button": mouse_event.button_index}, mouse_event)
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button": event.button_index}
	if event is InputEventJoypadMotion:
		return {"type": "joy_axis", "axis": event.axis, "value": event.axis_value}
	return {}


func _modifier_mask(event: InputEvent) -> int:
	if not event is InputEventWithModifiers:
		return 0
	var modified := event as InputEventWithModifiers
	return (1 if modified.shift_pressed else 0) \
		| (2 if modified.ctrl_pressed else 0) \
		| (4 if modified.alt_pressed else 0) \
		| (8 if modified.meta_pressed else 0)


func _with_serialized_modifiers(definition: Dictionary, event: InputEventWithModifiers) -> Dictionary:
	definition["shift"] = event.shift_pressed
	definition["ctrl"] = event.ctrl_pressed
	definition["alt"] = event.alt_pressed
	definition["meta"] = event.meta_pressed
	return definition


func _apply_serialized_modifiers(event: InputEventWithModifiers, definition: Dictionary) -> void:
	event.shift_pressed = bool(definition.get("shift", false))
	event.ctrl_pressed = bool(definition.get("ctrl", false))
	event.alt_pressed = bool(definition.get("alt", false))
	event.meta_pressed = bool(definition.get("meta", false))
