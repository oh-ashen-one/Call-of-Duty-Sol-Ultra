class_name BreakwaterGameWorld
extends Node3D

signal hud_snapshot_ready(snapshot: Dictionary)
signal kill_feed_ready(killer: String, victim: String, weapon: String, player_involved: bool)
signal hit_feedback_ready(kill: bool, headshot: bool)
signal damage_feedback_ready(intensity: float)
signal pickup_feedback_ready(item_name: String)
signal pickup_prompt_ready(item_name: String, action_hint: String)
signal pickup_prompt_cleared
signal respawn_feedback_ready(seconds: float)
signal match_completed(result: Dictionary)

const PLAYER_ID: StringName = &"player"
const TARGET_SCORE := 30
const MAP_RADAR_RADIUS := 48.0

var player: PlayerController
var bots: Array[BotController] = []
var match_rules: MatchRules
var audio: AudioDirector
var vfx: VFXDirector
var map_data: Dictionary = {}
var combatants: Dictionary = {}

var selected_loadout: Dictionary = BreakwaterContent.loadout(0)
var selected_appearance: Dictionary = {"skin": &"harbor_slate", "camo": &"saltline"}
var capture_mouse := true
var telemetry_enabled := true

var _spawn_points: Array[Vector3] = []
var _spawn_safe_radii: Array[float] = []
var _patrol_points: Array[Vector3] = []
var _pickup_points: Array[Vector3] = []
var _wired_grenades: Dictionary = {}
var _last_weapon_by_shooter: Dictionary = {}
var _hud_accumulator := 0.0
var _elapsed := 0.0
var _player_respawn_remaining := 0.0
var _shots_fired := 0
var _hits_landed := 0
var _headshots := 0
var _player_shot_has_hit := false
var bot_grenades_thrown := 0
var bot_pickups_collected := 0
var bot_vs_bot_kills := 0
var bot_vs_player_kills := 0
var _view_model: Node3D
var _view_model_recoil := 0.0
var _view_model_reload := 0.0
var _view_model_reload_duration := 1.0
var _view_model_pump := 0.0
var _view_model_pump_duration := 0.62
var _view_model_action := 0.0
var _finished := false
var _focused_pickup_id := 0
var _impact_audio_cooldown := 0.0


func configure(loadout: Dictionary, appearance: Dictionary, should_capture_mouse := true) -> void:
	selected_loadout = loadout.duplicate(true)
	selected_appearance = appearance.duplicate(true)
	capture_mouse = should_capture_mouse


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_match()


func _process(delta: float) -> void:
	_elapsed += delta
	_impact_audio_cooldown = maxf(_impact_audio_cooldown - delta, 0.0)
	_hud_accumulator += delta
	_wire_new_grenades()
	_update_pickup_focus()
	_update_view_model(delta)
	if _player_respawn_remaining > 0.0:
		_player_respawn_remaining = maxf(0.0, _player_respawn_remaining - delta)
		respawn_feedback_ready.emit(_player_respawn_remaining)
	if telemetry_enabled and _hud_accumulator >= 0.08:
		_hud_accumulator = 0.0
		hud_snapshot_ready.emit(make_hud_snapshot())


func make_hud_snapshot() -> Dictionary:
	if player == null or player.health == null:
		return {}
	var state := player.current_weapon_state()
	var weapon := player.current_weapon()
	var leader_id := match_rules.get_leader_id() if match_rules != null else &""
	var leader_name := String(match_rules.display_names.get(leader_id, "--")) if match_rules != null else "--"
	var heading := _player_heading()
	return {
		"health": player.health.current_health,
		"max_health": player.health.max_health,
		"ammo": state.magazine_ammo if state != null else 0,
		"reserve": state.reserve_ammo if state != null else 0,
		"magazine_size": weapon.magazine_size if weapon != null else 0,
		"weapon_name": weapon.display_name if weapon != null else "Unarmed",
		"fire_mode": "AUTO" if weapon != null and weapon.automatic else "SEMI",
		"frag_count": int(player.grenade_inventory.get(&"frag", 0)),
		"tactical_count": int(player.grenade_inventory.get(player.tactical_grenade_id, 0)),
		"tactical_name": String(player.tactical_grenade_id),
		"score": match_rules.get_score(PLAYER_ID) if match_rules != null else 0,
		"leader_name": leader_name,
		"leader_score": match_rules.get_score(leader_id) if match_rules != null else 0,
		"score_limit": TARGET_SCORE,
		"heading": heading,
		"blips": _radar_blips(),
		"crosshair_spread": _crosshair_spread(weapon),
		"flash": player.flash_strength,
		"concussion": player.concussion_strength,
		"standings": standings_for_ui(),
		"elapsed": _elapsed,
		"fps": Engine.get_frames_per_second(),
	}


