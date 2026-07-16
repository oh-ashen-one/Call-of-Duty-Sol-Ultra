class_name CombatantController
extends CharacterBody3D

## Shared combat implementation for players and bots. GameWorld only needs to
## instantiate a controller, assign identity/spawn points, add it to the tree and
## register it with MatchRules.

signal eliminated(victim_id: StringName, killer_id: StringName)
signal respawned(combatant_id: StringName)
signal health_changed(combatant_id: StringName, current: float, maximum: float)
signal weapon_changed(combatant_id: StringName, weapon: WeaponDefinition)
signal ammo_changed(combatant_id: StringName, magazine: int, reserve: int)
signal weapon_fired(
	shooter_id: StringName,
	weapon_id: StringName,
	origin: Vector3,
	direction: Vector3,
)
signal weapon_trace(
	shooter_id: StringName,
	weapon_id: StringName,
	origin: Vector3,
	destination: Vector3,
	impact_normal: Vector3,
	impacted: bool,
)
signal hit_confirmed(target_id: StringName, damage: float, killed: bool, headshot: bool)
signal weapon_hit_confirmed(target_id: StringName, damage: float, killed: bool, headshot: bool)
signal grenade_thrown(combatant_id: StringName, grenade_id: StringName)
signal melee_performed(combatant_id: StringName)
signal status_effect_applied(effect_type: int, strength: float, duration: float)

@export var combatant_id: StringName = &"combatant"
@export var display_name: String = "Combatant"
@export var is_player_controlled: bool = false
@export_range(0.1, 10.0, 0.1) var respawn_delay: float = 2.5
@export_range(0.5, 3.0, 0.05) var eye_height: float = 1.62
@export_range(1, 4, 1) var max_weapon_slots: int = 2
@export var auto_build_collision: bool = true

var health: HealthComponent
var weapon_states: Array[WeaponState] = []
var active_weapon_index: int = 0
var spawn_points: Array[Vector3] = []
var spawn_safe_radii: Array[float] = []
var spawn_selector: Callable
var flash_strength: float = 0.0
var flash_remaining: float = 0.0
var concussion_strength: float = 0.0
var concussion_remaining: float = 0.0

var _respawn_remaining: float = 0.0
var _rng := RandomNumberGenerator.new()
var _saved_collision_layer: int = 1
var _saved_collision_mask: int = 1


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.55
	floor_constant_speed = true
	_rng.seed = hash(str(combatant_id)) + get_instance_id()
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	add_to_group("combatants")
	_ensure_health_component()
	if auto_build_collision:
		_ensure_collision_shape()
	if weapon_states.is_empty():
		set_loadout(WeaponCatalog.default_loadout())
	set_process(true)


func _process(delta: float) -> void:
	for state in weapon_states:
		state.tick(delta)
	flash_remaining = maxf(flash_remaining - delta, 0.0)
	concussion_remaining = maxf(concussion_remaining - delta, 0.0)
	if flash_remaining <= 0.0:
		flash_strength = move_toward(flash_strength, 0.0, delta * 2.5)
	if concussion_remaining <= 0.0:
		concussion_strength = move_toward(concussion_strength, 0.0, delta * 2.5)
	if _respawn_remaining > 0.0:
		_respawn_remaining = maxf(_respawn_remaining - delta, 0.0)
		if _respawn_remaining <= 0.0:
			respawn_now()


func configure_identity(id: StringName, label: String) -> void:
	combatant_id = id
	display_name = label
	_rng.seed = hash(str(id))


func set_spawn_points(points: Array[Vector3]) -> void:
	spawn_points = points.duplicate()


func set_spawn_safe_radii(radii: Array[float]) -> void:
	spawn_safe_radii = radii.duplicate()


func set_loadout(definitions: Array[WeaponDefinition]) -> void:
	weapon_states.clear()
	for definition in definitions:
		if definition == null or weapon_states.size() >= max_weapon_slots:
			continue
		var state := WeaponState.new(definition)
		state.ammo_changed.connect(_on_weapon_ammo_changed.bind(state))
		weapon_states.append(state)
	active_weapon_index = clampi(active_weapon_index, 0, maxi(weapon_states.size() - 1, 0))
	if not weapon_states.is_empty():
		weapon_changed.emit(combatant_id, current_weapon())
		_emit_current_ammo()


func current_weapon_state() -> WeaponState:
	if active_weapon_index < 0 or active_weapon_index >= weapon_states.size():
		return null
	return weapon_states[active_weapon_index]


func current_weapon() -> WeaponDefinition:
	var state := current_weapon_state()
	return state.definition if state != null else null


