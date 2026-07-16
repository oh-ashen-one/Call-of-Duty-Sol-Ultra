extends Node

## Project Breakwater composition root: menu flow, game-world lifecycle, HUD
## binding, automated capture, and unattended bot verification hooks.

var ui: BreakwaterUICoordinator
var game_world: BreakwaterGameWorld
var menu_audio: AudioDirector
var _last_result: Dictionary = {}
var _benchmark_mode := false
var _last_standings_hash := 0


func _ready() -> void:
	menu_audio = AudioDirector.new()
	menu_audio.name = "MenuAudioDirector"
	add_child(menu_audio)
	ui = BreakwaterUICoordinator.new()
	ui.name = "BreakwaterUI"
	add_child(ui)
	ui.match_start_requested.connect(_start_match)
	ui.restart_match_requested.connect(_restart_match)
	ui.leave_match_requested.connect(_leave_match)
	ui.quit_requested.connect(get_tree().quit)
	ui.post_match.return_to_menu_requested.connect(_leave_match)
	call_deferred(&"_wire_menu_audio")
	call_deferred(&"_run_command_line_mode")


func _start_match(loadout: Dictionary, appearance: Dictionary) -> void:
	menu_audio.set_ambience_active(false)
	_destroy_world()
	game_world = BreakwaterGameWorld.new()
	game_world.name = "ActiveMatch"
	game_world.configure(loadout, appearance, true)
	if not _benchmark_mode:
		game_world.hud_snapshot_ready.connect(_on_hud_snapshot)
		game_world.kill_feed_ready.connect(ui.hud.add_kill_feed)
		game_world.hit_feedback_ready.connect(ui.hud.show_hit_marker)
		game_world.damage_feedback_ready.connect(ui.hud.show_damage)
		game_world.pickup_feedback_ready.connect(_on_pickup_feedback)
		game_world.pickup_prompt_ready.connect(ui.hud.show_pickup_prompt)
		game_world.pickup_prompt_cleared.connect(ui.hud.clear_pickup_prompt)
		game_world.respawn_feedback_ready.connect(ui.hud.show_respawn)
	game_world.match_completed.connect(_on_match_completed)
	add_child(game_world)
	if not _benchmark_mode:
		ui.enter_match()


func _restart_match() -> void:
	_start_match(ui.get_loadout(), ui.get_appearance())


func _leave_match() -> void:
	_destroy_world()
	menu_audio.set_ambience_active(true)


func _destroy_world() -> void:
	if game_world == null:
		return
	game_world.shutdown()
	game_world.queue_free()
	game_world = null
	get_tree().paused = false


func _on_hud_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or ui == null:
		return
	ui.hud.set_health(float(snapshot.health), float(snapshot.max_health))
	ui.hud.set_ammo(int(snapshot.ammo), int(snapshot.reserve), int(snapshot.magazine_size))
	ui.hud.set_weapon(String(snapshot.weapon_name), String(snapshot.fire_mode))
	ui.hud.set_equipment("FRAG", int(snapshot.frag_count), String(snapshot.tactical_name), int(snapshot.tactical_count))
	ui.hud.set_match_score(int(snapshot.score), String(snapshot.leader_name), int(snapshot.leader_score), int(snapshot.score_limit))
	ui.hud.set_compass_heading(float(snapshot.heading))
	ui.hud.set_minimap_data(float(snapshot.heading), snapshot.blips)
	ui.hud.set_crosshair_spread(float(snapshot.crosshair_spread))
	ui.hud.set_status_effects(float(snapshot.flash), float(snapshot.concussion))
	var standings_hash := hash(snapshot.standings)
	if standings_hash != _last_standings_hash:
		_last_standings_hash = standings_hash
		ui.scoreboard.update_players(snapshot.standings, int(snapshot.score_limit))


func _on_pickup_feedback(item_name: String) -> void:
	ui.hud.show_pickup_prompt(item_name, "EQUIPPED", 1.8)


func _on_match_completed(result: Dictionary) -> void:
	_last_result = result.duplicate(true)
	if _benchmark_mode:
		return
	menu_audio.set_ambience_active(true)
	menu_audio.play_result_stinger(bool(result.get("player_won", false)))
	ui.end_match(result)


func _wire_menu_audio() -> void:
	if ui == null or menu_audio == null:
		return
	for node in ui.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button == null:
			continue
		if not button.focus_entered.is_connected(_on_menu_focus_entered):
			button.focus_entered.connect(_on_menu_focus_entered)
		if not button.mouse_entered.is_connected(_on_menu_focus_entered):
			button.mouse_entered.connect(_on_menu_focus_entered)
		if not button.pressed.is_connected(_on_menu_button_pressed):
			button.pressed.connect(_on_menu_button_pressed)


func _on_menu_focus_entered() -> void:
	menu_audio.play_ui(false)


func _on_menu_button_pressed() -> void:
	menu_audio.play_ui(true)