func standings_for_ui() -> Array[Dictionary]:
	var standings: Array[Dictionary] = []
	if match_rules == null:
		return standings
	for row: Dictionary in match_rules.scoreboard():
		var id := StringName(row.get("id", &""))
		var actor := combatants.get(id) as CombatantController
		standings.append({
			"id": id,
			"name": String(row.get("name", id)),
			"kills": int(row.get("score", 0)),
			"deaths": int(row.get("deaths", 0)),
			"is_player": id == PLAYER_ID,
			"alive": actor != null and actor.is_alive(),
		})
	return standings


func shutdown() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	if player != null:
		player.set_input_enabled(false)
	for bot in bots:
		bot.set_ai_enabled(false)
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(&"grenades"):
			if is_ancestor_of(node):
				node.queue_free()
	if vfx != null:
		vfx.clear_transient_effects()
	# Results keep the final arena visible, but the entire simulation becomes a
	# frozen snapshot: no delayed respawns, regeneration, pickup timers, or
	# grenade detonations can continue behind the post-match screen.
	process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_match() -> void:
	map_data = WorldBuilder.build(self)
	_spawn_points = _to_vector_array(map_data.get("spawn_points", []))
	for marker_variant: Variant in map_data.get("spawn_markers", []):
		var marker := marker_variant as Marker3D
		_spawn_safe_radii.append(float(marker.get_meta(&"safe_radius", 8.0)) if marker != null else 8.0)
	_patrol_points = _to_vector_array(map_data.get("patrol_points", []))
	_pickup_points = _to_vector_array(map_data.get("pickup_points", []))

	match_rules = MatchRules.new()
	match_rules.name = "FreeForAllRules"
	match_rules.target_score = TARGET_SCORE
	add_child(match_rules)
	match_rules.kill_recorded.connect(_on_kill_recorded)
	match_rules.match_finished.connect(_on_match_finished)

	audio = AudioDirector.new()
	audio.name = "AudioDirector"
	add_child(audio)
	vfx = VFXDirector.new()
	vfx.name = "VFXDirector"
	vfx.effects_enabled = DisplayServer.get_name() != "headless"
	add_child(vfx)

	_spawn_pickups()
	_spawn_player()
	_spawn_bots()
	_build_view_model()
	var settings := get_node_or_null("/root/SettingsManager") as BreakwaterSettingsManager
	if settings != null:
		settings.apply_scene_quality()
	audio.set_match_intensity(true)
	call_deferred(&"_emit_initial_hud")


func _spawn_player() -> void:
	player = PlayerController.new()
	player.name = "Player"
	player.configure_identity(PLAYER_ID, "YOU")
	player.capture_mouse_on_ready = capture_mouse
	player.set_spawn_points(_spawn_points)
	player.set_spawn_safe_radii(_spawn_safe_radii)
	player.lethal_grenade_id = StringName(selected_loadout.get("lethal", &"frag"))
	player.tactical_grenade_id = StringName(selected_loadout.get("tactical", &"flash"))
	player.set_loadout(_resolve_loadout(selected_loadout))
	add_child(player)
	player.global_position = _spawn_points[0] if not _spawn_points.is_empty() else Vector3(0.0, 1.0, 0.0)
	player.health.grant_spawn_protection()
	combatants[PLAYER_ID] = player
	match_rules.register_combatant(player)
	_connect_combatant(player)
	player.weapon_hit_confirmed.connect(_on_player_weapon_hit_confirmed)
	player.hit_confirmed.connect(_on_player_hit_confirmed)
	player.health.damage_taken.connect(_on_player_damaged)
	player.eliminated.connect(_on_player_eliminated)
	player.respawned.connect(_on_player_respawned)
	player.movement_audio_requested.connect(audio.play_movement)
	_wire_player_reload_state()
	_apply_player_settings()
	var settings := get_node_or_null("/root/SettingsManager") as BreakwaterSettingsManager
	if settings != null:
		settings.bind_camera(player.camera)
		if not settings.setting_changed.is_connected(_on_setting_changed):
			settings.setting_changed.connect(_on_setting_changed)


