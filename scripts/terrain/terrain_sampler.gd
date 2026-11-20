class_name TerrainSampler
extends RefCounted
## Read-only terrain queries. Safe to call from worker threads because nothing
## is modified after _init(). Everything that needs ground height, sea level,
## slope or colors should ask this class instead of using its own numbers.

var config: TerrainConfig
var seed_value: int = 0
var sea_level: float = 0.0

const BIOME_MEADOW := 0
const BIOME_MESA := 1

var _continent := FastNoiseLite.new()
var _rolling := FastNoiseLite.new()
var _zone := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _biome := FastNoiseLite.new()
var _cliff_min_normal_y: float = 0.85


func _init(p_config: TerrainConfig) -> void:
	config = p_config
	seed_value = config.world_seed if config.world_seed != 0 else maxi(randi(), 1)

	_setup_noise(_continent, seed_value, config.noise_frequency, 2)
	_setup_noise(_rolling, seed_value + 101, config.rolling_frequency, 1)
	_setup_noise(_zone, seed_value + 202, config.mountain_zone_frequency, 1)
	_setup_noise(_ridge, seed_value + 303, config.mountain_frequency, 3)
	_setup_noise(_biome, seed_value + 404, config.biome_frequency, 1)
	_cliff_min_normal_y = cos(deg_to_rad(config.cliff_slope_degrees))

	sea_level = config.sea_level()


func _setup_noise(n: FastNoiseLite, p_seed: int, freq: float, octaves: int) -> void:
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE


## World-space ground height at (x, z). Sea areas return a flat seabed below sea level.
## Pipeline: island mask -> inland rise + rolling bumps -> ridged mountains -> terraces.
func height_at(x: float, z: float) -> float:
	var land_t := (_continent.get_noise_2d(x, z) - config.land_threshold) / config.land_range
	if land_t <= 0.0:
		return sea_level - config.seabed_depth
	land_t = minf(land_t, 1.0)

	# Smooth inland rise; the curve widens the flat lowlands near coasts.
	var inland := pow(smoothstep(0.0, 1.0, land_t), config.inland_curve)
	var h := inland * config.base_relief
	h += _rolling.get_noise_2d(x, z) * config.rolling_amplitude * inland

	# Ridged mountains, only inside mountain zones and away from coasts.
	var zone := smoothstep(config.mountain_zone_threshold, config.mountain_zone_threshold + 0.35, _zone.get_noise_2d(x, z))
	var m := zone * smoothstep(0.3, 0.7, land_t)
	var sharpness := config.terrace_sharpness_low
	if m > 0.0:
		var ridge := clampf(1.0 - absf(_ridge.get_noise_2d(x, z)), 0.0, 1.0)
		h += pow(ridge, config.ridge_sharpness) * m * config.mountain_height
		sharpness = lerpf(config.terrace_sharpness_low, config.terrace_sharpness_high, m)

	h = _terrace(maxf(h, 0.0), sharpness)
	return minf(sea_level + config.lowland_height + h, config.height_multiplier)


## Snaps h to multiples of terrace_step: flat plateaus joined by short risers.
## The plateau heights are constant (k * step), only the riser width changes with sharpness.
func _terrace(h: float, sharpness: float) -> float:
	var step := maxf(config.terrace_step, 0.001)
	var t := h / step
	var k := floorf(t)
	var w := maxf((1.0 - sharpness) * 0.5, 0.0001)
	var s := clampf((t - k - (0.5 - w)) / (2.0 * w), 0.0, 1.0)
	s = s * s * (3.0 - 2.0 * s)
	return (k + s) * step


## Heights for a (count+1) x (count+1) grid of vertices starting at (origin_x, origin_z),
## spaced vertex_spacing apart. Index = ix * (count + 1) + iz.
## Sampling each grid point once is ~4x cheaper than sampling per cell corner.
func sample_grid(origin_x: float, origin_z: float, count: int) -> PackedFloat32Array:
	var n := count + 1
	var s := config.vertex_spacing
	var out := PackedFloat32Array()
	out.resize(n * n)
	for ix in n:
		for iz in n:
			out[ix * n + iz] = height_at(origin_x + ix * s, origin_z + iz * s)
	return out


## Tuning aid: samples a square area around the origin and reports land share and heights.
func debug_summary(half_extent: float = 1500.0, step: float = 30.0, reference_altitude: float = 50.0) -> Dictionary:
	var total := 0
	var land := 0
	var above_ref := 0
	var max_h := -INF
	var sum_land := 0.0
	var mesa := 0
	var count := int(2.0 * half_extent / step) + 1
	for i in count:
		for j in count:
			var px := -half_extent + i * step
			var pz := -half_extent + j * step
			var h := height_at(px, pz)
			total += 1
			max_h = maxf(max_h, h)
			if h > sea_level:
				land += 1
				sum_land += h
				if biome_at(px, pz) == BIOME_MESA:
					mesa += 1
				if h > reference_altitude:
					above_ref += 1
	return {
		"land_percent": snappedf(100.0 * land / maxf(total, 1), 0.1),
		"max_height": snappedf(max_h, 0.1),
		"mean_land_height": snappedf(sum_land / maxf(land, 1), 0.1),
		"mesa_percent_of_land": snappedf(100.0 * mesa / maxf(land, 1), 0.1),
		"land_above_reference_percent": snappedf(100.0 * above_ref / maxf(land, 1), 0.1),
	}


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


## Which biome is at (x, z): BIOME_MEADOW or BIOME_MESA. Hard borders.
func biome_at(x: float, z: float) -> int:
	return BIOME_MESA if _biome.get_noise_2d(x, z) > config.biome_threshold else BIOME_MEADOW


## Color for one triangle. normal_y is the face normal's Y (1 = flat, 0 = vertical),
## height is the triangle's average world height.
## Water is no longer painted onto the terrain (the water plane draws it).
func face_color(normal_y: float, height: float, biome: int) -> Color:
	var palette := config.palette_for(biome)
	if normal_y < _cliff_min_normal_y:
		return palette.cliff_color_at(height)
	if height < sea_level + config.beach_height:
		return palette.beach_color
	return palette.top_color_at(height)


## True for faces steep enough to count as cliffs (strata colors and shader stripes).
func is_cliff_face(normal_y: float) -> bool:
	return normal_y < _cliff_min_normal_y


## Color for a visible triangle. Triangles that dip below sea level are shoreline
## ramps, so they get the beach color whatever their slope. Everything else uses face_color().
func triangle_color(normal_y: float, min_height: float, avg_height: float, biome: int) -> Color:
	if min_height < sea_level:
		return config.palette_for(biome).beach_color
	return face_color(normal_y, avg_height, biome)


## Legacy: single-ramp vertex color for a given world-space height.
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
