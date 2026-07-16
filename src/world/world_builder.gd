class_name WorldBuilder
extends RefCounted
## Procedural construction for the original "Breakwater Station" arena.
##
## The builder deliberately uses engine primitives only, so the map has no
## external asset or licensing dependency.  Gameplay code can consume either
## the returned Vector3 arrays or the marker nodes (which are also placed in
## descriptive scene-tree groups).

const WORLD_NAME: StringName = &"BreakwaterStation"
const MAP_BOUNDS := AABB(Vector3(-49.0, -2.0, -39.0), Vector3(98.0, 18.0, 78.0))

static var _materials: Dictionary = {}


## Builds a complete arena under `parent` and returns its integration points.
##
## Dictionary keys:
## - root: Node3D
## - environment: WorldEnvironment
## - spawn_points / patrol_points / pickup_points: Array[Vector3]
## - navigation_links: Array[Vector2i], indices into patrol_points
## - spawn_markers / patrol_markers / pickup_markers: Array[Marker3D]
## - pickup_kinds: Array[StringName], aligned with pickup_points
## - combat_bounds: AABB
## - landmark_nodes: Dictionary[StringName, Node3D]
static func build(parent: Node3D) -> Dictionary:
	if parent == null:
		push_error("WorldBuilder.build requires a valid Node3D parent")
		return {}

	_materials = _create_materials()

	var world := Node3D.new()
	world.name = WORLD_NAME
	parent.add_child(world)

	var environment := _build_environment(world)
	_build_ocean_and_island(world)
	_build_operations_route(world)
	_build_tidal_courtyard(world)
	_build_seawall_route(world)
	_build_cross_routes(world)
	_build_vertical_flanks(world)
	var landmarks := _build_landmarks(world)
	_build_vegetation(world)
	_build_perimeter(world)

	var spawn_positions: Array[Vector3] = [
		Vector3(-41.0, 0.15, -27.0),
		Vector3(40.0, 0.15, -27.0),
		Vector3(-43.0, 0.15, 7.0),
		Vector3(42.0, 0.15, 8.0),
		Vector3(-39.0, 0.85, 30.0),
		Vector3(42.0, 0.85, 23.0),
		Vector3(-13.0, 0.15, 31.0),
		Vector3(14.0, 0.15, -27.0),
	]
	var patrol_positions: Array[Vector3] = [
		# Operations interior route.
		Vector3(-27.0, 0.15, -24.0), Vector3(-14.0, 0.15, -24.0),
		Vector3(0.0, 0.15, -24.0), Vector3(15.0, 0.15, -24.0),
		Vector3(28.0, 0.15, -24.0),
		# Open tidal courtyard route.
		Vector3(-31.0, 0.15, -10.0), Vector3(-18.0, 0.15, 1.0),
		Vector3(-29.0, 0.15, 11.0), Vector3(-5.0, 0.15, 10.0),
		Vector3(7.0, 0.15, -7.0), Vector3(21.0, 0.15, 4.0),
		Vector3(32.0, 0.15, -9.0), Vector3(31.0, 0.15, 12.0),
		# Seawall/service route.
		Vector3(-35.0, 0.85, 20.0), Vector3(-22.0, 0.15, 29.0),
		Vector3(-4.0, 0.15, 22.0), Vector3(11.0, 0.15, 30.0),
		Vector3(27.0, 0.85, 22.0), Vector3(40.0, 0.85, 30.0),
		# Vertical/flank positions.
		Vector3(-39.0, 7.55, -6.0), Vector3(36.0, 4.25, 1.0),
		Vector3(30.0, 6.55, -22.0),
		# West observation-ramp bottom, midpoint, and top.
		Vector3(-39.0, 0.2, 16.0), Vector3(-39.0, 3.65, 7.0),
		Vector3(-39.0, 7.35, -2.0),
		# South catwalk-ramp bottom, midpoint, and top.
		Vector3(36.0, 0.85, 28.8), Vector3(36.0, 2.4, 22.75),
		Vector3(36.0, 4.2, 16.2),
		# North roof-ramp bottom, midpoint, and top.
		Vector3(34.0, 4.2, -9.8), Vector3(33.0, 5.36, -12.75),
		Vector3(31.0, 6.6, -15.7),
	]
	# A compact authored traversal graph keeps autonomous combatants on the three
	# readable routes and their real ramp/catwalk transitions. The graph is used
	# as a deterministic fallback when a runtime NavigationMap is unavailable.
	var navigation_links: Array[Vector2i] = [
		# Operations lane.
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4),
		# Tidal courtyard loop and cross-lanes.
		Vector2i(5, 6), Vector2i(5, 7), Vector2i(6, 7), Vector2i(6, 8),
		Vector2i(6, 9), Vector2i(7, 8), Vector2i(8, 9), Vector2i(9, 10),
		Vector2i(10, 11), Vector2i(10, 12), Vector2i(11, 12),
		# Seawall/service lane.
		Vector2i(13, 14), Vector2i(14, 15), Vector2i(15, 16),
		Vector2i(16, 17), Vector2i(17, 18),
		# Route-to-route connectors.
		Vector2i(0, 5), Vector2i(1, 6), Vector2i(2, 9), Vector2i(3, 9),
		Vector2i(4, 11), Vector2i(7, 13), Vector2i(8, 15),
		Vector2i(10, 17), Vector2i(12, 18),
		# West observation deck via the physical ramp.
		Vector2i(5, 22), Vector2i(7, 22), Vector2i(13, 22),
		Vector2i(22, 23), Vector2i(23, 24), Vector2i(24, 19),
		# East catwalk via its south ramp.
		Vector2i(17, 25), Vector2i(18, 25), Vector2i(25, 26),
		Vector2i(26, 27), Vector2i(27, 20),
		# Operations roof via the north catwalk ramp.
		Vector2i(20, 28), Vector2i(28, 29), Vector2i(29, 30),
		Vector2i(30, 21),
	]
	var pickup_positions: Array[Vector3] = [
		Vector3(-22.0, 0.25, -21.0), Vector3(4.0, 0.25, -27.0),
		Vector3(24.0, 0.25, -20.0), Vector3(-27.0, 0.25, 7.0),
		Vector3(-8.0, 0.25, 4.0), Vector3(15.0, 0.25, 5.0),
		Vector3(32.0, 0.25, -5.0), Vector3(-31.0, 0.85, 25.0),
		Vector3(-8.0, 0.25, 29.0), Vector3(21.0, 0.25, 24.0),
		Vector3(39.0, 0.85, 20.0), Vector3(36.0, 4.35, 5.0),
	]
	var pickup_kinds: Array[StringName] = [
		&"assault_rifle", &"frag", &"smg", &"flash",
		&"pump_shotgun", &"ammo", &"dmr", &"concussion",
		&"lmg", &"ammo", &"pistol", &"frag",
	]

	_add_pickup_pads(world, pickup_positions, pickup_kinds)
	var spawn_markers := _add_markers(world, &"SpawnPoints", &"ffa_spawn", spawn_positions)
	var patrol_markers := _add_markers(world, &"PatrolPoints", &"patrol_point", patrol_positions)
	var pickup_markers := _add_markers(world, &"PickupPoints", &"pickup_point", pickup_positions)
	for index in pickup_markers.size():
		pickup_markers[index].set_meta(&"pickup_kind", pickup_kinds[index])
		if pickup_kinds[index] in [&"frag", &"flash", &"concussion"]:
			pickup_markers[index].add_to_group(&"grenade_pickup_point")
	for index in spawn_markers.size():
		spawn_markers[index].set_meta(&"safe_radius", 8.0)
	for index in patrol_markers.size():
		var route_name: StringName = &"operations" if index < 5 else (&"courtyard" if index < 13 else (&"seawall" if index < 19 else &"vertical"))
		patrol_markers[index].set_meta(&"route", route_name)

	world.set_meta(&"display_name", "Breakwater Station")
	world.set_meta(&"route_count", 3)
	world.set_meta(&"combat_bounds", MAP_BOUNDS)

	return {
		"root": world,
		"environment": environment,
		"spawn_points": spawn_positions,
		"patrol_points": patrol_positions,
		"navigation_links": navigation_links,
		"pickup_points": pickup_positions,
		"pickup_kinds": pickup_kinds,
		"spawn_markers": spawn_markers,
		"patrol_markers": patrol_markers,
		"pickup_markers": pickup_markers,
		"combat_bounds": MAP_BOUNDS,
		"landmark_nodes": landmarks,
	}


