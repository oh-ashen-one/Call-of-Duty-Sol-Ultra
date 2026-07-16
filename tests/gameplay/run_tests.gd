extends SceneTree

## Run with:
##   godot --headless --path . --script tests/gameplay/run_tests.gd

class FakeCollector:
	extends Node
	var combatant_id: StringName = &"collector"
	var received_weapon: WeaponDefinition

	func pickup_weapon(definition: WeaponDefinition) -> bool:
		received_weapon = definition
		return true


var _assertions: int = 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings := root.get_node_or_null("SettingsManager") as BreakwaterSettingsManager
	if settings != null:
		settings.reset_bindings(false)
	_test_weapon_catalog_and_runtime()
	_test_health_and_respawn()
	_test_match_rules()
	_test_grenade_falloff()
	await _test_live_grenade_effects()
	await _test_authoritative_weapon_traces()
	_test_pickup_contract()
	await _test_player_supplies_and_accuracy()
	await _test_player_interaction_priority()
	_test_input_contract()
	await _test_player_input_dispatch()
	await _test_movement_stances()
	await _test_melee_and_safe_respawn()
	await _test_bot_equipment_and_pickups()
	await _test_unattended_bot_combat()
	if _failures.is_empty():
		print("GAMEPLAY TESTS PASS — %d assertions" % _assertions)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("GAMEPLAY TESTS FAIL — %d failure(s), %d assertions" % [_failures.size(), _assertions])
		quit(1)


func _test_weapon_catalog_and_runtime() -> void:
	var arsenal := WeaponCatalog.create_all()
	_expect_equal(arsenal.size(), 6, "catalog contains all six weapons")
	var unique_ids: Dictionary = {}
	var unique_classes: Dictionary = {}
	for weapon in arsenal:
		_expect(weapon.is_valid_definition(), "%s is valid" % weapon.display_name)
		unique_ids[weapon.weapon_id] = true
		unique_classes[weapon.weapon_class] = true
	_expect_equal(unique_ids.size(), 6, "weapon ids are unique")
	_expect_equal(unique_classes.size(), 6, "arsenal covers six distinct weapon classes")
	_expect_equal(BreakwaterContent.OPERATOR_SKINS.size(), 3, "three operator skins are authored")
	_expect_equal(BreakwaterContent.WEAPON_CAMOS.size(), 3, "three weapon camos are authored")
	var rifle := WeaponCatalog.get_weapon(&"vx4_carbine")
	_expect(rifle != null, "rifle lookup succeeds")
	_expect(rifle.damage_at_distance(100.0) < rifle.damage_at_distance(2.0), "damage falls off")
	_expect(rifle.damage_at_distance(2.0, true) > rifle.damage_at_distance(2.0), "headshots multiply damage")
	var state := WeaponState.new(rifle)
	_expect(state.consume_shot(), "loaded weapon fires")
	_expect_equal(state.magazine_ammo, rifle.magazine_size - 1, "shot consumes one round")
	state.cooldown_remaining = 0.0
	state.magazine_ammo = 0
	_expect(state.begin_reload(), "empty weapon begins reload")
	state.tick(rifle.reload_seconds)
	_expect_equal(state.magazine_ammo, rifle.magazine_size, "reload fills magazine")
	_expect_equal(state.reserve_ammo, rifle.starting_reserve - rifle.magazine_size, "reload consumes reserve")
	state.magazine_ammo = rifle.magazine_size - 2
	state.cooldown_remaining = 0.0
	_expect(state.begin_reload(), "partially loaded rifle begins a reload")
	_expect(state.consume_shot(), "fire input interrupts a magazine reload when a round remains")
	_expect_near(state.reload_remaining, 0.0, 0.001, "interrupted magazine reload clears its action timer")

	var shotgun := WeaponCatalog.get_weapon(&"breaker_12")
	_expect(shotgun != null, "pump shotgun lookup succeeds")
	_expect(shotgun.pump_action, "shotgun definition requires a pump cycle")
	_expect(shotgun.pump_seconds > 0.0, "shotgun pump cycle has a positive duration")
	_expect(shotgun.reload_one_shell_at_a_time, "shotgun definition reloads one shell at a time")
	_expect(
		shotgun.shell_insert_seconds > 0.0 and shotgun.shell_insert_seconds < shotgun.reload_seconds,
		"individual shell timing is distinct from a full-magazine reload"
	)
	var pump_probe := shotgun.duplicate() as WeaponDefinition
	pump_probe.rounds_per_minute = 1200.0
	var pump_state := WeaponState.new(pump_probe)
	var pump_durations: Array[float] = []
	pump_state.pump_started.connect(func(duration: float) -> void: pump_durations.append(duration))
	_expect(pump_state.consume_shot(), "loaded pump shotgun fires")
	_expect_equal(pump_durations.size(), 1, "shotgun shot emits one pump event")
	_expect_near(pump_durations[0], pump_probe.pump_seconds, 0.001, "pump event carries authored cycle duration")
	_expect(
		pump_state.cooldown_remaining >= pump_probe.pump_seconds,
		"pump duration gates firing even when the nominal fire-rate cooldown is shorter"
	)
	_expect(not pump_state.consume_shot(), "pump shotgun cannot fire again during its action cycle")

	var shell_state := WeaponState.new(shotgun)
	shell_state.magazine_ammo = 0
	shell_state.reserve_ammo = 3
	var shell_cycles: Array[float] = []
	shell_state.reload_started.connect(func(duration: float) -> void: shell_cycles.append(duration))
	_expect(shell_state.begin_reload(), "empty shotgun begins a shell reload")
	_expect_near(shell_state.reload_remaining, shotgun.shell_insert_seconds, 0.001, "shotgun uses per-shell reload timing")
	shell_state.tick(shotgun.shell_insert_seconds)
	_expect_equal(shell_state.magazine_ammo, 1, "one reload cycle inserts exactly one shell")
	_expect_equal(shell_state.reserve_ammo, 2, "one reload cycle consumes exactly one reserve shell")
	_expect_equal(shell_cycles.size(), 2, "shotgun queues the next shell while capacity and reserve remain")
	_expect(shell_state.reload_remaining > 0.0, "shell-by-shell reload continues after the first insert")
	_expect(shell_state.consume_shot(), "loaded shell can interrupt an in-progress shotgun reload")
	_expect_equal(shell_state.magazine_ammo, 0, "interrupted shell reload fires the chambered round")
	_expect_near(shell_state.reload_remaining, 0.0, 0.001, "firing cancels the remaining shell reload")


