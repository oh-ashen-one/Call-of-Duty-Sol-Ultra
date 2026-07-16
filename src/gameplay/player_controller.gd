class_name PlayerController
extends CombatantController

## First-person input, locomotion and camera controller. Input actions are created
## at runtime when absent, allowing the module to run in a fresh Godot project and
## still be rebound later by the settings UI.

signal movement_audio_requested(kind: StringName, strength: float)

@export_range(1.0, 20.0, 0.1) var walk_speed: float = 6.4
@export_range(1.0, 30.0, 0.1) var sprint_speed: float = 9.25
@export_range(1.0, 20.0, 0.1) var crouch_speed: float = 3.8
@export_range(1.0, 30.0, 0.1) var slide_speed: float = 11.5
@export_range(0.1, 2.0, 0.05) var slide_duration: float = 0.72
@export_range(1.0, 20.0, 0.1) var jump_velocity: float = 5.4
@export_range(0.01, 2.0, 0.01) var mouse_sensitivity: float = 0.12
@export_range(0.1, 12.0, 0.1) var controller_sensitivity: float = 3.25
@export_range(0.0, 0.9, 0.01) var controller_deadzone: float = 0.18
@export_range(50.0, 120.0, 1.0) var hip_fov: float = 86.0
@export_range(35.0, 100.0, 1.0) var ads_fov: float = 67.0
@export_range(0.1, 1.0, 0.05) var ads_sensitivity_scale: float = 0.72
@export var invert_y: bool = false
@export_range(0.0, 1.0, 0.05) var camera_shake_strength: float = 0.75
@export var vibration_enabled: bool = true
@export var capture_mouse_on_ready: bool = true
@export var input_enabled: bool = true
@export var lethal_grenade_id: StringName = &"frag"
@export var tactical_grenade_id: StringName = &"flash"
@export_range(0.9, 1.6, 0.05) var crouched_capsule_height: float = 1.2

var camera: Camera3D
var view_pivot: Node3D
var is_aiming: bool = false
var is_crouching: bool = false
var is_sprinting: bool = false
var slide_remaining: float = 0.0
var grenade_inventory: Dictionary = {}

var _look_pitch: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO
var _melee_cooldown: float = 0.0
var _gravity: float = 9.8
var _camera_impulse: float = 0.0
var _camera_shake_time: float = 0.0
var _combatant_collision: CollisionShape3D
var _standing_capsule_height := 1.8
var _step_distance := 0.0


func _ready() -> void:
	is_player_controlled = true
	ensure_default_input_actions()
	super._ready()
	_cache_stance_collision()
	_ensure_camera_rig()
	_reset_equipment_inventory()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	health.respawned.connect(_on_player_respawned)
	health.killed.connect(_on_player_killed)
	if capture_mouse_on_ready:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not is_alive():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_event := event as InputEventMouseMotion
		var sensitivity_scale := ads_sensitivity_scale if is_aiming else 1.0
		_apply_look(
			-mouse_event.relative.x * mouse_sensitivity * sensitivity_scale,
			-mouse_event.relative.y * mouse_sensitivity * sensitivity_scale,
		)


func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not can_process():
		velocity = Vector3.ZERO
		return
	if not input_enabled or not is_alive():
		velocity.x = move_toward(velocity.x, 0.0, delta * 15.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 15.0)
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		return
	var was_grounded := is_on_floor()
	var downward_speed := maxf(-velocity.y, 0.0)
	_update_controller_look(delta)
	_update_stance_and_movement(delta)
	_update_combat_input(delta)
	# A winning hit can end the match from inside the combat callback. Avoid
	# touching camera/physics state if the arena was stopped synchronously.
	if not input_enabled or not can_process():
		velocity = Vector3.ZERO
		return
	_update_camera(delta)
	move_and_slide()
	_update_movement_audio(delta, was_grounded, downward_speed)


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if enabled and capture_mouse_on_ready:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_feedback_settings(shake_strength: float, vibration: bool) -> void:
	camera_shake_strength = clampf(shake_strength, 0.0, 1.0)
	vibration_enabled = vibration