func _spawn_bots() -> void:
	for index in 7:
		var bot := BotController.new()
		bot.name = "Bot_%02d" % (index + 1)
		bot.configure_identity(StringName("bot_%d" % (index + 1)), BreakwaterContent.bot_name(index))
		bot.skin_index = index % 3
		bot.skill = 0.52 + float(index % 4) * 0.08
		bot.preferred_engagement_range = 17.0 + float(index % 3) * 5.0
		bot.set_spawn_points(_spawn_points)
		bot.set_spawn_safe_radii(_spawn_safe_radii)
		bot.set_navigation_route(_patrol_points, _to_link_array(map_data.get("navigation_links", [])))
		add_child(bot)
		bot.global_position = _spawn_points[index + 1] if index + 1 < _spawn_points.size() else Vector3(index * 3.0, 1.0, 8.0)
		bot.health.grant_spawn_protection()
		bots.append(bot)
		combatants[bot.combatant_id] = bot
		match_rules.register_combatant(bot)
		_connect_combatant(bot)


func _spawn_pickups() -> void:
	var pickup_kinds: Array = map_data.get("pickup_kinds", [])
	for index in _pickup_points.size():
		var pickup := WeaponPickup.new()
		pickup.name = "FieldPickup_%02d" % index
		var kind := StringName(pickup_kinds[index]) if index < pickup_kinds.size() else &"assault_rifle"
		var weapon := _weapon_for_pickup_kind(kind)
		if weapon != null:
			pickup.configure(weapon, 12.0 + float(index % 3) * 2.0)
		else:
			pickup.configure_supply(kind, 10.0 + float(index % 3) * 2.0)
		# WeaponPickup caches its authored bob height in _ready(), so place it
		# before entering the tree. This preserves elevated catwalk pickups.
		pickup.position = _pickup_points[index]
		add_child(pickup)
		pickup.collected.connect(_on_pickup_collected)


func _weapon_for_pickup_kind(kind: StringName) -> WeaponDefinition:
	var weapon_ids := {
		&"assault_rifle": &"vx4_carbine",
		&"smg": &"kestrel_smg",
		&"pump_shotgun": &"breaker_12",
		&"dmr": &"helix_dmr",
		&"lmg": &"atlas_lmg",
		&"pistol": &"sparrow_pistol",
	}
	var weapon_id: StringName = weapon_ids.get(kind, &"")
	return WeaponCatalog.get_weapon(weapon_id) if not weapon_id.is_empty() else null


func _connect_combatant(actor: CombatantController) -> void:
	actor.weapon_fired.connect(_on_weapon_fired)
	actor.weapon_trace.connect(_on_weapon_trace)
	actor.weapon_changed.connect(_on_weapon_changed)
	actor.grenade_thrown.connect(_on_grenade_thrown)
	actor.melee_performed.connect(_on_melee_performed)
	actor.respawned.connect(_on_any_respawned)


func _resolve_loadout(loadout: Dictionary) -> Array[WeaponDefinition]:
	var primary_id := _resolve_weapon_alias(StringName(loadout.get("primary", &"vx4_carbine")))
	var secondary_id := _resolve_weapon_alias(StringName(loadout.get("secondary", &"sparrow_pistol")))
	var primary := WeaponCatalog.get_weapon(primary_id)
	var secondary := WeaponCatalog.get_weapon(secondary_id)
	if primary == null:
		primary = WeaponCatalog.get_weapon(&"vx4_carbine")
	if secondary == null or secondary == primary:
		secondary = WeaponCatalog.get_weapon(&"sparrow_pistol")
	return [primary, secondary]


func _resolve_weapon_alias(id: StringName) -> StringName:
	const ALIASES := {
		&"ar_cormorant": &"vx4_carbine",
		&"smg_riptide": &"kestrel_smg",
		&"shotgun_ballast": &"breaker_12",
		&"dmr_beacon": &"helix_dmr",
		&"lmg_tidewall": &"atlas_lmg",
		&"pistol_signal": &"sparrow_pistol",
	}
	return ALIASES.get(id, id)