func _test_health_and_respawn() -> void:
	var health := HealthComponent.new()
	health.max_health = 100.0
	health.current_health = 100.0
	var kill_capture: Array[StringName] = [&""]
	health.killed.connect(func(killer: StringName) -> void: kill_capture[0] = killer)
	var applied := health.apply_damage(35.0, &"bot_a", true)
	_expect_near(applied, 35.0, 0.001, "damage applies")
	_expect_near(health.current_health, 65.0, 0.001, "health decreases")
	health.advance(health.regeneration_delay - 0.1)
	_expect_near(health.current_health, 65.0, 0.001, "regeneration waits for delay")
	health.advance(0.5)
	_expect(health.current_health > 65.0, "health regenerates after delay")
	health.force_kill(&"bot_b")
	_expect(not health.is_alive, "lethal damage kills")
	_expect_equal(kill_capture[0], &"bot_b", "killer is retained")
	health.respawn(1.0)
	_expect(health.is_alive and is_equal_approx(health.current_health, 100.0), "respawn restores health")
	_expect_near(health.apply_damage(50.0, &"bot_a"), 0.0, 0.001, "spawn protection blocks damage")
	health.advance(1.0)
	_expect_near(health.apply_damage(50.0, &"bot_a"), 50.0, 0.001, "damage resumes after protection")
	health.free()


func _test_match_rules() -> void:
	var rules := MatchRules.new()
	rules.target_score = 3
	_expect(rules.record_elimination(&"alpha", &"bravo"), "valid elimination scores")
	_expect(rules.record_elimination(&"alpha", &"charlie"), "second elimination scores")
	_expect(rules.record_elimination(&"alpha", &"bravo"), "winning elimination scores")
	_expect_equal(rules.get_score(&"alpha"), 3, "score reaches exact target")
	_expect_equal(rules.winner_id, &"alpha", "first-to-target winner recorded")
	_expect(not rules.match_active, "match stops at target")
	_expect(not rules.record_elimination(&"alpha", &"bravo"), "post-match kills are ignored")
	_expect_equal(rules.get_score(&"alpha"), 3, "winning score cannot exceed target")
	rules.reset_match()
	_expect_equal(rules.get_score(&"alpha"), 0, "reset clears score")
	_expect(rules.match_active, "reset reactivates match")
	rules.free()


func _test_grenade_falloff() -> void:
	_expect_near(GrenadeProjectile.radial_factor(0.0, 10.0), 1.0, 0.001, "grenade center has full effect")
	var midpoint := GrenadeProjectile.radial_factor(5.0, 10.0)
	_expect(midpoint > 0.0 and midpoint < 1.0, "grenade effect falls off")
	_expect_near(GrenadeProjectile.radial_factor(10.0, 10.0), 0.0, 0.001, "grenade edge has no effect")
	var grenades := GrenadeDefinition.create_all()
	_expect_equal(grenades.size(), 3, "frag, flash and concussion definitions exist")


