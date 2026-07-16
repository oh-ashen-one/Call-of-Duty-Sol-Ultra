extends SceneTree

## End-to-end contracts beyond the focused gameplay suite.

var _assertions := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var settings := root.get_node_or_null("SettingsManager") as BreakwaterSettingsManager
	var original_settings_path := settings.settings_path if settings != null else ""
	var isolated_settings_path := "user://breakwater_settings_verifier_runtime.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_settings_path))
	if settings != null:
		# All UI controls exercise their real persistence path, but the verifier
		# must never overwrite a player's actual settings or custom bindings.
		settings.settings_path = isolated_settings_path
		settings.save_settings()
	_test_exact_score_limits()
	await _test_settings_persistence_and_controller_map()
	await _test_world_and_full_match_composition()
	await _test_ui_lifecycle()
	await _test_application_journey()
	if settings != null:
		settings.settings_path = original_settings_path
		settings.load_settings()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_settings_path))
	if _failures.is_empty():
		print("INTEGRATION TESTS PASS — %d assertions" % _assertions)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("INTEGRATION TESTS FAIL — %d failure(s), %d assertions" % [_failures.size(), _assertions])
		quit(1)


func _test_exact_score_limits() -> void:
	var player_win := MatchRules.new()
	player_win.target_score = 30
	for index in 30:
		_expect(player_win.record_elimination(&"player", StringName("bot_%d" % (index % 7))), "player elimination %d counts" % index)
	_expect_equal(player_win.get_score(&"player"), 30, "player victory occurs at exactly 30")
	_expect_equal(player_win.winner_id, &"player", "player is recorded as winner")
	_expect(not player_win.record_elimination(&"player", &"bot_1"), "score cannot advance after victory")
	player_win.free()

	var bot_win := MatchRules.new()
	bot_win.target_score = 30
	for index in 30:
		bot_win.record_elimination(&"bot_1", StringName("opponent_%d" % index))
	_expect_equal(bot_win.get_score(&"bot_1"), 30, "bot victory occurs at exactly 30")
	_expect_equal(bot_win.winner_id, &"bot_1", "bot is recorded as winner")
	bot_win.free()


func _test_settings_persistence_and_controller_map() -> void:
	var settings := root.get_node_or_null("SettingsManager") as BreakwaterSettingsManager
	_expect(settings != null, "SettingsManager autoload is available")
	if settings == null:
		return
	var original_sensitivity := float(settings.get_value(&"controls", &"mouse_sensitivity", 0.18))
	settings.set_value(&"controls", &"mouse_sensitivity", 0.271, true)
	var config := ConfigFile.new()
	var load_error := config.load(settings.settings_path)
	_expect_equal(load_error, OK, "settings ConfigFile saves successfully")
	_expect_near(float(config.get_value("controls", "mouse_sensitivity", 0.0)), 0.271, 0.0001, "saved setting round-trips")
	settings.set_value(&"controls", &"mouse_sensitivity", original_sensitivity, true)

	_expect(_has_joy_axis(&"move_forward", JOY_AXIS_LEFT_Y, -1.0), "left stick maps forward")
	_expect(_has_joy_axis(&"fire", JOY_AXIS_TRIGGER_RIGHT, 1.0), "right trigger maps fire")
	_expect(_has_joy_axis(&"aim", JOY_AXIS_TRIGGER_LEFT, 1.0), "left trigger maps ADS")
	_expect(_has_joy_button(&"pause", JOY_BUTTON_START), "controller start maps pause")
	var rebound_button := InputEventJoypadButton.new()
	rebound_button.button_index = JOY_BUTTON_Y
	settings.rebind_action(&"jump", rebound_button, true, false)
	_expect(_has_joy_button(&"jump", JOY_BUTTON_Y) and not _has_joy_button(&"jump", JOY_BUTTON_A), "controller buttons can be rebound")
	_expect(_has_key(&"jump", KEY_SPACE), "controller rebinding preserves keyboard input")
	settings.reset_bindings(false)

	var look_probe := PlayerController.new()
	look_probe.invert_y = false
	look_probe._apply_look(0.0, 5.0)
	var normal_pitch := look_probe._look_pitch
	look_probe._look_pitch = 0.0
	look_probe.invert_y = true
	look_probe._apply_look(0.0, 5.0)
	_expect(normal_pitch > 0.0 and look_probe._look_pitch < 0.0, "invert-Y reverses pitch exactly once")
	look_probe.set_feedback_settings(0.35, false)
	look_probe.add_camera_impulse(0.6, 1.0)
	_expect_near(look_probe.camera_shake_strength, 0.35, 0.001, "camera-shake setting reaches player feedback")
	_expect(not look_probe.vibration_enabled and look_probe.camera_impulse_level() > 0.0, "vibration toggle and camera impulse are functional")
	look_probe.free()

	var test_path := "user://breakwater_settings_integration_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	var writer := BreakwaterSettingsManager.new()
	writer.settings_path = test_path
	root.add_child(writer)
	await process_frame
	writer.set_value(&"audio", &"master_volume", 0.61, false)
	writer.set_value(&"audio", &"music_volume", 0.52, false)
	writer.set_value(&"audio", &"sfx_volume", 0.73, false)
	writer.set_value(&"audio", &"ui_volume", 0.44, false)
	writer.set_value(&"controls", &"mouse_sensitivity", 0.19, false)
	writer.set_value(&"controls", &"ads_sensitivity", 0.63, false)
	writer.set_value(&"controls", &"controller_sensitivity", 3.7, false)
	writer.set_value(&"controls", &"controller_deadzone", 0.23, false)
	writer.set_value(&"controls", &"vibration", false, false)
	writer.set_value(&"controls", &"invert_y", true, false)
	writer.set_value(&"video", &"fov", 103.0, false)
	writer.set_value(&"video", &"window_mode", "windowed", false)
	writer.set_value(&"video", &"resolution", Vector2i(1600, 900), false)
	writer.set_value(&"video", &"render_scale", 0.8, false)
	writer.set_value(&"video", &"quality", "medium", false)
	writer.set_value(&"video", &"vsync", false, false)
	writer.set_value(&"gameplay", &"camera_shake", 0.25, false)
	writer.set_value(&"gameplay", &"hit_markers", false, false)
	writer.set_value(&"gameplay", &"crosshair", false, false)
	writer.set_value(&"gameplay", &"crosshair_color", Color("ff6b4a"), false)
	var persisted_jump := InputEventJoypadButton.new()
	persisted_jump.button_index = JOY_BUTTON_Y
	writer.rebind_action(&"jump", persisted_jump, true, false)
	var bare_k := InputEventKey.new()
	bare_k.physical_keycode = KEY_K
	writer.rebind_action(&"crouch", bare_k, true, false)
	var shifted_k := InputEventKey.new()
	shifted_k.physical_keycode = KEY_K
	shifted_k.shift_pressed = true
	writer.rebind_action(&"melee", shifted_k, true, false)
	_expect_equal(writer.save_settings(), OK, "isolated settings fixture saves")
	writer.queue_free()
	await process_frame

	var reader := BreakwaterSettingsManager.new()
	reader.settings_path = test_path
	root.add_child(reader)
	await process_frame
	_expect_near(float(reader.get_value(&"audio", &"master_volume", 0.0)), 0.61, 0.001, "fresh manager reloads master volume")
	_expect_near(float(reader.get_value(&"audio", &"music_volume", 0.0)), 0.52, 0.001, "fresh manager reloads music volume")
	_expect_near(float(reader.get_value(&"audio", &"sfx_volume", 0.0)), 0.73, 0.001, "fresh manager reloads SFX volume")
	_expect_near(float(reader.get_value(&"audio", &"ui_volume", 0.0)), 0.44, 0.001, "fresh manager reloads UI volume")
	_expect_near(float(reader.get_value(&"controls", &"mouse_sensitivity", 0.0)), 0.19, 0.001, "fresh manager reloads mouse sensitivity")
	_expect_near(float(reader.get_value(&"controls", &"ads_sensitivity", 0.0)), 0.63, 0.001, "fresh manager reloads ADS sensitivity")
	_expect_near(float(reader.get_value(&"controls", &"controller_sensitivity", 0.0)), 3.7, 0.001, "fresh manager reloads controller sensitivity")
	_expect_near(float(reader.get_value(&"controls", &"controller_deadzone", 0.0)), 0.23, 0.001, "fresh manager reloads controller dead zone")
	_expect(not bool(reader.get_value(&"controls", &"vibration", true)), "fresh manager reloads vibration toggle")
	_expect(bool(reader.get_value(&"controls", &"invert_y", false)), "fresh manager reloads invert-Y")
	_expect_near(float(reader.get_value(&"video", &"fov", 0.0)), 103.0, 0.001, "fresh manager reloads FOV")
	_expect_equal(reader.get_value(&"video", &"window_mode", ""), "windowed", "fresh manager reloads window mode")
	_expect_equal(reader.get_value(&"video", &"resolution", Vector2i.ZERO), Vector2i(1600, 900), "fresh manager reloads resolution")
	_expect_near(float(reader.get_value(&"video", &"render_scale", 0.0)), 0.8, 0.001, "fresh manager reloads render scale")
	_expect_equal(reader.get_value(&"video", &"quality", ""), "medium", "fresh manager reloads graphics preset")
	_expect(not bool(reader.get_value(&"video", &"vsync", true)), "fresh manager reloads VSync")
	_expect_near(float(reader.get_value(&"gameplay", &"camera_shake", 0.0)), 0.25, 0.001, "fresh manager reloads camera shake")
	_expect(not bool(reader.get_value(&"gameplay", &"hit_markers", true)), "fresh manager reloads hit-marker toggle")
	_expect(not bool(reader.get_value(&"gameplay", &"crosshair", true)), "fresh manager reloads crosshair toggle")
	_expect_equal(reader.get_value(&"gameplay", &"crosshair_color", Color.BLACK), Color("ff6b4a"), "fresh manager reloads crosshair color")
	_expect(_has_joy_button(&"jump", JOY_BUTTON_Y), "fresh manager reloads controller binding")
	_expect(_has_key(&"crouch", KEY_K), "bare key binding survives an isolated settings reload")
	_expect(_has_modified_key(&"melee", KEY_K, true), "modifier-assisted key binding survives an isolated settings reload")
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	_expect(sfx_bus >= 0 and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(sfx_bus)), 0.73), "reloaded SFX setting applies to the runtime audio bus")
	_expect_near(_bus_linear_volume(&"Master"), 0.61, 0.001, "reloaded master volume applies to the runtime audio bus")
	_expect_near(_bus_linear_volume(&"Music"), 0.52, 0.001, "reloaded music volume applies to the runtime audio bus")
	_expect_near(_bus_linear_volume(&"UI"), 0.44, 0.001, "reloaded UI volume applies to the runtime audio bus")
	_expect_near(root.scaling_3d_scale, 0.8, 0.001, "reloaded render scale applies to the root viewport")
	reader.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	settings.load_settings()


