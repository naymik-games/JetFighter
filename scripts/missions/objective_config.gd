class_name ObjectiveConfig
extends Resource
## One mission objective: a special target that must be destroyed.
## Pure data. MissionManager (Step 3) sequences these, the chain generator (Step 2)
## turns the leg settings into fixed world positions, and ObjectiveTarget (Step 4)
## is what actually spawns in the world.

enum Kind { FUEL_DEPOT, RADIO_TOWER, RADAR_STATION, HEADQUARTERS }

@export_group("Identity")
@export var kind: Kind = Kind.FUEL_DEPOT
## Shown in the objective panel and on the HUD pointer. Empty = a default name for the kind.
@export var display_name: String = ""
## Short line shown when the objective is revealed.
@export var reveal_text: String = ""
## Scene spawned for this objective (an ObjectiveTarget). Assigned in Step 4.
@export var target_scene: PackedScene
## 0 = use the scene's own max_health. Above 0 overrides it (a headquarters can take more hits).
@export var health_override: int = 0
## Score value of this objective (read by the scoring step).
@export var base_points: int = 1000

@export_group("Leg (distance from the previous objective, or the start point)")
## Flight time at cruise speed between the previous objective and this one.
@export var leg_seconds_min: float = 20.0
@export var leg_seconds_max: float = 40.0
## Largest turn away from the previous leg's bearing. Keeps legs from doubling back.
@export_range(0.0, 180.0, 1.0) var max_turn_degrees: float = 70.0

@export_group("Placement")
## The site must be land and fairly flat within this radius (world units) of the objective.
@export var footprint_radius: float = 14.0
## Steepest mesh slope allowed anywhere on the footprint, in degrees.
@export_range(0.0, 45.0, 0.5) var max_slope_degrees: float = 18.0

@export_group("Timer")
## False = no time limit on this objective.
@export var timed: bool = true
## 0 = compute the limit from the leg length and defense level (see time_limit_for_leg).
## Above 0 = use exactly this many seconds.
@export var timer_override: float = 0.0

@export_group("Defenses")
## 0 = undefended "easy" target. Higher = more turrets and tanks around it.
@export_range(0, 5, 1) var defense_level: int = 0
## Network id given to the SAMs that defend this objective (empty = none).
## A radar elsewhere in the mission can take the whole network offline.
@export var defender_network: StringName = &""

@export_group("Effects")
## When this objective is destroyed, these SAM networks go offline.
@export var disables_networks: PackedStringArray = PackedStringArray()


func get_display_name() -> String:
	if display_name != "":
		return display_name
	return kind_name(kind)


static func kind_name(k: Kind) -> String:
	match k:
		Kind.FUEL_DEPOT:
			return "Fuel Depot"
		Kind.RADIO_TOWER:
			return "Radio Tower"
		Kind.RADAR_STATION:
			return "Radar Station"
		Kind.HEADQUARTERS:
			return "Headquarters"
	return "Objective"


## Leg length range in world units, for a given cruise speed.
func leg_distance_range(cruise_speed: float) -> Vector2:
	var lo := minf(leg_seconds_min, leg_seconds_max)
	var hi := maxf(leg_seconds_min, leg_seconds_max)
	return Vector2(lo, hi) * cruise_speed


## Time limit in seconds for this objective, or -1.0 when it has no limit.
## Auto formula: travel time at cruise speed * slack, plus a combat allowance that
## grows with defense level. All the tuning numbers live on the MissionConfig.
func time_limit_for_leg(leg_distance: float, mission: MissionConfig) -> float:
	if not timed:
		return -1.0
	if timer_override > 0.0:
		return timer_override
	var travel := leg_distance / maxf(mission.cruise_speed, 0.001) * mission.timer_slack
	var combat := mission.base_combat_seconds + mission.combat_seconds_per_defense_level * float(defense_level)
	return travel + combat


## Quick builder used by hand-written test missions.
static func make(p_kind: Kind, p_defense: int = 0, p_defender_network: StringName = &"", p_disables: PackedStringArray = PackedStringArray()) -> ObjectiveConfig:
	var o := ObjectiveConfig.new()
	o.kind = p_kind
	o.defense_level = p_defense
	o.defender_network = p_defender_network
	o.disables_networks = p_disables
	return o