func _test_live_grenade_effects() -> void:
	var arena := Node3D.new()
	root.add_child(arena)

	var frag_target := _make_test_combatant(&"frag_target", Vector3.ZERO)
	arena.add_child(frag_target)
	await process_frame
	var frag := GrenadeProjectile.new()
	frag.configure(GrenadeDefinition.create_frag(), &"thrower")
	arena.add_child(frag)
	frag.global_position = frag_target.get_eye_position() + Vector3(0.0, 0.0, -0.25)
	frag.detonate()
	_expect(not frag_target.is_alive(), "live frag grenade applies lethal radial damage")
	_expect_equal(frag_target.health.last_attacker_id, &"thrower", "frag damage retains kill attribution")
	frag_target.queue_free()
	await process_frame

	var flash_target := _make_test_combatant(&"flash_target", Vector3.ZERO)
	arena.add_child(flash_target)
	await process_frame
	var flash := GrenadeProjectile.new()
	flash.configure(GrenadeDefinition.create_flash(), &"thrower")
	arena.add_child(flash)
	flash.global_position = flash_target.get_eye_position() + Vector3(0.0, 0.0, -0.75)
	flash.detonate()
	_expect(flash_target.flash_strength > 0.5, "live flash grenade applies a visible status effect")
	_expect(flash_target.status_aim_scale() < 0.6, "flash reduces combatant aim response")
	flash_target._process(8.0)
	_expect_near(flash_target.flash_strength, 0.0, 0.001, "flash effect expires")
	flash_target.queue_free()
	await process_frame

	var protected_target := _make_test_combatant(&"protected_target", Vector3.ZERO)
	arena.add_child(protected_target)
	await process_frame
	protected_target.health.grant_spawn_protection(2.0)
	var protected_feedback: Array[StringName] = []
	var protected_flash := GrenadeProjectile.new()
	protected_flash.configure(GrenadeDefinition.create_flash(), &"thrower")
	protected_flash.combatant_affected.connect(func(target_id: StringName, _strength: float) -> void: protected_feedback.append(target_id))
	arena.add_child(protected_flash)
	protected_flash.global_position = protected_target.get_eye_position() + Vector3(0.0, 0.0, -0.5)
	protected_flash.detonate()
	_expect_near(protected_target.flash_strength, 0.0, 0.001, "spawn protection blocks hostile tactical status effects")
	_expect(protected_feedback.is_empty(), "protected grenade target cannot generate a false hit marker event")
	protected_target.queue_free()
	await process_frame

	var concussion_target := _make_test_combatant(&"concussion_target", Vector3.ZERO)
	arena.add_child(concussion_target)
	await process_frame
	var concussion := GrenadeProjectile.new()
	concussion.configure(GrenadeDefinition.create_concussion(), &"thrower")
	arena.add_child(concussion)
	concussion.global_position = concussion_target.get_eye_position() + Vector3(0.0, 0.0, -0.75)
	concussion.detonate()
	_expect(concussion_target.concussion_strength > 0.5, "live concussion applies status pressure")
	_expect(concussion_target.health.current_health < concussion_target.health.max_health, "concussion also applies blast damage")
	_expect(concussion_target.status_movement_scale() < 0.75, "concussion slows movement")
	concussion_target._process(8.0)
	_expect_near(concussion_target.concussion_strength, 0.0, 0.001, "concussion effect expires")
	concussion_target.queue_free()
	await process_frame

	var player := PlayerController.new()
	player.capture_mouse_on_ready = false
	player.tactical_grenade_id = &"concussion"
	player.configure_identity(&"equipment_probe", "Equipment Probe")
	arena.add_child(player)
	await process_frame
	var frag_count := int(player.grenade_inventory.get(&"frag", 0))
	_expect(player.grenade_inventory.has(&"concussion") and not player.grenade_inventory.has(&"flash"), "selected tactical loadout exclusively controls carried equipment")
	player._try_throw_grenade(&"frag")
	_expect_equal(int(player.grenade_inventory.get(&"frag", 0)), frag_count - 1, "throwing decrements grenade inventory")
	player.health.respawn(0.0)
	_expect_equal(int(player.grenade_inventory.get(&"frag", 0)), 1, "respawn restores grenade inventory")
	arena.queue_free()
	await process_frame


func _test_pickup_contract() -> void:
	var pickup := WeaponPickup.new()
	pickup.configure(WeaponCatalog.get_weapon(&"kestrel_smg"), 12.0)
	var collector := FakeCollector.new()
	_expect(pickup.try_collect(collector), "pickup delegates to combatant")
	_expect(collector.received_weapon != null, "collector receives weapon definition")
	_expect_equal(collector.received_weapon.weapon_id, &"kestrel_smg", "pickup provides configured weapon")
	_expect(not pickup.try_collect(collector), "unavailable pickup cannot be collected twice")
	pickup.free()
	collector.free()


func _test_player_supplies_and_accuracy() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var player := PlayerController.new()
	player.capture_mouse_on_ready = false
	player.configure_identity(&"supply_player", "Supply Player")
	arena.add_child(player)
	await process_frame

	var state := player.current_weapon_state()
	state.reserve_ammo = state.definition.starting_reserve - state.definition.magazine_size
	var reserve_before := state.reserve_ammo
	_expect(player.receive_supply(&"ammo"), "player accepts an ammunition supply")
	_expect_equal(
		state.reserve_ammo,
		reserve_before + state.definition.magazine_size,
		"ammunition supply adds one magazine to the active weapon reserve",
	)
	_expect(not player.receive_supply(&"ammo"), "player rejects ammunition when every reserve is at capacity")
	_expect_equal(state.reserve_ammo, state.definition.starting_reserve, "ammunition reserve cannot exceed its authored capacity")
	player.grenade_inventory[&"frag"] = 1
	_expect(player.receive_supply(&"frag"), "player accepts a grenade supply below the carry cap")
	_expect_equal(int(player.grenade_inventory[&"frag"]), 2, "grenade supply increments inventory")
	_expect(not player.receive_supply(&"frag"), "player rejects a grenade supply at the carry cap")
	_expect_equal(int(player.grenade_inventory[&"frag"]), 2, "rejected grenade supply cannot exceed the carry cap")
	_expect(not player.receive_supply(&"unknown"), "player rejects unknown supply types")

	player.grenade_inventory[&"flash"] = 1
	var supply_pickup := WeaponPickup.new()
	supply_pickup.configure_supply(&"flash", 12.0)
	arena.add_child(supply_pickup)
	var collected_ids: Array[StringName] = []
	var respawned_ids: Array[StringName] = []
	supply_pickup.collected.connect(func(_collector_id: StringName, item_id: StringName) -> void: collected_ids.append(item_id))
	supply_pickup.became_available.connect(func(item_id: StringName) -> void: respawned_ids.append(item_id))
	supply_pickup._on_body_entered(player)
	_expect_equal(int(player.grenade_inventory[&"flash"]), 2, "collected tactical supply updates player inventory")
	_expect_equal(collected_ids.size(), 1, "player contact emits one supply collection event")
	if not collected_ids.is_empty():
		_expect_equal(collected_ids[0], &"flash", "supply pickup reports its authored item identifier")
	_expect(not supply_pickup.is_available, "collected supply becomes unavailable until respawn")
	supply_pickup._process(12.0)
	_expect(supply_pickup.is_available, "supply pickup respawns after its authored delay")
	_expect_equal(respawned_ids.size(), 1, "supply respawn emits one availability event")
	if not respawned_ids.is_empty():
		_expect_equal(respawned_ids[0], &"flash", "supply respawn reports its authored item identifier")
	var capped_pickup := WeaponPickup.new()
	capped_pickup.configure_supply(&"flash", 12.0)
	arena.add_child(capped_pickup)
	capped_pickup._on_body_entered(player)
	_expect(capped_pickup.is_available, "supply rejected at the carry cap remains available")
	_expect(not player.grenade_inventory.has(&"concussion"), "default flash loadout does not secretly carry concussion equipment")

	var world := BreakwaterGameWorld.new()
	world.audio = AudioDirector.new()
	world.audio._disabled = true
	world.vfx = VFXDirector.new()
	world.vfx.effects_enabled = false
	world._on_player_hit_confirmed(&"melee_target", 65.0, false, false)
	_expect_equal(world._hits_landed, 0, "melee hit feedback cannot inflate firearm accuracy")
	world._on_weapon_fired(BreakwaterGameWorld.PLAYER_ID, &"breaker_12", Vector3.ZERO, Vector3.FORWARD)
	world._on_player_weapon_hit_confirmed(&"pellet_target_a", 12.0, false, false)
	world._on_player_weapon_hit_confirmed(&"pellet_target_b", 12.0, false, false)
	_expect_equal(world._shots_fired, 1, "one shotgun trigger pull records one shot")
	_expect_equal(world._hits_landed, 1, "multiple shotgun pellet hits record one landed shot")
	world._on_weapon_fired(&"bot_1", &"atlas_lmg", Vector3.ZERO, Vector3.FORWARD)
	_expect_equal(world._shots_fired, 1, "bot gunfire cannot alter player shot statistics")
	world._on_weapon_fired(BreakwaterGameWorld.PLAYER_ID, &"breaker_12", Vector3.ZERO, Vector3.FORWARD)
	_expect_near(float(world._hits_landed) / float(world._shots_fired), 0.5, 0.001, "accuracy is calculated per trigger pull")
	world.audio.free()
	world.vfx.free()
	world.free()
	arena.queue_free()
	await process_frame


