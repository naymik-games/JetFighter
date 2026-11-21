class_name SpawnRule
extends Resource
## One kind of thing that can spawn on terrain chunks (tank, SAM turret, ...).
## Rules are listed in a SpawnTable. Order matters: rules earlier in the list
## are placed first, and later rules keep their min_spacing away from them.

@export var rule_name: StringName = &"spawn"
@export var scene: PackedScene

@export_group("Frequency")
## Chance that this rule spawns anything in a given chunk.
@export_range(0.0, 1.0) var chance_per_chunk: float = 0.75
## Extra chance added per 1000 units of distance from the table's origin (difficulty ramp).
@export var chance_growth_per_1000: float = 0.0
@export var min_count: int = 1
@export var max_count: int = 1
## 0 = every spawn is placed independently. Above 0, later spawns of this rule
## are placed within this radius of the first one (a convoy or a base).
@export var cluster_radius: float = 0.0

@export_group("Placement")
## Height above the water surface. 1.0 keeps spawns off beaches and out of water.
@export var min_altitude: float = 1.0
@export var max_altitude: float = 1000.0
@export var max_slope_degrees: float = 25.0
## Keep at least this far from every spawn already planned in the same chunk.
@export var min_spacing: float = 12.0
## Only spawn at least this far from the table's origin (the jet's start).
@export var min_distance_from_origin: float = 0.0
@export var max_attempts: int = 10

@export_group("Orientation")
@export var random_yaw: bool = true
## Tilt the entity to match the ground surface.
@export var align_to_surface: bool = false
@export var ground_offset: float = 0.0

@export_group("Defense network")
## Entities from this rule join this defense network (e.g. &"net_a"), so a mission can switch the
## whole network off. The Terrain node sets this from the mission's world_networks at start
## (an empty value there clears it), so leave it empty here.
@export var network_id: StringName = &""