static func _create_materials() -> Dictionary:
	var palette: Dictionary = {}
	palette[&"concrete"] = _material("Warm Concrete", Color("9ba2a0"), 0.0, 0.82)
	palette[&"concrete_dark"] = _material("Wet Concrete", Color("3f4d52"), 0.0, 0.72)
	palette[&"white"] = _material("Research White", Color("d9dfdb"), 0.04, 0.57)
	palette[&"navy"] = _material("Station Navy", Color("18333f"), 0.22, 0.48)
	palette[&"blue"] = _material("Route Blue", Color("247a91"), 0.16, 0.42)
	palette[&"orange"] = _material("Safety Orange", Color("e87938"), 0.08, 0.45)
	palette[&"yellow"] = _material("Safety Yellow", Color("e5bd4d"), 0.05, 0.52)
	palette[&"steel"] = _material("Brushed Steel", Color("65757a"), 0.72, 0.3)
	palette[&"black"] = _material("Fixture Black", Color("111b20"), 0.32, 0.36)
	palette[&"ground"] = _material("Salt Grass Ground", Color("536c58"), 0.0, 0.96)
	palette[&"sand"] = _material("Coastal Aggregate", Color("bcae86"), 0.0, 0.98)
	palette[&"wood"] = _material("Weathered Timber", Color("745a3e"), 0.0, 0.82)
	palette[&"leaf"] = _material("Coastal Pine", Color("315c43"), 0.0, 0.92)
	palette[&"leaf_light"] = _material("Sunlit Shrub", Color("5d7f52"), 0.0, 0.92)
	palette[&"rock"] = _material("Breakwater Rock", Color("4d5b5c"), 0.0, 0.94)
	palette[&"solar"] = _material("Solar Glass", Color("173c58"), 0.62, 0.16)
	palette[&"glass"] = _transparent_material("Sea Glass", Color(0.30, 0.72, 0.77, 0.34), 0.12, 0.11)
	palette[&"water"] = _material("Ocean", Color("1b7186"), 0.38, 0.18)
	palette[&"foam"] = _emissive_material("Sea Foam", Color("9fd6d0"), Color("58aeb3"), 0.32)
	palette[&"cyan_light"] = _emissive_material("Cyan Guidance", Color("8ee8e5"), Color("43d5d4"), 2.8)
	palette[&"warm_light"] = _emissive_material("Warm Guidance", Color("ffe3a5"), Color("ffb95c"), 2.3)
	palette[&"red_light"] = _emissive_material("Warning Beacon", Color("ff7967"), Color("f43d2e"), 3.2)
	return palette