func _test_authoritative_weapon_traces() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var shooter := _make_test_combatant(&"trace_shooter", Vector3.ZERO)
	var target := _make_test_combatant(&"trace_target", Vector3(0.0, 0.0, -4.0))
	var precise := WeaponCatalog.get_weapon(&"vx4_carbine").duplicate() as WeaponDefinition
	precise.hip_spread_degrees = 0.0
	precise.ads_spread_degrees = 0.0
	shooter.set_loadout([precise])
	arena.add_child(shooter)
	arena.add_child(target)
	await physics_frame
	await physics_frame
	var traces: Array[Dictionary] = []
	shooter.weapon_trace.connect(func(
		_shooter_id: StringName,
		_weapon_id: StringName,
		origin: Vector3,
		destination: Vector3,
		normal: Vector3,
		impacted: bool,
	) -> void:
		traces.append({"origin": origin, "destination": destination, "normal": normal, "impacted": impacted})
	)
	_expect(shooter.fire_hitscan(shooter.get_eye_position(), Vector3.FORWARD), "precise test weapon fires")
	_expect_equal(traces.size(), 1, "single-pellet weapon emits one authoritative trace")
	if not traces.is_empty():
		_expect(bool(traces[0].impacted), "authoritative trace reports its real collision")
		_expect(float((traces[0].destination as Vector3).z) < -3.0, "authoritative trace ends on the target rather than the unspread center proxy")

	var shotgun := WeaponCatalog.get_weapon(&"breaker_12").duplicate() as WeaponDefinition
	shotgun.hip_spread_degrees = 0.0
	shotgun.ads_spread_degrees = 0.0
	shooter.set_loadout([shotgun])
	traces.clear()
	_expect(shooter.fire_hitscan(shooter.get_eye_position(), Vector3.UP), "shotgun test trigger fires")
	_expect_equal(traces.size(), shotgun.pellets_per_shot, "shotgun emits one authoritative tracer endpoint per pellet")
	var all_missed := true
	for trace in traces:
		all_missed = all_missed and not bool(trace.impacted)
	_expect(all_missed, "unobstructed misses are represented as misses in trace data")
	arena.queue_free()
	await process_frame


func _test_player_interaction_priority() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var player := PlayerController.new()
	player.capture_mouse_on_ready = false
	player.configure_identity(&"interaction_player", "Interaction Player")
	arena.add_child(player)
	var front_pickup := WeaponPickup.new()
	front_pickup.configure(WeaponCatalog.get_weapon(&"atlas_lmg"), 12.0)
	front_pickup.position = Vector3(0.0, 0.0, -1.2)
	arena.add_child(front_pickup)
	await physics_frame
	await physics_frame
	var old_state := player.current_weapon_state()
	old_state.magazine_ammo = 1
	_expect(player.nearest_weapon_pickup() == front_pickup, "pickup focus requires a nearby weapon in the view cone")
	player._handle_contextual_reload_interact(true, true)
	_expect(not front_pickup.is_available and player.current_weapon().weapon_id == &"atlas_lmg", "shared controller button contextually collects a focused weapon")
	_expect_near(old_state.reload_remaining, 0.0, 0.001, "successful interaction suppresses the simultaneous reload action")

	var behind_pickup := WeaponPickup.new()
	behind_pickup.configure(WeaponCatalog.get_weapon(&"helix_dmr"), 12.0)
	behind_pickup.position = Vector3(0.0, 0.0, 1.0)
	arena.add_child(behind_pickup)
	await physics_frame
	_expect(player.nearest_weapon_pickup() == null, "weapons behind the first-person view do not produce interaction prompts")

	var blocked_pickup := WeaponPickup.new()
	blocked_pickup.configure(WeaponCatalog.get_weapon(&"kestrel_smg"), 12.0)
	blocked_pickup.position = Vector3(0.0, 0.0, -2.4)
	arena.add_child(blocked_pickup)
	var wall := StaticBody3D.new()
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(2.0, 2.4, 0.25)
	wall_collision.shape = wall_shape
	wall_collision.position = Vector3(0.0, 1.2, -1.6)
	wall.add_child(wall_collision)
	arena.add_child(wall)
	await physics_frame
	_expect(player.nearest_weapon_pickup() == null, "solid cover blocks weapon prompts and through-wall collection")
	arena.queue_free()
	await process_frame


