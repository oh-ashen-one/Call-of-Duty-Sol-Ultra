class_name BreakwaterTacticalMinimap
extends Control
## Abstract radar display. Positions are supplied in normalized map space (-1..1).

var player_heading := 0.0
var blips: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(184.0, 184.0)


func set_radar_data(heading_degrees: float, radar_blips: Array[Dictionary]) -> void:
	player_heading = heading_degrees
	blips = radar_blips.duplicate(true)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.47
	draw_circle(center, radius, Color(BreakwaterUI.DEEP_NAVY, 0.78))
	for ratio in [0.33, 0.66, 1.0]:
		draw_arc(center, radius * ratio, 0.0, TAU, 64, Color(BreakwaterUI.SEA_GLASS, 0.16), 1.0, true)
	draw_line(center - Vector2(radius, 0.0), center + Vector2(radius, 0.0), Color(BreakwaterUI.SEA_GLASS, 0.13), 1.0)
	draw_line(center - Vector2(0.0, radius), center + Vector2(0.0, radius), Color(BreakwaterUI.SEA_GLASS, 0.13), 1.0)
	for blip: Dictionary in blips:
		var map_position: Vector2 = blip.get("position", Vector2.ZERO)
		map_position = map_position.limit_length(1.0)
		var rotated := map_position.rotated(-deg_to_rad(player_heading))
		var blip_position := center + Vector2(rotated.x, rotated.y) * radius * 0.84
		var relation := String(blip.get("relation", "enemy"))
		var color := BreakwaterUI.SAFETY_CORAL if relation == "enemy" else BreakwaterUI.SEA_GLASS
		if relation == "objective":
			color = BreakwaterUI.SUN_GOLD
		draw_circle(blip_position, float(blip.get("size", 4.0)), color)
	# Enemy blips already rotate into heading-up space, so the player marker
	# remains fixed toward the top of the radar.
	var heading_vector := Vector2.UP
	var player_triangle := PackedVector2Array([
		center + heading_vector * 10.0,
		center + heading_vector.rotated(2.4) * 7.0,
		center + heading_vector.rotated(-2.4) * 7.0,
	])
	draw_colored_polygon(player_triangle, BreakwaterUI.MIST)