func switch_weapon(slot: int) -> bool:
	if slot < 0 or slot >= weapon_states.size() or slot == active_weapon_index:
		return false
	var old_state := current_weapon_state()
	if old_state != null:
		old_state.cancel_reload()
	active_weapon_index = slot
	weapon_changed.emit(combatant_id, current_weapon())
	_emit_current_ammo()
	return true


func cycle_weapon(direction: int = 1) -> bool:
	if weapon_states.size() < 2:
		return false
	return switch_weapon(posmod(active_weapon_index + direction, weapon_states.size()))


func reload_weapon() -> bool:
	var state := current_weapon_state()
	return state != null and state.begin_reload()


func pickup_weapon(definition: WeaponDefinition) -> bool:
	if definition == null:
		return false
	for index in weapon_states.size():
		var existing := weapon_states[index]
		if existing.definition.weapon_id == definition.weapon_id:
			var added := existing.add_reserve(maxi(definition.magazine_size, definition.starting_reserve / 2))
			if index == active_weapon_index:
				_emit_current_ammo()
			return added > 0
	var new_state := WeaponState.new(definition)
	new_state.ammo_changed.connect(_on_weapon_ammo_changed.bind(new_state))
	if weapon_states.size() < max_weapon_slots:
		weapon_states.append(new_state)
		active_weapon_index = weapon_states.size() - 1
	else:
		weapon_states[active_weapon_index] = new_state
	weapon_changed.emit(combatant_id, definition)
	_emit_current_ammo()
	return true


func receive_supply(supply_id: StringName, amount: int = 1) -> bool:
	if supply_id != &"ammo" or amount <= 0:
		return false
	var accepted := false
	for state in weapon_states:
		if state == null or state.definition == null:
			continue
		accepted = state.add_reserve(state.definition.magazine_size * amount) > 0 or accepted
	return accepted


func fire_hitscan(
	origin: Vector3,
	direction: Vector3,
	aiming_down_sights: bool = false,
	spread_override_degrees: float = -1.0,
) -> bool:
	if not is_alive():
		return false
	var state := current_weapon_state()
	if state == null:
		return false
	if not state.consume_shot():
		if state.magazine_ammo <= 0:
			state.begin_reload()
		return false
	var weapon := state.definition
	var normalized_direction := direction.normalized()
	weapon_fired.emit(combatant_id, weapon.weapon_id, origin, normalized_direction)
	var spread := weapon.ads_spread_degrees if aiming_down_sights else weapon.hip_spread_degrees
	if spread_override_degrees >= 0.0:
		spread = spread_override_degrees
	for _pellet in weapon.pellets_per_shot:
		var shot_direction := _direction_with_spread(normalized_direction, spread)
		_resolve_hitscan_pellet(origin, shot_direction, weapon)
	return true


func fire_at_combatant(target: CombatantController, accuracy: float = 0.75) -> bool:
	if target == null or not target.is_alive() or not is_alive():
		return false
	var state := current_weapon_state()
	if state == null:
		return false
	if not state.consume_shot():
		if state.magazine_ammo <= 0:
			state.begin_reload()
		return false
	var weapon := state.definition
	var origin := get_eye_position()
	var target_point := target.get_eye_position() - Vector3.UP * 0.35
	var direction := origin.direction_to(target_point)
	weapon_fired.emit(combatant_id, weapon.weapon_id, origin, direction)
	if not has_line_of_sight_to(target):
		for _pellet in weapon.pellets_per_shot:
			_emit_trace_from_ray(origin, direction, weapon, [get_rid()])
		return true
	var distance := origin.distance_to(target_point)
	var range_penalty := clampf(distance / maxf(weapon.maximum_range, 1.0), 0.0, 1.0)
	var hit_chance := clampf(accuracy * (1.0 - range_penalty * 0.55), 0.04, 0.98)
	for _pellet in weapon.pellets_per_shot:
		if _rng.randf() > hit_chance:
			var miss_spread := maxf(weapon.hip_spread_degrees, lerpf(8.0, 2.5, accuracy))
			var miss_direction := _direction_with_spread(direction, miss_spread)
			_emit_trace_from_ray(origin, miss_direction, weapon, _combatant_exclusion_rids())
			continue
		var headshot := _rng.randf() < 0.06 + hit_chance * 0.08
		var hit_position := target.get_eye_position() if headshot else target_point
		weapon_trace.emit(
			combatant_id,
			weapon.weapon_id,
			origin,
			hit_position,
			-origin.direction_to(hit_position),
			true,
		)
		var damage := weapon.damage_at_distance(distance, headshot)
		var applied := target.apply_damage(damage, combatant_id, headshot)
		if applied > 0.0:
			weapon_hit_confirmed.emit(target.combatant_id, applied, not target.is_alive(), headshot)
			hit_confirmed.emit(target.combatant_id, applied, not target.is_alive(), headshot)
	return true