func _run_command_line_mode() -> void:
	var args := OS.get_cmdline_user_args()
	if "--capture-suite" in args:
		_configure_qa_window()
		await _capture_suite()
		return
	var benchmark_seconds := _argument_float(args, "--bot-benchmark=", 0.0)
	if benchmark_seconds > 0.0:
		_configure_qa_window()
		var time_scale := _argument_float(args, "--time-scale=", 1.0)
		await _run_bot_benchmark(benchmark_seconds, time_scale)
		return
	if "--autoplay" in args:
		_start_match(ui.get_loadout(), ui.get_appearance())


func _capture_suite() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_capture_frame("res://screenshots/01_title.png")
	ui.show_home()
	await get_tree().process_frame
	_capture_frame("res://screenshots/02_ready_deck.png")
	_start_match(ui.get_loadout(), ui.get_appearance())
	await get_tree().create_timer(2.5).timeout
	_capture_frame("res://screenshots/03_breakwater_station.png")
	if game_world != null and not game_world.bots.is_empty():
		for _index in 30:
			game_world.match_rules.record_elimination(&"player", game_world.bots[0].combatant_id)
	await get_tree().process_frame
	await get_tree().process_frame
	_capture_frame("res://screenshots/04_victory.png")
	print("CAPTURE_SUITE_OK")
	get_tree().quit()


func _run_bot_benchmark(simulated_seconds: float, time_scale: float) -> void:
	_benchmark_mode = true
	Engine.time_scale = clampf(time_scale, 1.0, 12.0)
	_start_benchmark_round()
	var simulated_elapsed := 0.0
	var bot_score_total := 0
	var bot_vs_bot_total := 0
	var bot_vs_player_total := 0
	var bot_grenades := 0
	var bot_pickups := 0
	var completed_rounds := 0
	var current_round_counted := false
	var standings: Array[Dictionary] = []
	while game_world != null and simulated_elapsed < simulated_seconds:
		await get_tree().process_frame
		simulated_elapsed += get_process_delta_time()
		if game_world != null and game_world._finished and not current_round_counted:
			var finished_stats := _benchmark_round_stats()
			bot_score_total += int(finished_stats.bot_kills)
			bot_vs_bot_total += int(finished_stats.bot_vs_bot)
			bot_vs_player_total += int(finished_stats.bot_vs_player)
			bot_grenades += int(finished_stats.bot_grenades)
			bot_pickups += int(finished_stats.bot_pickups)
			standings = finished_stats.standings
			completed_rounds += 1
			current_round_counted = true
			if simulated_elapsed < simulated_seconds:
				_start_benchmark_round()
				current_round_counted = false
	if game_world != null and not current_round_counted:
		var active_stats := _benchmark_round_stats()
		bot_score_total += int(active_stats.bot_kills)
		bot_vs_bot_total += int(active_stats.bot_vs_bot)
		bot_vs_player_total += int(active_stats.bot_vs_player)
		bot_grenades += int(active_stats.bot_grenades)
		bot_pickups += int(active_stats.bot_pickups)
		standings = active_stats.standings
	print(
		"BOT_BENCHMARK simulated=%.1fs scale=%.1f rounds=%d bot_kills=%d bot_vs_bot=%d bot_vs_player=%d bot_grenades=%d bot_pickups=%d standings=%s"
		% [simulated_seconds, Engine.time_scale, completed_rounds, bot_score_total, bot_vs_bot_total, bot_vs_player_total, bot_grenades, bot_pickups, str(standings)]
	)
	_capture_frame("res://screenshots/05_bot_benchmark.png")
	Engine.time_scale = 1.0
	get_tree().quit(0 if bot_score_total > 0 and bot_vs_bot_total > 0 else 2)


func _start_benchmark_round() -> void:
	_start_match(ui.get_loadout(), ui.get_appearance())
	if game_world == null:
		return
	game_world.telemetry_enabled = false
	game_world.player.set_input_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _benchmark_round_stats() -> Dictionary:
	if game_world == null:
		return {"bot_kills": 0, "bot_vs_bot": 0, "bot_vs_player": 0, "bot_grenades": 0, "bot_pickups": 0, "standings": []}
	var standings := game_world.standings_for_ui()
	var bot_kills := 0
	for row: Dictionary in standings:
		if not bool(row.get("is_player", false)):
			bot_kills += int(row.get("kills", 0))
	return {
		"bot_kills": bot_kills,
		"bot_vs_bot": game_world.bot_vs_bot_kills,
		"bot_vs_player": game_world.bot_vs_player_kills,
		"bot_grenades": game_world.bot_grenades_thrown,
		"bot_pickups": game_world.bot_pickups_collected,
		"standings": standings,
	}


func _capture_frame(resource_path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("CAPTURE_SKIPPED_HEADLESS %s" % resource_path)
		return
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(absolute_path)
	if error == OK:
		print("CAPTURED %s" % resource_path)
	else:
		push_error("Could not capture %s: %s" % [resource_path, error_string(error)])


func _argument_float(args: PackedStringArray, prefix: String, fallback: float) -> float:
	for argument in args:
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix).to_float()
	return fallback


func _configure_qa_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var settings := get_node_or_null("/root/SettingsManager") as BreakwaterSettingsManager
	if settings != null:
		settings.set_value(&"video", &"window_mode", "windowed", false)
		settings.set_value(&"video", &"resolution", Vector2i(1920, 1080), false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