static func _build_environment(parent: Node3D) -> WorldEnvironment:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "CoastalEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.82
	environment.fog_enabled = true
	environment.fog_light_color = Color("bad6d3")
	environment.fog_light_energy = 0.54
	environment.fog_density = 0.0032
	environment.fog_height = -1.0
	environment.fog_height_density = 0.055

	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("287ca8")
	sky_material.sky_horizon_color = Color("b8dce0")
	sky_material.ground_bottom_color = Color("164958")
	sky_material.ground_horizon_color = Color("8eb7b3")
	sky_material.sun_angle_max = 12.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material
	environment.sky = sky
	world_environment.environment = environment
	parent.add_child(world_environment)
	world_environment.add_to_group(&"quality_environment")

	var sun := DirectionalLight3D.new()
	sun.name = "LateMorningSun"
	sun.rotation_degrees = Vector3(-52.0, -31.0, 0.0)
	sun.light_color = Color("fff1d2")
	sun.light_energy = 0.92
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 115.0
	sun.directional_shadow_fade_start = 0.72
	parent.add_child(sun)
	sun.add_to_group(&"quality_shadow_light")

	var fill := DirectionalLight3D.new()
	fill.name = "OceanBounce"
	fill.rotation_degrees = Vector3(42.0, 145.0, 0.0)
	fill.light_color = Color("6cb9ca")
	fill.light_energy = 0.16
	fill.shadow_enabled = false
	parent.add_child(fill)

	var courtyard_probe := ReflectionProbe.new()
	courtyard_probe.name = "CourtyardReflectionProbe"
	courtyard_probe.position = Vector3(0.0, 5.0, 1.0)
	courtyard_probe.size = Vector3(64.0, 14.0, 42.0)
	courtyard_probe.origin_offset = Vector3(0.0, 1.0, 0.0)
	courtyard_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	parent.add_child(courtyard_probe)
	courtyard_probe.add_to_group(&"quality_reflection")

	return world_environment


static func _build_ocean_and_island(parent: Node3D) -> void:
	var ocean := _add_box(parent, "Ocean", Vector3(280.0, 0.35, 280.0), Vector3(0.0, -2.3, 0.0), _materials[&"water"], false, Vector3.ZERO, false)
	ocean.add_to_group(&"ocean")

	# Layered foundations give the base a readable silhouette from every route.
	_add_box(parent, "IslandFoundation", Vector3(96.0, 1.45, 76.0), Vector3(0.0, -0.75, 0.0), _materials[&"rock"])
	_add_box(parent, "MainDeck", Vector3(92.0, 0.3, 72.0), Vector3(0.0, -0.08, 0.0), _materials[&"concrete"])
	_add_box(parent, "NorthAggregate", Vector3(88.0, 0.12, 17.0), Vector3(0.0, 0.08, -23.5), _materials[&"concrete_dark"])
	_add_box(parent, "CourtyardPaving", Vector3(80.0, 0.12, 28.0), Vector3(0.0, 0.08, 0.0), _materials[&"sand"])
	_add_box(parent, "SouthServiceDeck", Vector3(88.0, 0.12, 20.0), Vector3(0.0, 0.08, 25.0), _materials[&"concrete_dark"])

	# Sea-foam stripes visually separate the playable island from the ocean.
	for side_x: float in [-47.0, 47.0]:
		_add_box(parent, "FoamEdgeX", Vector3(0.18, 0.06, 74.0), Vector3(side_x, -1.95, 0.0), _materials[&"foam"], false, Vector3.ZERO, false)
	for side_z: float in [-37.0, 37.0]:
		_add_box(parent, "FoamEdgeZ", Vector3(94.0, 0.06, 0.18), Vector3(0.0, -1.95, side_z), _materials[&"foam"], false, Vector3.ZERO, false)

	# Low-poly rocks hide the rectangular foundation and sell the breakwater.
	var rock_positions: Array[Vector3] = [
		Vector3(-49.0, -1.25, -31.0), Vector3(-50.0, -1.35, -18.0),
		Vector3(-49.5, -1.2, 13.0), Vector3(-48.8, -1.3, 33.0),
		Vector3(49.0, -1.35, -29.0), Vector3(49.7, -1.2, -5.0),
		Vector3(49.2, -1.3, 19.0), Vector3(48.8, -1.2, 34.0),
		Vector3(-35.0, -1.25, 39.0), Vector3(-11.0, -1.3, 39.5),
		Vector3(16.0, -1.25, 39.0), Vector3(39.0, -1.2, 39.0),
	]
	for index in rock_positions.size():
		var rock := _add_sphere(parent, "BreakwaterRock_%02d" % index, 2.3 + float(index % 3) * 0.35, rock_positions[index], _materials[&"rock"], false)
		rock.scale = Vector3(1.35, 0.62, 0.9 + float(index % 2) * 0.25)
		rock.rotation_degrees.y = float(index * 37)


