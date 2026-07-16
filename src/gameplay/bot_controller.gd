class_name BotController
extends CombatantController

## Autonomous free-for-all opponent. Bots discover every living member of the
## `combatants` group, including other bots, so their match continues unattended.

enum BotState {
	PATROL,
	SEEK_PICKUP,
	CHASE,
	ENGAGE,
}

@export_range(0.0, 1.0, 0.01) var skill: float = 0.68
@export_range(1.0, 20.0, 0.1) var movement_speed: float = 5.6
@export_range(2.0, 250.0, 1.0) var awareness_range: float = 95.0
@export_range(1.0, 100.0, 1.0) var preferred_engagement_range: float = 24.0
@export_range(0.05, 2.0, 0.05) var thinking_interval: float = 0.28
@export_range(0.0, 1.0, 0.01) var grenade_aggression: float = 0.28
@export_range(0, 2, 1) var skin_index: int = 0
@export var auto_select_loadout: bool = true
@export var ai_enabled: bool = true

var target: CombatantController
var navigation_agent: NavigationAgent3D
var bot_state: BotState = BotState.PATROL
var navigation_points: Array[Vector3] = []
var navigation_links: Array[Vector2i] = []

var _think_remaining: float = 0.0
var _grenade_cooldown: float = 4.0
var _pickup_seek_remaining: float = 0.0
var _pickup_reconsider_remaining: float = 0.0
var _strafe_sign: float = 1.0
var _patrol_destination: Vector3 = Vector3.ZERO
var _desired_pickup: WeaponPickup
var _bot_rng := RandomNumberGenerator.new()
var _gravity: float = 9.8
var _route_graph := AStar3D.new()
var _body_material: StandardMaterial3D
var _visor_material: StandardMaterial3D
var _base_body_color := Color.WHITE
var _base_visor_color := Color.WHITE
var _weapon_visual: Node3D


func _ready() -> void:
	is_player_controlled = false
	super._ready()
	_bot_rng.seed = hash(str(combatant_id)) * 31 + 17
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	if auto_select_loadout:
		_assign_distinct_loadout()
	_ensure_navigation_agent()
	_ensure_bot_visuals()
	if not weapon_changed.is_connected(_on_bot_weapon_changed):
		weapon_changed.connect(_on_bot_weapon_changed)
	_rebuild_bot_weapon(current_weapon())
	_choose_patrol_destination()


func _process(delta: float) -> void:
	super._process(delta)
	_update_status_visuals()


func _physics_process(delta: float) -> void:
	# Match completion can disable the arena synchronously from inside this
	# bot's weapon hit callback. Do not touch the physics body after its parent
	# has stopped processing, including later callbacks already queued by Godot.
	if not is_inside_tree() or not can_process():
		velocity = Vector3.ZERO
		return
	if not ai_enabled or not is_alive():
		velocity.x = move_toward(velocity.x, 0.0, delta * 12.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 12.0)
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		return
	_think_remaining -= delta
	_grenade_cooldown = maxf(_grenade_cooldown - delta, 0.0)
	_pickup_seek_remaining = maxf(_pickup_seek_remaining - delta, 0.0)
	_pickup_reconsider_remaining = maxf(_pickup_reconsider_remaining - delta, 0.0)
	if _think_remaining <= 0.0:
		_think_remaining = thinking_interval * _bot_rng.randf_range(0.8, 1.2)
		_update_decision()
	_execute_movement(delta)
	_execute_combat()
	if not ai_enabled or not can_process():
		velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


func set_ai_enabled(enabled: bool) -> void:
	ai_enabled = enabled


func receive_supply(supply_id: StringName, amount: int = 1) -> bool:
	if supply_id == &"ammo":
		return super.receive_supply(supply_id, amount)
	if supply_id not in [&"frag", &"flash", &"concussion"] or amount <= 0:
		return false
	if _grenade_cooldown <= 1.0:
		return false
	_grenade_cooldown = maxf(0.0, _grenade_cooldown - 6.0 * amount)
	return true


func set_navigation_route(points: Array[Vector3], links: Array[Vector2i]) -> void:
	navigation_points = points.duplicate()
	navigation_links = links.duplicate()
	_rebuild_route_graph()


func navigation_waypoint_count() -> int:
	return navigation_points.size()


func navigation_connection_count() -> int:
	return navigation_links.size()


func route_path_to(destination: Vector3) -> PackedVector3Array:
	if _route_graph.get_point_count() == 0:
		return PackedVector3Array()
	var start_id := _route_graph.get_closest_point(global_position)
	var destination_id := _route_graph.get_closest_point(destination)
	if start_id < 0 or destination_id < 0:
		return PackedVector3Array()
	return _route_graph.get_point_path(start_id, destination_id)