func _on_weapon_fired(shooter_id: StringName, weapon_id: StringName, origin: Vector3, direction: Vector3) -> void:
	_last_weapon_by_shooter[shooter_id] = weapon_id
	if shooter_id == PLAYER_ID:
		_shots_fired += 1
		_player_shot_has_hit = false
		_view_model_recoil = 1.0
	if player == null or shooter_id == PLAYER_ID or player.global_position.distance_to(origin) < 42.0:
		audio.play_shot(weapon_id)
	if vfx.effects_enabled:
		vfx.spawn_weapon_flash(_muzzle_flash_origin(shooter_id, origin, direction), direction)


func _muzzle_flash_origin(shooter_id: StringName, fallback: Vector3, direction: Vector3) -> Vector3:
	var barrel: Node3D
	if shooter_id == PLAYER_ID and is_instance_valid(_view_model):
		barrel = _view_model.get_node_or_null("Barrel") as Node3D
	else:
		var bot := combatants.get(shooter_id) as BotController
		if bot != null and is_instance_valid(bot._weapon_visual):
			barrel = bot._weapon_visual.get_node_or_null("Barrel") as Node3D
	return barrel.global_position + direction.normalized() * 0.16 if barrel != null else fallback


func _on_weapon_trace(
	shooter_id: StringName,
	_weapon_id: StringName,
	origin: Vector3,
	destination: Vector3,
	impact_normal: Vector3,
	impacted: bool,
) -> void:
	if impacted:
		if vfx.effects_enabled:
			vfx.spawn_impact(destination, impact_normal, false)
		if _impact_audio_cooldown <= 0.0 \
			and (player == null or shooter_id == PLAYER_ID or player.global_position.distance_to(destination) < 28.0):
			audio.play_impact()
			_impact_audio_cooldown = 0.035
	if vfx.effects_enabled:
		vfx.spawn_tracer(origin, destination, Color("f2c14e") if shooter_id == PLAYER_ID else Color("ff8066"))


func _on_weapon_changed(actor_id: StringName, weapon: WeaponDefinition) -> void:
	if actor_id != PLAYER_ID or weapon == null:
		return
	_rebuild_view_model(weapon)
	_wire_player_reload_state()
	if _view_model != null:
		_view_model_action = -1.0
		audio.play_weapon_swap()


func _wire_player_reload_state() -> void:
	if player == null:
		return
	var state := player.current_weapon_state()
	if state != null and not state.reload_started.is_connected(_on_player_reload_started):
		state.reload_started.connect(_on_player_reload_started)
	if state != null and not state.pump_started.is_connected(_on_player_pump_started):
		state.pump_started.connect(_on_player_pump_started)


func _on_grenade_thrown(actor_id: StringName, grenade_id: StringName) -> void:
	_last_weapon_by_shooter[actor_id] = grenade_id
	if actor_id != PLAYER_ID:
		bot_grenades_thrown += 1
	var actor := combatants.get(actor_id) as CombatantController
	if player == null or actor_id == PLAYER_ID or (actor != null and player.global_position.distance_to(actor.global_position) < 28.0):
		audio.play_grenade_throw()
	if actor_id == PLAYER_ID:
		_view_model_action = -0.75


func _on_melee_performed(actor_id: StringName) -> void:
	_last_weapon_by_shooter[actor_id] = &"melee"
	var actor := combatants.get(actor_id) as CombatantController
	if player == null or actor_id == PLAYER_ID or (actor != null and player.global_position.distance_to(actor.global_position) < 18.0):
		audio.play_melee()
	if actor_id == PLAYER_ID:
		_view_model_action = 1.0


func _on_player_weapon_hit_confirmed(_target_id: StringName, _damage: float, _killed: bool, headshot: bool) -> void:
	if not _player_shot_has_hit:
		_hits_landed += 1
		_player_shot_has_hit = true
	if headshot:
		_headshots += 1


func _on_player_hit_confirmed(_target_id: StringName, _damage: float, killed: bool, headshot: bool) -> void:
	audio.play_hit(killed)
	hit_feedback_ready.emit(killed, headshot)


func _on_player_damaged(amount: float, _attacker_id: StringName, _headshot: bool) -> void:
	if player != null:
		player.add_camera_impulse(clampf(amount / 80.0, 0.2, 0.85), clampf(amount / 70.0, 0.25, 0.9), 0.14)
	damage_feedback_ready.emit(clampf(amount / 55.0, 0.2, 1.0))


func _on_player_eliminated(_victim_id: StringName, _killer_id: StringName) -> void:
	_player_respawn_remaining = player.respawn_delay
	respawn_feedback_ready.emit(_player_respawn_remaining)


