class_name SonarSweep
extends Control
## Lightweight animated signature used by the title and offline matchmaking screens.

signal pulse_completed

@export_range(0.1, 2.0, 0.05) var sweep_speed := 0.46
@export_range(2, 7, 1) var ring_count := 4
@export var active := true:
	set(value):
		active = value
		set_process(value)
		queue_redraw()

var _angle := -PI * 0.5
var _previous_angle := _angle


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(340.0, 340.0)
	set_process(active)


func _process(delta: float) -> void:
	_previous_angle = _angle
	_angle = fmod(_angle + delta * TAU * sweep_speed, TAU)
	if _angle < _previous_angle:
		pulse_completed.emit()
	queue_redraw()


func _draw() -> void:
	var center := size * Vector2(0.48, 0.52)
	var radius := minf(size.x, size.y) * 0.46
	if radius <= 1.0:
		return
	for ring_index in range(1, ring_count + 1):
		var ring_radius := radius * float(ring_index) / float(ring_count)
		draw_arc(center, ring_radius, 0.0, TAU, 96, Color(BreakwaterUI.SEA_GLASS, 0.08 + ring_index * 0.025), 1.0, true)
	draw_line(center - Vector2(radius, 0.0), center + Vector2(radius, 0.0), Color(BreakwaterUI.SEA_GLASS, 0.1), 1.0)
	draw_line(center - Vector2(0.0, radius), center + Vector2(0.0, radius), Color(BreakwaterUI.SEA_GLASS, 0.1), 1.0)
	if not active:
		return
	var trail_width := 0.72
	var points := PackedVector2Array([center])
	var colors := PackedColorArray([Color(BreakwaterUI.SEA_GLASS, 0.0)])
	for point_index in range(15):
		var ratio := float(point_index) / 14.0
		var point_angle := _angle - trail_width + trail_width * ratio
		points.append(center + Vector2.from_angle(point_angle) * radius)
		colors.append(Color(BreakwaterUI.SEA_GLASS, 0.01 + ratio * 0.2))
	draw_polygon(points, colors)
	var endpoint := center + Vector2.from_angle(_angle) * radius
	draw_line(center, endpoint, Color(BreakwaterUI.SEA_GLASS, 0.82), 2.0, true)
	draw_circle(center, 4.0, BreakwaterUI.SUN_GOLD)


func set_reduced_motion(enabled: bool) -> void:
	active = not enabled