func _test_world_and_full_match_composition() -> void:
	var world := BreakwaterGameWorld.new()
	world.configure(
		{"primary": &"kestrel_smg", "secondary": &"sparrow_pistol", "lethal": &"frag", "tactical": &"concussion"},
		{"skin": &"rescue_coral", "camo": &"signal_flare"},
		false,
	)
	root.add_child(world)
	await process_frame
	await process_frame
	_expect_equal(world.map_data.get("spawn_points", []).size(), 8, "Breakwater map exposes eight spawns")
	_expect_equal(world._spawn_safe_radii, [8.0, 8.0, 8.0, 8.0, 8.0, 8.0, 8.0, 8.0], "authored spawn safety radii reach every combatant")
	_expect(world.map_data.get("patrol_points", []).size() >= 20, "map exposes route waypoints")
	_expect(world.map_data.get("pickup_points", []).size() >= 6, "map exposes weapon pickup positions")
	_expect_equal(world.combatants.size(), 8, "full match has player plus seven bots")
	_expect_equal(world.bots.size(), 7, "seven autonomous bots are created")
	var bot_primary_ids: Dictionary = {}
	var bot_primary_classes: Dictionary = {}
	for bot in world.bots:
		var authored_primary := bot.weapon_states[0].definition
		bot_primary_ids[authored_primary.weapon_id] = true
		bot_primary_classes[authored_primary.weapon_class] = true
	_expect_equal(bot_primary_ids.size(), 5, "seven-bot roster deterministically fields every non-pistol primary")
	_expect_equal(bot_primary_classes.size(), 5, "live bot roster guarantees five distinct primary weapon classes")
	_expect(world.player.health.is_protected(), "player receives protection on the initial spawn")
	for bot in world.bots:
		_expect(bot.health.is_protected(), "%s receives protection on the initial spawn" % bot.display_name)
	_expect(world.map_data.get("navigation_links", []).size() >= 30, "map exposes an authored route-navigation graph")
	for bot in world.bots:
		_expect_equal(bot.navigation_waypoint_count(), world.map_data.get("patrol_points", []).size(), "%s receives every patrol waypoint" % bot.display_name)
		_expect(bot.navigation_connection_count() >= 30, "%s receives connected combat routes" % bot.display_name)
		_expect(is_instance_valid(bot._weapon_visual), "%s displays its equipped weapon" % bot.display_name)
	_expect(world.bots[0].route_path_to(world.bots[6].global_position).size() > 0, "bot route graph resolves a cross-map path")
	_expect_equal(get_nodes_in_group(&"field_pickups").size(), 12, "twelve field pickups are active")
	_expect_equal(get_nodes_in_group(&"weapon_pickups").size(), 6, "six authored weapon pickups are active")
	var supply_ids: Dictionary = {}
	for node in get_nodes_in_group(&"field_pickups"):
		var field_pickup := node as WeaponPickup
		if field_pickup != null and field_pickup.pickup_kind == &"supply":
			supply_ids[field_pickup.supply_id] = true
	_expect(supply_ids.has(&"ammo"), "field pickups include ammunition resupply")
	_expect(supply_ids.has(&"frag") and supply_ids.has(&"flash") and supply_ids.has(&"concussion"), "field pickups include all grenade types")
	_expect_equal((world.map_data.get("landmark_nodes", {}) as Dictionary).size(), 3, "map exposes three recognizable landmarks")
	_expect_equal(get_nodes_in_group(&"combat_route").size(), 3, "map builds three primary combat routes")
	_expect_equal(get_nodes_in_group(&"quality_reflection").size(), 1, "map includes a reflection probe")
	_expect_equal(get_nodes_in_group(&"quality_detail").size(), 1, "map includes optimized coastal vegetation detail")
	var elevated_pickup := world.get_node_or_null("FieldPickup_11") as WeaponPickup
	_expect(elevated_pickup != null and elevated_pickup.global_position.y > 4.0, "catwalk pickup preserves its elevated authored position")
	if elevated_pickup != null:
		_expect_near(elevated_pickup._base_y, 4.35, 0.01, "catwalk pickup bobs around the authored catwalk height")
	var snapshot := world.make_hud_snapshot()
	_expect_equal(int(snapshot.get("score_limit", 0)), 30, "HUD advertises first-to-30")
	_expect_equal((snapshot.get("standings", []) as Array).size(), 8, "HUD standings include all combatants")
	_expect(world.player.camera != null and world.player.camera.current, "first-person camera is active")
	_expect_equal(world.player.current_weapon().weapon_id, &"kestrel_smg", "non-default equipped primary reaches the live player")
	_expect_equal(world.player.tactical_grenade_id, &"concussion", "non-default tactical selection reaches the live player")
	_expect(world.player.grenade_inventory.has(&"concussion") and not world.player.grenade_inventory.has(&"flash"), "live inventory contains only the equipped tactical type")
	var camo := BreakwaterContent.weapon_camo_by_id(&"signal_flare")
	var skin := BreakwaterContent.operator_skin_by_id(&"rescue_coral")
	var receiver := world._view_model.get_node_or_null("Receiver") as MeshInstance3D
	var right_glove := world._view_model.get_node_or_null("RightGlove") as MeshInstance3D
	_expect(receiver != null and (receiver.material_override as StandardMaterial3D).albedo_color == camo.base, "selected weapon camo visibly reaches the first-person receiver")
	_expect(right_glove != null and (right_glove.material_override as StandardMaterial3D).albedo_color == skin.primary, "selected operator skin visibly reaches the first-person gloves")
	var barrel := world._view_model.get_node_or_null("Barrel") as Node3D
	var fallback_flash_origin := Vector3(250.0, 250.0, 250.0)
	var player_flash_origin := world._muzzle_flash_origin(BreakwaterGameWorld.PLAYER_ID, fallback_flash_origin, world.player.get_view_direction())
	_expect(barrel != null and player_flash_origin.distance_to(barrel.global_position) < 0.3, "player muzzle flash originates at the first-person barrel")
	var bot_barrel := world.bots[0]._weapon_visual.get_node_or_null("Barrel") as Node3D
	var bot_flash_origin := world._muzzle_flash_origin(world.bots[0].combatant_id, fallback_flash_origin, world.bots[0].get_view_direction())
	_expect(bot_barrel != null and bot_flash_origin.distance_to(bot_barrel.global_position) < 0.3, "bot muzzle flash originates at its visible weapon barrel")
	world._on_kill_recorded(&"bot_1", &"bot_2", 1)
	world._on_kill_recorded(&"bot_1", BreakwaterGameWorld.PLAYER_ID, 2)
	world._on_kill_recorded(&"bot_1", &"bot_1", 2)
	_expect_equal(world.bot_vs_bot_kills, 1, "telemetry classifies bot-versus-bot eliminations separately")
	_expect_equal(world.bot_vs_player_kills, 1, "telemetry classifies bot-versus-player eliminations separately")
	_expect_equal(world.bot_vs_bot_kills, 1, "bot suicides cannot satisfy bot-versus-bot benchmark telemetry")
	world.bot_vs_bot_kills = 0
	world.bot_vs_player_kills = 0
	var reload_state := world.player.current_weapon_state()
	reload_state.magazine_ammo = 0
	_expect(reload_state.begin_reload() and world._view_model_reload > 0.0, "initial weapon reload drives viewmodel feedback")
	world._update_view_model(reload_state.definition.reload_seconds * 0.5)
	_expect(world._view_model_reload > 0.45, "reload presentation remains active for the authored weapon duration")
	world._update_view_model(reload_state.definition.reload_seconds * 0.55)
	_expect_near(world._view_model_reload, 0.0, 0.01, "reload presentation finishes with the authored reload timer")
	reload_state.cancel_reload()
	_expect(reload_state.begin_reload(), "weapon can begin another reload presentation after the authored cycle")
	reload_state.cancel_reload()
	world._update_view_model(0.01)
	_expect_near(world._view_model_reload, 0.0, 0.001, "canceling reload immediately clears the viewmodel reload pose")
	world.player.movement_audio_requested.emit(&"footstep", 0.8)
	_expect_equal(int(world.audio.movement_requests.get(&"footstep", 0)), 1, "player movement feedback reaches the procedural audio layer")
	var authored_score := world.audio._make_score()
	_expect(authored_score.get_length() >= 11.9 and authored_score.data.size() > 400000, "audio layer contains an original looping musical score")
	var interaction_pickup := WeaponPickup.new()
	interaction_pickup.configure(WeaponCatalog.get_weapon(&"helix_dmr"), 10.0)
	world.add_child(interaction_pickup)
	interaction_pickup.global_position = world.player.global_position + Vector3(0.0, 0.0, -1.0)
	_expect(world.player.nearest_weapon_pickup() == interaction_pickup, "player detects a nearby interactable weapon")
	_expect(world.player._try_interact() and not interaction_pickup.is_available, "interact action collects the focused weapon")

	var blast_target := CombatantController.new()
	blast_target.configure_identity(&"grenade_feedback_target", "Grenade Feedback Target")
	world.add_child(blast_target)
	blast_target.global_position = Vector3(0.0, 20.0, 0.0)
	world.combatants[blast_target.combatant_id] = blast_target
	await process_frame
	blast_target.health.spawn_protection_remaining = 0.0
	var grenade_feedback: Array[bool] = []
	world.hit_feedback_ready.connect(func(killed: bool, _headshot: bool) -> void: grenade_feedback.append(killed))
	var player_frag := GrenadeProjectile.new()
	player_frag.configure(GrenadeDefinition.create_frag(), BreakwaterGameWorld.PLAYER_ID, world.player)
	world.add_child(player_frag)
	player_frag.global_position = blast_target.get_eye_position()
	world._wire_new_grenades()
	player_frag.detonate()
	_expect_equal(grenade_feedback.size(), 1, "player grenade effect emits one HUD hit-feedback event")
	if not grenade_feedback.is_empty():
		_expect(grenade_feedback[0], "lethal player grenade effect emits kill-marker feedback")
	world.combatants.erase(blast_target.combatant_id)
	blast_target.queue_free()
	await process_frame

	var settings := root.get_node_or_null("SettingsManager") as BreakwaterSettingsManager
	if settings != null:
		var original_runtime := settings.get_settings_snapshot()
		settings.set_value(&"controls", &"mouse_sensitivity", 0.31, false)
		settings.set_value(&"controls", &"ads_sensitivity", 0.58, false)
		settings.set_value(&"controls", &"controller_sensitivity", 4.2, false)
		settings.set_value(&"controls", &"controller_deadzone", 0.27, false)
		settings.set_value(&"controls", &"invert_y", true, false)
		settings.set_value(&"controls", &"vibration", false, false)
		settings.set_value(&"gameplay", &"camera_shake", 0.33, false)
		settings.set_value(&"video", &"fov", 101.0, false)
		_expect_near(world.player.mouse_sensitivity, 0.31, 0.001, "mouse sensitivity applies to the live player")
		_expect_near(world.player.ads_sensitivity_scale, 0.58, 0.001, "ADS sensitivity applies to the live player")
		_expect_near(world.player.controller_sensitivity, 4.2, 0.001, "controller sensitivity applies to the live player")
		_expect_near(world.player.controller_deadzone, 0.27, 0.001, "controller dead zone applies to the live player")
		_expect(world.player.invert_y and not world.player.vibration_enabled, "invert-Y and vibration settings apply to the live player")
		_expect_near(world.player.camera_shake_strength, 0.33, 0.001, "camera shake applies to the live player")
		_expect_near(world.player.hip_fov, 101.0, 0.001, "FOV setting applies to the live player camera target")
		_expect_near(world.player.camera.fov, 101.0, 0.001, "FOV setting updates the bound first-person camera immediately")
		var original_quality := String(settings.get_value(&"video", &"quality", "high"))
		settings.set_value(&"video", &"quality", "low", false)
		var sun := get_first_node_in_group(&"quality_shadow_light") as DirectionalLight3D
		var coastal_environment := get_first_node_in_group(&"quality_environment") as WorldEnvironment
		var reflection := get_first_node_in_group(&"quality_reflection") as Node3D
		var detail := get_first_node_in_group(&"quality_detail") as Node3D
		var persistent_cover := get_first_node_in_group(&"persistent_cover") as Node3D
		_expect(sun != null and not sun.shadow_enabled, "low graphics preset disables dynamic sun shadows")
		_expect(coastal_environment != null and not coastal_environment.environment.fog_enabled, "low graphics preset disables atmospheric fog")
		_expect(reflection != null and not reflection.visible, "low graphics preset disables the reflection probe")
		_expect(detail != null and not detail.visible, "low graphics preset hides optional vegetation detail")
		_expect(persistent_cover != null and persistent_cover.is_visible_in_tree(), "low graphics preset keeps collidable planter cover visible")
		_expect(world.vfx.max_transient_effects == 14 and not world.vfx.dynamic_effect_lights, "low graphics preset constrains transient VFX and dynamic effect lights")
		settings.set_value(&"video", &"quality", "high", false)
		_expect(sun.shadow_enabled and coastal_environment.environment.fog_enabled and reflection.visible and detail.visible, "high graphics preset restores lighting, fog, reflections, and detail")
		_expect(world.vfx.max_transient_effects == 48 and world.vfx.dynamic_effect_lights, "high graphics preset restores the full VFX budget")
		settings.set_value(&"video", &"quality", original_quality, false)
		for section_key: Variant in original_runtime.keys():
			var section_values: Dictionary = original_runtime[section_key]
			for setting_key: Variant in section_values.keys():
				settings.set_value(StringName(section_key), StringName(setting_key), section_values[setting_key], false)

	for actor in world.bots:
		if actor != world.bots[0]:
			actor.set_ai_enabled(false)
	world.player.set_input_enabled(false)
	world.player.global_position = Vector3(0.0, 0.0, 34.0)
	for pickup_node in get_nodes_in_group(&"field_pickups"):
		if world.is_ancestor_of(pickup_node):
			pickup_node.queue_free()
	await process_frame
	var climber := world.bots[0]
	var patrol_points: Array = world.map_data.get("patrol_points", [])
	climber.awareness_range = 0.1
	climber.target = null
	climber._desired_pickup = null
	climber.global_position = patrol_points[22] + Vector3.UP * 0.15
	climber.velocity = Vector3.ZERO
	climber._patrol_destination = patrol_points[19]
	climber.bot_state = BotController.BotState.PATROL
	for _frame in 600:
		await physics_frame
		if climber.global_position.y > 6.2:
			break
	var blocking_name := "none"
	var blocking_normal := Vector3.ZERO
	if climber.get_slide_collision_count() > 0:
		var blocking_collision := climber.get_slide_collision(climber.get_slide_collision_count() - 1)
		blocking_normal = blocking_collision.get_normal()
		var blocking_node := blocking_collision.get_collider() as Node
		if blocking_node != null:
			blocking_name = str(blocking_node.get_path())
	_expect(
		climber.global_position.y > 6.2,
		"bot follows authored west-ramp waypoints onto the vertical flank (reached %s velocity %s state %s blocker %s normal %s)" % [climber.global_position, climber.velocity, climber.bot_state, blocking_name, blocking_normal],
	)
	climber.global_position = patrol_points[28] + Vector3.UP * 0.15
	climber.velocity = Vector3.ZERO
	climber.target = null
	climber._desired_pickup = null
	climber._patrol_destination = patrol_points[21]
	climber.bot_state = BotController.BotState.PATROL
	for _frame in 600:
		await physics_frame
		if climber.global_position.y > 6.2 and climber.global_position.z < -16.0:
			break
	_expect(
		climber.global_position.y > 6.2 and climber.global_position.z < -16.0,
		"bot crosses the physical north connector onto the operations roof (reached %s velocity %s state %s)" % [climber.global_position, climber.velocity, climber.bot_state],
	)
	climber.global_position = patrol_points[25] + Vector3.UP * 0.15
	climber.velocity = Vector3.ZERO
	climber.target = null
	climber._desired_pickup = null
	climber._patrol_destination = patrol_points[20]
	climber.bot_state = BotController.BotState.PATROL
	var south_max_y := climber.global_position.y
	for _frame in 600:
		await physics_frame
		south_max_y = maxf(south_max_y, climber.global_position.y)
		if climber.global_position.y > 3.75 and climber.global_position.z < 17.0:
			break
	_expect(
		climber.global_position.y > 3.75 and climber.global_position.z < 17.0,
		"bot traverses the physical south ramp onto the east catwalk (reached %s max_y %.2f velocity %s state %s)" % [climber.global_position, south_max_y, climber.velocity, climber.bot_state],
	)
	world.shutdown()
	world.queue_free()
	await process_frame