func _on_player_respawned(_id: StringName) -> void:
	_player_respawn_remaining = 0.0
	respawn_feedback_ready.emit(0.0)


func _on_any_respawned(actor_id: StringName) -> void:
	var actor := combatants.get(actor_id) as CombatantController
	if actor != null:
		vfx.spawn_respawn_beacon(actor.global_position)


func _on_pickup_collected(collector_id: StringName, weapon_id: StringName) -> void:
	if collector_id != PLAYER_ID:
		bot_pickups_collected += 1
		return
	var definition := WeaponCatalog.get_weapon(weapon_id)
	var supply_names := {
		&"ammo": "AMMUNITION",
		&"frag": "FRAG GRENADE",
		&"flash": "LUMEN FLASH",
		&"concussion": "PULSE CONCUSSION",
	}
	_focused_pickup_id = 0
	pickup_prompt_cleared.emit()
	pickup_feedback_ready.emit(definition.display_name if definition != null else String(supply_names.get(weapon_id, String(weapon_id))))
	audio.play_ui(true)


func _on_kill_recorded(killer_id: StringName, victim_id: StringName, _score: int) -> void:
	if String(killer_id).begins_with("bot_"):
		if victim_id == PLAYER_ID:
			bot_vs_player_kills += 1
		elif killer_id != victim_id and String(victim_id).begins_with("bot_"):
			bot_vs_bot_kills += 1
	var killer_name := String(match_rules.display_names.get(killer_id, "ENVIRONMENT"))
	var victim_name := String(match_rules.display_names.get(victim_id, victim_id))
	var weapon_id := StringName(_last_weapon_by_shooter.get(killer_id, &"vx4_carbine"))
	var weapon := WeaponCatalog.get_weapon(weapon_id)
	var source_names := {
		&"frag": "FRAG GRENADE",
		&"flash": "LUMEN FLASH",
		&"concussion": "PULSE CONCUSSION",
		&"melee": "MELEE",
	}
	var weapon_name := weapon.display_name if weapon != null else String(source_names.get(weapon_id, "ENV"))
	kill_feed_ready.emit(killer_name, victim_name, weapon_name, killer_id == PLAYER_ID or victim_id == PLAYER_ID)


