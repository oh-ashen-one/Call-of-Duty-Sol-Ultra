class_name BreakwaterUICoordinator
extends CanvasLayer
## Drop-in UI composition root for main.gd. It owns menu routing, HUD, and overlays.

signal match_start_requested(loadout: Dictionary, appearance: Dictionary)
signal restart_match_requested
signal leave_match_requested
signal quit_requested

var hud: BreakwaterGameHUD
var scoreboard: BreakwaterScoreboard
var pause_menu: BreakwaterPauseMenu
var title_home: BreakwaterTitleHomeScreen
var matchmaking: BreakwaterMatchmakingScreen
var loadout: BreakwaterLoadoutScreen
var skins: BreakwaterSkinsScreen
var settings: BreakwaterSettingsScreen
var credits: BreakwaterCreditsScreen
var post_match: BreakwaterPostMatchScreen

var _menu_screens: Array[Control] = []
var _settings_return := &"home"
var _in_match := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_screens()
	_connect_navigation()
	show_title()


func show_title() -> void:
	_in_match = false
	_hide_match_ui()
	_show_menu(title_home)
	title_home.show_title()


func show_home() -> void:
	_in_match = false
	_hide_match_ui()
	_show_menu(title_home)
	title_home.show_home()


func begin_matchmaking() -> void:
	_show_menu(matchmaking)
	matchmaking.begin()


func enter_match() -> void:
	_in_match = true
	_hide_menus()
	hud.reset_for_match()
	hud.show()
	scoreboard.input_enabled = true
	scoreboard.hide_board()
	pause_menu.close_pause(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func end_match(result: Dictionary) -> void:
	_in_match = false
	hud.hide()
	scoreboard.input_enabled = false
	scoreboard.hide_board()
	pause_menu.close_pause(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_menu(post_match)
	post_match.show_results(result)


func open_pause() -> void:
	if not _in_match:
		return
	scoreboard.input_enabled = false
	scoreboard.hide_board()
	pause_menu.open_pause(true)


func get_loadout() -> Dictionary:
	return loadout.get_loadout()


func get_appearance() -> Dictionary:
	return skins.get_selection()


func _build_screens() -> void:
	title_home = BreakwaterTitleHomeScreen.new()
	matchmaking = BreakwaterMatchmakingScreen.new()
	loadout = BreakwaterLoadoutScreen.new()
	skins = BreakwaterSkinsScreen.new()
	settings = BreakwaterSettingsScreen.new()
	credits = BreakwaterCreditsScreen.new()
	post_match = BreakwaterPostMatchScreen.new()
	_menu_screens = [title_home, matchmaking, loadout, skins, settings, credits, post_match]
	for screen: Control in _menu_screens:
		add_child(screen)

	hud = BreakwaterGameHUD.new()
	add_child(hud)
	hud.hide()
	scoreboard = BreakwaterScoreboard.new()
	add_child(scoreboard)
	pause_menu = BreakwaterPauseMenu.new()
	add_child(pause_menu)


func _connect_navigation() -> void:
	title_home.play_requested.connect(begin_matchmaking)
	title_home.loadout_requested.connect(func() -> void: _show_menu(loadout))
	title_home.skins_requested.connect(func() -> void: _show_menu(skins))
	title_home.settings_requested.connect(_open_home_settings)
	title_home.credits_requested.connect(func() -> void: _show_menu(credits))
	title_home.quit_requested.connect(quit_requested.emit)
	matchmaking.cancel_requested.connect(show_home)
	matchmaking.match_ready.connect(_on_matchmaking_ready)
	loadout.back_requested.connect(show_home)
	loadout.apply_requested.connect(func(_value: Dictionary) -> void: show_home())
	skins.back_requested.connect(show_home)
	skins.apply_requested.connect(func(_value: Dictionary) -> void: show_home())
	settings.back_requested.connect(_return_from_settings)
	credits.back_requested.connect(show_home)
	post_match.rematch_requested.connect(restart_match_requested.emit)
	post_match.return_to_menu_requested.connect(show_home)
	hud.pause_requested.connect(open_pause)
	pause_menu.resume_requested.connect(_resume_from_pause)
	pause_menu.restart_requested.connect(_restart_from_pause)
	pause_menu.settings_requested.connect(_open_pause_settings)
	pause_menu.quit_to_menu_requested.connect(_leave_from_pause)


func _show_menu(target: Control) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for screen: Control in _menu_screens:
		if screen == target:
			screen.show()
			if screen is BreakwaterUIScreen:
				screen.focus_default()
		else:
			screen.hide()


func _hide_menus() -> void:
	for screen: Control in _menu_screens:
		screen.hide()


func _hide_match_ui() -> void:
	hud.hide()
	scoreboard.input_enabled = false
	scoreboard.hide_board()
	pause_menu.close_pause(true)


func _resume_from_pause() -> void:
	if not _in_match:
		return
	scoreboard.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_matchmaking_ready() -> void:
	match_start_requested.emit(get_loadout(), get_appearance())


func _open_home_settings() -> void:
	_settings_return = &"home"
	_show_menu(settings)


func _open_pause_settings() -> void:
	_settings_return = &"pause"
	hud.hide()
	scoreboard.input_enabled = false
	scoreboard.hide_board()
	pause_menu.hide()
	_show_menu(settings)


func _return_from_settings() -> void:
	if _settings_return == &"pause" and _in_match:
		_hide_menus()
		hud.show()
		pause_menu.restore_pause_view()
		return
	show_home()


func _restart_from_pause() -> void:
	pause_menu.close_pause(true)
	restart_match_requested.emit()


func _leave_from_pause() -> void:
	pause_menu.close_pause(true)
	show_home()
	leave_match_requested.emit()