func _update_decision() -> void:
	# Refresh the opponent on every think tick. A permanently sticky target can
	# strand an FFA bot behind geometry while nearby opponents keep fighting.
	target = _select_target()
	if _desired_pickup != null:
		if not is_instance_valid(_desired_pickup) or not _desired_pickup.is_available:
			_desired_pickup = null
		elif _pickup_seek_remaining <= 0.0:
			_desired_pickup = null
			# Spend time fighting or patrolling before considering another pickup;
			# otherwise low reserve ammo can immediately reselect an unreachable item.
			_pickup_reconsider_remaining = 7.0
	var target_is_immediate := target != null \
		and global_position.distance_to(target.global_position) <= preferred_engagement_range * 1.5 \
		and has_line_of_sight_to(target)
	if target_is_immediate:
		_desired_pickup = null
	var state := current_weapon_state()
	var needs_ammo := state != null and state.reserve_ammo < state.definition.magazine_size
	if _desired_pickup == null \
		and _pickup_reconsider_remaining <= 0.0 \
		and not target_is_immediate \
		and (needs_ammo or _bot_rng.randf() < 0.08):
		_desired_pickup = _select_nearby_pickup()
		if _desired_pickup != null:
			_pickup_seek_remaining = 7.0
	if _desired_pickup != null:
		bot_state = BotState.SEEK_PICKUP
		return
	if target == null:
		bot_state = BotState.PATROL
		return
	var distance := global_position.distance_to(target.global_position)
	bot_state = BotState.ENGAGE if distance <= preferred_engagement_range * 1.35 else BotState.CHASE
	_select_weapon_for_distance(distance)


func _execute_movement(delta: float) -> void:
	var destination := _patrol_destination
	match bot_state:
		BotState.SEEK_PICKUP:
			if _desired_pickup != null:
				destination = _desired_pickup.global_position
				if global_position.distance_to(destination) < 1.6:
					_desired_pickup.try_collect(self)
					_desired_pickup = null
					_pickup_seek_remaining = 0.0
		BotState.CHASE:
			if target != null:
				destination = target.global_position
		BotState.ENGAGE:
			if target != null:
				var to_target := global_position.direction_to(target.global_position)
				var side := to_target.cross(Vector3.UP).normalized() * _strafe_sign
				destination = global_position + side * 5.0 - to_target * 1.2
				if _bot_rng.randf() < 0.012:
					_strafe_sign *= -1.0
		BotState.PATROL:
			if global_position.distance_to(destination) < 2.0:
				_choose_patrol_destination()
				destination = _patrol_destination
	var direction := _navigation_direction(destination)
	var target_speed := movement_speed * status_movement_scale()
	if bot_state == BotState.ENGAGE:
		target_speed *= 0.72
	var desired_velocity := direction * target_speed
	velocity.x = move_toward(velocity.x, desired_velocity.x, delta * 18.0)
	velocity.z = move_toward(velocity.z, desired_velocity.z, delta * 18.0)
	if direction.length_squared() > 0.01:
		var facing_position := global_position + direction
		if target != null and bot_state == BotState.ENGAGE:
			facing_position = target.global_position
		var flat_target := Vector3(facing_position.x, global_position.y, facing_position.z)
		look_at(flat_target, Vector3.UP)


func _execute_combat() -> void:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return
	var distance := global_position.distance_to(target.global_position)
	if distance > awareness_range or not has_line_of_sight_to(target):
		return
	var accuracy := lerpf(0.44, 0.9, skill) * status_aim_scale()
	# Movement and target motion keep bots fair while still deadly at high skill.
	accuracy *= 0.9 if velocity.length_squared() > 4.0 else 1.0
	fire_at_combatant(target, accuracy)
	if _grenade_cooldown <= 0.0 \
		and distance > 6.0 \
		and distance < 24.0 \
		and _bot_rng.randf() < grenade_aggression * 0.035:
		var grenade_ids: Array[StringName] = [&"frag", &"flash", &"concussion"]
		var grenade_id := grenade_ids[_bot_rng.randi_range(0, grenade_ids.size() - 1)]
		var grenade := GrenadeDefinition.get_grenade(grenade_id)
		var direction := (get_eye_position().direction_to(target.get_eye_position()) + Vector3.UP * 0.28).normalized()
		throw_grenade(grenade, get_eye_position() + direction * 0.55, direction)
		_grenade_cooldown = _bot_rng.randf_range(8.0, 15.0)


func _select_target() -> CombatantController:
	if not is_inside_tree():
		return null
	var best: CombatantController
	var best_score := INF
	for node in get_tree().get_nodes_in_group("combatants"):
		var candidate := node as CombatantController
		if candidate == null or candidate == self or not candidate.is_alive():
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance > awareness_range:
			continue
		var selection_score := distance
		if has_line_of_sight_to(candidate):
			selection_score *= 0.62
		selection_score *= _bot_rng.randf_range(0.88, 1.12)
		if selection_score < best_score:
			best_score = selection_score
			best = candidate
	return best


