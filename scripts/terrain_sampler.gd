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


## Height of the actual chunk MESH at (x, z). The mesh is triangulated every
## vertex_spacing units, so on slopes it differs slightly from height_at().
## Use this to place things so they sit exactly on the visible surface.
func surface_height_at(x: float, z: float) -> float:
	var c := _surface_cell(x, z)
	var h00: float = c[4]
	var h10: float = c[5]
	var h01: float = c[6]
	var h11: float = c[7]
	var fx: float = c[2]
	var fz: float = c[3]
	if fx + fz <= 1.0:
		return h00 + fx * (h10 - h00) + fz * (h01 - h00)
	return h11 + (1.0 - fx) * (h01 - h11) + (1.0 - fz) * (h10 - h11)


## Normal of the mesh triangle under (x, z) (flat-shaded, matches what you see).
func surface_normal_at(x: float, z: float) -> Vector3:
	var c := _surface_cell(x, z)
	var s := config.vertex_spacing
	var x0: float = c[0]
	var z0: float = c[1]
	var fx: float = c[2]
	var fz: float = c[3]
	var v00 := Vector3(x0, c[4], z0)
	var v10 := Vector3(x0 + s, c[5], z0)
	var v01 := Vector3(x0, c[6], z0 + s)
	var v11 := Vector3(x0 + s, c[7], z0 + s)

	var n: Vector3
	if fx + fz <= 1.0:
		n = (v01 - v00).cross(v10 - v00)
	else:
		n = (v11 - v10).cross(v01 - v10)
	if n.y < 0.0:
		n = -n
	return n.normalized()


## Slope of the mesh triangle under (x, z), in degrees (0 = flat).
func surface_slope_degrees_at(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(surface_normal_at(x, z).y, -1.0, 1.0)))


# Returns [x0, z0, fx, fz, h00, h10, h01, h11] for the grid cell containing (x, z).
# Triangles match the chunk builder: (v00, v10, v01) and (v10, v11, v01).
func _surface_cell(x: float, z: float) -> Array:
	var s := config.vertex_spacing
	var x0 := floorf(x / s) * s
	var z0 := floorf(z / s) * s
	return [
		x0, z0, (x - x0) / s, (z - z0) / s,
		height_at(x0, z0), height_at(x0 + s, z0),
		height_at(x0, z0 + s), height_at(x0 + s, z0 + s)
	]
