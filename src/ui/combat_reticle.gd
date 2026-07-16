class_name BreakwaterCombatReticle
extends Control
## Procedural crosshair, hit marker, and kill confirmation.

var crosshair_visible := true
var crosshair_color := BreakwaterUI.MIST
var spread_pixels := 9.0
var _hit_time := 0.0
var _kill_confirm := false
var _headshot := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func set_spread(spread: float) -> void:
	spread_pixels = clampf(spread, 4.0, 44.0)
	queue_redraw()


func show_hit(kill := false, headshot := false) -> void:
	_hit_time = 0.18 if not kill else 0.34
	_kill_confirm = kill
	_headshot = headshot
	set_process(true)
	queue_redraw()


func reset_feedback() -> void:
	spread_pixels = 9.0
	_hit_time = 0.0
	_kill_confirm = false
	_headshot = false
	rotation = 0.0
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_hit_time = maxf(0.0, _hit_time - delta)
	if _hit_time <= 0.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	if crosshair_visible:
		var color := Color(crosshair_color, 0.9)
		var arm := 6.0
		draw_line(center + Vector2(spread_pixels, 0.0), center + Vector2(spread_pixels + arm, 0.0), color, 2.0, true)
		draw_line(center - Vector2(spread_pixels, 0.0), center - Vector2(spread_pixels + arm, 0.0), color, 2.0, true)
		draw_line(center + Vector2(0.0, spread_pixels), center + Vector2(0.0, spread_pixels + arm), color, 2.0, true)
		draw_line(center - Vector2(0.0, spread_pixels), center - Vector2(0.0, spread_pixels + arm), color, 2.0, true)
		draw_circle(center, 1.5, color)
	if _hit_time <= 0.0:
		return
	var marker_color := BreakwaterUI.SUN_GOLD if _headshot else (BreakwaterUI.SAFETY_CORAL if _kill_confirm else BreakwaterUI.MIST)
	var distance := 10.0
	var length := 7.0 if not _kill_confirm else 10.0
	for direction in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(1.0, 1.0)]:
		var normalized: Vector2 = direction.normalized()
		draw_line(center + normalized * distance, center + normalized * (distance + length), marker_color, 2.5, true)
