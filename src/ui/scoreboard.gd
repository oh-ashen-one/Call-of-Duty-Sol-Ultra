class_name BreakwaterScoreboard
extends Control
## Hold-to-view free-for-all standings overlay.

signal board_opened
signal board_closed

var _rows: VBoxContainer
var _score_limit_label: Label
var _close_hint: Label
var _settings_manager: BreakwaterSettingsManager
var _score_limit := 30
var input_enabled := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = BreakwaterUI.create_theme()
	_build_board()
	hide()
	call_deferred(&"_auto_bind_manager")


func bind_settings(manager: BreakwaterSettingsManager) -> void:
	_settings_manager = manager
	if not manager.bindings_changed.is_connected(_on_binding_changed):
		manager.bindings_changed.connect(_on_binding_changed)
	_refresh_close_hint()


func update_players(players: Array[Dictionary], score_limit := 30) -> void:
	_score_limit = score_limit
	_score_limit_label.text = "FREE-FOR-ALL  /  FIRST TO %d" % _score_limit
	for child: Node in _rows.get_children():
		child.queue_free()
	var sorted := players.duplicate(true)
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("kills", 0)) == int(b.get("kills", 0)):
			return int(a.get("deaths", 0)) < int(b.get("deaths", 0))
		return int(a.get("kills", 0)) > int(b.get("kills", 0))
	)
	for index in sorted.size():
		_rows.add_child(_player_row(index + 1, sorted[index]))


func show_board() -> void:
	show()
	board_opened.emit()


func hide_board() -> void:
	hide()
	board_closed.emit()


func _input(event: InputEvent) -> void:
	if not input_enabled or get_tree().paused:
		return
	if event.is_action_pressed(&"scoreboard"):
		show_board()
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"scoreboard"):
		hide_board()
		get_viewport().set_input_as_handled()


func _build_board() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(BreakwaterUI.ABYSS, 0.82)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 150)
	margin.add_theme_constant_override(&"margin_top", 80)
	margin.add_theme_constant_override(&"margin_right", 150)
	margin.add_theme_constant_override(&"margin_bottom", 80)
	add_child(margin)
	var panel := BreakwaterUI.panel(&"GlassPanel")
	margin.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override(&"separation", 7)
	panel.add_child(stack)
	stack.add_child(BreakwaterUI.section_label("BREAKWATER STATION / LIVE STANDINGS"))
	stack.add_child(BreakwaterUI.label("COMBAT ROSTER", &"HeadingLabel"))
	_score_limit_label = BreakwaterUI.data_label("FREE-FOR-ALL  /  FIRST TO 30")
	_score_limit_label.add_theme_color_override(&"font_color", BreakwaterUI.SUN_GOLD)
	stack.add_child(_score_limit_label)
	stack.add_child(BreakwaterUI.h_rule())
	stack.add_child(_header_row())
	_rows = VBoxContainer.new()
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 4)
	stack.add_child(_rows)
	_close_hint = BreakwaterUI.data_label("TAB / PAD BACK  •  CLOSE")
	stack.add_child(_close_hint)


func _header_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	row.add_child(_column("RANK", 80.0))
	var operator := _column("OPERATOR", 0.0)
	operator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(operator)
	row.add_child(_column("ELIMS", 100.0, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_column("DEATHS", 100.0, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_column("STATUS", 150.0, HORIZONTAL_ALIGNMENT_RIGHT))
	return row


func _player_row(rank: int, player: Dictionary) -> PanelContainer:
	var is_player := bool(player.get("is_player", false))
	var row_panel := PanelContainer.new()
	row_panel.add_theme_stylebox_override(
		&"panel",
		BreakwaterUI.panel_style(
			Color(BreakwaterUI.SEA_GLASS, 0.13) if is_player else Color(BreakwaterUI.SLATE, 0.72),
			BreakwaterUI.SUN_GOLD if is_player else Color(BreakwaterUI.SLATE_LIGHT, 0.5),
			1,
			4,
			10,
			4 if is_player else 0
		)
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	row_panel.add_child(row)
	row.add_child(_column("%02d" % rank, 80.0))
	var operator := _column(String(player.get("name", "UNKNOWN")).to_upper(), 0.0)
	operator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	operator.add_theme_color_override(&"font_color", BreakwaterUI.SUN_GOLD if is_player else BreakwaterUI.MIST)
	row.add_child(operator)
	row.add_child(_column("%02d" % int(player.get("kills", 0)), 100.0, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_column("%02d" % int(player.get("deaths", 0)), 100.0, HORIZONTAL_ALIGNMENT_RIGHT))
	var status := "ACTIVE" if bool(player.get("alive", true)) else "REDEPLOYING"
	row.add_child(_column(status, 150.0, HORIZONTAL_ALIGNMENT_RIGHT))
	return row_panel


func _column(text_value: String, width: float, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label_node := BreakwaterUI.data_label(text_value, alignment)
	label_node.custom_minimum_size.x = width
	return label_node


func _on_binding_changed(action: StringName) -> void:
	if action == &"scoreboard":
		_refresh_close_hint()


func _refresh_close_hint() -> void:
	if _close_hint == null:
		return
	var hint := "TAB / PAD BACK"
	if _settings_manager != null:
		hint = _settings_manager.action_display_name(&"scoreboard").to_upper()
	_close_hint.text = "%s  •  CLOSE" % hint


func _auto_bind_manager() -> void:
	if _settings_manager != null:
		return
	var candidate := get_node_or_null("/root/SettingsManager")
	if candidate is BreakwaterSettingsManager:
		bind_settings(candidate)
