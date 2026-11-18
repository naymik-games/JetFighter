class_name TerrainSampler
extends RefCounted
## Read-only terrain queries. Safe to call from worker threads because nothing
## is modified after _init(). Everything that needs ground height, sea level,
## slope or colors should ask this class instead of using its own numbers.

var config: TerrainConfig
var seed_value: int = 0
var sea_level: float = 0.0

var _noise := FastNoiseLite.new()


func _init(p_config: TerrainConfig) -> void:
	config = p_config
	seed_value = config.world_seed if config.world_seed != 0 else maxi(randi(), 1)

	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = config.noise_frequency

	sea_level = config.sea_level()


## World-space ground height at (x, z). Water areas return sea level.
func height_at(x: float, z: float) -> float:
	return maxf(_noise.get_noise_2d(x, z), config.water_floor) * config.height_multiplier


func normalized_height_at(x: float, z: float) -> float:
	return height_at(x, z) / maxf(config.height_multiplier, 0.0001)


## True when the ground at (x, z) is above the water surface by more than margin.
func is_land(x: float, z: float, margin: float = 0.0) -> bool:
	return height_at(x, z) > sea_level + margin


## Surface normal estimated from neighboring samples.
func normal_at(x: float, z: float, sample_dist: float = -1.0) -> Vector3:
	var e := sample_dist if sample_dist > 0.0 else config.vertex_spacing * 0.5
	var dx := height_at(x - e, z) - height_at(x + e, z)
	var dz := height_at(x, z - e) - height_at(x, z + e)
	return Vector3(dx, 2.0 * e, dz).normalized()


## Slope in degrees (0 = flat, 90 = vertical).
func slope_degrees_at(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(normal_at(x, z).y, -1.0, 1.0)))


## Vertex color for a given world-space height.
func color_at_height(y: float) -> Color:
	return config.color_for_normalized_height(y / maxf(config.height_multiplier, 0.0001))