func _test_input_contract() -> void:
	PlayerController.ensure_default_input_actions()
	var required := PlayerController.required_input_actions()
	for action in required:
		_expect(InputMap.has_action(action), "input action %s exists" % action)
		_expect(_has_controller_binding(action), "input action %s has a controller binding" % action)
	_expect(not required.has("move_backward"), "legacy move_backward action is absent from player contract")
	_expect(not required.has("ads"), "legacy ads action is absent from player contract")

	var movement_probe := PlayerController.new()
	movement_probe.capture_mouse_on_ready = false
	movement_probe.controller_deadzone = 0.25
	Input.action_press(&"move_right", 0.12)
	movement_probe._update_stance_and_movement(0.1)
	_expect_near(movement_probe.velocity.x, 0.0, 0.001, "movement below the configured stick dead zone is ignored")
	Input.action_release(&"move_right")
	movement_probe.velocity = Vector3.ZERO
	Input.action_press(&"move_right", 0.8)
	movement_probe._update_stance_and_movement(0.1)
	_expect(movement_probe.velocity.x > 0.1, "movement above the configured stick dead zone is accepted")
	Input.action_release(&"move_right")
	var pitch_before := movement_probe._look_pitch
	movement_probe._apply_weapon_recoil(WeaponCatalog.get_weapon(&"vx4_carbine"), 1.0)
	_expect(movement_probe._look_pitch > pitch_before, "weapon recoil raises the first-person camera")
	movement_probe.free()


func _test_player_input_dispatch() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var player := PlayerController.new()
	player.capture_mouse_on_ready = false
	player.configure_identity(&"input_player", "Input Player")
	player.set_loadout([
		WeaponCatalog.get_weapon(&"vx4_carbine"),
		WeaponCatalog.get_weapon(&"sparrow_pistol"),
	])
	arena.add_child(player)
	await process_frame
	player.set_physics_process(false)

	var forward_press := _key_event(KEY_W, true)
	Input.parse_input_event(forward_press)
	await process_frame
	player._update_stance_and_movement(0.1)
	_expect(player.velocity.z < -0.1, "physical W input drives the live movement path")
	Input.parse_input_event(_key_event(KEY_W, false))
	await process_frame

	Input.parse_input_event(_mouse_button_event(MOUSE_BUTTON_RIGHT, true))
	await process_frame
	player._update_stance_and_movement(0.016)
	_expect(player.is_aiming, "right mouse button reaches live ADS state")
	Input.parse_input_event(_mouse_button_event(MOUSE_BUTTON_RIGHT, false))
	await process_frame

	var shots: Array[StringName] = []
	player.weapon_fired.connect(func(_actor_id: StringName, weapon_id: StringName, _origin: Vector3, _direction: Vector3) -> void: shots.append(weapon_id))
	var rifle_state := player.current_weapon_state()
	var magazine_before := rifle_state.magazine_ammo
	Input.parse_input_event(_mouse_button_event(MOUSE_BUTTON_LEFT, true))
	await process_frame
	player._update_combat_input(0.016)
	Input.parse_input_event(_mouse_button_event(MOUSE_BUTTON_LEFT, false))
	await process_frame
	_expect_equal(rifle_state.magazine_ammo, magazine_before - 1, "left mouse button fires through the live combat input path")
	_expect_equal(shots, [&"vx4_carbine"], "dispatched fire input reports the equipped weapon")

	rifle_state.cooldown_remaining = 0.0
	rifle_state.magazine_ammo = maxi(rifle_state.magazine_ammo - 4, 1)
	Input.parse_input_event(_key_event(KEY_R, true))
	await process_frame
	player._update_combat_input(0.016)
	Input.parse_input_event(_key_event(KEY_R, false))
	await process_frame
	_expect(rifle_state.reload_remaining > 0.0, "physical R input starts a live weapon reload")

	Input.parse_input_event(_key_event(KEY_1, true))
	await process_frame
	player._update_combat_input(0.016)
	Input.parse_input_event(_key_event(KEY_1, false))
	await process_frame
	_expect_equal(player.current_weapon().weapon_id, &"sparrow_pistol", "physical swap input changes the live weapon slot")

	var melee_events: Array[StringName] = []
	player.melee_performed.connect(func(actor_id: StringName) -> void: melee_events.append(actor_id))
	Input.parse_input_event(_key_event(KEY_V, true))
	await process_frame
	player._update_combat_input(0.016)
	Input.parse_input_event(_key_event(KEY_V, false))
	await process_frame
	_expect_equal(melee_events, [&"input_player"], "physical V input executes the live melee path")

	var thrown: Array[StringName] = []
	player.grenade_thrown.connect(func(_actor_id: StringName, grenade_id: StringName) -> void: thrown.append(grenade_id))
	Input.parse_input_event(_key_event(KEY_G, true))
	await process_frame
	player._update_combat_input(0.016)
	Input.parse_input_event(_key_event(KEY_G, false))
	await process_frame
	Input.parse_input_event(_key_event(KEY_Q, true))
	await process_frame
	player._update_combat_input(0.016)
	Input.parse_input_event(_key_event(KEY_Q, false))
	await process_frame
	_expect_equal(thrown, [&"frag", &"flash"], "physical grenade inputs execute both lethal and tactical throw paths")
	_expect_equal(int(player.grenade_inventory.get(&"frag", 0)), 0, "live frag input consumes lethal equipment")
	_expect_equal(int(player.grenade_inventory.get(&"flash", 0)), 0, "live tactical input consumes tactical equipment")

	arena.queue_free()
	await process_frame


