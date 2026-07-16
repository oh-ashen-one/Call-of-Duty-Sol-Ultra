class_name GrenadeDefinition
extends Resource

enum GrenadeType {
	FRAG,
	FLASH,
	CONCUSSION,
}

@export var grenade_id: StringName = &"frag"
@export var display_name: String = "Arc Fragmentation Grenade"
@export var grenade_type: GrenadeType = GrenadeType.FRAG
@export_range(0.1, 10.0, 0.05) var fuse_seconds: float = 2.6
@export_range(0.5, 50.0, 0.5) var effect_radius: float = 8.0
@export_range(0.0, 500.0, 1.0) var maximum_damage: float = 145.0
@export_range(0.0, 30.0, 0.1) var status_duration: float = 0.0
@export_range(1.0, 40.0, 0.5) var throw_speed: float = 15.5
@export var tint: Color = Color("526b59")


static func create_frag() -> GrenadeDefinition:
	var grenade := GrenadeDefinition.new()
	grenade.grenade_id = &"frag"
	grenade.display_name = "Arc Fragmentation Grenade"
	grenade.grenade_type = GrenadeType.FRAG
	grenade.fuse_seconds = 2.6
	grenade.effect_radius = 8.5
	grenade.maximum_damage = 145.0
	grenade.status_duration = 0.0
	grenade.throw_speed = 15.5
	grenade.tint = Color("536956")
	return grenade


static func create_flash() -> GrenadeDefinition:
	var grenade := GrenadeDefinition.new()
	grenade.grenade_id = &"flash"
	grenade.display_name = "Lumen Flash Grenade"
	grenade.grenade_type = GrenadeType.FLASH
	grenade.fuse_seconds = 1.45
	grenade.effect_radius = 13.0
	grenade.maximum_damage = 0.0
	grenade.status_duration = 4.5
	grenade.throw_speed = 16.5
	grenade.tint = Color("d7d9c5")
	return grenade


static func create_concussion() -> GrenadeDefinition:
	var grenade := GrenadeDefinition.new()
	grenade.grenade_id = &"concussion"
	grenade.display_name = "Pulse Concussion Grenade"
	grenade.grenade_type = GrenadeType.CONCUSSION
	grenade.fuse_seconds = 1.7
	grenade.effect_radius = 10.0
	grenade.maximum_damage = 10.0
	grenade.status_duration = 5.0
	grenade.throw_speed = 16.0
	grenade.tint = Color("4aa4aa")
	return grenade


static func create_all() -> Array[GrenadeDefinition]:
	return [create_frag(), create_flash(), create_concussion()]


static func get_grenade(grenade_id: StringName) -> GrenadeDefinition:
	for grenade in create_all():
		if grenade.grenade_id == grenade_id:
			return grenade
	return null