func _select_nearby_pickup() -> WeaponPickup:
	if not is_inside_tree():
		return null
	var nearest: WeaponPickup
	var nearest_distance := 20.0
	for node in get_tree().get_nodes_in_group(&"field_pickups"):
		var pickup := node as WeaponPickup
		if pickup == null or not pickup.is_available or not _pickup_is_useful(pickup):
			continue
		var distance := global_position.distance_to(pickup.global_position)
		if distance < nearest_distance:
			nearest = pickup
			nearest_distance = distance
	return nearest


func _pickup_is_useful(pickup: WeaponPickup) -> bool:
	if pickup.pickup_kind == &"weapon":
		if pickup.definition == null:
			return false
		for state in weapon_states:
			if state.definition.weapon_id == pickup.definition.weapon_id:
				return state.reserve_ammo < state.definition.starting_reserve
		return true
	if pickup.supply_id == &"ammo":
		for state in weapon_states:
			if state.reserve_ammo < state.definition.starting_reserve:
				return true
		return false
	if pickup.supply_id in [&"frag", &"flash", &"concussion"]:
		return _grenade_cooldown > 1.0
	return false


func _select_weapon_for_distance(distance: float) -> void:
	if weapon_states.size() < 2:
		return
	var best_index := active_weapon_index
	var best_score := INF
	for index in weapon_states.size():
		var definition := weapon_states[index].definition
		var ideal_range := (definition.falloff_start + definition.falloff_end) * 0.4
		if definition.weapon_class == WeaponDefinition.WeaponClass.SHOTGUN:
			ideal_range = 8.0
		var score := absf(distance - ideal_range)
		if weapon_states[index].magazine_ammo <= 0 and weapon_states[index].reserve_ammo <= 0:
			score += 1000.0
		if score < best_score:
			best_score = score
			best_index = index
	switch_weapon(best_index)


func _navigation_direction(destination: Vector3) -> Vector3:
	var next_position := destination
	var route_path := route_path_to(destination)
	if global_position.distance_to(destination) > 7.0 and not route_path.is_empty():
		var path_index := 0
		var first_waypoint_delta := route_path[0] - global_position
		first_waypoint_delta.y = 0.0
		if first_waypoint_delta.length() < 6.0 and route_path.size() > 1:
			path_index = 1
		next_position = route_path[path_index]
	elif navigation_agent != null and navigation_agent.is_inside_tree():
		navigation_agent.target_position = destination
		if not navigation_agent.is_navigation_finished():
			var candidate := navigation_agent.get_next_path_position()
			if candidate.distance_squared_to(global_position) > 0.01:
				next_position = candidate
	var flat_delta := next_position - global_position
	flat_delta.y = 0.0
	return _steer_around_obstacle(flat_delta.normalized())


func _choose_patrol_destination() -> void:
	if not navigation_points.is_empty():
		_patrol_destination = navigation_points[_bot_rng.randi_range(0, navigation_points.size() - 1)]
	elif not spawn_points.is_empty():
		_patrol_destination = spawn_points[_bot_rng.randi_range(0, spawn_points.size() - 1)]
	else:
		_patrol_destination = global_position + Vector3(
			_bot_rng.randf_range(-18.0, 18.0),
			0.0,
			_bot_rng.randf_range(-18.0, 18.0),
		)


func _rebuild_route_graph() -> void:
	_route_graph.clear()
	for index in navigation_points.size():
		_route_graph.add_point(index, navigation_points[index])
	for link in navigation_links:
		if link.x < 0 or link.y < 0 \
			or link.x >= navigation_points.size() \
			or link.y >= navigation_points.size() \
			or _route_graph.are_points_connected(link.x, link.y):
			continue
		_route_graph.connect_points(link.x, link.y, true)


func _steer_around_obstacle(direction: Vector3) -> Vector3:
	if direction.is_zero_approx() or get_world_3d() == null:
		return direction
	var origin := global_position + Vector3.UP * 0.65
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 1.8)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return direction
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	# Ramps are walkable floor, not avoidance obstacles. Treating their sloped
	# normals like walls makes bots sidestep off the authored vertical routes.
	if normal.y > 0.62:
		return direction
	normal.y = 0.0
	if normal.length_squared() < 0.01:
		return direction.rotated(Vector3.UP, _strafe_sign * PI * 0.5)
	var slide := direction.slide(normal.normalized())
	if slide.length_squared() < 0.04:
		slide = direction.rotated(Vector3.UP, _strafe_sign * PI * 0.5)
	return slide.normalized()


