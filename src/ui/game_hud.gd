class_name BreakwaterGameHUD
extends Control
## Combat HUD. Feed it gameplay state through the public setter methods.

signal pause_requested

var _settings_manager: BreakwaterSettingsManager
var _health_bar: ProgressBar
var _health_label: Label
var _ammo_label: Label
var _reserve_label: Label
var _weapon_label: Label
var _equipment_label: Label
var _score_label: Label
var _leader_label: Label
var _compass_label: Label
var _kill_feed: VBoxContainer
var _pickup_prompt: Label
var _respawn_label: Label
var _damage_vignette: ColorRect
var _flash_overlay: ColorRect
var _concussion_overlay: ColorRect
var _reticle: BreakwaterCombatReticle
var _minimap: BreakwaterTacticalMinimap
var _frag_count := 1
var _tactical_count := 1
var _frag_name := "FRAG"
var _tactical_name := "FLASH"
var _pickup_token := 0
var _pickup_item_name := ""
var _pickup_action_hint := ""
var _damage_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = BreakwaterUI.create_theme()
	_build_hud()
	call_deferred(&"_auto_bind_manager")


func bind_settings(manager: BreakwaterSettingsManager) -> void:
	_settings_manager = manager
	if not _settings_manager.setting_changed.is_connected(_on_setting_changed):
		_settings_manager.setting_changed.connect(_on_setting_changed)
	if not _settings_manager.bindings_changed.is_connected(_on_binding_changed):
		_settings_manager.bindings_changed.connect(_on_binding_changed)
	_apply_feedback_settings()
	_refresh_equipment_label()


func set_health(current: float, maximum: float = 100.0) -> void:
	_health_bar.max_value = maxf(maximum, 1.0)
	_health_bar.value = clampf(current, 0.0, maximum)
	_health_label.text = "%03d" % ceili(maxf(current, 0.0))
	var ratio := current / maxf(maximum, 1.0)
	_health_bar.modulate = BreakwaterUI.SAFETY_CORAL if ratio <= 0.28 else BreakwaterUI.MIST


func set_ammo(in_magazine: int, reserve: int, magazine_size := -1) -> void:
	_ammo_label.text = "%02d" % maxi(in_magazine, 0)
	_reserve_label.text = "/ %03d" % maxi(reserve, 0)
	_ammo_label.modulate = BreakwaterUI.SAFETY_CORAL if in_magazine <= maxi(3, magazine_size / 5) else BreakwaterUI.MIST


func set_weapon(weapon_name: String, fire_mode := "AUTO") -> void:
	_weapon_label.text = "%s  /  %s" % [weapon_name.to_upper(), fire_mode.to_upper()]


func set_equipment(lethal_name: String, lethal_count: int, tactical_name: String, tactical_count: int) -> void:
	_frag_name = lethal_name.to_upper()
	_frag_count = lethal_count
	_tactical_name = tactical_name.to_upper()
	_tactical_count = tactical_count
	_refresh_equipment_label()


func set_match_score(player_score: int, leader_name: String, leader_score: int, score_limit := 30) -> void:
	_score_label.text = "%02d / %02d" % [player_score, score_limit]
	_leader_label.text = "LEADER  %s  %02d" % [leader_name.to_upper(), leader_score]
	_score_label.modulate = BreakwaterUI.SUN_GOLD if player_score >= leader_score and player_score > 0 else BreakwaterUI.MIST


func set_compass_heading(heading_degrees: float) -> void:
	var normalized := fposmod(heading_degrees, 360.0)
	var cardinal := _cardinal_for_heading(normalized)
	_compass_label.text = "%s   %03d°" % [cardinal, roundi(normalized)]


func set_minimap_data(heading_degrees: float, blips: Array[Dictionary]) -> void:
	_minimap.set_radar_data(heading_degrees, blips)


