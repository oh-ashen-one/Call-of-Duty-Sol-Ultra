class_name WeaponPickup
extends Area3D

signal collected(collector_id: StringName, weapon_id: StringName)
signal became_available(weapon_id: StringName)

@export var definition: WeaponDefinition
@export var pickup_kind: StringName = &"weapon"
@export var supply_id: StringName = &""
@export_range(0.0, 120.0, 0.5) var respawn_seconds: float = 15.0
@export_range(0.0, 4.0, 0.05) var bob_height: float = 0.18
@export_range(0.0, 8.0, 0.05) var spin_speed: float = 1.1

var is_available: bool = true
var _respawn_remaining: float = 0.0
var _base_y: float = 0.0
var _age: float = 0.0


func configure(weapon: WeaponDefinition, pickup_respawn_seconds: float = 15.0) -> void:
	pickup_kind = &"weapon"
	definition = weapon
	respawn_seconds = pickup_respawn_seconds


func configure_supply(id: StringName, pickup_respawn_seconds: float = 15.0) -> void:
	pickup_kind = &"supply"
	supply_id = id
	definition = null
	respawn_seconds = pickup_respawn_seconds


func _ready() -> void:
	add_to_group(&"field_pickups")
	if pickup_kind == &"weapon":
		add_to_group(&"weapon_pickups")
	if pickup_kind == &"weapon" and definition == null:
		definition = WeaponCatalog.get_weapon(&"vx4_carbine")
	_base_y = position.y
	_ensure_primitive()
	body_entered.connect(_on_body_entered)
	monitoring = true


func _process(delta: float) -> void:
	_age += delta
	if is_available:
		rotation.y += spin_speed * delta
		position.y = _base_y + sin(_age * 2.0) * bob_height
		return
	_respawn_remaining = maxf(_respawn_remaining - delta, 0.0)
	if _respawn_remaining <= 0.0:
		is_available = true
		visible = true
		monitoring = true
		became_available.emit(item_id())


func try_collect(body: Node) -> bool:
	if not is_available or body == null:
		return false
	var accepted: Variant = false
	if pickup_kind == &"weapon":
		if definition == null or not body.has_method("pickup_weapon"):
			return false
		accepted = body.call("pickup_weapon", definition)
	elif pickup_kind == &"supply":
		if supply_id.is_empty() or not body.has_method("receive_supply"):
			return false
		accepted = body.call("receive_supply", supply_id, 1)
	if accepted != true:
		return false
	var collector_id := StringName(str(body.get("combatant_id")))
	collected.emit(collector_id, item_id())
	if respawn_seconds <= 0.0:
		queue_free()
	else:
		is_available = false
		visible = false
		set_deferred(&"monitoring", false)
		_respawn_remaining = respawn_seconds
	return true


func _on_body_entered(body: Node3D) -> void:
	# Players confirm weapon replacements with Interact; autonomous combatants
	# and all combatants collect field supplies by contact.
	if body is PlayerController and pickup_kind == &"weapon":
		return
	try_collect(body)


func item_id() -> StringName:
	return definition.weapon_id if pickup_kind == &"weapon" and definition != null else supply_id


func display_name() -> String:
	if pickup_kind == &"weapon" and definition != null:
		return definition.display_name
	var names := {
		&"ammo": "AMMUNITION",
		&"frag": "FRAG GRENADE",
		&"flash": "LUMEN FLASH",
		&"concussion": "PULSE CONCUSSION",
	}
	return String(names.get(supply_id, String(supply_id).to_upper()))


func _ensure_primitive() -> void:
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(1.15, 0.35, 0.45)
	collision.shape = box_shape
	add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.05, 0.22, 0.28)
	mesh_instance.mesh = box_mesh
	var material := StandardMaterial3D.new()
	var supply_colors := {
		&"ammo": Color("f2c14e"),
		&"frag": Color("ff6b4a"),
		&"flash": Color("5ed3c6"),
		&"concussion": Color("7e6edb"),
	}
	var tint: Color = definition.view_model_color if pickup_kind == &"weapon" and definition != null else supply_colors.get(supply_id, Color("f2c14e"))
	material.albedo_color = tint
	material.metallic = 0.72
	material.roughness = 0.25
	material.emission_enabled = true
	material.emission = tint * 0.22
	mesh_instance.material_override = material
	add_child(mesh_instance)