func _test_melee_and_safe_respawn() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var attacker := _make_test_combatant(&"melee_attacker", Vector3.ZERO)
	var victim := _make_test_combatant(&"melee_victim", Vector3(0.0, 0.0, -0.95))
	arena.add_child(attacker)
	arena.add_child(victim)
	var melee_attempts: Array[StringName] = []
	attacker.melee_performed.connect(func(actor_id: StringName) -> void: melee_attempts.append(actor_id))
	await physics_frame
	await physics_frame
	_expect(not attacker.perform_melee(attacker.get_eye_position(), Vector3.BACK), "missed melee reports no damage")
	_expect_equal(melee_attempts.size(), 1, "missed melee still emits one feedback event")
	var health_before := victim.health.current_health
	_expect(attacker.perform_melee(attacker.get_eye_position(), Vector3.FORWARD), "melee ray damages a nearby opponent")
	_expect_equal(melee_attempts.size(), 2, "connected melee emits exactly one feedback event")
	_expect(victim.health.current_health < health_before, "melee removes health")
	_expect_equal(victim.health.last_attacker_id, &"melee_attacker", "melee retains attacker attribution")

	var respawner := _make_test_combatant(&"respawner", Vector3.ZERO)
	respawner.set_spawn_points([
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		Vector3(30.0, 0.0, 0.0),
	])
	respawner.set_loadout([WeaponCatalog.get_weapon(&"vx4_carbine")])
	var threat_a := _make_test_combatant(&"threat_a", Vector3(0.5, 0.0, 0.0))
	var threat_b := _make_test_combatant(&"threat_b", Vector3(10.5, 0.0, 0.0))
	arena.add_child(respawner)
	arena.add_child(threat_a)
	arena.add_child(threat_b)
	await process_frame
	respawner.flash_strength = 1.0
	respawner.flash_remaining = 6.0
	respawner.concussion_strength = 1.0
	respawner.concussion_remaining = 6.0
	respawner.current_weapon_state().magazine_ammo = 0
	respawner.current_weapon_state().reserve_ammo = 0
	respawner.health.force_kill(&"threat_a")
	respawner.respawn_now()
	_expect_near(respawner.global_position.x, 30.0, 0.01, "respawn selects the point farthest from live threats")
	_expect(respawner.health.is_protected(), "safe respawn grants spawn protection")
	_expect_equal(respawner.current_weapon_state().magazine_ammo, respawner.current_weapon().magazine_size, "respawn refills the magazine")
	_expect_equal(respawner.current_weapon_state().reserve_ammo, respawner.current_weapon().starting_reserve, "respawn restores reserve ammunition")
	_expect_near(respawner.flash_strength + respawner.concussion_strength, 0.0, 0.001, "respawn clears tactical impairment for every combatant")
	arena.queue_free()
	await process_frame

	var cover_arena := Node3D.new()
	root.add_child(cover_arena)
	var cover_respawner := _make_test_combatant(&"cover_respawner", Vector3.ZERO)
	var clear_far_spawn := Vector3(-20.0, 0.0, 10.0)
	var sheltered_spawn := Vector3(10.0, 0.0, 0.0)
	cover_respawner.set_spawn_points([clear_far_spawn, sheltered_spawn])
	cover_respawner.set_spawn_safe_radii([8.0, 8.0])
	var sightline_threat := _make_test_combatant(&"sightline_threat", Vector3(10.0, 0.0, 10.0))
	cover_arena.add_child(cover_respawner)
	cover_arena.add_child(sightline_threat)
	var sightline_wall := StaticBody3D.new()
	var sightline_collision := CollisionShape3D.new()
	var sightline_shape := BoxShape3D.new()
	sightline_shape.size = Vector3(7.0, 3.0, 0.4)
	sightline_collision.shape = sightline_shape
	sightline_collision.position = Vector3(10.0, 1.5, 5.0)
	sightline_wall.add_child(sightline_collision)
	cover_arena.add_child(sightline_wall)
	await physics_frame
	_expect_equal(cover_respawner._choose_safest_spawn(), sheltered_spawn, "safe-spawn scoring prefers hard cover over a farther exposed sightline")
	cover_arena.queue_free()
	await process_frame


