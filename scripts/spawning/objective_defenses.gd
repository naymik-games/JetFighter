class_name ObjectiveDefenses
extends RefCounted
## Plans the tanks and SAMs that guard an objective, from its defense_level (0 to 5).
## Deterministic: the same mission seed always gives the same defenders in the same spots.
## Pure functions over a TerrainSampler, so it works for objectives far outside the loaded area.
##
## Tuning lives in the two tables below. Keep SAM numbers low: more than a few get cluttered.

## Tanks and SAMs per defense level (index = level).
const TANKS: Array[int] = [0, 2, 3, 4, 5, 6]
const SAMS: Array[int] = [0, 0, 1, 2, 3, 4]

## Names of the SpawnRules whose scenes are used. Must match rule_name in your SpawnTable.
const TANK_RULE: StringName = &"tank"
const SAM_RULE: StringName = &"sam_turret"

## Ring (distance from the objective) each kind is placed in, and its limits.
const TANK_RING := Vector2(24.0, 55.0)
const SAM_RING := Vector2(50.0, 90.0)
const TANK_MAX_SLOPE: float = 22.0
const SAM_MAX_SLOPE: float = 15.0
const TANK_SPACING: float = 12.0
const SAM_SPACING: float = 35.0
const MIN_ALTITUDE: float = 1.5
const ATTEMPTS: int = 12

## Random world spawns stay at least this far from every objective site.
const EXCLUSION_RADIUS: float = 60.0


static func plan(sampler: TerrainSampler, objective: ObjectiveConfig, placement: ObjectivePlacement, mission_seed: int) -> Array[DefenderSpawn]:
	var out: Array[DefenderSpawn] = []
	var level := clampi(objective.defense_level, 0, TANKS.size() - 1)
	var center := placement.xz()

	for i in TANKS[level]:
		_add(out, sampler, placement, mission_seed, center, TANK_RULE, TANK_RING, TANK_MAX_SLOPE, TANK_SPACING, &"")
	for i in SAMS[level]:
		_add(out, sampler, placement, mission_seed, center, SAM_RULE, SAM_RING, SAM_MAX_SLOPE, SAM_SPACING, objective.defender_network)
	return out


static func _add(out: Array[DefenderSpawn], sampler: TerrainSampler, placement: ObjectivePlacement, mission_seed: int, center: Vector2, kind: StringName, ring: Vector2, max_slope: float, spacing: float, network: StringName) -> void:
	var n := out.size()
	for attempt in ATTEMPTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = ObjectiveChain.mix_seed(mission_seed, 5000 + placement.index * 100 + n, attempt)

		var angle := rng.randf() * TAU
		var dist := rng.randf_range(ring.x, ring.y)
		var xz := center + Vector2(cos(angle), sin(angle)) * dist
		var yaw := rng.randf() * TAU

		var height := sampler.surface_height_at(xz.x, xz.y)
		if height - sampler.sea_level < MIN_ALTITUDE:
			continue
		if sampler.surface_slope_degrees_at(xz.x, xz.y) > max_slope:
			continue
		if _too_close(out, xz, spacing):
			continue

		var spawn := DefenderSpawn.new()
		spawn.id = "d%d_%d" % [placement.index + 1, n]
		spawn.kind = kind
		spawn.position = Vector3(xz.x, height, xz.y)
		spawn.normal = sampler.surface_normal_at(xz.x, xz.y)
		spawn.yaw = yaw
		spawn.network = network
		out.append(spawn)
		return
	# No acceptable spot: this defender is simply skipped (the same way every run).


static func _too_close(existing: Array[DefenderSpawn], xz: Vector2, spacing: float) -> bool:
	for other in existing:
		if Vector2(other.position.x, other.position.z).distance_to(xz) < spacing:
			return true
	return false