func add_kill_feed(killer: String, victim: String, weapon: String, player_involved := false) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override(&"panel", BreakwaterUI.panel_style(Color(BreakwaterUI.DEEP_NAVY, 0.72), Color(BreakwaterUI.SEA_GLASS, 0.15), 1, 3, 8, 3 if player_involved else 0))
	var copy := BreakwaterUI.data_label("%s  [%s]  %s" % [killer, weapon, victim], HORIZONTAL_ALIGNMENT_RIGHT)
	copy.add_theme_color_override(&"font_color", BreakwaterUI.SUN_GOLD if player_involved else BreakwaterUI.MIST)
	row.add_child(copy)
	_kill_feed.add_child(row)
	while _kill_feed.get_child_count() > 5:
		var oldest := _kill_feed.get_child(0)
		_kill_feed.remove_child(oldest)
		oldest.queue_free()
	var timer := get_tree().create_timer(5.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(row):
			row.queue_free()
	)


func show_hit_marker(kill := false, headshot := false) -> void:
	if _settings_manager != null and not bool(_settings_manager.get_value("gameplay", "hit_markers", true)):
		return
	_reticle.show_hit(kill, headshot)


func set_crosshair_spread(pixels: float) -> void:
	_reticle.set_spread(pixels)


func show_damage(intensity := 1.0) -> void:
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()
	_damage_vignette.modulate.a = clampf(intensity, 0.18, 0.82)
	_damage_tween = create_tween()
	_damage_tween.tween_property(_damage_vignette, "modulate:a", 0.0, 0.48)


func set_status_effects(flash_strength: float, concussion_strength: float) -> void:
	var flash := clampf(flash_strength, 0.0, 1.0)
	var concussion := clampf(concussion_strength, 0.0, 1.0)
	_flash_overlay.modulate.a = pow(flash, 0.72) * 0.92
	var pulse := 0.72 + sin(Time.get_ticks_msec() * 0.012) * 0.28
	_concussion_overlay.modulate.a = concussion * 0.2 * pulse
	_reticle.rotation = sin(Time.get_ticks_msec() * 0.019) * concussion * 0.045


func show_pickup_prompt(item_name: String, action_hint := "E", auto_hide_seconds := 0.0) -> void:
	_pickup_token += 1
	var token := _pickup_token
	_pickup_item_name = item_name
	_pickup_action_hint = action_hint
	_refresh_pickup_prompt_text()
	_pickup_prompt.show()
	if auto_hide_seconds <= 0.0:
		return
	var timer := get_tree().create_timer(auto_hide_seconds)
	timer.timeout.connect(func() -> void:
		if token == _pickup_token:
			_pickup_prompt.hide()
	)


func _refresh_pickup_prompt_text() -> void:
	if _pickup_prompt == null or _pickup_item_name.is_empty():
		return
	var action_hint := _pickup_action_hint
	var resolved_hint := action_hint.to_upper()
	if _settings_manager != null and InputMap.has_action(StringName(action_hint)):
		resolved_hint = _settings_manager.action_display_name(StringName(action_hint)).to_upper()
	_pickup_prompt.text = (
		"EQUIPPED  /  %s" % _pickup_item_name.to_upper()
		if action_hint == "EQUIPPED"
		else "%s  PICK UP %s" % [resolved_hint, _pickup_item_name.to_upper()]
	)


func clear_pickup_prompt() -> void:
	_pickup_token += 1
	_pickup_item_name = ""
	_pickup_action_hint = ""
	_pickup_prompt.hide()


func show_respawn(countdown_seconds: float) -> void:
	if countdown_seconds <= 0.0:
		_respawn_label.hide()
	else:
		_respawn_label.text = "REDEPLOYING IN %.1f" % countdown_seconds
		_respawn_label.show()


