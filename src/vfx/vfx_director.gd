class_name VFXDirector
extends Node3D

## Small, deterministic effects layer built entirely from Godot primitives.

const SEA_GLASS := Color("5ed3c6")
const CORAL := Color("ff6b4a")
const SUN_GOLD := Color("f2c14e")

var effects_enabled := true
var max_transient_effects := 48
var dynamic_effect_lights := true


func _ready() -> void:
	add_to_group(&"quality_vfx")


func set_quality(quality: String) -> void:
	match quality:
		"low":
			max_transient_effects = 14
			dynamic_effect_lights = false
		"medium":
			max_transient_effects = 28
			dynamic_effect_lights = false
		_:
			max_transient_effects = 48
			dynamic_effect_lights = true


func spawn_weapon_flash(origin: Vector3, direction: Vector3, tint: Color = SUN_GOLD) -> void:
	if not effects_enabled or not _has_effect_capacity():
		return
	var flash := MeshInstance3D.new()
	flash.name = "MuzzleFlash"
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.18
	flash.mesh = mesh
	flash.material_override = _emissive_material(tint, 4.5)
	add_child(flash)
	flash.global_position = origin + direction.normalized() * 0.18
	var light: OmniLight3D
	if dynamic_effect_lights:
		light = OmniLight3D.new()
		light.light_color = tint
		light.light_energy = 2.4
		light.omni_range = 3.5
		flash.add_child(light)
	var tween := flash.create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ZERO, 0.075).set_trans(Tween.TRANS_QUAD)
	if light != null:
		tween.tween_property(light, "light_energy", 0.0, 0.06)
	tween.chain().tween_callback(flash.queue_free)


func spawn_tracer(origin: Vector3, destination: Vector3, tint: Color = SEA_GLASS) -> void:
	if not effects_enabled or not _has_effect_capacity():
		return
	var distance := origin.distance_to(destination)
	if distance <= 0.05:
		return
	var tracer := MeshInstance3D.new()
	tracer.name = "Tracer"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.018, distance)
	tracer.mesh = mesh
	tracer.material_override = _emissive_material(tint, 5.0)
	add_child(tracer)
	tracer.global_position = origin.lerp(destination, 0.5)
	tracer.look_at(destination, Vector3.UP)
	tracer.scale = Vector3(1.0, 1.0, 0.04)
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "scale:z", 1.0, 0.045).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.025)
	tween.tween_property(tracer, "scale", Vector3(0.0, 0.0, 1.0), 0.075)
	tween.tween_callback(tracer.queue_free)


func spawn_impact(position: Vector3, normal: Vector3 = Vector3.UP, critical := false) -> void:
	if not effects_enabled or not _has_effect_capacity():
		return
	var root := Node3D.new()
	root.name = "CriticalImpact" if critical else "Impact"
	add_child(root)
	root.global_position = position
	var tint := CORAL if critical else SUN_GOLD
	for index in 6:
		var spark := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.018
		mesh.height = 0.05
		spark.mesh = mesh
		spark.material_override = _emissive_material(tint, 3.2)
		root.add_child(spark)
		var angle := TAU * float(index) / 6.0
		var tangent := Vector3(cos(angle), 0.35 + 0.2 * (index % 2), sin(angle))
		if normal.length_squared() > 0.1:
			tangent = (tangent + normal * 0.55).normalized()
		var tween := spark.create_tween().set_parallel(true)
		tween.tween_property(spark, "position", tangent * (0.4 + index * 0.05), 0.22)
		tween.tween_property(spark, "scale", Vector3.ZERO, 0.22)
	var cleanup := root.create_tween()
	cleanup.tween_interval(0.25)
	cleanup.tween_callback(root.queue_free)


func spawn_explosion(position: Vector3, tactical := false, tactical_tint: Color = SEA_GLASS) -> void:
	if not effects_enabled or not _has_effect_capacity():
		return
	var root := Node3D.new()
	root.name = "TacticalBurst" if tactical else "Explosion"
	add_child(root)
	root.global_position = position
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	sphere.mesh = mesh
	var tint := tactical_tint if tactical else CORAL
	sphere.material_override = _emissive_material(tint, 5.5)
	sphere.scale = Vector3.ONE * 0.08
	root.add_child(sphere)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	ring.mesh = torus
	ring.material_override = _emissive_material(SUN_GOLD if not tactical else tint, 4.0)
	root.add_child(ring)
	var light: OmniLight3D
	if dynamic_effect_lights:
		light = OmniLight3D.new()
		light.light_color = tint
		light.light_energy = 7.0
		light.omni_range = 9.0
		root.add_child(light)
	var tween := root.create_tween().set_parallel(true)
	tween.tween_property(sphere, "scale", Vector3.ONE * (2.2 if tactical else 1.45), 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "scale", Vector3.ONE * 4.5, 0.48).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	if light != null:
		tween.tween_property(light, "light_energy", 0.0, 0.38)
	tween.chain().tween_callback(root.queue_free)


func spawn_respawn_beacon(position: Vector3, tint: Color = SEA_GLASS) -> void:
	if not effects_enabled or not _has_effect_capacity():
		return
	var ring := MeshInstance3D.new()
	ring.name = "RespawnBeacon"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.5
	mesh.outer_radius = 0.55
	ring.mesh = mesh
	ring.material_override = _emissive_material(tint, 2.5)
	add_child(ring)
	ring.global_position = position + Vector3.UP * 0.04
	ring.scale = Vector3.ONE * 0.1
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 3.0, 0.65).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "position:y", ring.position.y + 0.5, 0.65)
	tween.chain().tween_callback(ring.queue_free)


func clear_transient_effects() -> void:
	for child in get_children():
		child.queue_free()


func _has_effect_capacity() -> bool:
	return get_child_count() < max_transient_effects


func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