func _on_match_finished(winner_id: StringName, _final_scores: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	# MatchRules can finish from a weapon/grenade callback inside a physics
	# notification. Stop new decisions immediately, then defer the destructive
	# freeze until that callback stack has unwound.
	if player != null:
		player.set_input_enabled(false)
	for bot in bots:
		bot.set_ai_enabled(false)
	call_deferred(&"_finalize_match", winner_id)


func _finalize_match(winner_id: StringName) -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	shutdown()
	audio.set_ambience_active(false)
	var result := {
		"player_won": winner_id == PLAYER_ID,
		"winner_name": String(match_rules.display_names.get(winner_id, winner_id)),
		"winning_score": TARGET_SCORE,
		"kills": match_rules.get_score(PLAYER_ID),
		"deaths": match_rules.get_deaths(PLAYER_ID),
		"headshots": _headshots,
		"accuracy": clampf(float(_hits_landed) / float(maxi(_shots_fired, 1)), 0.0, 1.0),
		"standings": standings_for_ui(),
	}
	match_completed.emit(result)


func _wire_new_grenades() -> void:
	for node in get_tree().get_nodes_in_group(&"grenades"):
		var grenade := node as GrenadeProjectile
		if grenade == null or _wired_grenades.has(grenade.get_instance_id()):
			continue
		_wired_grenades[grenade.get_instance_id()] = true
		grenade.detonation_started.connect(_on_grenade_detonation_started)
		grenade.detonated.connect(_on_grenade_detonated)
		if grenade.owner_id == PLAYER_ID:
			grenade.combatant_affected.connect(_on_player_grenade_affected)


func _on_grenade_detonation_started(grenade_id: StringName, owner_id: StringName) -> void:
	_last_weapon_by_shooter[owner_id] = grenade_id


func _on_grenade_detonated(grenade_id: StringName, position: Vector3, _owner_id: StringName) -> void:
	var tactical := grenade_id != &"frag"
	var tactical_tint := Color("f0ffff") if grenade_id == &"flash" else Color("9176ef")
	vfx.spawn_explosion(position, tactical, tactical_tint)
	audio.play_explosion(0.65 if tactical else 1.0)
	if player != null:
		var distance_factor := 1.0 - clampf(player.global_position.distance_to(position) / 22.0, 0.0, 1.0)
		if distance_factor > 0.0:
			player.add_camera_impulse(distance_factor * (0.48 if tactical else 0.95), distance_factor, 0.22)


func _on_player_grenade_affected(target_id: StringName, _strength: float) -> void:
	if target_id == PLAYER_ID:
		return
	var target := combatants.get(target_id) as CombatantController
	var killed := target != null and not target.is_alive()
	audio.play_hit(killed)
	hit_feedback_ready.emit(killed, false)


func _update_pickup_focus() -> void:
	if player == null or not player.is_alive():
		if _focused_pickup_id != 0:
			_focused_pickup_id = 0
			pickup_prompt_cleared.emit()
		return
	var pickup := player.nearest_weapon_pickup()
	var pickup_id := pickup.get_instance_id() if pickup != null else 0
	if pickup_id == _focused_pickup_id:
		return
	_focused_pickup_id = pickup_id
	if pickup == null:
		pickup_prompt_cleared.emit()
	else:
		pickup_prompt_ready.emit(pickup.display_name(), "interact")


func _build_view_model() -> void:
	if player == null or player.camera == null:
		return
	_view_model = Node3D.new()
	_view_model.name = "ViewModel"
	_view_model.position = Vector3(0.38, -0.36, -0.78)
	_view_model.scale = Vector3.ONE * 0.7
	player.camera.add_child(_view_model)
	_rebuild_view_model(player.current_weapon())


func _rebuild_view_model(weapon: WeaponDefinition) -> void:
	if _view_model == null or weapon == null:
		return
	for child in _view_model.get_children():
		child.queue_free()
	var camo := _appearance_camo()
	var skin := _appearance_skin()
	var body_size := Vector3(0.22, 0.18, 0.72)
	match weapon.weapon_class:
		WeaponDefinition.WeaponClass.SMG: body_size = Vector3(0.2, 0.17, 0.56)
		WeaponDefinition.WeaponClass.SHOTGUN: body_size = Vector3(0.2, 0.2, 0.86)
		WeaponDefinition.WeaponClass.DMR: body_size = Vector3(0.18, 0.18, 0.92)
		WeaponDefinition.WeaponClass.LMG: body_size = Vector3(0.28, 0.25, 0.82)
		WeaponDefinition.WeaponClass.PISTOL: body_size = Vector3(0.14, 0.17, 0.34)
	_add_view_box("Receiver", body_size, Vector3.ZERO, camo.base, float(camo.metallic))
	_add_view_box("CamoIndex", Vector3(body_size.x + 0.015, body_size.y * 0.24, body_size.z * 0.44), Vector3(0.0, body_size.y * 0.3, -body_size.z * 0.1), camo.accent, 0.52)
	_add_view_box("Grip", Vector3(0.12, 0.28, 0.13), Vector3(0.0, -0.19, 0.12), Color("202a30"), 0.18, Vector3(deg_to_rad(-16.0), 0.0, 0.0))
	_add_view_box("Barrel", Vector3(0.075, 0.075, body_size.z * 0.56), Vector3(0.0, 0.01, -body_size.z * 0.72), Color("18232a"), 0.82)
	_add_view_box("Sight", Vector3(0.08, 0.09, 0.15), Vector3(0.0, body_size.y * 0.7, -0.1), camo.accent, 0.55)
	_add_view_box("RightGlove", Vector3(0.14, 0.17, 0.24), Vector3(0.12, -0.19, 0.13), skin.primary, 0.08)
	_add_view_box("LeftGlove", Vector3(0.14, 0.17, 0.24), Vector3(-0.11, -0.2, -body_size.z * 0.2), skin.secondary, 0.08)


func _add_view_box(node_name: String, size: Vector3, position: Vector3, color: Color, metallic: float, rotation := Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.34
	instance.material_override = material
	_view_model.add_child(instance)


func _update_view_model(delta: float) -> void:
	if _view_model == null or player == null:
		return
	_view_model_recoil = move_toward(_view_model_recoil, 0.0, delta * 8.5)
	var active_state := player.current_weapon_state()
	if active_state == null or active_state.reload_remaining <= 0.0:
		_view_model_reload = 0.0
	else:
		_view_model_reload = move_toward(
			_view_model_reload,
			0.0,
			delta / maxf(_view_model_reload_duration, 0.01),
		)
	_view_model_pump = move_toward(
		_view_model_pump,
		0.0,
		delta / maxf(_view_model_pump_duration, 0.01),
	)
	_view_model_action = move_toward(_view_model_action, 0.0, delta * 4.5)
	var speed_ratio := clampf(Vector2(player.velocity.x, player.velocity.z).length() / player.sprint_speed, 0.0, 1.0)
	var bob := Vector3(sin(_elapsed * 10.5) * 0.012, absf(cos(_elapsed * 10.5)) * 0.009, 0.0) * speed_ratio
	var target := Vector3(0.0, -0.3, -0.73) if player.is_aiming else Vector3(0.38, -0.36, -0.78)
	var pump_arc := sin(_view_model_pump * PI)
	target += bob + Vector3(
		0.0,
		-pump_arc * 0.035,
		_view_model_recoil * 0.09 + pump_arc * 0.12,
	)
	target += Vector3(_view_model_action * 0.08, -absf(_view_model_action) * 0.05, 0.0)
	_view_model.position = _view_model.position.lerp(target, 1.0 - exp(-delta * 15.0))
	_view_model.rotation = Vector3(
		_view_model_recoil * 0.09 + pump_arc * 0.08,
		-bob.x * 0.8,
		_view_model_reload * 0.7 + _view_model_action * 0.28,
	)


func _on_player_reload_started(duration: float) -> void:
	_view_model_reload = 1.0
	_view_model_reload_duration = maxf(duration, 0.01)
	audio.play_reload()


func _on_player_pump_started(duration: float) -> void:
	_view_model_pump = 1.0
	_view_model_pump_duration = maxf(duration, 0.01)
	audio.play_pump()


func _appearance_skin() -> Dictionary:
	var id := StringName(selected_appearance.get("skin", &"harbor_slate"))
	return BreakwaterContent.operator_skin_by_id(id)


func _appearance_camo() -> Dictionary:
	var id := StringName(selected_appearance.get("camo", &"saltline"))
	return BreakwaterContent.weapon_camo_by_id(id)


func _apply_player_settings() -> void:
	var settings := get_node_or_null("/root/SettingsManager") as BreakwaterSettingsManager
	if settings == null or player == null:
		return
	player.mouse_sensitivity = float(settings.get_value("controls", "mouse_sensitivity", 0.18))
	player.ads_sensitivity_scale = float(settings.get_value("controls", "ads_sensitivity", 0.72))
	player.controller_sensitivity = float(settings.get_value("controls", "controller_sensitivity", 2.6))
	player.controller_deadzone = float(settings.get_value("controls", "controller_deadzone", 0.16))
	player.invert_y = bool(settings.get_value("controls", "invert_y", false))
	player.set_feedback_settings(
		float(settings.get_value("gameplay", "camera_shake", 0.75)),
		bool(settings.get_value("controls", "vibration", true)),
	)
	player.hip_fov = float(settings.get_value("video", "fov", 90.0))
	player.ads_fov = maxf(52.0, player.hip_fov - 20.0)


func _on_setting_changed(section: StringName, _key: StringName, _value: Variant) -> void:
	if section == &"controls" or section == &"video" or section == &"gameplay":
		_apply_player_settings()


func _player_heading() -> float:
	if player == null:
		return 0.0
	var forward := player.get_view_direction()
	return fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)


func _radar_blips() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if player == null:
		return result
	for id: Variant in combatants.keys():
		if StringName(id) == PLAYER_ID:
			continue
		var actor := combatants[id] as CombatantController
		if actor == null or not actor.is_alive():
			continue
		var delta := actor.global_position - player.global_position
		result.append({
			"position": Vector2(delta.x, delta.z) / MAP_RADAR_RADIUS,
			"relation": "enemy",
			"size": 4.0,
		})
	return result


func _crosshair_spread(weapon: WeaponDefinition) -> float:
	if player == null or weapon == null:
		return 7.0
	return 5.0 + player.current_ballistic_spread_degrees(weapon) * 4.5


func _to_vector_array(source: Variant) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if source is Array:
		for value in source:
			if value is Vector3:
				result.append(value)
	return result


func _to_link_array(source: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if source is Array:
		for value in source:
			if value is Vector2i:
				result.append(value)
	return result


func _emit_initial_hud() -> void:
	hud_snapshot_ready.emit(make_hud_snapshot())