func reset_for_match() -> void:
	# Match UI nodes persist across rematches, so invalidate every delayed callback
	# and transient effect before accepting snapshots from the new world.
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()
	_damage_tween = null
	_pickup_token += 1
	_pickup_item_name = ""
	_pickup_action_hint = ""
	_pickup_prompt.text = ""
	_pickup_prompt.hide()
	_respawn_label.text = ""
	_respawn_label.hide()
	_damage_vignette.modulate.a = 0.0
	_flash_overlay.modulate.a = 0.0
	_concussion_overlay.modulate.a = 0.0
	for row: Node in _kill_feed.get_children():
		_kill_feed.remove_child(row)
		row.queue_free()
	_reticle.reset_feedback()

	set_health(100.0, 100.0)
	set_ammo(0, 0, 1)
	set_weapon("FIELD KIT", "SAFE")
	set_equipment("FRAG", 1, "FLASH", 1)
	set_match_score(0, "--", 0, 30)
	set_compass_heading(0.0)
	_minimap.set_radar_data(0.0, [])


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"pause"):
		pause_requested.emit()
		get_viewport().set_input_as_handled()


func _build_hud() -> void:
	_damage_vignette = ColorRect.new()
	_damage_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_vignette.color = Color(BreakwaterUI.SAFETY_CORAL, 0.34)
	_damage_vignette.modulate.a = 0.0
	_damage_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_vignette)
	_concussion_overlay = ColorRect.new()
	_concussion_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_concussion_overlay.color = Color(BreakwaterUI.SEA_GLASS, 0.24)
	_concussion_overlay.modulate.a = 0.0
	_concussion_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_concussion_overlay)
	_flash_overlay = ColorRect.new()
	_flash_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_overlay.color = Color("edf7f5")
	_flash_overlay.modulate.a = 0.0
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_overlay)

	_reticle = BreakwaterCombatReticle.new()
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_reticle)

	var radar_frame := BreakwaterUI.panel(&"GlassPanel")
	radar_frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	radar_frame.position = Vector2(30.0, 28.0)
	radar_frame.size = Vector2(218.0, 232.0)
	add_child(radar_frame)
	var radar_stack := VBoxContainer.new()
	radar_stack.add_theme_constant_override(&"separation", 4)
	radar_frame.add_child(radar_stack)
	radar_stack.add_child(BreakwaterUI.section_label("TACTICAL PLOT"))
	_minimap = BreakwaterTacticalMinimap.new()
	radar_stack.add_child(_minimap)

	var compass_panel := BreakwaterUI.panel(&"GlassPanel")
	compass_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass_panel.position = Vector2(-125.0, 22.0)
	compass_panel.size = Vector2(250.0, 54.0)
	add_child(compass_panel)
	_compass_label = BreakwaterUI.data_label("N   000°", HORIZONTAL_ALIGNMENT_CENTER)
	_compass_label.add_theme_color_override(&"font_color", BreakwaterUI.MIST)
	compass_panel.add_child(_compass_label)

	var score_panel := BreakwaterUI.panel(&"GlassPanel")
	score_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_panel.position = Vector2(-150.0, 86.0)
	score_panel.size = Vector2(300.0, 105.0)
	add_child(score_panel)
	var score_stack := VBoxContainer.new()
	score_panel.add_child(score_stack)
	_score_label = BreakwaterUI.label("00 / 30", &"ScoreLabel", HORIZONTAL_ALIGNMENT_CENTER)
	score_stack.add_child(_score_label)
	_leader_label = BreakwaterUI.data_label("LEADER  --  00", HORIZONTAL_ALIGNMENT_CENTER)
	score_stack.add_child(_leader_label)

	_kill_feed = VBoxContainer.new()
	_kill_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_kill_feed.position = Vector2(-520.0, 30.0)
	_kill_feed.size = Vector2(490.0, 260.0)
	_kill_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_kill_feed.add_theme_constant_override(&"separation", 4)
	add_child(_kill_feed)

	var health_panel := BreakwaterUI.panel(&"GlassPanel")
	health_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_panel.position = Vector2(30.0, -150.0)
	health_panel.size = Vector2(390.0, 115.0)
	add_child(health_panel)
	var health_stack := VBoxContainer.new()
	health_panel.add_child(health_stack)
	var health_row := HBoxContainer.new()
	health_stack.add_child(health_row)
	var health_caption := BreakwaterUI.section_label("VITALS")
	health_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_row.add_child(health_caption)
	_health_label = BreakwaterUI.label("100", &"ScoreLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	health_row.add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size.y = 12.0
	_health_bar.add_theme_stylebox_override(&"background", BreakwaterUI.panel_style(Color(BreakwaterUI.SLATE_LIGHT, 0.75), Color.TRANSPARENT, 0, 3, 0))
	_health_bar.add_theme_stylebox_override(&"fill", BreakwaterUI.panel_style(BreakwaterUI.SEA_GLASS, BreakwaterUI.SEA_GLASS, 0, 3, 0))
	health_stack.add_child(_health_bar)
	_equipment_label = BreakwaterUI.data_label("G  FRAG ×1     Q  FLASH ×1")
	health_stack.add_child(_equipment_label)

	var ammo_panel := BreakwaterUI.panel(&"GlassPanel")
	ammo_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_panel.position = Vector2(-430.0, -150.0)
	ammo_panel.size = Vector2(400.0, 115.0)
	add_child(ammo_panel)
	var ammo_stack := VBoxContainer.new()
	ammo_panel.add_child(ammo_stack)
	_weapon_label = BreakwaterUI.section_label("CORMORANT AR  /  AUTO")
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_stack.add_child(_weapon_label)
	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_stack.add_child(ammo_row)
	_ammo_label = BreakwaterUI.label("30", &"ScoreLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo_label.add_theme_font_size_override(&"font_size", 43)
	ammo_row.add_child(_ammo_label)
	_reserve_label = BreakwaterUI.data_label("/ 090")
	_reserve_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	ammo_row.add_child(_reserve_label)

	_pickup_prompt = BreakwaterUI.data_label("E  PICK UP WEAPON", HORIZONTAL_ALIGNMENT_CENTER)
	_pickup_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pickup_prompt.position = Vector2(-260.0, -126.0)
	_pickup_prompt.size = Vector2(520.0, 42.0)
	_pickup_prompt.add_theme_color_override(&"font_color", BreakwaterUI.SUN_GOLD)
	_pickup_prompt.hide()
	add_child(_pickup_prompt)

	_respawn_label = BreakwaterUI.label("REDEPLOYING IN 3.0", &"HeadingLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_respawn_label.set_anchors_preset(Control.PRESET_CENTER)
	_respawn_label.position = Vector2(-360.0, -45.0)
	_respawn_label.size = Vector2(720.0, 90.0)
	_respawn_label.hide()
	add_child(_respawn_label)


func _cardinal_for_heading(heading: float) -> String:
	var cardinals := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return cardinals[wrapi(roundi(heading / 45.0), 0, 8)]


func _apply_feedback_settings() -> void:
	if _settings_manager == null:
		return
	_reticle.crosshair_visible = bool(_settings_manager.get_value("gameplay", "crosshair", true))
	_reticle.crosshair_color = _settings_manager.get_value("gameplay", "crosshair_color", BreakwaterUI.MIST)
	_reticle.queue_redraw()


func _on_setting_changed(section: StringName, _key: StringName, _value: Variant) -> void:
	if section == &"gameplay":
		_apply_feedback_settings()


func _on_binding_changed(action: StringName) -> void:
	if action in [&"throw_frag", &"throw_tactical"]:
		_refresh_equipment_label()
	if action == &"interact" and _pickup_action_hint == "interact" and _pickup_prompt.visible:
		_refresh_pickup_prompt_text()


func _refresh_equipment_label() -> void:
	if _equipment_label == null:
		return
	var lethal_hint := "G"
	var tactical_hint := "Q"
	if _settings_manager != null:
		lethal_hint = _settings_manager.action_display_name(&"throw_frag").to_upper()
		tactical_hint = _settings_manager.action_display_name(&"throw_tactical").to_upper()
	_equipment_label.text = "%s  %s ×%d     %s  %s ×%d" % [
		lethal_hint, _frag_name, _frag_count,
		tactical_hint, _tactical_name, _tactical_count,
	]


func _auto_bind_manager() -> void:
	if _settings_manager != null:
		return
	var candidate := get_node_or_null("/root/SettingsManager")
	if candidate is BreakwaterSettingsManager:
		bind_settings(candidate)
