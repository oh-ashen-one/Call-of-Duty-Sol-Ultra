class_name BreakwaterMatchmakingScreen
extends BreakwaterUIScreen
## Convincing, explicitly offline practice matchmaking and loading sequence.

signal cancel_requested
signal match_ready
signal stage_changed(stage: MatchStage)

enum MatchStage { IDLE, SEARCHING, FOUND, LOADING, ERROR }

@export var auto_advance := true

var _stage := MatchStage.IDLE
var _stage_time := 0.0
var _loading_progress := 0.0
var _deployment_emitted := false
var _status_label: Label
var _detail_label: Label
var _progress: ProgressBar
var _cancel_button: Button
var _sonar: SonarSweep


func build_screen() -> void:
	var layout := make_page_layout("Practice matchmaking", "LOCAL COMBAT SIMULATION")
	var stack: VBoxContainer = layout.stack
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override(&"separation", 44)
	stack.add_child(split)

	var sonar_panel := BreakwaterUI.panel(&"GlassPanel")
	sonar_panel.custom_minimum_size = Vector2(520.0, 520.0)
	sonar_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(sonar_panel)
	_sonar = SonarSweep.new()
	_sonar.custom_minimum_size = Vector2(490.0, 490.0)
	sonar_panel.add_child(_sonar)

	var status_panel := BreakwaterUI.panel()
	status_panel.custom_minimum_size.x = 540.0
	split.add_child(status_panel)
	var status_stack := VBoxContainer.new()
	status_stack.add_theme_constant_override(&"separation", 18)
	status_panel.add_child(status_stack)
	status_stack.add_child(BreakwaterUI.section_label("SESSION TELEMETRY"))
	_status_label = BreakwaterUI.label("STANDING BY", &"HeadingLabel")
	status_stack.add_child(_status_label)
	_detail_label = BreakwaterUI.label("Select deploy to begin a local practice session.")
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_stack.add_child(_detail_label)
	status_stack.add_child(BreakwaterUI.h_rule())
	status_stack.add_child(_data_row("PLAYLIST", "FREE-FOR-ALL"))
	status_stack.add_child(_data_row("COMBATANTS", "8 / 8"))
	status_stack.add_child(_data_row("SCORE LIMIT", "30"))
	status_stack.add_child(_data_row("NETWORK", "OFFLINE SIMULATION"))
	var flexible := Control.new()
	flexible.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status_stack.add_child(flexible)
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 10.0
	_progress.add_theme_stylebox_override(&"background", BreakwaterUI.panel_style(BreakwaterUI.SLATE_LIGHT, BreakwaterUI.SLATE_LIGHT, 0, 4, 0))
	_progress.add_theme_stylebox_override(&"fill", BreakwaterUI.panel_style(BreakwaterUI.SEA_GLASS, BreakwaterUI.SEA_GLASS, 0, 4, 0))
	status_stack.add_child(_progress)
	_cancel_button = BreakwaterUI.button("CANCEL SEARCH")
	_cancel_button.pressed.connect(_on_cancel_pressed)
	status_stack.add_child(_cancel_button)
	status_stack.add_child(make_footer_hint("Practice matchmaking simulates the presentation of an online lobby; all combat runs locally."))
	set_process(false)


func begin() -> void:
	_stage = MatchStage.SEARCHING
	_stage_time = 0.0
	_loading_progress = 0.0
	_deployment_emitted = false
	_progress.value = 7.0
	_status_label.text = "SEARCHING LOCAL ROSTER"
	_detail_label.text = "Pinging autonomous combat profiles aboard Breakwater Station…"
	_cancel_button.text = "CANCEL SEARCH"
	_cancel_button.disabled = false
	_sonar.active = true
	stage_changed.emit(_stage)
	set_process(auto_advance)


func mark_match_found() -> void:
	_stage = MatchStage.FOUND
	_stage_time = 0.0
	_progress.value = 42.0
	_status_label.text = "PRACTICE MATCH FOUND"
	_detail_label.text = "Roster locked. Preparing combat simulation and safe spawn routes."
	_cancel_button.disabled = true
	stage_changed.emit(_stage)


func begin_loading() -> void:
	_stage = MatchStage.LOADING
	_stage_time = 0.0
	_loading_progress = 0.0
	_progress.value = 48.0
	_status_label.text = "LOADING BREAKWATER STATION"
	_detail_label.text = "Staging map geometry, weapons, navigation, and seven combatants."
	stage_changed.emit(_stage)


func set_loading_progress(progress: float) -> void:
	_loading_progress = clampf(progress, 0.0, 1.0)
	_progress.value = lerpf(48.0, 100.0, _loading_progress)
	if _loading_progress >= 1.0:
		_finish_loading()


func show_error(message: String) -> void:
	_stage = MatchStage.ERROR
	set_process(false)
	_status_label.text = "SESSION COULD NOT START"
	_detail_label.text = message
	_progress.value = 0.0
	_cancel_button.text = "RETURN"
	_cancel_button.disabled = false
	_sonar.active = false
	stage_changed.emit(_stage)


func focus_default() -> void:
	_cancel_button.grab_focus()


func _process(delta: float) -> void:
	_stage_time += delta
	match _stage:
		MatchStage.SEARCHING:
			_progress.value = minf(38.0, 7.0 + _stage_time * 10.0)
			if _stage_time >= 2.4:
				mark_match_found()
		MatchStage.FOUND:
			if _stage_time >= 1.15:
				begin_loading()
		MatchStage.LOADING:
			set_loading_progress(_loading_progress + delta * 0.34)


func _finish_loading() -> void:
	if _deployment_emitted:
		return
	_deployment_emitted = true
	set_process(false)
	_status_label.text = "DEPLOYMENT READY"
	_detail_label.text = "Local simulation synchronized. Entering Breakwater Station."
	_sonar.active = false
	match_ready.emit()


func _on_cancel_pressed() -> void:
	set_process(false)
	_sonar.active = false
	_stage = MatchStage.IDLE
	_stage_time = 0.0
	_loading_progress = 0.0
	_status_label.text = "STANDING BY"
	_detail_label.text = "Select deploy to begin a local practice session."
	_progress.value = 0.0
	stage_changed.emit(_stage)
	cancel_requested.emit()


func _data_row(left_text: String, right_text: String) -> Control:
	var row := HBoxContainer.new()
	var left := BreakwaterUI.data_label(left_text)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var right := BreakwaterUI.data_label(right_text, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_theme_color_override(&"font_color", BreakwaterUI.MIST)
	row.add_child(right)
	return row