static func _build_operations_route(parent: Node3D) -> void:
	var route := Node3D.new()
	route.name = "Route01_OperationsHall"
	route.add_to_group(&"combat_route")
	parent.add_child(route)

	# Roof and back wall; the front is segmented into generous combat entrances.
	_add_box(route, "OperationsRoof", Vector3(64.0, 0.55, 16.0), Vector3(0.0, 6.25, -23.5), _materials[&"white"])
	_add_box(route, "BackWallLower", Vector3(64.0, 1.35, 0.55), Vector3(0.0, 0.68, -31.3), _materials[&"navy"])
	_add_box(route, "BackWallUpper", Vector3(64.0, 2.25, 0.55), Vector3(0.0, 5.05, -31.3), _materials[&"white"])
	for x: float in [-28.0, -18.0, -8.0, 2.0, 12.0, 22.0, 28.0]:
		_add_box(route, "WindowMullion", Vector3(0.45, 3.05, 0.62), Vector3(x, 2.85, -31.25), _materials[&"steel"])
	for x: float in [-23.0, -13.0, -3.0, 7.0, 17.0, 25.0]:
		_add_box(route, "OceanWindow", Vector3(8.8, 2.7, 0.18), Vector3(x, 2.85, -31.2), _materials[&"glass"], false, Vector3.ZERO, false)

	# Front wall chunks frame four entries without funneling combatants.
	for spec: Array in [
		[-29.0, 6.0], [-18.0, 8.0], [-4.0, 7.0], [10.0, 7.0], [24.0, 8.0], [31.0, 2.0],
	]:
		_add_box(route, "FrontWall", Vector3(float(spec[1]), 6.0, 0.55), Vector3(float(spec[0]), 3.0, -15.65), _materials[&"white"])

	# Interior rooms remain porous: waist cover and offset partitions preserve flow.
	_add_box(route, "WestLabPartition", Vector3(0.45, 4.8, 7.0), Vector3(-12.5, 2.4, -26.3), _materials[&"navy"])
	_add_box(route, "WestLabPartitionGap", Vector3(0.45, 2.2, 3.2), Vector3(-12.5, 1.1, -18.0), _materials[&"navy"])
	_add_box(route, "EastLabPartition", Vector3(0.45, 4.8, 7.0), Vector3(13.0, 2.4, -20.7), _materials[&"navy"])
	_add_box(route, "EastLabPartitionGap", Vector3(0.45, 2.2, 3.0), Vector3(13.0, 1.1, -29.4), _materials[&"navy"])
	for cover_position: Vector3 in [
		Vector3(-24.0, 0.75, -26.0), Vector3(-18.0, 0.75, -20.0),
		Vector3(-4.0, 0.75, -27.5), Vector3(5.0, 0.75, -20.0),
		Vector3(20.0, 0.75, -27.0), Vector3(27.0, 0.75, -20.5),
	]:
		_add_box(route, "LabConsole", Vector3(3.4, 1.5, 1.2), cover_position, _materials[&"blue"])
		_add_box(route, "ConsoleGlow", Vector3(2.6, 0.05, 0.75), cover_position + Vector3(0.0, 0.78, 0.0), _materials[&"cyan_light"], false, Vector3(deg_to_rad(-4.0), 0.0, 0.0), false)

	# Efficient emissive strips provide interior readability without many lights.
	for x: float in [-24.0, -8.0, 8.0, 24.0]:
		_add_box(route, "CeilingStrip", Vector3(7.0, 0.08, 0.24), Vector3(x, 5.88, -23.5), _materials[&"warm_light"], false, Vector3.ZERO, false)

	_add_sign(route, "OPERATIONS // TIDAL RESEARCH", Vector3(-19.0, 4.55, -15.32), Vector3(0.0, 0.0, 0.0), 0.62)
	_add_sign(route, "BRK-07", Vector3(23.0, 4.5, -15.32), Vector3(0.0, 0.0, 0.0), 0.78, _materials[&"orange"])


static func _build_tidal_courtyard(parent: Node3D) -> void:
	var route := Node3D.new()
	route.name = "Route02_TidalCourtyard"
	route.add_to_group(&"combat_route")
	parent.add_child(route)

	# Painted route bands help navigation at sprint speed.
	_add_box(route, "BlueRouteBand", Vector3(70.0, 0.025, 0.42), Vector3(0.0, 0.17, -12.8), _materials[&"blue"], false, Vector3.ZERO, false)
	_add_box(route, "OrangeRouteBand", Vector3(70.0, 0.025, 0.42), Vector3(0.0, 0.17, 13.0), _materials[&"orange"], false, Vector3.ZERO, false)

	# Solar canopy: strong silhouette, partial shade, and chest-high cover.
	for x: float in [-28.0, -21.0]:
		_add_cylinder(route, "CanopyPost", 0.17, 3.3, Vector3(x, 1.65, -3.0), _materials[&"steel"])
		_add_cylinder(route, "CanopyPost", 0.17, 3.3, Vector3(x, 1.65, 4.0), _materials[&"steel"])
	for x: float in [-28.0, -21.0]:
		_add_box(route, "SolarPanel", Vector3(6.0, 0.22, 3.7), Vector3(x, 3.55, 0.5), _materials[&"solar"], false, Vector3(deg_to_rad(-11.0), 0.0, 0.0), true)
		for stripe: float in [-1.8, 0.0, 1.8]:
			_add_box(route, "SolarCellLine", Vector3(0.035, 0.02, 3.45), Vector3(x + stripe, 3.67, 0.28), _materials[&"cyan_light"], false, Vector3(deg_to_rad(-11.0), 0.0, 0.0), false)

	# Hydroponics pods create organic, irregular cover in the west courtyard.
	for pod_position: Vector3 in [Vector3(-30.0, 0.7, 9.0), Vector3(-20.0, 0.7, 10.5), Vector3(-13.0, 0.7, 3.0)]:
		_add_box(route, "HydroPod", Vector3(4.8, 1.4, 2.2), pod_position, _materials[&"white"])
		_add_box(route, "HydroPodGlass", Vector3(4.2, 0.55, 1.8), pod_position + Vector3(0.0, 0.82, 0.0), _materials[&"glass"], false, Vector3.ZERO, false)

	# East courtyard cargo stacks are offset to avoid long, dominant sightlines.
	_add_container(route, "CargoBlue", Vector3(25.0, 1.35, -7.5), Vector3(7.2, 2.7, 3.0), _materials[&"blue"])
	_add_container(route, "CargoWhite", Vector3(31.0, 1.35, 6.0), Vector3(3.0, 2.7, 7.2), _materials[&"white"])
	_add_container(route, "CargoOrange", Vector3(18.0, 1.35, 9.5), Vector3(6.4, 2.7, 3.0), _materials[&"orange"])

	# General-purpose cover retains diagonal movement around the landmark.
	for cover: Array in [
		[Vector3(-7.5, 0.62, -8.0), Vector3(4.6, 1.24, 1.0), 13.0],
		[Vector3(7.5, 0.62, 8.0), Vector3(4.6, 1.24, 1.0), -17.0],
		[Vector3(12.0, 0.62, -4.0), Vector3(1.0, 1.24, 4.6), 7.0],
		[Vector3(-15.5, 0.62, -9.5), Vector3(3.8, 1.24, 1.0), -8.0],
	]:
		_add_box(route, "CourtyardBarrier", cover[1] as Vector3, cover[0] as Vector3, _materials[&"concrete_dark"], true, Vector3(0.0, deg_to_rad(float(cover[2])), 0.0))


