class_name WeaponState
extends RefCounted

## Per-combatant mutable state for a WeaponDefinition.

signal reload_started(duration: float)
signal reload_finished(magazine: int, reserve: int)
signal ammo_changed(magazine: int, reserve: int)
signal pump_started(duration: float)

var definition: WeaponDefinition
var magazine_ammo: int = 0
var reserve_ammo: int = 0
var cooldown_remaining: float = 0.0
var reload_remaining: float = 0.0


func _init(weapon: WeaponDefinition = null) -> void:
	if weapon != null:
		configure(weapon)


func configure(weapon: WeaponDefinition) -> void:
	definition = weapon
	magazine_ammo = weapon.magazine_size
	reserve_ammo = weapon.starting_reserve
	cooldown_remaining = 0.0
	reload_remaining = 0.0


func tick(delta: float) -> void:
	cooldown_remaining = maxf(cooldown_remaining - delta, 0.0)
	if reload_remaining <= 0.0:
		return
	reload_remaining = maxf(reload_remaining - delta, 0.0)
	if reload_remaining <= 0.0:
		_complete_reload()


func can_fire() -> bool:
	return definition != null \
		and magazine_ammo > 0 \
		and cooldown_remaining <= 0.0 \
		and reload_remaining <= 0.0


func consume_shot() -> bool:
	if definition != null \
		and reload_remaining > 0.0 \
		and magazine_ammo > 0 \
		and cooldown_remaining <= 0.0:
		cancel_reload()
	if not can_fire():
		return false
	magazine_ammo -= 1
	cooldown_remaining = maxf(
		definition.seconds_per_shot(),
		definition.pump_seconds if definition.pump_action else 0.0,
	)
	ammo_changed.emit(magazine_ammo, reserve_ammo)
	if definition.pump_action:
		pump_started.emit(definition.pump_seconds)
	return true


func begin_reload() -> bool:
	if definition == null \
		or reload_remaining > 0.0 \
		or magazine_ammo >= definition.magazine_size \
		or reserve_ammo <= 0:
		return false
	reload_remaining = definition.shell_insert_seconds if definition.reload_one_shell_at_a_time else definition.reload_seconds
	reload_started.emit(reload_remaining)
	return true


func cancel_reload() -> void:
	reload_remaining = 0.0


func refill() -> void:
	if definition == null:
		return
	magazine_ammo = definition.magazine_size
	reserve_ammo = definition.starting_reserve
	cooldown_remaining = 0.0
	reload_remaining = 0.0
	ammo_changed.emit(magazine_ammo, reserve_ammo)


func add_reserve(amount: int) -> int:
	if amount <= 0 or definition == null:
		return 0
	var capacity := maxi(definition.starting_reserve, 0)
	var accepted := mini(amount, maxi(capacity - reserve_ammo, 0))
	if accepted <= 0:
		return 0
	reserve_ammo += accepted
	ammo_changed.emit(magazine_ammo, reserve_ammo)
	return accepted


func _complete_reload() -> void:
	if definition.reload_one_shell_at_a_time:
		var transferred_shell := mini(1, reserve_ammo)
		magazine_ammo += transferred_shell
		reserve_ammo -= transferred_shell
		ammo_changed.emit(magazine_ammo, reserve_ammo)
		if magazine_ammo < definition.magazine_size and reserve_ammo > 0:
			reload_remaining = definition.shell_insert_seconds
			reload_started.emit(reload_remaining)
		else:
			reload_finished.emit(magazine_ammo, reserve_ammo)
		return
	var wanted := definition.magazine_size - magazine_ammo
	var transferred := mini(wanted, reserve_ammo)
	magazine_ammo += transferred
	reserve_ammo -= transferred
	ammo_changed.emit(magazine_ammo, reserve_ammo)
	reload_finished.emit(magazine_ammo, reserve_ammo)