func add_camera_impulse(amount: float, vibration_strength := 0.0, duration := 0.08) -> void:
	_camera_impulse = clampf(maxf(_camera_impulse, amount), 0.0, 1.0)
	if vibration_enabled and vibration_strength > 0.0:
		for device in Input.get_connected_joypads():
			Input.start_joy_vibration(device, vibration_strength * 0.65, vibration_strength, duration)


func camera_impulse_level() -> float:
	return _camera_impulse


func get_view_direction() -> Vector3:
	return -camera.global_transform.basis.z.normalized() if camera != null else super.get_view_direction()


func get_eye_position() -> Vector3:
	return camera.global_position if camera != null else super.get_eye_position()


static func required_input_actions() -> PackedStringArray:
	return PackedStringArray([
		"move_forward", "move_back", "move_left", "move_right",
		"jump", "sprint", "crouch", "fire", "aim", "reload", "interact", "melee",
		"throw_frag", "throw_tactical", "swap_weapon", "scoreboard", "pause",
	])


static func ensure_default_input_actions() -> void:
	_add_key_action(&"move_forward", KEY_W)
	_add_key_action(&"move_back", KEY_S)
	_add_key_action(&"move_left", KEY_A)
	_add_key_action(&"move_right", KEY_D)
	_add_key_action(&"jump", KEY_SPACE)
	_add_key_action(&"sprint", KEY_SHIFT)
	_add_key_action(&"crouch", KEY_CTRL)
	_add_key_action(&"reload", KEY_R)
	_add_key_action(&"melee", KEY_V)
	_add_key_action(&"interact", KEY_E)
	_add_key_action(&"swap_weapon", KEY_1)
	_add_key_action(&"throw_frag", KEY_G)
	_add_key_action(&"throw_tactical", KEY_Q)
	_add_key_action(&"scoreboard", KEY_TAB)
	_add_key_action(&"pause", KEY_ESCAPE)
	_add_mouse_action(&"fire", MOUSE_BUTTON_LEFT)
	_add_mouse_action(&"aim", MOUSE_BUTTON_RIGHT)
	# Controller bindings are owned by SettingsManager so trigger/shoulder mappings
	# remain rebindable and are never duplicated here.
	for action in required_input_actions():
		_ensure_action(action)


func _update_stance_and_movement(delta: float) -> void:
	var input_vector := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back", controller_deadzone
	)
	var desired_direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	var wants_crouch := Input.is_action_pressed("crouch")
	var can_start_slide := Input.is_action_pressed("sprint") and input_vector.y < -0.25 and is_on_floor()
	is_aiming = Input.is_action_pressed("aim")
	is_sprinting = Input.is_action_pressed("sprint") \
		and input_vector.y < -0.25 \
		and not is_aiming \
		and not wants_crouch \
		and not Input.is_action_pressed("fire")
	if Input.is_action_just_pressed("crouch") and can_start_slide:
		slide_remaining = slide_duration
		_slide_direction = desired_direction if not desired_direction.is_zero_approx() else -transform.basis.z
		movement_audio_requested.emit(&"slide", 1.0)
	_update_collision_stance(wants_crouch or slide_remaining > 0.0)
	if slide_remaining > 0.0:
		slide_remaining = maxf(slide_remaining - delta, 0.0)
		var slide_ratio := slide_remaining / maxf(slide_duration, 0.01)
		var slide_velocity := slide_speed * lerpf(0.62, 1.0, slide_ratio) * status_movement_scale()
		velocity.x = _slide_direction.x * slide_velocity
		velocity.z = _slide_direction.z * slide_velocity
	else:
		var target_speed := walk_speed
		if is_sprinting:
			target_speed = sprint_speed
		elif is_crouching:
			target_speed = crouch_speed
		var weapon := current_weapon()
		if weapon != null:
			target_speed *= weapon.movement_speed_scale
		target_speed *= status_movement_scale()
		var target_velocity := desired_direction * target_speed
		var acceleration := 34.0 if is_on_floor() else 9.0
		velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and slide_remaining <= 0.0:
			velocity.y = jump_velocity
			movement_audio_requested.emit(&"jump", 0.72)
	else:
		velocity.y -= _gravity * delta