static func _build_seawall_route(parent: Node3D) -> void:
	var route := Node3D.new()
	route.name = "Route03_SeawallServiceLane"
	route.add_to_group(&"combat_route")
	parent.add_child(route)

	# Raised shoulders make the middle lane read as a service trench without
	# creating a navigation hole in the underlying deck.
	_add_box(route, "WestShoulder", Vector3(20.0, 0.75, 15.0), Vector3(-34.0, 0.38, 25.5), _materials[&"concrete"])
	_add_box(route, "EastShoulder", Vector3(20.0, 0.75, 15.0), Vector3(34.0, 0.38, 25.5), _materials[&"concrete"])
	_add_box(route, "TrenchWestLip", Vector3(1.0, 1.45, 15.0), Vector3(-23.5, 0.73, 25.5), _materials[&"yellow"])
	_add_box(route, "TrenchEastLip", Vector3(1.0, 1.45, 15.0), Vector3(23.5, 0.73, 25.5), _materials[&"yellow"])

	# Paired service bridges keep all three routes interconnected.
	for x: float in [-13.0, 11.0]:
		_add_box(route, "ServiceBridge", Vector3(8.0, 0.32, 4.0), Vector3(x, 1.02, 25.5), _materials[&"steel"])
		_add_box(route, "BridgeRailL", Vector3(8.0, 0.8, 0.12), Vector3(x, 1.45, 23.55), _materials[&"orange"])
		_add_box(route, "BridgeRailR", Vector3(8.0, 0.8, 0.12), Vector3(x, 1.45, 27.45), _materials[&"orange"])

	_add_container(route, "SouthContainerA", Vector3(-35.0, 2.1, 20.0), Vector3(7.5, 2.8, 3.2), _materials[&"navy"])
	# Keep the south catwalk ramp throat open; this cargo stack previously
	# overlapped the only walkable approach and forced bots underneath the deck.
	_add_container(route, "SouthContainerB", Vector3(28.5, 2.1, 30.0), Vector3(7.5, 2.8, 3.2), _materials[&"orange"])
	_add_container(route, "SouthContainerC", Vector3(2.0, 1.4, 32.5), Vector3(6.5, 2.8, 3.1), _materials[&"blue"])
	for x: float in [-20.0, -5.0, 17.0, 29.0]:
		_add_box(route, "ServiceCrate", Vector3(2.5, 1.4, 2.2), Vector3(x, 0.7, 19.5 + float(int(x) % 3) * 2.0), _materials[&"wood"])

	# The outer seawall is readable cover with deliberate firing gaps.
	for x: float in [-40.0, -28.0, -16.0, -4.0, 8.0, 20.0, 32.0, 42.0]:
		_add_box(route, "SeawallBlock", Vector3(8.0, 1.35, 1.4), Vector3(x, 0.68, 35.0), _materials[&"concrete_dark"])
		_add_box(route, "SeawallCap", Vector3(8.2, 0.16, 1.65), Vector3(x, 1.43, 35.0), _materials[&"white"], false)

	_add_sign(route, "SEAWALL // SOUTH", Vector3(-13.0, 1.05, 34.25), Vector3(0.0, 0.0, 0.0), 0.48, _materials[&"yellow"])


static func _build_cross_routes(parent: Node3D) -> void:
	var links := Node3D.new()
	links.name = "CrossRouteConnectors"
	parent.add_child(links)

	# Three broad north/south lanes stitch the combat loops together.
	for x: float in [-34.0, 0.0, 35.0]:
		_add_box(links, "ConnectorPaving", Vector3(5.5, 0.08, 50.0), Vector3(x, 0.16, 8.5), _materials[&"concrete"])
		_add_box(links, "ConnectorGuide", Vector3(0.18, 0.025, 48.0), Vector3(x, 0.22, 8.5), _materials[&"cyan_light"], false, Vector3.ZERO, false)

	# Waist-high cover breaks connector sightlines while leaving two-way flow.
	for item: Array in [
		[Vector3(-36.0, 0.65, -8.0), 18.0], [Vector3(-32.0, 0.65, 15.0), -12.0],
		[Vector3(-2.0, 0.65, -11.0), -15.0], [Vector3(2.0, 0.65, 16.0), 15.0],
		[Vector3(33.0, 0.65, -12.0), 12.0], [Vector3(37.0, 0.65, 16.0), -18.0],
	]:
		_add_box(links, "ConnectorCover", Vector3(4.2, 1.3, 0.9), item[0] as Vector3, _materials[&"concrete_dark"], true, Vector3(0.0, deg_to_rad(float(item[1])), 0.0))


