class_name HealthComponent
extends Node

## Authoritative health, spawn protection, regeneration, death and reset logic.
## Call advance() directly in headless tests; normal scenes are advanced by _process.

signal health_changed(current: float, maximum: float)
signal damage_taken(amount: float, attacker_id: StringName, headshot: bool)
signal killed(killer_id: StringName)
signal respawned

@export_range(1.0, 1000.0, 1.0) var max_health: float = 100.0
@export_range(0.0, 30.0, 0.1) var regeneration_delay: float = 4.0
@export_range(0.0, 200.0, 1.0) var regeneration_per_second: float = 28.0
@export_range(0.0, 10.0, 0.05) var spawn_protection_seconds: float = 1.25

var current_health: float = 100.0
var is_alive: bool = true
var last_attacker_id: StringName = &""
var time_since_damage: float = 999.0
var spawn_protection_remaining: float = 0.0


func _ready() -> void:
	current_health = max_health
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	spawn_protection_remaining = maxf(spawn_protection_remaining - delta, 0.0)
	if not is_alive:
		return
	time_since_damage += delta
	if time_since_damage < regeneration_delay or current_health >= max_health:
		return
	var previous := current_health
	current_health = minf(max_health, current_health + regeneration_per_second * delta)
	if not is_equal_approx(previous, current_health):
		health_changed.emit(current_health, max_health)


func apply_damage(
	amount: float,
	attacker_id: StringName = &"",
	headshot: bool = false,
	bypass_protection: bool = false,
) -> float:
	if not is_alive or amount <= 0.0:
		return 0.0
	if spawn_protection_remaining > 0.0 and not bypass_protection:
		return 0.0
	var applied := minf(amount, current_health)
	current_health -= applied
	time_since_damage = 0.0
	if not attacker_id.is_empty():
		last_attacker_id = attacker_id
	damage_taken.emit(applied, attacker_id, headshot)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		is_alive = false
		current_health = 0.0
		killed.emit(attacker_id)
	return applied


func force_kill(killer_id: StringName = &"") -> void:
	if not is_alive:
		return
	apply_damage(current_health, killer_id, false, true)


func grant_spawn_protection(protection_seconds: float = -1.0) -> void:
	spawn_protection_remaining = (
		spawn_protection_seconds if protection_seconds < 0.0 else maxf(protection_seconds, 0.0)
	)


func respawn(protection_seconds: float = -1.0) -> void:
	is_alive = true
	current_health = max_health
	last_attacker_id = &""
	time_since_damage = 999.0
	spawn_protection_remaining = (
		spawn_protection_seconds if protection_seconds < 0.0 else protection_seconds
	)
	health_changed.emit(current_health, max_health)
	respawned.emit()


func health_ratio() -> float:
	return current_health / maxf(max_health, 0.001)


func is_protected() -> bool:
	return spawn_protection_remaining > 0.0