func _test_ui_lifecycle() -> void:
	var ui := BreakwaterUICoordinator.new()
	root.add_child(ui)
	await process_frame
	var settings_manager := root.get_node_or_null("SettingsManager") as BreakwaterSettingsManager
	_expect(ui.title_home != null and ui.title_home.visible, "title/home screen boots visible")
	_expect(ui.matchmaking != null and ui.loadout != null and ui.skins != null, "front-end screens are composed")
	_expect(ui.settings != null and ui.credits != null, "settings and credits screens exist")
	_expect(not ui.scoreboard.input_enabled, "scoreboard input is disabled on the title screen")
	if settings_manager != null:
		var original_hit_markers := bool(settings_manager.get_value(&"gameplay", &"hit_markers", true))
		var original_crosshair := bool(settings_manager.get_value(&"gameplay", &"crosshair", true))
		var original_crosshair_color: Color = settings_manager.get_value(&"gameplay", &"crosshair_color", BreakwaterUI.MIST)
		settings_manager.set_value(&"gameplay", &"crosshair", false, false)
		settings_manager.set_value(&"gameplay", &"crosshair_color", Color("ff6b4a"), false)
		settings_manager.set_value(&"gameplay", &"hit_markers", false, false)
		_expect(not ui.hud._reticle.crosshair_visible, "crosshair toggle applies to the live HUD")
		_expect_equal(ui.hud._reticle.crosshair_color, Color("ff6b4a"), "crosshair color applies to the live HUD")
		ui.hud._reticle.reset_feedback()
		ui.hud.show_hit_marker(true, true)
		_expect_near(ui.hud._reticle._hit_time, 0.0, 0.001, "disabled hit markers suppress live hit feedback")
		settings_manager.set_value(&"gameplay", &"hit_markers", original_hit_markers, false)
		settings_manager.set_value(&"gameplay", &"crosshair", original_crosshair, false)
		settings_manager.set_value(&"gameplay", &"crosshair_color", original_crosshair_color, false)
	ui.show_home()
	var focus_before := ui.get_viewport().gui_get_focus_owner()
	var dpad_down := InputEventJoypadButton.new()
	dpad_down.button_index = JOY_BUTTON_DPAD_DOWN
	dpad_down.pressed = true
	Input.parse_input_event(dpad_down)
	await process_frame
	dpad_down.pressed = false
	Input.parse_input_event(dpad_down)
	await process_frame
	var focus_after := ui.get_viewport().gui_get_focus_owner()
	_expect(focus_before != null and focus_after is BaseButton and focus_after != focus_before, "controller D-pad advances menu focus")

	var initial_loadout := ui.get_loadout()
	ui._show_menu(ui.loadout)
	_expect_equal(ui.loadout._preset_option.item_count, BreakwaterContent.LOADOUTS.size() + 1, "loadout selector exposes Custom plus every authored preset")
	for preset_index in BreakwaterContent.LOADOUTS.size():
		var preset: Dictionary = BreakwaterContent.LOADOUTS[preset_index]
		ui.loadout._on_preset_selected(preset_index + 1)
		var pending_preset := ui.loadout.get_pending_loadout()
		_expect(
			pending_preset.primary == preset.primary
			and pending_preset.secondary == preset.secondary
			and pending_preset.lethal == preset.lethal
			and pending_preset.tactical == preset.tactical,
			"%s preset stages its complete authored weapon and equipment package" % preset.name,
		)
	ui.loadout._on_preset_selected(2)
	_expect("BREAKER-12" in ui.loadout._sidearm_caption.text, "secondary caption reflects the staged preset weapon")
	_expect_equal(ui.get_loadout().primary, initial_loadout.primary, "unequipped loadout edits do not alter the active match loadout")
	ui.loadout._select_primary(&"vx4_carbine")
	_expect_equal(ui.loadout._preset_option.selected, 0, "manual weapon edits switch the selector to Custom")
	ui.loadout._cancel_and_return()
	_expect_equal(ui.loadout.get_pending_loadout(), initial_loadout, "loadout Back discards staged weapon and equipment edits")
	_expect("SPARROW PISTOL" in ui.loadout._sidearm_caption.text, "loadout Back restores the equipped secondary caption")
	ui._show_menu(ui.loadout)
	ui.loadout._on_preset_selected(2)
	ui.loadout._emit_apply()
	_expect_equal(ui.get_loadout().primary, &"kestrel_smg", "Equip Loadout commits the staged primary")
	_expect_equal(ui.get_loadout().secondary, &"breaker_12", "Equip Loadout commits the staged secondary")
	_expect_equal(ui.get_loadout().tactical, &"concussion", "Equip Loadout commits the staged tactical grenade")
	ui.loadout._on_tactical_selected(0)
	_expect_equal(ui.loadout._preset_option.selected, 0, "manual equipment edits switch the selector to Custom")
	ui.loadout.set_loadout(initial_loadout)

	var initial_appearance := ui.get_appearance()
	ui._show_menu(ui.skins)
	ui.skins._select_skin(&"rescue_coral")
	ui.skins._select_camo(&"signal_flare")
	_expect_equal(ui.get_appearance(), initial_appearance, "unapplied appearance edits do not alter the active selection")
	ui.skins._cancel_and_return()
	_expect_equal(ui.skins.get_pending_selection(), initial_appearance, "appearance Back discards staged skin and camo edits")
	ui._show_menu(ui.skins)
	ui.skins._select_skin(&"rescue_coral")
	ui.skins._select_camo(&"signal_flare")
	ui.skins._emit_apply()
	_expect_equal(ui.get_appearance(), {"skin": &"rescue_coral", "camo": &"signal_flare"}, "Apply Appearance commits both staged selections")
	ui.skins.set_selection(initial_appearance)

	var automatic_match_requests := [0]
	ui.match_start_requested.connect(func(_loadout: Dictionary, _appearance: Dictionary) -> void: automatic_match_requests[0] += 1)
	ui.matchmaking.auto_advance = true
	ui.begin_matchmaking()
	ui.matchmaking._process(2.5)
	_expect_equal(ui.matchmaking._stage, BreakwaterMatchmakingScreen.MatchStage.FOUND, "automatic matchmaking advances from search to found")
	ui.matchmaking._process(1.2)
	_expect_equal(ui.matchmaking._stage, BreakwaterMatchmakingScreen.MatchStage.LOADING, "automatic matchmaking advances from found to loading")
	ui.matchmaking._process(3.1)
	_expect_equal(automatic_match_requests[0], 1, "automatic loading emits exactly one deployment request")
	ui.matchmaking.set_loading_progress(1.0)
	_expect_equal(automatic_match_requests[0], 1, "completed loading is idempotent when progress is reported again")
	ui.show_home()

	_seed_stale_hud_state(ui.hud)
	ui.enter_match()
	_expect_hud_match_reset(ui.hud, "initial match entry")
	_expect(ui.hud.visible, "HUD appears on match entry")
	_expect(ui.scoreboard.input_enabled, "scoreboard input is enabled during a match")
	if settings_manager != null:
		var actual_scoreboard_binding := InputEventJoypadButton.new()
		actual_scoreboard_binding.button_index = JOY_BUTTON_DPAD_LEFT
		settings_manager.rebind_action(&"scoreboard", actual_scoreboard_binding, true, false)
		var scoreboard_press := InputEventJoypadButton.new()
		scoreboard_press.button_index = JOY_BUTTON_DPAD_LEFT
		scoreboard_press.pressed = true
		Input.parse_input_event(scoreboard_press)
		await process_frame
		_expect(ui.scoreboard.visible, "GUI-consumed controller input opens a rebound scoreboard")
		scoreboard_press.pressed = false
		Input.parse_input_event(scoreboard_press)
		await process_frame
		_expect(not ui.scoreboard.visible, "releasing a rebound controller input closes the scoreboard")
		var actual_pause_binding := InputEventJoypadButton.new()
		actual_pause_binding.button_index = JOY_BUTTON_DPAD_DOWN
		settings_manager.rebind_action(&"pause", actual_pause_binding, true, false)
		var pause_press := InputEventJoypadButton.new()
		pause_press.button_index = JOY_BUTTON_DPAD_DOWN
		pause_press.pressed = true
		Input.parse_input_event(pause_press)
		await process_frame
		_expect(ui.pause_menu.visible and paused, "GUI-consumed controller input opens pause through a rebound action")
		pause_press.pressed = false
		Input.parse_input_event(pause_press)
		await process_frame
		pause_press.pressed = true
		Input.parse_input_event(pause_press)
		await process_frame
		_expect(not ui.pause_menu.visible and not paused, "the rebound pause action resumes while a button owns GUI focus")
		pause_press.pressed = false
		Input.parse_input_event(pause_press)
		await process_frame
	ui.open_pause()
	ui._open_pause_settings()
	_expect(ui.settings.visible and not ui.hud.visible and not ui.pause_menu.visible, "pause settings hide combat HUD and pause rail")
	if settings_manager != null:
		var master_slider: HSlider
		for widget in get_nodes_in_group(&"settings_widget"):
			if ui.settings.is_ancestor_of(widget) \
				and widget is HSlider \
				and StringName(widget.get_meta(&"section", &"")) == &"audio" \
				and StringName(widget.get_meta(&"key", &"")) == &"master_volume":
				master_slider = widget
				break
		var original_master := float(settings_manager.get_value(&"audio", &"master_volume", 0.85))
		if master_slider != null:
			master_slider.value = 0.57
		_expect(master_slider != null and is_equal_approx(float(settings_manager.get_value(&"audio", &"master_volume", 0.0)), 0.57), "changing a real settings widget writes and applies its setting")
		settings_manager.set_value(&"audio", &"master_volume", original_master, true)
	ui.settings._begin_binding_capture(&"melee")
	await process_frame
	var captured_accept := InputEventJoypadButton.new()
	captured_accept.button_index = JOY_BUTTON_A
	captured_accept.pressed = true
	Input.parse_input_event(captured_accept)
	await process_frame
	_expect(ui.settings._capture_action.is_empty(), "settings captures GUI-consumed controller buttons for rebinding")
	_expect(_has_joy_button(&"melee", JOY_BUTTON_A), "controller accept button reaches the active binding capture")
	_expect(not _has_joy_button(&"jump", JOY_BUTTON_A), "rebinding removes conflicting gameplay actions from the same controller button")
	_expect(ui.get_viewport().gui_get_focus_owner() == ui.settings._binding_buttons[&"melee"], "completed controller capture restores focus to its binding row")
	if settings_manager != null:
		var scoreboard_binding := InputEventJoypadButton.new()
		scoreboard_binding.button_index = JOY_BUTTON_Y
		settings_manager.rebind_action(&"scoreboard", scoreboard_binding, true, false)
		var pause_binding := InputEventJoypadButton.new()
		pause_binding.button_index = JOY_BUTTON_B
		settings_manager.rebind_action(&"pause", pause_binding, true, false)
		var frag_binding := InputEventJoypadButton.new()
		frag_binding.button_index = JOY_BUTTON_A
		settings_manager.rebind_action(&"throw_frag", frag_binding, true, false)
		var interact_binding := InputEventJoypadButton.new()
		interact_binding.button_index = JOY_BUTTON_DPAD_RIGHT
		settings_manager.rebind_action(&"interact", interact_binding, true, false)
		ui.hud.set_equipment("FRAG", 1, "FLASH", 1)
		ui.hud.show_pickup_prompt("VX-4 CARBINE", "interact")
		_expect("PAD Y" in ui.scoreboard._close_hint.text, "scoreboard hint follows a rebound controller action")
		_expect("PAD B" in ui.pause_menu._resume_hint.text, "pause hint follows a rebound controller action")
		_expect("PAD A" in ui.hud._equipment_label.text, "equipment hint follows a rebound controller action")
		_expect("D-PAD RIGHT" in ui.hud._pickup_prompt.text, "active pickup prompt refreshes after Interact is rebound")
		settings_manager.reset_bindings(true)
	captured_accept.pressed = false
	Input.parse_input_event(captured_accept)
	await process_frame

	ui.settings._begin_binding_capture(&"jump")
	ui.settings._save_and_return()
	await process_frame
	_expect(ui.hud.visible and ui.pause_menu.visible, "returning from pause settings restores HUD and pause rail")
	_expect(ui.get_viewport().gui_get_focus_owner() == ui.pause_menu._resume_button, "returning from pause settings restores controller focus to Resume")
	_expect(ui.settings._capture_action.is_empty() and ui.settings._capture_prompt.text.is_empty(), "leaving settings cancels an unfinished binding capture")
	var binding_buttons_enabled := true
	for button: Variant in ui.settings._binding_buttons.values():
		binding_buttons_enabled = binding_buttons_enabled and not (button as Button).disabled
	_expect(binding_buttons_enabled, "leaving settings restores every binding button")
	ui.pause_menu.close_pause(true)
	ui._resume_from_pause()
	ui.hud.set_status_effects(0.5, 0.4)
	ui.scoreboard.update_players([
		{"name": "YOU", "kills": 3, "deaths": 1, "is_player": true, "alive": true},
		{"name": "KITE", "kills": 4, "deaths": 2, "is_player": false, "alive": true},
	], 30)
	for index in 8:
		ui.hud.add_kill_feed("BOT %d" % index, "TARGET", "VX-4", false)
	_expect_equal(ui.hud._kill_feed.get_child_count(), 5, "kill feed trims bursts without stalling")
	ui.end_match({
		"player_won": true,
		"winner_name": "YOU",
		"winning_score": 30,
		"kills": 30,
		"deaths": 4,
		"headshots": 8,
		"accuracy": 0.42,
		"standings": [{"name": "YOU", "kills": 30, "deaths": 4, "is_player": true, "alive": true}],
	})
	_expect(ui.post_match.visible and not ui.hud.visible, "post-match screen replaces HUD")
	_expect(not ui.scoreboard.input_enabled, "scoreboard input is disabled on the results screen")
	ui.show_home()
	_expect(not ui.scoreboard.input_enabled, "scoreboard input remains disabled on the home screen")
	ui.queue_free()
	await process_frame


