class_name SpawnTable
extends Resource
## The full list of spawn rules plus chunk-wide limits.

@export var rules: Array[SpawnRule] = []
## World X/Z where the jet starts. Distance rules and the difficulty ramp measure from here.
@export var origin: Vector2 = Vector2.ZERO
## Spawns stay this far inside the chunk edge so they never straddle two chunks.
@export var edge_margin: float = 20.0
@export var max_spawns_per_chunk: int = 8


## Builds the default table from the two scenes already assigned on the Terrain node.
static func make_default(tank_scene: PackedScene, sam_scene: PackedScene) -> SpawnTable:
	var table := SpawnTable.new()

	var tank := SpawnRule.new()
	tank.rule_name = &"tank"
	tank.scene = tank_scene
	tank.chance_per_chunk = 0.8
	tank.min_count = 1
	tank.max_count = 3
	tank.cluster_radius = 45.0
	tank.min_altitude = 1.0
	tank.max_slope_degrees = 22.0
	tank.min_spacing = 14.0
	tank.min_distance_from_origin = 100.0
	tank.align_to_surface = true
	table.rules.append(tank)

	var sam := SpawnRule.new()
	sam.rule_name = &"sam_turret"
	sam.scene = sam_scene
	sam.chance_per_chunk = 0.3
	sam.chance_growth_per_1000 = 0.1
	sam.min_count = 1
	sam.max_count = 1
	sam.min_altitude = 1.5
	sam.max_slope_degrees = 15.0
	sam.min_spacing = 40.0
	sam.min_distance_from_origin = 350.0
	table.rules.append(sam)

	return table