func _test_movement_stances() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var floor := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(12.0, 0.5, 12.0)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -0.25
	floor.add_child(floor_collision)
	arena.add_child(floor)
	var player := PlayerController.new()
	player.capture_mouse_on_ready = false
	arena.add_child(player)
	await physics_frame
	await physics_frame
	player.set_physics_process(false)
	var movement_cues: Array[StringName] = []
	player.movement_audio_requested.connect(func(kind: StringName, _strength: float) -> void: movement_cues.append(kind))
	var standing_height := player.current_capsule_height()

	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	player._update_stance_and_movement(0.016)
	_expect(player.is_sprinting and player.velocity.length() > 0.0, "sprint raises forward movement state")
	Input.action_press(&"fire")
	player._update_stance_and_movement(0.016)
	_expect(not player.is_sprinting, "fire input transitions out of full sprint before combat")
	Input.action_release(&"fire")
	Input.action_release(&"sprint")
	Input.action_press(&"aim")
	player._update_stance_and_movement(0.016)
	player._update_camera(0.25)
	_expect(player.is_aiming and not player.is_sprinting, "ADS suppresses sprint")
	_expect(player.camera.fov < player.hip_fov, "ADS narrows first-person field of view")
	Input.action_release(&"aim")
	Input.action_release(&"move_forward")
	await process_frame

	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	Input.action_press(&"crouch")
	player._update_stance_and_movement(0.016)
	_expect(player.is_crouching, "crouch input lowers the movement stance")
	_expect(player.slide_remaining > 0.0 and Vector2(player.velocity.x, player.velocity.z).length() > player.walk_speed, "crouch while sprinting starts a fast slide")
	_expect(player.current_capsule_height() < standing_height, "crouch and slide physically reduce the collision capsule")
	_expect(&"slide" in movement_cues, "starting a slide emits movement audio feedback")

	var ceiling := StaticBody3D.new()
	var ceiling_collision := CollisionShape3D.new()
	var ceiling_shape := BoxShape3D.new()
	ceiling_shape.size = Vector3(3.0, 0.25, 3.0)
	ceiling_collision.shape = ceiling_shape
	ceiling_collision.position.y = 1.65
	ceiling.add_child(ceiling_collision)
	arena.add_child(ceiling)
	await physics_frame
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	Input.action_release(&"crouch")
	player.slide_remaining = 0.0
	player._update_stance_and_movement(0.016)
	_expect(player.is_crouching and player.current_capsule_height() < standing_height, "ceiling clearance prevents unsafe stand-up")
	ceiling.queue_free()
	await physics_frame
	player._update_stance_and_movement(0.016)
	_expect(not player.is_crouching and is_equal_approx(player.current_capsule_height(), standing_height), "player stands after moving clear of low cover")
	player.global_position.y = 0.001
	player.velocity = Vector3.DOWN
	player.move_and_slide()
	Input.action_release(&"jump")
	await process_frame
	Input.action_press(&"jump")
	player._update_stance_and_movement(0.016)
	_expect(player.velocity.y > 0.0, "jump input applies upward velocity while grounded")
	_expect(&"jump" in movement_cues, "jumping emits movement audio feedback")
	Input.action_release(&"jump")
	player.velocity = Vector3(player.walk_speed, 0.0, 0.0)
	player.is_aiming = false
	player.is_crouching = false
	player.slide_remaining = 0.0
	var moving_spread := player.current_ballistic_spread_degrees()
	player.velocity = Vector3.ZERO
	var stationary_spread := player.current_ballistic_spread_degrees()
	_expect(moving_spread > stationary_spread, "movement expands the same ballistic spread used by firing")
	player.velocity = Vector3(player.walk_speed, 0.0, 0.0)
	player.is_crouching = true
	var crouched_moving_spread := player.current_ballistic_spread_degrees()
	_expect(crouched_moving_spread < moving_spread, "crouching reduces the live movement accuracy penalty")
	var spread_world := BreakwaterGameWorld.new()
	spread_world.player = player
	_expect_near(
		spread_world._crosshair_spread(player.current_weapon()),
		5.0 + crouched_moving_spread * 4.5,
		0.001,
		"HUD crosshair reports the exact ballistic spread used by player fire",
	)
	spread_world.free()
	player._update_movement_audio(1.0, true, 0.0)
	player._update_movement_audio(0.016, false, 8.0)
	_expect(&"footstep" in movement_cues and &"land" in movement_cues, "footsteps and landing each emit distinct movement feedback")
	player.is_aiming = true
	player.is_sprinting = true
	player.is_crouching = true
	player.slide_remaining = 0.5
	player._on_player_killed(&"test")
	_expect(not player.is_aiming and not player.is_sprinting and not player.is_crouching and player.slide_remaining <= 0.0, "death clears every transient movement and combat stance")
	arena.queue_free()
	await process_frame