static func _build_vertical_flanks(parent: Node3D) -> void:
	var flanks := Node3D.new()
	flanks.name = "VerticalFlanks"
	parent.add_child(flanks)

	# West observation deck and a broad, walkable access ramp.
	_add_box(flanks, "WestTowerBase", Vector3(8.0, 7.0, 8.0), Vector3(-39.0, 3.5, -6.0), _materials[&"navy"])
	_add_box(flanks, "WestTowerDeck", Vector3(10.0, 0.5, 10.0), Vector3(-39.0, 7.25, -6.0), _materials[&"steel"])
	# Overlap both decks slightly so controllers encounter a continuous walkable
	# surface instead of a sharp collision lip at the foot of the ramp.
	_add_box(flanks, "WestRamp", Vector3(5.0, 0.5, 19.0), Vector3(-39.0, 3.5, 7.0), _materials[&"steel"], true, Vector3(deg_to_rad(23.0), 0.0, 0.0))
	for x: float in [-41.55, -36.45]:
		_add_box(flanks, "WestRampRail", Vector3(0.14, 1.0, 19.0), Vector3(x, 4.05, 7.0), _materials[&"orange"], false, Vector3(deg_to_rad(23.0), 0.0, 0.0))
	for offset: Vector3 in [Vector3(-4.8, 0.7, 0.0), Vector3(4.8, 0.7, 0.0), Vector3(0.0, 0.7, -4.8), Vector3(0.0, 0.7, 4.8)]:
		var size := Vector3(0.15, 1.0, 9.5) if absf(offset.x) > 0.1 else Vector3(9.5, 1.0, 0.15)
		_add_box(flanks, "WestDeckRail", size, Vector3(-39.0, 7.55, -6.0) + offset, _materials[&"orange"], false)

	# East catwalk connects courtyard, service lane, and operations rooftop.
	_add_box(flanks, "EastCatwalk", Vector3(5.0, 0.45, 29.0), Vector3(36.0, 4.0, 2.0), _materials[&"steel"])
	for x: float in [33.55, 38.45]:
		_add_box(flanks, "CatwalkRail", Vector3(0.12, 0.92, 29.0), Vector3(x, 4.56, 2.0), _materials[&"yellow"], false)
	# Meet the catwalk's south face at walking height. Extending the former ramp
	# underneath the deck left a 0.6 m collision lip that bots could not climb.
	_add_box(flanks, "SouthCatwalkRamp", Vector3(5.0, 0.45, 13.5), Vector3(36.0, 2.2, 22.75), _materials[&"steel"], true, Vector3(deg_to_rad(15.5), 0.0, 0.0))
	# This short connector meets the catwalk and the front edge of the operations
	# roof instead of passing underneath the roof's collision slab.
	_add_box(flanks, "NorthRoofRamp", Vector3(5.0, 0.45, 6.4), Vector3(33.0, 5.36, -12.75), _materials[&"steel"], true, Vector3(deg_to_rad(23.0), 0.0, 0.0))

	# Rooftop cover prevents the high route from dominating the courtyard.
	_add_box(flanks, "RoofPlantRoom", Vector3(12.0, 2.7, 5.5), Vector3(8.0, 7.58, -24.0), _materials[&"navy"])
	_add_box(flanks, "RoofVentA", Vector3(3.0, 1.15, 2.5), Vector3(-15.0, 6.95, -22.0), _materials[&"steel"])
	_add_box(flanks, "RoofVentB", Vector3(3.0, 1.15, 2.5), Vector3(24.0, 6.95, -26.0), _materials[&"steel"])


static func _build_landmarks(parent: Node3D) -> Dictionary:
	var landmarks: Dictionary = {}

	# Central "Tideglass Core": a compact energy monument that doubles as cover.
	var core := Node3D.new()
	core.name = "Landmark_TideglassCore"
	core.position = Vector3(0.0, 0.0, 1.0)
	parent.add_child(core)
	_add_cylinder(core, "CorePlinth", 3.4, 0.65, Vector3(0.0, 0.33, 0.0), _materials[&"concrete_dark"])
	_add_cylinder(core, "CoreGlass", 2.25, 4.5, Vector3(0.0, 2.5, 0.0), _materials[&"glass"], true)
	_add_cylinder(core, "CoreColumn", 0.72, 6.5, Vector3(0.0, 3.5, 0.0), _materials[&"cyan_light"])
	for y: float in [1.0, 2.7, 4.4]:
		_add_cylinder(core, "CoreBand", 2.42, 0.18, Vector3(0.0, y, 0.0), _materials[&"steel"], false)
	_add_sphere(core, "CoreBeacon", 0.42, Vector3(0.0, 7.05, 0.0), _materials[&"red_light"], false)
	landmarks[&"tideglass_core"] = core

	# North-west weather radar, angled toward the open sea.
	var radar := Node3D.new()
	radar.name = "Landmark_WeatherRadar"
	radar.position = Vector3(-25.0, 6.52, -24.0)
	parent.add_child(radar)
	_add_cylinder(radar, "RadarPedestal", 0.9, 2.4, Vector3(0.0, 1.2, 0.0), _materials[&"steel"])
	var dish_holder := Node3D.new()
	dish_holder.name = "RadarDish"
	dish_holder.position = Vector3(0.0, 3.0, 0.0)
	dish_holder.rotation_degrees = Vector3(58.0, -24.0, 0.0)
	radar.add_child(dish_holder)
	var dish_mesh := SphereMesh.new()
	dish_mesh.radius = 2.25
	dish_mesh.height = 1.25
	dish_mesh.radial_segments = 20
	dish_mesh.rings = 8
	dish_mesh.is_hemisphere = true
	var dish_instance := MeshInstance3D.new()
	dish_instance.mesh = dish_mesh
	dish_instance.material_override = _materials[&"white"]
	dish_holder.add_child(dish_instance)
	_add_cylinder(dish_holder, "RadarFeed", 0.11, 2.1, Vector3(0.0, 0.7, 0.0), _materials[&"orange"], false)
	landmarks[&"weather_radar"] = radar

	# South-east marker mast is visible through fog and assists player orientation.
	var mast := Node3D.new()
	mast.name = "Landmark_HarborMast"
	mast.position = Vector3(42.0, 0.0, 28.0)
	parent.add_child(mast)
	_add_cylinder(mast, "Mast", 0.32, 13.0, Vector3(0.0, 6.5, 0.0), _materials[&"steel"])
	for y: float in [3.0, 6.5, 10.0]:
		_add_box(mast, "MastArm", Vector3(3.8, 0.16, 0.16), Vector3(0.0, y, 0.0), _materials[&"orange"], false)
		_add_sphere(mast, "MastLight", 0.25, Vector3(1.85, y, 0.0), _materials[&"red_light"], false)
	_add_sphere(mast, "MastBeacon", 0.38, Vector3(0.0, 13.35, 0.0), _materials[&"warm_light"], false)
	landmarks[&"harbor_mast"] = mast

	return landmarks


