class_name WeaponCatalog
extends RefCounted

## Original Project Breakwater arsenal. Keeping the values here makes loadout/UI
## construction deterministic and avoids scene-specific weapon tuning.


static func create_all() -> Array[WeaponDefinition]:
	var weapons: Array[WeaponDefinition] = [
		_make_weapon(
			&"vx4_carbine", "VX-4 Carbine", WeaponDefinition.WeaponClass.ASSAULT_RIFLE,
			28.0, 720.0, 30, 120, 2.15, true, 1, 1.35, 0.22, 0.72, 0.25,
			22.0, 62.0, 0.55, 130.0, 1.0, Color("476f88")
		),
		_make_weapon(
			&"kestrel_smg", "Kestrel SMG", WeaponDefinition.WeaponClass.SMG,
			22.0, 900.0, 36, 144, 1.8, true, 1, 1.8, 0.38, 0.52, 0.34,
			12.0, 38.0, 0.48, 95.0, 1.08, Color("6f7d83")
		),
		_make_weapon(
			&"breaker_12", "Breaker-12", WeaponDefinition.WeaponClass.SHOTGUN,
			14.0, 78.0, 8, 40, 2.75, false, 8, 5.4, 3.2, 1.65, 0.65,
			7.0, 23.0, 0.28, 52.0, 0.94, Color("89614a")
		),
		_make_weapon(
			&"helix_dmr", "Helix DMR", WeaponDefinition.WeaponClass.DMR,
			48.0, 300.0, 14, 70, 2.35, false, 1, 1.15, 0.08, 1.35, 0.32,
			38.0, 96.0, 0.68, 180.0, 0.93, Color("68795a")
		),
		_make_weapon(
			&"atlas_lmg", "Atlas LMG", WeaponDefinition.WeaponClass.LMG,
			31.0, 610.0, 72, 216, 4.45, true, 1, 2.05, 0.42, 0.95, 0.42,
			28.0, 78.0, 0.62, 145.0, 0.82, Color("6f6450")
		),
		_make_weapon(
			&"sparrow_pistol", "Sparrow Pistol", WeaponDefinition.WeaponClass.PISTOL,
			30.0, 420.0, 15, 60, 1.45, false, 1, 1.65, 0.3, 0.8, 0.3,
			16.0, 46.0, 0.5, 90.0, 1.12, Color("555b65")
		),
	]
	var shotgun := weapons[2]
	shotgun.pump_action = true
	shotgun.pump_seconds = 0.62
	shotgun.reload_one_shell_at_a_time = true
	shotgun.shell_insert_seconds = 0.58
	return weapons


static func get_weapon(weapon_id: StringName) -> WeaponDefinition:
	for weapon in create_all():
		if weapon.weapon_id == weapon_id:
			return weapon
	return null


static func default_loadout() -> Array[WeaponDefinition]:
	return [get_weapon(&"vx4_carbine"), get_weapon(&"sparrow_pistol")]


static func _make_weapon(
	id: StringName,
	label: String,
	category: WeaponDefinition.WeaponClass,
	damage: float,
	rpm: float,
	magazine: int,
	reserve: int,
	reload_time: float,
	is_automatic: bool,
	pellets: int,
	hip_spread: float,
	ads_spread: float,
	pitch_recoil: float,
	yaw_recoil: float,
	falloff_near: float,
	falloff_far: float,
	min_damage: float,
	max_range: float,
	move_scale: float,
	model_color: Color,
) -> WeaponDefinition:
	var weapon := WeaponDefinition.new()
	weapon.weapon_id = id
	weapon.display_name = label
	weapon.weapon_class = category
	weapon.base_damage = damage
	weapon.rounds_per_minute = rpm
	weapon.magazine_size = magazine
	weapon.starting_reserve = reserve
	weapon.reload_seconds = reload_time
	weapon.automatic = is_automatic
	weapon.pellets_per_shot = pellets
	weapon.hip_spread_degrees = hip_spread
	weapon.ads_spread_degrees = ads_spread
	weapon.recoil_pitch = pitch_recoil
	weapon.recoil_yaw = yaw_recoil
	weapon.falloff_start = falloff_near
	weapon.falloff_end = falloff_far
	weapon.minimum_damage_ratio = min_damage
	weapon.maximum_range = max_range
	weapon.movement_speed_scale = move_scale
	weapon.view_model_color = model_color
	return weapon