func _test_bot_equipment_and_pickups() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var bot := _make_test_bot(&"supply_bot", Vector3.ZERO)
	bot.auto_select_loadout = false
	var low_damage_weapon := WeaponCatalog.get_weapon(&"vx4_carbine").duplicate() as WeaponDefinition
	low_damage_weapon.base_damage = 0.1
	bot.set_loadout([low_damage_weapon])
	arena.add_child(bot)
	_expect(is_instance_valid(bot._weapon_visual) and bot._weapon_visual.get_node_or_null("Receiver") != null, "bot visibly carries its equipped procedural weapon")
	var pickup_weapon := WeaponCatalog.get_weapon(&"kestrel_smg").duplicate() as WeaponDefinition
	pickup_weapon.weapon_id = &"test_pickup_smg"
	var pickup := WeaponPickup.new()
	pickup.configure(pickup_weapon, 20.0)
	arena.add_child(pickup)
	pickup.global_position = bot.global_position + Vector3(0.0, 0.0, -0.8)
	await process_frame
	bot.current_weapon_state().reserve_ammo = 0
	bot._update_decision()
	_expect_equal(bot.bot_state, BotController.BotState.SEEK_PICKUP, "ammo-starved bot chooses a nearby field pickup")
	bot._execute_movement(0.016)
	_expect(not pickup.is_available, "bot collects its selected pickup")
	_expect_equal(bot.current_weapon().weapon_id, &"test_pickup_smg", "bot equips a collected weapon")
	_expect(is_instance_valid(bot._weapon_visual) and bot._weapon_visual.get_node_or_null("Receiver") != null, "bot weapon presentation updates after a pickup")
	bot.current_weapon_state().reserve_ammo = 0
	var ammo_pickup := WeaponPickup.new()
	ammo_pickup.configure_supply(&"ammo", 20.0)
	arena.add_child(ammo_pickup)
	_expect(ammo_pickup.try_collect(bot), "bot accepts an ammunition field supply")
	_expect_equal(bot.current_weapon_state().reserve_ammo, bot.current_weapon().magazine_size, "bot ammunition supply restores one reserve magazine")
	bot._grenade_cooldown = 8.0
	var tactical_pickup := WeaponPickup.new()
	tactical_pickup.configure_supply(&"concussion", 20.0)
	arena.add_child(tactical_pickup)
	_expect(tactical_pickup.try_collect(bot), "bot accepts a useful tactical field supply")
	_expect_near(bot._grenade_cooldown, 2.0, 0.001, "bot tactical supply advances grenade readiness")
	bot._grenade_cooldown = 0.5
	var rejected_tactical := WeaponPickup.new()
	rejected_tactical.configure_supply(&"flash", 20.0)
	arena.add_child(rejected_tactical)
	_expect(not rejected_tactical.try_collect(bot), "grenade-ready bot rejects an unnecessary tactical supply")
	_expect(rejected_tactical.is_available, "rejected bot supply remains available for another combatant")
	_expect(bot._select_nearby_pickup() == null, "bot pickup selection filters out supplies it cannot currently use")
	bot.apply_status_effect(GrenadeDefinition.GrenadeType.FLASH, 0.8, 2.0)
	bot._update_status_visuals()
	_expect(bot._body_material.emission_enabled and bot._body_material.albedo_color != bot._base_body_color, "flash status visibly changes an affected bot")
	bot.flash_strength = 0.0
	bot.apply_status_effect(GrenadeDefinition.GrenadeType.CONCUSSION, 0.8, 2.0)
	bot._update_status_visuals()
	_expect(bot._visor_material.albedo_color.b > bot._base_visor_color.b + 0.25, "concussion uses a visibly distinct bot status tint")

	var target := _make_test_combatant(&"grenade_target", Vector3(0.0, 0.0, -10.0))
	arena.add_child(target)
	await physics_frame
	bot.target = target
	bot._desired_pickup = null
	bot._grenade_cooldown = 0.0
	bot.grenade_aggression = 1.0
	var thrown_ids: Array[StringName] = []
	bot.grenade_thrown.connect(func(_actor_id: StringName, grenade_id: StringName) -> void: thrown_ids.append(grenade_id))
	for _attempt in 400:
		bot._execute_combat()
		if not thrown_ids.is_empty():
			break
	_expect(not thrown_ids.is_empty(), "combat bot autonomously throws equipment")
	if not thrown_ids.is_empty():
		_expect(thrown_ids[0] in [&"frag", &"flash", &"concussion"], "bot selects a valid grenade type")
	var grenade_nodes := get_nodes_in_group(&"grenades")
	_expect(not grenade_nodes.is_empty(), "bot grenade creates a live projectile")
	if not grenade_nodes.is_empty():
		_expect_equal((grenade_nodes[0] as GrenadeProjectile).owner_id, &"supply_bot", "bot grenade retains owner attribution")
	arena.queue_free()
	await process_frame


func _test_unattended_bot_combat() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var floor := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(30.0, 0.5, 30.0)
	floor_collision.shape = floor_shape
	floor_collision.position.y = -0.25
	floor.add_child(floor_collision)
	arena.add_child(floor)
	var rules := MatchRules.new()
	rules.target_score = 1
	arena.add_child(rules)
	var bot_a := _make_test_bot(&"test_bot_a", Vector3(-2.0, 0.0, 0.0))
	var bot_b := _make_test_bot(&"test_bot_b", Vector3(2.0, 0.0, 0.0))
	arena.add_child(bot_a)
	arena.add_child(bot_b)
	rules.register_combatant(bot_a)
	rules.register_combatant(bot_b)
	var test_weapon := WeaponCatalog.get_weapon(&"vx4_carbine").duplicate() as WeaponDefinition
	test_weapon.base_damage = 100.0
	test_weapon.rounds_per_minute = 1000.0
	bot_a.set_loadout([test_weapon])
	bot_b.set_loadout([test_weapon])
	for _frame in 240:
		if not rules.match_active:
			break
		await process_frame
	_expect(not rules.match_active, "autonomous bots eliminate one another without player input")
	_expect(not rules.winner_id.is_empty(), "bot-only fight produces a winner")
	arena.queue_free()
	await process_frame


func _make_test_bot(id: StringName, at: Vector3) -> BotController:
	var bot := BotController.new()
	bot.configure_identity(id, str(id))
	bot.position = at
	bot.auto_select_loadout = false
	bot.skill = 1.0
	bot.thinking_interval = 0.05
	bot.preferred_engagement_range = 15.0
	bot.awareness_range = 50.0
	bot.respawn_delay = 10.0
	bot.set_spawn_points([at])
	return bot


func _make_test_combatant(id: StringName, at: Vector3) -> CombatantController:
	var actor := CombatantController.new()
	actor.configure_identity(id, str(id))
	actor.position = at
	return actor


func _has_controller_binding(action: StringName) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


func _key_event(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = pressed
	return event


func _mouse_button_event(button: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (expected %.3f, got %.3f)" % [message, expected, actual])