static func _build_vegetation(parent: Node3D) -> void:
	var vegetation := Node3D.new()
	vegetation.name = "CoastalVegetation"
	parent.add_child(vegetation)
	var detail := Node3D.new()
	detail.name = "ScalableVegetationDetail"
	detail.add_to_group(&"quality_detail")
	vegetation.add_child(detail)

	var tree_positions: Array[Vector3] = [
		Vector3(-43.0, 0.0, -13.0), Vector3(-42.0, 0.0, 14.0),
		Vector3(-29.0, 0.0, 14.0), Vector3(43.0, 0.0, -13.0),
		Vector3(43.0, 0.0, 14.0), Vector3(28.0, 0.0, 14.0),
	]
	for index in tree_positions.size():
		_add_coastal_tree(detail, index, tree_positions[index], 0.85 + float(index % 3) * 0.12)

	# MultiMeshes keep the numerous decorative grass tufts to two draw calls.
	var grass_positions: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		for index in 18:
			var x := -42.0 + float(index) * 5.0
			var z := side * (14.3 + float(index % 3) * 0.7)
			grass_positions.append(Vector3(x, 0.25, z))
	_add_multimesh_cylinders(detail, "BeachGrass", grass_positions, 0.13, 0.65, _materials[&"leaf_light"])

	var planter_positions: Array[Vector3] = [
		Vector3(-39.0, 0.55, -18.0), Vector3(-31.0, 0.55, -18.0),
		Vector3(30.0, 0.55, -18.0), Vector3(39.0, 0.55, -18.0),
	]
	for planter_position in planter_positions:
		var planter := _add_box(vegetation, "Planter", Vector3(5.5, 1.1, 1.5), planter_position, _materials[&"concrete_dark"])
		planter.add_to_group(&"persistent_cover")
		for offset: float in [-1.6, 0.0, 1.6]:
			_add_sphere(detail, "PlanterShrub", 0.72, planter_position + Vector3(offset, 1.05, 0.0), _materials[&"leaf_light"], false)


static func _build_perimeter(parent: Node3D) -> void:
	var perimeter := Node3D.new()
	perimeter.name = "PerimeterSafety"
	parent.add_child(perimeter)

	# Visible rail sections communicate the arena boundary. Hidden continuous
	# collision behind them prevents falls without adding visual clutter.
	for x: float in [-44.0, -32.0, -20.0, -8.0, 4.0, 16.0, 28.0, 40.0]:
		_add_box(perimeter, "NorthRail", Vector3(9.0, 0.85, 0.12), Vector3(x, 1.0, -36.0), _materials[&"steel"], false)
	for z: float in [-29.0, -17.0, -5.0, 7.0, 19.0, 31.0]:
		_add_box(perimeter, "WestRail", Vector3(0.12, 0.85, 8.8), Vector3(-46.0, 1.0, z), _materials[&"steel"], false)
		_add_box(perimeter, "EastRail", Vector3(0.12, 0.85, 8.8), Vector3(46.0, 1.0, z), _materials[&"steel"], false)

	_add_invisible_wall(perimeter, "BoundaryNorth", Vector3(94.0, 12.0, 0.5), Vector3(0.0, 5.0, -36.4))
	_add_invisible_wall(perimeter, "BoundarySouth", Vector3(94.0, 12.0, 0.5), Vector3(0.0, 5.0, 36.4))
	_add_invisible_wall(perimeter, "BoundaryWest", Vector3(0.5, 12.0, 73.0), Vector3(-46.4, 5.0, 0.0))
	_add_invisible_wall(perimeter, "BoundaryEast", Vector3(0.5, 12.0, 73.0), Vector3(46.4, 5.0, 0.0))


static func _add_markers(parent: Node3D, container_name: StringName, group_name: StringName, positions: Array[Vector3]) -> Array[Marker3D]:
	var container := Node3D.new()
	container.name = container_name
	parent.add_child(container)
	var markers: Array[Marker3D] = []
	for index in positions.size():
		var marker := Marker3D.new()
		marker.name = "%s_%02d" % [String(group_name).to_pascal_case(), index]
		marker.position = positions[index]
		marker.add_to_group(group_name)
		marker.set_meta(&"index", index)
		container.add_child(marker)
		if group_name == &"ffa_spawn":
			marker.look_at_from_position(marker.position, Vector3(0.0, marker.position.y, 0.0), Vector3.UP)
		markers.append(marker)
	return markers