func _update_combat_input(delta: float) -> void:
	_melee_cooldown = maxf(_melee_cooldown - delta, 0.0)
	var weapon := current_weapon()
	if weapon != null:
		var wants_fire := Input.is_action_pressed("fire") if weapon.automatic else Input.is_action_just_pressed("fire")
		if wants_fire:
			var fired := fire_hitscan(
				get_eye_position(),
				get_view_direction(),
				is_aiming,
				current_ballistic_spread_degrees(weapon),
			)
			if fired and view_pivot != null:
				var recoil_scale := 0.68 if is_aiming else 1.0
				add_camera_impulse(clampf(weapon.recoil_pitch / 12.0, 0.08, 0.38), 0.18, 0.045)
				_apply_weapon_recoil(weapon, recoil_scale)
	# Reload and interact intentionally share the default controller face button.
	# Give a valid nearby pickup contextual priority so one press cannot both
	# replace a weapon and start an unrelated reload.
	_handle_contextual_reload_interact(
		Input.is_action_just_pressed("interact"),
		Input.is_action_just_pressed("reload"),
	)
	if Input.is_action_just_pressed("melee") and _melee_cooldown <= 0.0:
		if weapon != null:
			current_weapon_state().cancel_reload()
		perform_melee(get_eye_position(), get_view_direction())
		_melee_cooldown = 0.65
	if Input.is_action_just_pressed("swap_weapon"):
		cycle_weapon()
	if Input.is_action_just_pressed("throw_frag"):
		_try_throw_grenade(&"frag")
	if Input.is_action_just_pressed("throw_tactical"):
		_try_throw_grenade(tactical_grenade_id)


func current_ballistic_spread_degrees(weapon: WeaponDefinition = current_weapon()) -> float:
	if weapon == null:
		return 0.0
	var spread := weapon.ads_spread_degrees if is_aiming else weapon.hip_spread_degrees
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var movement_penalty := horizontal_speed * 0.10
	if is_crouching:
		movement_penalty *= 0.72
	if slide_remaining > 0.0:
		movement_penalty *= 1.25
	return spread + movement_penalty


func _update_controller_look(delta: float) -> void:
	var joypads := Input.get_connected_joypads()
	if joypads.is_empty():
		return
	var device := int(joypads[0])
	var look_vector := Vector2(
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y),
	)
	if look_vector.length_squared() <= controller_deadzone * controller_deadzone:
		return
	var sensitivity_scale := ads_sensitivity_scale if is_aiming else 1.0
	_apply_look(
		-look_vector.x * controller_sensitivity * sensitivity_scale * delta * 55.0,
		-look_vector.y * controller_sensitivity * sensitivity_scale * delta * 55.0,
	)


func _apply_look(yaw_degrees: float, pitch_degrees: float) -> void:
	rotation.y += deg_to_rad(yaw_degrees) * status_aim_scale()
	var y_multiplier := -1.0 if invert_y else 1.0
	_look_pitch = clampf(
		_look_pitch + deg_to_rad(pitch_degrees) * y_multiplier * status_aim_scale(),
		deg_to_rad(-88.0),
		deg_to_rad(88.0),
	)


func _apply_weapon_recoil(weapon: WeaponDefinition, recoil_scale: float = 1.0) -> void:
	if weapon == null:
		return
	# Positive X rotation raises the -Z camera direction in Godot, so recoil
	# adds pitch just like an upward mouse movement.
	_look_pitch = clampf(
		_look_pitch + deg_to_rad(weapon.recoil_pitch * recoil_scale),
		deg_to_rad(-88.0),
		deg_to_rad(88.0),
	)
	rotation.y += deg_to_rad(
		_rng.randf_range(-weapon.recoil_yaw, weapon.recoil_yaw) * recoil_scale
	)