func _test_application_journey() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_expect(packed != null, "main application scene loads")
	if packed == null:
		return
	var app := packed.instantiate()
	root.add_child(app)
	await process_frame
	_expect(app.menu_audio.ambience_active, "menu ambience is requested at application boot")
	var buttons: Array[Node] = app.ui.find_children("*", "BaseButton", true, false)
	var audio_wired: bool = not buttons.is_empty()
	for node in buttons:
		var button := node as BaseButton
		audio_wired = audio_wired \
			and button.focus_entered.is_connected(app._on_menu_focus_entered) \
			and button.pressed.is_connected(app._on_menu_button_pressed)
	_expect(audio_wired, "all menu buttons are wired for focus and confirmation audio")
	app._on_menu_focus_entered()
	app._on_menu_button_pressed()
	_expect_equal(app.menu_audio.ui_navigation_requests, 1, "menu focus requests a navigation cue in headless mode")
	_expect_equal(app.menu_audio.ui_confirm_requests, 1, "menu press requests a confirmation cue in headless mode")
	await process_frame
	app.ui.show_home()
	_expect(app.ui.title_home.visible, "title advances to the ready-deck home screen")
	app.ui.matchmaking.auto_advance = false
	app.ui.begin_matchmaking()
	_expect(app.ui.matchmaking.visible and app.ui.matchmaking._stage == BreakwaterMatchmakingScreen.MatchStage.SEARCHING, "offline practice search starts")
	app.ui.matchmaking._on_cancel_pressed()
	await process_frame
	_expect(app.ui.title_home.visible and app.ui.matchmaking._stage == BreakwaterMatchmakingScreen.MatchStage.IDLE, "cancelling practice search returns home and resets its stage")
	_expect(not app.ui.matchmaking._sonar.active and not app.ui.matchmaking._sonar.is_processing(), "cancelled hidden matchmaking sonar stops processing")
	app.ui.begin_matchmaking()
	app.ui.matchmaking.mark_match_found()
	_expect_equal(app.ui.matchmaking._stage, BreakwaterMatchmakingScreen.MatchStage.FOUND, "practice roster is found")
	app.ui.matchmaking.begin_loading()
	app.ui.matchmaking.set_loading_progress(1.0)
	await process_frame
	_expect(app.game_world != null and app.ui.hud.visible, "loading deploys the eight-combatant match")
	_expect(not app.menu_audio.ambience_active and app.game_world.audio.ambience_active, "match handoff stops menu ambience and starts match ambience")
	var loaded_world: BreakwaterGameWorld = app.game_world
	app.ui.open_pause()
	app.ui.pause_menu.restart_requested.emit()
	await process_frame
	await process_frame
	_expect(app.game_world != null and app.game_world != loaded_world and not paused, "pause Restart creates a fresh unpaused match")
	app.ui.open_pause()
	app.ui.pause_menu.quit_to_menu_requested.emit()
	await process_frame
	await process_frame
	_expect(app.game_world == null and app.ui.title_home.visible and app.menu_audio.ambience_active, "pause Leave Practice destroys the match and restores Home")
	app._start_match(app.ui.get_loadout(), app.ui.get_appearance())
	await process_frame
	_expect(app.game_world != null and app.ui.hud.visible, "a new practice match can start after leaving through pause")

	var first_world: BreakwaterGameWorld = app.game_world
	for bot in first_world.bots:
		bot.set_ai_enabled(false)
	var player_results: Array[Dictionary] = []
	first_world.match_completed.connect(func(result: Dictionary) -> void: player_results.append(result))
	for index in 29:
		first_world.match_rules.record_elimination(&"player", StringName("opponent_%d" % index))
	await process_frame
	_expect(first_world.match_rules.match_active and player_results.is_empty() and app.ui.hud.visible, "player score 29 does not finish the match")
	var lingering_grenade := GrenadeProjectile.new()
	var lingering_definition := GrenadeDefinition.create_frag()
	lingering_definition.fuse_seconds = 20.0
	lingering_grenade.configure(lingering_definition, &"bot_1", first_world.bots[0])
	first_world.add_child(lingering_grenade)
	var final_victim := first_world.bots[0]
	if not final_victim.is_alive():
		final_victim.respawn_now(first_world._spawn_points[1])
	final_victim.respawn_delay = 0.01
	final_victim.health.spawn_protection_remaining = 0.0
	final_victim.global_position = Vector3(0.0, 12.0, 120.0)
	final_victim.health.current_health = 1.0
	var winning_grenade := GrenadeProjectile.new()
	var winning_definition := GrenadeDefinition.create_frag()
	winning_definition.effect_radius = 3.0
	winning_definition.maximum_damage = 200.0
	winning_definition.fuse_seconds = 20.0
	winning_grenade.configure(winning_definition, &"player", first_world.player)
	first_world.add_child(winning_grenade)
	winning_grenade.global_position = final_victim.get_eye_position()
	winning_grenade.detonate()
	_expect(first_world._finished and first_world.process_mode != Node.PROCESS_MODE_DISABLED, "grenade final kill defers the arena freeze until detonation unwinds")
	await process_frame
	_expect(app.ui.post_match.visible and app.ui.post_match._outcome_label.text == "VICTORY", "player reaching 30 presents victory results")
	_expect_equal(player_results.size(), 1, "player reaching 30 emits exactly one result")
	_expect_equal(int(player_results[0].get("winning_score", 0)), 30, "player result records the exact score limit")
	_expect(not first_world.audio.ambience_active and app.menu_audio.ambience_active, "results stop match ambience and restore menu ambience")
	_expect_equal(app.menu_audio.stinger_requests, 1, "victory presents one original result stinger")
	var frozen_elapsed := first_world._elapsed
	for _frame in 4:
		await process_frame
	_expect(first_world.process_mode == Node.PROCESS_MODE_DISABLED and is_equal_approx(first_world._elapsed, frozen_elapsed), "results freeze the complete gameplay simulation subtree")
	_expect(not final_victim.is_alive(), "final-kill victim cannot respawn behind the results screen")
	_expect(not is_instance_valid(lingering_grenade), "live grenades are retired when the match ends")
	first_world.match_rules.record_elimination(&"player", &"opponent_extra")
	_expect_equal(player_results.size(), 1, "post-win eliminations cannot emit duplicate results")
	_seed_stale_hud_state(app.ui.hud)
	app.ui.post_match.rematch_requested.emit()
	_expect_hud_match_reset(app.ui.hud, "rematch")
	await process_frame
	_expect(app.game_world != null and app.game_world != first_world and app.ui.hud.visible, "rematch creates a fresh match")
	_expect_equal(app.game_world.match_rules.get_score(&"player"), 0, "rematch resets scores")
	_expect(not app.menu_audio.ambience_active and app.game_world.audio.ambience_active, "rematch restores match-only ambience")
	var bot_results: Array[Dictionary] = []
	app.game_world.match_completed.connect(func(result: Dictionary) -> void: bot_results.append(result))
	for index in 29:
		app.game_world.match_rules.record_elimination(&"bot_1", StringName("opponent_%d" % index))
	await process_frame
	_expect(app.game_world.match_rules.match_active and bot_results.is_empty(), "bot score 29 does not finish the match")
	app.game_world.match_rules.record_elimination(&"bot_1", &"opponent_29")
	await process_frame
	_expect(app.ui.post_match.visible and app.ui.post_match._outcome_label.text == "DEFEAT", "bot reaching 30 presents defeat results")
	_expect_equal(bot_results.size(), 1, "bot reaching 30 emits exactly one result")
	_expect_equal(app.menu_audio.stinger_requests, 2, "defeat presents one additional original result stinger")
	app.ui.post_match.return_to_menu_requested.emit()
	await process_frame
	_expect(app.game_world == null and app.ui.title_home.visible, "return to menu destroys the match and restores home")
	_expect(app.menu_audio.ambience_active, "return to menu leaves menu ambience active")
	app.queue_free()
	await process_frame