func perform_melee(origin: Vector3, direction: Vector3, damage: float = 65.0) -> bool:
	if not is_alive() or get_world_3d() == null:
		return false
	# Every valid melee attempt drives first-person animation and audio; whether
	# the trace connects remains the boolean result of this method.
	melee_performed.emit(combatant_id)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 2.4)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var target := _combatant_from_collider(result.get("collider"))
	if target == null or target == self:
		return false
	var applied := target.apply_damage(damage, combatant_id, false)
	if applied > 0.0:
		hit_confirmed.emit(target.combatant_id, applied, not target.is_alive(), false)
		return true
	return false


func throw_grenade(
	definition: GrenadeDefinition,
	origin: Vector3,
	direction: Vector3,
	parent_override: Node = null,
) -> GrenadeProjectile:
	if definition == null or not is_alive():
		return null
	var projectile := GrenadeProjectile.new()
	projectile.configure(definition, combatant_id, self)
	projectile.position = origin
	var destination_parent := parent_override if parent_override != null else get_parent()
	if destination_parent == null:
		projectile.free()
		return null
	destination_parent.add_child(projectile)
	projectile.global_position = origin
	projectile.linear_velocity = direction.normalized() * definition.throw_speed + velocity * 0.35
	projectile.angular_velocity = Vector3(7.0, 4.0, 3.0)
	grenade_thrown.emit(combatant_id, definition.grenade_id)
	return projectile


func apply_damage(amount: float, attacker_id: StringName, headshot: bool = false) -> float:
	_ensure_health_component()
	return health.apply_damage(amount, attacker_id, headshot)


func apply_status_effect(
	effect_type: int,
	strength: float,
	duration: float,
	_source_id: StringName = &"",
) -> bool:
	if not is_alive() or health.is_protected():
		return false
	var clamped_strength := clampf(strength, 0.0, 1.0)
	if clamped_strength <= 0.0 or duration <= 0.0:
		return false
	match effect_type:
		GrenadeDefinition.GrenadeType.FLASH:
			flash_strength = maxf(flash_strength, clamped_strength)
			flash_remaining = maxf(flash_remaining, duration * clamped_strength)
		GrenadeDefinition.GrenadeType.CONCUSSION:
			concussion_strength = maxf(concussion_strength, clamped_strength)
			concussion_remaining = maxf(concussion_remaining, duration * clamped_strength)
		_:
			return false
	status_effect_applied.emit(effect_type, clamped_strength, duration * clamped_strength)
	return true


func status_movement_scale() -> float:
	return lerpf(1.0, 0.42, concussion_strength)


func status_aim_scale() -> float:
	var combined := maxf(flash_strength, concussion_strength * 0.75)
	return lerpf(1.0, 0.18, combined)


func is_alive() -> bool:
	return health != null and health.is_alive


func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * eye_height


func get_view_direction() -> Vector3:
	return -global_transform.basis.z.normalized()


func is_headshot_position(world_position: Vector3) -> bool:
	return world_position.y >= global_position.y + eye_height * 0.72


func has_line_of_sight_to(target: CombatantController) -> bool:
	if target == null or get_world_3d() == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(get_eye_position(), target.get_eye_position())
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true
	return _combatant_from_collider(result.get("collider")) == target


func respawn_now(at_position: Variant = null) -> void:
	var chosen_position: Vector3
	if at_position is Vector3:
		chosen_position = at_position
	elif spawn_selector.is_valid():
		var selected: Variant = spawn_selector.call(self)
		chosen_position = selected if selected is Vector3 else _choose_safest_spawn()
	else:
		chosen_position = _choose_safest_spawn()
	global_position = chosen_position
	velocity = Vector3.ZERO
	visible = true
	collision_layer = _saved_collision_layer
	collision_mask = _saved_collision_mask
	health.respawn()
	flash_strength = 0.0
	flash_remaining = 0.0
	concussion_strength = 0.0
	concussion_remaining = 0.0
	for state in weapon_states:
		state.refill()
	respawned.emit(combatant_id)


func _choose_safest_spawn() -> Vector3:
	if spawn_points.is_empty():
		return global_position
	if not is_inside_tree():
		return spawn_points[0]
	var safest := spawn_points[0]
	var safest_score := -INF
	for index in spawn_points.size():
		var point := spawn_points[index]
		var nearest_enemy_distance := INF
		var visible_threats := 0
		for node in get_tree().get_nodes_in_group("combatants"):
			var enemy := node as CombatantController
			if enemy == null or enemy == self or not enemy.is_alive():
				continue
			nearest_enemy_distance = minf(nearest_enemy_distance, point.distance_to(enemy.global_position))
			if _spawn_has_line_of_sight(point, enemy):
				visible_threats += 1
		var safe_radius := spawn_safe_radii[index] if index < spawn_safe_radii.size() else 8.0
		var safety_score := nearest_enemy_distance
		if nearest_enemy_distance >= safe_radius:
			safety_score += 10000.0
		if visible_threats == 0:
			safety_score += 1000.0
		else:
			safety_score -= float(visible_threats) * 75.0
		if safety_score > safest_score:
			safest_score = safety_score
			safest = point
	return safest


