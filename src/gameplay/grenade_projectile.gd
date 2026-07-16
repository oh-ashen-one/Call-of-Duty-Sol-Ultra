class_name GrenadeProjectile
extends RigidBody3D

## Physics grenade with radial falloff and shared combatant status-effect API.

signal detonated(grenade_id: StringName, position: Vector3, owner_id: StringName)
signal detonation_started(grenade_id: StringName, owner_id: StringName)
signal combatant_affected(target_id: StringName, strength: float)

var definition: GrenadeDefinition
var owner_id: StringName = &""
var thrower: CombatantController
var fuse_remaining: float = 2.5
var has_detonated: bool = false


func configure(
	grenade: GrenadeDefinition,
	grenade_owner_id: StringName,
	owner_combatant: CombatantController = null,
) -> void:
	definition = grenade
	owner_id = grenade_owner_id
	thrower = owner_combatant
	fuse_remaining = grenade.fuse_seconds


func _ready() -> void:
	add_to_group("grenades")
	if definition == null:
		definition = GrenadeDefinition.create_frag()
		fuse_remaining = definition.fuse_seconds
	_ensure_primitive()
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4


func _physics_process(delta: float) -> void:
	if has_detonated:
		return
	fuse_remaining -= delta
	if fuse_remaining <= 0.0:
		detonate()


func detonate() -> void:
	if has_detonated:
		return
	has_detonated = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	detonation_started.emit(definition.grenade_id, owner_id)
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("combatants"):
			var combatant := node as CombatantController
			if combatant == null or not combatant.is_alive():
				continue
			_affect_combatant(combatant)
	detonated.emit(definition.grenade_id, global_position, owner_id)
	queue_free()


static func radial_factor(distance: float, radius: float) -> float:
	if radius <= 0.0 or distance >= radius:
		return 0.0
	var normalized := clampf(distance / radius, 0.0, 1.0)
	return pow(1.0 - normalized, 1.35)


func _affect_combatant(combatant: CombatantController) -> void:
	var target_position := combatant.get_eye_position()
	var distance := global_position.distance_to(target_position)
	var strength := radial_factor(distance, definition.effect_radius)
	if strength <= 0.0:
		return
	strength *= _line_of_sight_factor(combatant)
	if strength <= 0.02:
		return
	var applied := false
	match definition.grenade_type:
		GrenadeDefinition.GrenadeType.FRAG:
			applied = combatant.apply_damage(definition.maximum_damage * strength, owner_id, false) > 0.0
		GrenadeDefinition.GrenadeType.FLASH:
			var to_grenade := combatant.get_eye_position().direction_to(global_position)
			var facing_factor := remap(
				combatant.get_view_direction().dot(to_grenade), -1.0, 1.0, 0.28, 1.0
			)
			strength *= facing_factor
			applied = combatant.apply_status_effect(
				GrenadeDefinition.GrenadeType.FLASH,
				strength,
				definition.status_duration,
				owner_id,
			)
		GrenadeDefinition.GrenadeType.CONCUSSION:
			var damage_applied := combatant.apply_damage(definition.maximum_damage * strength, owner_id, false) > 0.0
			var status_applied := combatant.apply_status_effect(
				GrenadeDefinition.GrenadeType.CONCUSSION,
				strength,
				definition.status_duration,
				owner_id,
			)
			applied = damage_applied or status_applied
	if applied:
		combatant_affected.emit(combatant.combatant_id, strength)


func _line_of_sight_factor(combatant: CombatantController) -> float:
	if get_world_3d() == null:
		return 1.0
	var query := PhysicsRayQueryParameters3D.create(global_position, combatant.get_eye_position())
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return 1.0
	var collider := result.get("collider") as Node
	while collider != null:
		if collider == combatant:
			return 1.0
		collider = collider.get_parent()
	# Hard cover substantially reduces, but does not entirely erase, blast pressure.
	return 0.16


func _ensure_primitive() -> void:
	var collision := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.11
	collision.shape = sphere_shape
	add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.11
	sphere_mesh.height = 0.22
	mesh_instance.mesh = sphere_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = definition.tint
	material.metallic = 0.65
	material.roughness = 0.28
	mesh_instance.material_override = material
	add_child(mesh_instance)