func _update_camera(delta: float) -> void:
	if camera == null or view_pivot == null:
		return
	view_pivot.rotation.x = lerp_angle(view_pivot.rotation.x, _look_pitch, 1.0 - exp(-delta * 24.0))
	var target_height := eye_height - (0.55 if is_crouching or slide_remaining > 0.0 else 0.0)
	view_pivot.position.y = lerpf(view_pivot.position.y, target_height, 1.0 - exp(-delta * 14.0))
	var target_fov := ads_fov if is_aiming else hip_fov
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-delta * 13.0))
	_camera_shake_time += delta
	_camera_impulse = move_toward(_camera_impulse, 0.0, delta * 3.6)
	var shake := _camera_impulse * _camera_impulse * camera_shake_strength
	camera.position = Vector3(
		sin(_camera_shake_time * 39.0) * 0.028,
		cos(_camera_shake_time * 51.0) * 0.022,
		0.0,
	) * shake
	camera.rotation = Vector3(
		sin(_camera_shake_time * 31.0) * 0.012,
		cos(_camera_shake_time * 37.0) * 0.009,
		sin(_camera_shake_time * 43.0) * 0.018,
	) * shake


func _try_throw_grenade(grenade_id: StringName) -> void:
	if int(grenade_inventory.get(grenade_id, 0)) <= 0:
		return
	var definition := GrenadeDefinition.get_grenade(grenade_id)
	var state := current_weapon_state()
	if state != null:
		state.cancel_reload()
	var projectile := throw_grenade(
		definition,
		get_eye_position() + get_view_direction() * 0.55,
		(get_view_direction() + Vector3.UP * 0.16).normalized(),
	)
	if projectile != null:
		grenade_inventory[grenade_id] = int(grenade_inventory[grenade_id]) - 1


func nearest_weapon_pickup(max_distance := 3.2) -> WeaponPickup:
	if not is_inside_tree():
		return null
	var nearest: WeaponPickup
	var nearest_distance := max_distance
	for node in get_tree().get_nodes_in_group(&"weapon_pickups"):
		var pickup := node as WeaponPickup
		if pickup == null or not pickup.is_available:
			continue
		var target_position := pickup.global_position + Vector3.UP * 0.45
		var to_pickup := target_position - get_eye_position()
		var distance := to_pickup.length()
		if distance <= 0.01 or get_view_direction().dot(to_pickup / distance) < 0.28:
			continue
		if not _has_pickup_line_of_sight(target_position):
			continue
		if distance <= nearest_distance:
			nearest = pickup
			nearest_distance = distance
	return nearest


func receive_supply(supply_id: StringName, amount: int = 1) -> bool:
	if supply_id == &"ammo":
		return super.receive_supply(supply_id, amount)
	if not grenade_inventory.has(supply_id) or amount <= 0:
		return false
	var current := int(grenade_inventory.get(supply_id, 0))
	if current >= 2:
		return false
	grenade_inventory[supply_id] = mini(2, current + amount)
	return true


func _try_interact() -> bool:
	var pickup := nearest_weapon_pickup()
	return pickup != null and pickup.try_collect(self)


func _handle_contextual_reload_interact(wants_interact: bool, wants_reload: bool) -> bool:
	var interacted := wants_interact and _try_interact()
	if wants_reload and not interacted:
		reload_weapon()
	return interacted


func _ensure_camera_rig() -> void:
	view_pivot = get_node_or_null("ViewPivot") as Node3D
	if view_pivot == null:
		view_pivot = Node3D.new()
		view_pivot.name = "ViewPivot"
		view_pivot.position.y = eye_height
		add_child(view_pivot)
	camera = view_pivot.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.fov = hip_fov
		camera.near = 0.05
		view_pivot.add_child(camera)
	camera.current = true