func _spawn_has_line_of_sight(point: Vector3, enemy: CombatantController) -> bool:
	if get_world_3d() == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * eye_height, enemy.get_eye_position())
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true
	return _combatant_from_collider(result.get("collider")) == enemy


func _ensure_health_component() -> void:
	if health != null:
		return
	for child in get_children():
		if child is HealthComponent:
			health = child
			break
	if health == null:
		health = HealthComponent.new()
		health.name = "HealthComponent"
		add_child(health)
	if not health.killed.is_connected(_on_killed):
		health.killed.connect(_on_killed)
	if not health.health_changed.is_connected(_on_health_changed):
		health.health_changed.connect(_on_health_changed)


func _ensure_collision_shape() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			return
	var collision := CollisionShape3D.new()
	collision.name = "CombatantCollision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)


func _resolve_hitscan_pellet(origin: Vector3, direction: Vector3, weapon: WeaponDefinition) -> void:
	if get_world_3d() == null:
		return
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * weapon.maximum_range)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		weapon_trace.emit(
			combatant_id,
			weapon.weapon_id,
			origin,
			origin + direction * weapon.maximum_range,
			Vector3.ZERO,
			false,
		)
		return
	var hit_position: Vector3 = result.get("position", origin + direction * weapon.maximum_range)
	weapon_trace.emit(
		combatant_id,
		weapon.weapon_id,
		origin,
		hit_position,
		result.get("normal", -direction),
		true,
	)
	var target := _combatant_from_collider(result.get("collider"))
	if target == null or target == self:
		return
	var headshot := target.is_headshot_position(hit_position)
	var damage := weapon.damage_at_distance(origin.distance_to(hit_position), headshot)
	var applied := target.apply_damage(damage, combatant_id, headshot)
	if applied > 0.0:
		weapon_hit_confirmed.emit(target.combatant_id, applied, not target.is_alive(), headshot)
		hit_confirmed.emit(target.combatant_id, applied, not target.is_alive(), headshot)


func _direction_with_spread(direction: Vector3, spread_degrees: float) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	var spread_radians := deg_to_rad(spread_degrees)
	var yaw := _rng.randf_range(-spread_radians, spread_radians)
	var pitch := _rng.randf_range(-spread_radians, spread_radians)
	return direction.rotated(Vector3.UP, yaw).rotated(global_transform.basis.x.normalized(), pitch).normalized()


func _emit_trace_from_ray(
	origin: Vector3,
	direction: Vector3,
	weapon: WeaponDefinition,
	excluded_rids: Array[RID],
) -> void:
	var destination := origin + direction * weapon.maximum_range
	var normal := Vector3.ZERO
	var impacted := false
	if get_world_3d() != null:
		var query := PhysicsRayQueryParameters3D.create(origin, destination)
		query.exclude = excluded_rids
		query.collide_with_areas = false
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		if not result.is_empty():
			destination = result.get("position", destination)
			normal = result.get("normal", -direction)
			impacted = true
	weapon_trace.emit(
		combatant_id,
		weapon.weapon_id,
		origin,
		destination,
		normal,
		impacted,
	)


func _combatant_exclusion_rids() -> Array[RID]:
	var result: Array[RID] = [get_rid()]
	if not is_inside_tree():
		return result
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var combatant := node as CombatantController
		if combatant != null and combatant != self:
			result.append(combatant.get_rid())
	return result


func _combatant_from_collider(collider: Variant) -> CombatantController:
	var node := collider as Node
	while node != null:
		if node is CombatantController:
			return node
		node = node.get_parent()
	return null


func _on_killed(killer_id: StringName) -> void:
	velocity = Vector3.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 0
	_respawn_remaining = respawn_delay
	eliminated.emit(combatant_id, killer_id)


func _on_health_changed(current: float, maximum: float) -> void:
	health_changed.emit(combatant_id, current, maximum)


func _on_weapon_ammo_changed(magazine: int, reserve: int, state: WeaponState) -> void:
	if state == current_weapon_state():
		ammo_changed.emit(combatant_id, magazine, reserve)


func _emit_current_ammo() -> void:
	var state := current_weapon_state()
	if state != null:
		ammo_changed.emit(combatant_id, state.magazine_ammo, state.reserve_ammo)
