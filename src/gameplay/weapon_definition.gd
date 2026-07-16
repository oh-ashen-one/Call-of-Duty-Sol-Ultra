class_name WeaponDefinition
extends Resource

## Data-only description of a firearm. Runtime magazine and cooldown state lives in
## WeaponState, so one definition can safely be shared by every combatant.

enum WeaponClass {
	ASSAULT_RIFLE,
	SMG,
	SHOTGUN,
	DMR,
	LMG,
	PISTOL,
}

@export var weapon_id: StringName = &"rifle"
@export var display_name: String = "VX-4 Carbine"
@export var weapon_class: WeaponClass = WeaponClass.ASSAULT_RIFLE
@export var automatic: bool = true
@export_range(1.0, 200.0, 0.5) var base_damage: float = 28.0
@export_range(1.0, 4.0, 0.05) var headshot_multiplier: float = 1.55
@export_range(0.0, 500.0, 0.5) var falloff_start: float = 22.0
@export_range(0.0, 500.0, 0.5) var falloff_end: float = 58.0
@export_range(0.05, 1.0, 0.01) var minimum_damage_ratio: float = 0.55
@export_range(30.0, 1500.0, 1.0) var rounds_per_minute: float = 720.0
@export_range(1, 20, 1) var pellets_per_shot: int = 1
@export_range(0.0, 15.0, 0.05) var hip_spread_degrees: float = 1.4
@export_range(0.0, 10.0, 0.05) var ads_spread_degrees: float = 0.25
@export_range(0.0, 8.0, 0.05) var recoil_pitch: float = 0.75
@export_range(0.0, 5.0, 0.05) var recoil_yaw: float = 0.28
@export_range(1, 200, 1) var magazine_size: int = 30
@export_range(0, 1000, 1) var starting_reserve: int = 120
@export_range(0.1, 10.0, 0.05) var reload_seconds: float = 2.15
@export var pump_action: bool = false
@export_range(0.0, 2.0, 0.05) var pump_seconds: float = 0.0
@export var reload_one_shell_at_a_time: bool = false
@export_range(0.1, 2.0, 0.05) var shell_insert_seconds: float = 0.65
@export_range(1.0, 500.0, 1.0) var maximum_range: float = 125.0
@export_range(0.1, 2.0, 0.05) var movement_speed_scale: float = 1.0
@export var view_model_color: Color = Color("4f7189")


func seconds_per_shot() -> float:
	return 60.0 / maxf(rounds_per_minute, 1.0)


func damage_at_distance(distance_meters: float, headshot: bool = false) -> float:
	var falloff_ratio := 1.0
	if distance_meters > falloff_start:
		var falloff_span := maxf(falloff_end - falloff_start, 0.001)
		var progress := clampf((distance_meters - falloff_start) / falloff_span, 0.0, 1.0)
		falloff_ratio = lerpf(1.0, minimum_damage_ratio, progress)
	var result := base_damage * falloff_ratio
	if headshot:
		result *= headshot_multiplier
	return result


func is_valid_definition() -> bool:
	return not weapon_id.is_empty() \
		and base_damage > 0.0 \
		and rounds_per_minute > 0.0 \
		and magazine_size > 0 \
		and reload_seconds > 0.0 \
		and falloff_end >= falloff_start