static func _add_pickup_pads(parent: Node3D, positions: Array[Vector3], pickup_kinds: Array[StringName]) -> void:
	var pads := Node3D.new()
	pads.name = "PickupPads"
	parent.add_child(pads)
	for index in positions.size():
		var pad_material: Material = _materials[&"orange"] if pickup_kinds[index] in [&"frag", &"flash", &"concussion"] else _materials[&"cyan_light"]
		_add_cylinder(pads, "PickupPad_%02d" % index, 0.72, 0.08, positions[index] - Vector3(0.0, 0.07, 0.0), pad_material, false, 18)


static func _add_box(
	parent: Node3D,
	object_name: String,
	size: Vector3,
	position: Vector3,
	material: Material,
	collision := true,
	rotation: Vector3 = Vector3.ZERO,
	cast_shadow := true
) -> Node3D:
	var holder: Node3D
	if collision:
		holder = StaticBody3D.new()
	else:
		holder = Node3D.new()
	holder.name = object_name
	holder.position = position
	holder.rotation = rotation
	parent.add_child(holder)

	var mesh := BoxMesh.new()
	mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mesh_instance)

	if collision:
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.name = "Collision"
		collider.shape = shape
		holder.add_child(collider)
	return holder


static func _add_cylinder(
	parent: Node3D,
	object_name: String,
	radius: float,
	height: float,
	position: Vector3,
	material: Material,
	collision := true,
	radial_segments := 16
) -> Node3D:
	var holder: Node3D
	if collision:
		holder = StaticBody3D.new()
	else:
		holder = Node3D.new()
	holder.name = object_name
	holder.position = position
	parent.add_child(holder)

	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	holder.add_child(mesh_instance)

	if collision:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		var collider := CollisionShape3D.new()
		collider.name = "Collision"
		collider.shape = shape
		holder.add_child(collider)
	return holder


static func _add_sphere(parent: Node3D, object_name: String, radius: float, position: Vector3, material: Material, collision := true) -> Node3D:
	var holder: Node3D
	if collision:
		holder = StaticBody3D.new()
	else:
		holder = Node3D.new()
	holder.name = object_name
	holder.position = position
	parent.add_child(holder)

	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	holder.add_child(mesh_instance)

	if collision:
		var shape := SphereShape3D.new()
		shape.radius = radius
		var collider := CollisionShape3D.new()
		collider.name = "Collision"
		collider.shape = shape
		holder.add_child(collider)
	return holder


static func _add_container(parent: Node3D, object_name: String, position: Vector3, size: Vector3, material: Material) -> void:
	_add_box(parent, object_name, size, position, material)
	var end_axis_x := size.x > size.z
	for stripe_index in 5:
		var t := -0.38 + float(stripe_index) * 0.19
		if end_axis_x:
			_add_box(parent, object_name + "_Rib", Vector3(0.12, size.y * 0.86, size.z + 0.035), position + Vector3(t * size.x, 0.0, 0.0), _materials[&"steel"], false, Vector3.ZERO, false)
		else:
			_add_box(parent, object_name + "_Rib", Vector3(size.x + 0.035, size.y * 0.86, 0.12), position + Vector3(0.0, 0.0, t * size.z), _materials[&"steel"], false, Vector3.ZERO, false)


static func _add_coastal_tree(parent: Node3D, index: int, position: Vector3, scale_factor: float) -> void:
	var tree := Node3D.new()
	tree.name = "CoastalPine_%02d" % index
	tree.position = position
	tree.scale = Vector3.ONE * scale_factor
	parent.add_child(tree)
	_add_cylinder(tree, "Trunk", 0.3, 3.5, Vector3(0.0, 1.75, 0.0), _materials[&"wood"], false, 9)
	for layer: Array in [[2.4, 1.75], [3.4, 1.45], [4.4, 1.05]]:
		var crown := _add_sphere(tree, "Crown", float(layer[1]), Vector3(0.0, float(layer[0]), 0.0), _materials[&"leaf"], false)
		crown.scale = Vector3(1.0, 0.68, 1.0)


static func _add_multimesh_cylinders(parent: Node3D, object_name: String, positions: Array[Vector3], radius: float, height: float, material: Material) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * 0.25
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 6
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = positions.size()
	multimesh.mesh = cylinder
	for index in positions.size():
		var basis := Basis(Vector3.UP, deg_to_rad(float(index * 41)))
		basis = basis.scaled(Vector3(0.85 + float(index % 3) * 0.12, 0.9 + float(index % 4) * 0.08, 0.85 + float(index % 2) * 0.18))
		multimesh.set_instance_transform(index, Transform3D(basis, positions[index]))
	var instance := MultiMeshInstance3D.new()
	instance.name = object_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


static func _add_sign(parent: Node3D, text: String, position: Vector3, rotation: Vector3, font_size: float, material: Material = null) -> void:
	var label_mesh := TextMesh.new()
	label_mesh.text = text
	label_mesh.font_size = 42
	label_mesh.depth = 0.025
	label_mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var label := MeshInstance3D.new()
	label.name = "Sign_" + text.left(12).replace(" ", "_")
	label.mesh = label_mesh
	label.position = position
	label.rotation = rotation
	label.scale = Vector3.ONE * font_size
	label.material_override = material if material != null else _materials[&"cyan_light"]
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(label)


static func _add_invisible_wall(parent: Node3D, object_name: String, size: Vector3, position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = object_name
	body.position = position
	body.add_to_group(&"arena_boundary")
	parent.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)


static func _material(resource_name: String, color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = resource_name
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


static func _transparent_material(resource_name: String, color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := _material(resource_name, color, metallic, roughness)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return material


static func _emissive_material(resource_name: String, color: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var material := _material(resource_name, color, 0.08, 0.35)
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material
