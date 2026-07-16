class_name BreakwaterPostMatchScreen
extends BreakwaterUIScreen
## Victory/defeat results, podium, and next actions.

signal rematch_requested
signal return_to_menu_requested

var _outcome_label: Label
var _summary_label: Label
var _podium: VBoxContainer
var _stats: HBoxContainer
var _rematch_button: Button


func build_screen() -> void:
	var layout := make_page_layout("After-action report", "BREAKWATER STATION / SESSION COMPLETE")
	var stack: VBoxContainer = layout.stack
	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override(&"separation", 26)
	stack.add_child(top)

	var result_panel := BreakwaterUI.panel(&"GlassPanel")
	result_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(result_panel)
	var result_stack := VBoxContainer.new()
	result_stack.add_theme_constant_override(&"separation", 12)
	result_panel.add_child(result_stack)
	result_stack.add_child(BreakwaterUI.section_label("SIMULATION OUTCOME"))
	_outcome_label = BreakwaterUI.label("VICTORY", &"DisplayLabel")
	result_stack.add_child(_outcome_label)
	_summary_label = BreakwaterUI.label("Score limit reached.")
	result_stack.add_child(_summary_label)
	result_stack.add_child(BreakwaterUI.h_rule())
	_stats = HBoxContainer.new()
	_stats.add_theme_constant_override(&"separation", 12)
	result_stack.add_child(_stats)
	var flex := Control.new()
	flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_stack.add_child(flex)
	result_stack.add_child(BreakwaterUI.data_label("OFFLINE PRACTICE  •  RESULTS STORED LOCALLY"))

	var podium_panel := BreakwaterUI.panel()
	podium_panel.custom_minimum_size.x = 560.0
	top.add_child(podium_panel)
	var podium_stack := VBoxContainer.new()
	podium_stack.add_theme_constant_override(&"separation", 8)
	podium_panel.add_child(podium_stack)
	podium_stack.add_child(BreakwaterUI.section_label("FINAL STANDINGS"))
	_podium = VBoxContainer.new()
	_podium.add_theme_constant_override(&"separation", 7)
	podium_stack.add_child(_podium)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override(&"separation", 12)
	stack.add_child(actions)
	var menu := BreakwaterUI.button("RETURN TO READY DECK")
	menu.pressed.connect(return_to_menu_requested.emit)
	actions.add_child(menu)
	_rematch_button = BreakwaterUI.button("REMATCH", &"PrimaryButton")
	_rematch_button.pressed.connect(rematch_requested.emit)
	actions.add_child(_rematch_button)


func show_results(result: Dictionary) -> void:
	var player_won := bool(result.get("player_won", false))
	_outcome_label.text = "VICTORY" if player_won else "DEFEAT"
	_outcome_label.add_theme_color_override(&"font_color", BreakwaterUI.SEA_GLASS if player_won else BreakwaterUI.SAFETY_CORAL)
	var winner := String(result.get("winner_name", "UNKNOWN")).to_upper()
	var winning_score := int(result.get("winning_score", 30))
	_summary_label.text = "%s secured the station at %d eliminations." % [winner, winning_score]
	_clear_children(_stats)
	_stats.add_child(_stat_card("ELIMINATIONS", int(result.get("kills", 0))))
	_stats.add_child(_stat_card("DEATHS", int(result.get("deaths", 0))))
	_stats.add_child(_stat_card("HEADSHOTS", int(result.get("headshots", 0))))
	_stats.add_child(_stat_card("ACCURACY", int(round(float(result.get("accuracy", 0.0)) * 100.0)), "%"))
	_clear_children(_podium)
	var standings: Array = result.get("standings", [])
	for index in mini(standings.size(), 8):
		_podium.add_child(_standing_row(index + 1, standings[index]))
	open()


func focus_default() -> void:
	_rematch_button.grab_focus()


func _stat_card(caption: String, value: int, suffix := "") -> PanelContainer:
	var card := BreakwaterUI.panel()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := VBoxContainer.new()
	card.add_child(stack)
	stack.add_child(BreakwaterUI.section_label(caption))
	stack.add_child(BreakwaterUI.label("%d%s" % [value, suffix], &"ScoreLabel"))
	return card


func _standing_row(rank: int, player: Dictionary) -> PanelContainer:
	var is_player := bool(player.get("is_player", false))
	var row_panel := PanelContainer.new()
	row_panel.add_theme_stylebox_override(&"panel", BreakwaterUI.panel_style(Color(BreakwaterUI.SLATE, 0.8), BreakwaterUI.SUN_GOLD if is_player else Color(BreakwaterUI.SLATE_LIGHT, 0.5), 1, 4, 11, 4 if is_player else 0))
	var row := HBoxContainer.new()
	row_panel.add_child(row)
	var rank_label := BreakwaterUI.data_label("%02d" % rank)
	rank_label.custom_minimum_size.x = 56.0
	row.add_child(rank_label)
	var name_label := BreakwaterUI.label(String(player.get("name", "UNKNOWN")).to_upper())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var score := BreakwaterUI.label("%02d" % int(player.get("kills", 0)), &"ScoreLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(score)
	return row_panel


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		child.queue_free()