func _seed_stale_hud_state(hud: BreakwaterGameHUD) -> void:
	hud.add_kill_feed("OLD COMBATANT", "OLD TARGET", "OLD WEAPON", true)
	hud.show_pickup_prompt("OLD PICKUP", "interact", 30.0)
	hud.show_respawn(2.5)
	hud.show_damage(0.8)
	hud.set_status_effects(0.9, 0.8)
	hud.set_crosshair_spread(38.0)
	hud._reticle.show_hit(true, true)
	# Ensure the reticle transform itself represents stale concussion feedback even
	# if the time-based sine happens to cross zero during this exact test frame.
	hud._reticle.rotation = 0.12


func _expect_hud_match_reset(hud: BreakwaterGameHUD, context: String) -> void:
	_expect_equal(hud._kill_feed.get_child_count(), 0, "%s clears the previous kill feed" % context)
	_expect(not hud._pickup_prompt.visible and hud._pickup_prompt.text.is_empty(), "%s clears the pickup prompt" % context)
	_expect(not hud._respawn_label.visible and hud._respawn_label.text.is_empty(), "%s clears the respawn countdown" % context)
	_expect_near(hud._damage_vignette.modulate.a, 0.0, 0.0001, "%s clears damage feedback" % context)
	_expect_near(hud._flash_overlay.modulate.a, 0.0, 0.0001, "%s clears flash feedback" % context)
	_expect_near(hud._concussion_overlay.modulate.a, 0.0, 0.0001, "%s clears concussion feedback" % context)
	_expect_near(hud._reticle.rotation, 0.0, 0.0001, "%s clears reticle concussion rotation" % context)
	_expect_near(hud._reticle._hit_time, 0.0, 0.0001, "%s clears hit-marker timing" % context)
	_expect(not hud._reticle._kill_confirm and not hud._reticle._headshot, "%s clears kill and headshot markers" % context)
	_expect_near(hud._reticle.spread_pixels, 9.0, 0.0001, "%s restores neutral crosshair spread" % context)
	_expect(not hud._reticle.is_processing(), "%s stops the hit-marker update loop" % context)


func _has_joy_axis(action: StringName, axis: JoyAxis, value: float) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis and is_equal_approx(event.axis_value, value):
			return true
	return false


func _bus_linear_volume(bus_name: StringName) -> float:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0 or AudioServer.is_bus_mute(bus_index):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(bus_index))


func _has_modified_key(action: StringName, key: Key, shift: bool) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
			if code == key and key_event.shift_pressed == shift:
				return true
	return false


func _has_joy_button(action: StringName, button: JoyButton) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button:
			return true
	return false


func _has_key(action: StringName, keycode: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (expected %.3f, got %.3f)" % [message, expected, actual])