func _assign_distinct_loadout() -> void:
	var arsenal := WeaponCatalog.create_all()
	var id_parts := String(combatant_id).split("_")
	var roster_index := absi(hash(str(combatant_id)))
	if not id_parts.is_empty() and String(id_parts[-1]).is_valid_int():
		roster_index = maxi(String(id_parts[-1]).to_int() - 1, 0)
	var primary_index := posmod(roster_index, arsenal.size() - 1)
	set_loadout([arsenal[primary_index], WeaponCatalog.get_weapon(&"sparrow_pistol")])


func _ensure_navigation_agent() -> void:
	navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if navigation_agent == null:
		navigation_agent = NavigationAgent3D.new()
		navigation_agent.name = "NavigationAgent3D"
		navigation_agent.path_height_offset = 0.0
		navigation_agent.radius = 0.48
		navigation_agent.path_desired_distance = 0.75
		navigation_agent.target_desired_distance = 2.0
		navigation_agent.avoidance_enabled = true
		add_child(navigation_agent)


func _ensure_bot_visuals() -> void:
	if get_node_or_null("BotBody") != null:
		return
	var skin_colors: Array[Color] = [Color("2d7886"), Color("a86145"), Color("718449")]
	var accent_colors: Array[Color] = [Color("e3b75f"), Color("4cc2b5"), Color("d26b84")]
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "BotBody"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.35
	body_mesh.mesh = capsule
	body_mesh.position.y = 0.82
	_body_material = StandardMaterial3D.new()
	_base_body_color = skin_colors[posmod(skin_index, skin_colors.size())]
	_body_material.albedo_color = _base_body_color
	_body_material.metallic = 0.18
	_body_material.roughness = 0.66
	body_mesh.material_override = _body_material
	add_child(body_mesh)
	var visor := MeshInstance3D.new()
	visor.name = "BotVisor"
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.38, 0.16, 0.12)
	visor.mesh = visor_mesh
	visor.position = Vector3(0.0, 1.53, -0.29)
	_visor_material = StandardMaterial3D.new()
	_base_visor_color = accent_colors[posmod(skin_index, accent_colors.size())]
	_visor_material.albedo_color = _base_visor_color
	_visor_material.emission_enabled = true
	_visor_material.emission = _base_visor_color * 0.45
	visor.material_override = _visor_material
	add_child(visor)


func _on_bot_weapon_changed(_actor_id: StringName, weapon: WeaponDefinition) -> void:
	_rebuild_bot_weapon(weapon)


func _rebuild_bot_weapon(weapon: WeaponDefinition) -> void:
	if weapon == null:
		return
	if is_instance_valid(_weapon_visual):
		remove_child(_weapon_visual)
		_weapon_visual.queue_free()
	_weapon_visual = Node3D.new()
	_weapon_visual.name = "EquippedWeapon"
	_weapon_visual.position = Vector3(0.34, 1.02, -0.34)
	_weapon_visual.rotation = Vector3(deg_to_rad(-8.0), 0.0, 0.0)
	add_child(_weapon_visual)
	var length := 0.68
	var width := 0.15
	match weapon.weapon_class:
		WeaponDefinition.WeaponClass.SMG: length = 0.48
		WeaponDefinition.WeaponClass.SHOTGUN: length = 0.82
		WeaponDefinition.WeaponClass.DMR: length = 0.9
		WeaponDefinition.WeaponClass.LMG:
			length = 0.78
			width = 0.22
		WeaponDefinition.WeaponClass.PISTOL:
			length = 0.28
			width = 0.1
	_add_bot_weapon_box("Receiver", Vector3(width, 0.14, length), Vector3.ZERO, weapon.view_model_color)
	_add_bot_weapon_box("Barrel", Vector3(0.055, 0.055, length * 0.52), Vector3(0.0, 0.01, -length * 0.7), Color("18232a"))


func _add_bot_weapon_box(node_name: String, size: Vector3, at: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.52
	material.roughness = 0.38
	instance.material_override = material
	_weapon_visual.add_child(instance)


func _update_status_visuals() -> void:
	if _body_material == null or _visor_material == null:
		return
	var flash_tint := Color("f4ffff")
	var concussion_tint := Color("9b78ff")
	var effect_strength := maxf(flash_strength, concussion_strength)
	var effect_tint := flash_tint if flash_strength >= concussion_strength else concussion_tint
	_body_material.albedo_color = _base_body_color.lerp(effect_tint, effect_strength * 0.7)
	_body_material.emission_enabled = effect_strength > 0.01
	_body_material.emission = effect_tint * effect_strength * 0.65
	_visor_material.albedo_color = _base_visor_color.lerp(effect_tint, effect_strength)
	_visor_material.emission = _visor_material.albedo_color * (0.45 + effect_strength * 1.8)
