class_name BreakwaterTitleHomeScreen
extends BreakwaterUIScreen
## Title gate and asymmetric home navigation.

signal play_requested
signal loadout_requested
signal skins_requested
signal settings_requested
signal credits_requested
signal quit_requested

var _title_layer: Control
var _home_layer: Control
var _play_button: Button
var _on_title := true


func build_screen() -> void:
	_build_sonar_field()
	_build_title_layer()
	_build_home_layer()
	show_title()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _on_title:
		return
	if event.is_pressed() and not event.is_echo():
		show_home()
		get_viewport().set_input_as_handled()


func show_title() -> void:
	_on_title = true
	_title_layer.show()
	_home_layer.hide()


func show_home() -> void:
	_on_title = false
	_title_layer.hide()
	_home_layer.show()
	_play_button.grab_focus()


func focus_default() -> void:
	if _on_title:
		return
	_play_button.grab_focus()


func _build_sonar_field() -> void:
	var background_texture := load("res://assets/ui/breakwater_station_menu.png") as Texture2D
	if background_texture != null:
		var background := TextureRect.new()
		background.name = "BreakwaterStationBackdrop"
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.texture = background_texture
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.modulate = Color(0.63, 0.72, 0.74, 0.72)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content_root.add_child(background)
	var atmosphere := ColorRect.new()
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atmosphere.color = Color(BreakwaterUI.DEEP_NAVY, 0.28)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(atmosphere)

	var sonar := SonarSweep.new()
	sonar.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	sonar.position = Vector2(-610.0, -390.0)
	sonar.size = Vector2(740.0, 740.0)
	sonar.modulate = Color(1.0, 1.0, 1.0, 0.82)
	content_root.add_child(sonar)

	var horizon := ColorRect.new()
	horizon.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	horizon.offset_top = -138.0
	horizon.color = Color(BreakwaterUI.SEA_GLASS, 0.035)
	horizon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(horizon)


func _build_title_layer() -> void:
	_title_layer = Control.new()
	_title_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_root.add_child(_title_layer)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 86)
	margin.add_theme_constant_override(&"margin_top", 0)
	margin.add_theme_constant_override(&"margin_right", 72)
	margin.add_theme_constant_override(&"margin_bottom", 66)
	_title_layer.add_child(margin)

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_END
	stack.add_theme_constant_override(&"separation", 7)
	margin.add_child(stack)
	stack.add_child(BreakwaterUI.section_label("BREAKWATER SYSTEMS / TRAINING ENVIRONMENT"))
	stack.add_child(BreakwaterUI.label("PROJECT\nBREAKWATER", &"DisplayLabel"))
	var descriptor := BreakwaterUI.label("COASTAL COMBAT READINESS PROGRAM", &"DataLabel")
	descriptor.add_theme_color_override(&"font_color", BreakwaterUI.SUN_GOLD)
	stack.add_child(descriptor)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 24.0
	stack.add_child(spacer)
	var prompt := BreakwaterUI.data_label("PRESS ANY KEY  •  OFFLINE PRACTICE BUILD")
	prompt.modulate = Color(BreakwaterUI.MIST, 0.78)
	stack.add_child(prompt)


func _build_home_layer() -> void:
	_home_layer = Control.new()
	_home_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_root.add_child(_home_layer)

	var rail := PanelContainer.new()
	rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rail.offset_right = 430.0
	rail.add_theme_stylebox_override(&"panel", BreakwaterUI.panel_style(Color(BreakwaterUI.ABYSS, 0.76), Color(BreakwaterUI.SEA_GLASS, 0.22), 1, 0, 42, 5))
	_home_layer.add_child(rail)

	var nav := VBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override(&"separation", 8)
	rail.add_child(nav)
	nav.add_child(BreakwaterUI.section_label("BREAKWATER STATION / READY DECK"))
	var wordmark := BreakwaterUI.label("PROJECT\nBREAKWATER", &"HeadingLabel")
	wordmark.custom_minimum_size.y = 104.0
	nav.add_child(wordmark)
	nav.add_child(BreakwaterUI.h_rule())
	_play_button = _nav_button("DEPLOY", play_requested.emit)
	_play_button.theme_type_variation = &"PrimaryButton"
	nav.add_child(_play_button)
	nav.add_child(_nav_button("LOADOUT", loadout_requested.emit))
	nav.add_child(_nav_button("OPERATOR SKINS", skins_requested.emit))
	nav.add_child(_nav_button("SETTINGS + CONTROLS", settings_requested.emit))
	nav.add_child(_nav_button("CREDITS", credits_requested.emit))
	var gap := Control.new()
	gap.custom_minimum_size.y = 18.0
	nav.add_child(gap)
	var quit := _nav_button("QUIT TO DESKTOP", quit_requested.emit)
	quit.theme_type_variation = &"DangerButton"
	nav.add_child(quit)
	var status := BreakwaterUI.data_label("LOCAL LINK  •  READY  /  BUILD 01")
	status.add_theme_color_override(&"font_color", BreakwaterUI.SEA_GLASS)
	nav.add_child(status)

	var briefing := BreakwaterUI.panel(&"GlassPanel")
	briefing.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	briefing.position = Vector2(-640.0, -330.0)
	briefing.size = Vector2(530.0, 220.0)
	_home_layer.add_child(briefing)
	var brief_stack := VBoxContainer.new()
	brief_stack.add_theme_constant_override(&"separation", 10)
	briefing.add_child(brief_stack)
	brief_stack.add_child(BreakwaterUI.section_label("ACTIVE TRAINING ROTATION"))
	brief_stack.add_child(BreakwaterUI.label("BREAKWATER STATION", &"HeadingLabel"))
	brief_stack.add_child(BreakwaterUI.label("Free-for-all  /  first to 30 eliminations\n7 autonomous combatants  /  no network connection required"))
	brief_stack.add_child(BreakwaterUI.data_label("CONDITIONS  SUNLIT  •  SEA STATE  CALM"))


func _nav_button(text_value: String, callback: Callable) -> Button:
	var node := BreakwaterUI.button(text_value, &"NavButton")
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.pressed.connect(callback)
	return node