func _on_player_respawned() -> void:
	_reset_equipment_inventory()
	_reset_transient_actions()
	flash_strength = 0.0
	concussion_strength = 0.0
	_camera_impulse = 0.0
	if camera != null:
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO


func _on_player_killed(_killer_id: StringName) -> void:
	_reset_transient_actions()


func _reset_equipment_inventory() -> void:
	grenade_inventory.clear()
	if lethal_grenade_id in [&"frag", &"flash", &"concussion"]:
		grenade_inventory[lethal_grenade_id] = 1
	if tactical_grenade_id in [&"frag", &"flash", &"concussion"]:
		grenade_inventory[tactical_grenade_id] = 1


func _reset_transient_actions() -> void:
	is_aiming = false
	is_crouching = false
	is_sprinting = false
	slide_remaining = 0.0
	_slide_direction = Vector3.ZERO
	_melee_cooldown = 0.0
	_step_distance = 0.0
	_look_pitch = 0.0
	_set_capsule_height(_standing_capsule_height)


func current_capsule_height() -> float:
	if _combatant_collision == null or not (_combatant_collision.shape is CapsuleShape3D):
		return 0.0
	return (_combatant_collision.shape as CapsuleShape3D).height


func _cache_stance_collision() -> void:
	_combatant_collision = get_node_or_null("CombatantCollision") as CollisionShape3D
	if _combatant_collision != null and _combatant_collision.shape is CapsuleShape3D:
		_standing_capsule_height = (_combatant_collision.shape as CapsuleShape3D).height


func _update_collision_stance(wants_low_stance: bool) -> void:
	if wants_low_stance:
		_set_capsule_height(crouched_capsule_height)
		is_crouching = true
		return
	if not _can_use_capsule_height(_standing_capsule_height):
		_set_capsule_height(crouched_capsule_height)
		is_crouching = true
		return
	_set_capsule_height(_standing_capsule_height)
	is_crouching = false


func _set_capsule_height(height: float) -> void:
	if _combatant_collision == null or not (_combatant_collision.shape is CapsuleShape3D):
		return
	var capsule := _combatant_collision.shape as CapsuleShape3D
	capsule.height = maxf(height, capsule.radius * 2.0)
	_combatant_collision.position.y = capsule.height * 0.5


func _can_use_capsule_height(height: float) -> bool:
	if not is_inside_tree() or get_world_3d() == null or _combatant_collision == null:
		return true
	var current_shape := _combatant_collision.shape as CapsuleShape3D
	if current_shape == null:
		return true
	var probe := CapsuleShape3D.new()
	probe.radius = current_shape.radius
	probe.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(global_transform.basis, global_position + Vector3.UP * (height * 0.5 + 0.025))
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _has_pickup_line_of_sight(target_position: Vector3) -> bool:
	if get_world_3d() == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(get_eye_position(), target_position)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _update_movement_audio(delta: float, was_grounded: bool, downward_speed: float) -> void:
	if not was_grounded and is_on_floor() and downward_speed >= 2.2:
		movement_audio_requested.emit(&"land", clampf(downward_speed / 10.0, 0.3, 1.0))
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or horizontal_speed < 1.0 or slide_remaining > 0.0:
		_step_distance = 0.0
		return
	_step_distance += horizontal_speed * delta
	var stride := 1.45 if is_sprinting else (1.9 if is_crouching else 1.7)
	if _step_distance >= stride:
		_step_distance = fmod(_step_distance, stride)
		movement_audio_requested.emit(&"footstep", clampf(horizontal_speed / sprint_speed, 0.35, 1.0))


static func _add_key_action(action: StringName, keycode: Key) -> void:
	_ensure_action(action)
	if not InputMap.action_get_events(action).is_empty():
		return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


static func _add_mouse_action(action: StringName, button: MouseButton) -> void:
	_ensure_action(action)
	if not InputMap.action_get_events(action).is_empty():
		return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


static func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
