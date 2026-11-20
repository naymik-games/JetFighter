class_name TerrainWater
extends MeshInstance3D
## One big flat water plane at sea level that follows the jet.
## Flat fog-colored water plus a tiling streak texture that drifts slowly.
## The streak UVs are computed from world position, so snapping the plane to a
## grid never makes the streaks slide. Created and updated by Terrain.

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, depth_draw_opaque;

uniform vec4 water_color : source_color = vec4(0.4, 0.55, 0.5, 1.0);
uniform vec4 streak_color : source_color = vec4(0.96, 0.94, 0.84, 1.0);
uniform sampler2D streak_tex : filter_linear_mipmap, repeat_enable;
uniform float streak_opacity = 0.75;
uniform float tile_size = 200.0;
uniform vec2 uv_offset = vec2(0.0);

varying vec2 streak_uv;

void vertex() {
	// Local position is small (plane-centered), so this stays precise far from the origin.
	streak_uv = VERTEX.xz / tile_size + uv_offset;
}

void fragment() {
	float m = texture(streak_tex, streak_uv).r * streak_opacity;
	ALBEDO = mix(water_color.rgb, streak_color.rgb, m);
}
"""

var _config: TerrainConfig
var _material := ShaderMaterial.new()
var _sea_level := 0.0
var _drift := 0.0 # in tiles, wrapped to 0..1


func setup(p_config: TerrainConfig, p_sea_level: float) -> void:
	_config = p_config
	_sea_level = p_sea_level
	name = "Water"
	top_level = true # ignore the parent's transform, we position in world space
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var plane := PlaneMesh.new()
	plane.size = Vector2(_config.water_plane_size, _config.water_plane_size)
	mesh = plane

	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material.shader = shader
	_material.set_shader_parameter("streak_tex", make_streak_texture(256, _config.water_streak_count, 7))
	_material.set_shader_parameter("streak_color", _config.water_streak_color)
	_material.set_shader_parameter("streak_opacity", _config.water_streak_opacity)
	_material.set_shader_parameter("tile_size", maxf(_config.water_tile_size, 1.0))
	material_override = _material
	position = Vector3(0.0, _sea_level, 0.0)


func _ready() -> void:
	var color := _config.water_color
	if _config.water_match_fog:
		var fog: Variant = _find_fog_color()
		if fog != null:
			color = fog
		else:
			push_warning("TerrainWater: no enabled fog found, using TerrainConfig.water_color.")
	set_water_color(color)


func set_water_color(color: Color) -> void:
	_material.set_shader_parameter("water_color", color)


## Call every frame with the jet's world position.
func follow(target: Vector3, delta: float) -> void:
	var snap := maxf(_config.water_snap, 1.0)
	var sx := snappedf(target.x, snap)
	var sz := snappedf(target.z, snap)
	global_position = Vector3(sx, _sea_level, sz)

	var tile := maxf(_config.water_tile_size, 1.0)
	_drift = fposmod(_drift + _config.water_drift_speed * delta / tile, 1.0)
	# uv = local / tile + offset. Adding plane_pos / tile makes the UV a pure function
	# of world position; subtracting the drift slides the pattern along +X.
	_material.set_shader_parameter("uv_offset", Vector2(
		fposmod(sx / tile - _drift, 1.0),
		fposmod(sz / tile, 1.0)))


func _find_fog_color() -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.environment != null and cam.environment.fog_enabled:
		return cam.environment.fog_light_color
	for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env != null and env.fog_enabled:
			return env.fog_light_color
	return null


## Tileable mask: thin hard-edged lens shapes, one per cell of a jittered grid.
## Only the red channel is used (white = streak).
static func make_streak_texture(size: int, count: int, rng_seed: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var cols := int(ceil(sqrt(float(count))))
	var rows := int(ceil(float(count) / cols))
	var cell_w := float(size) / cols
	var cell_h := float(size) / rows

	for row in rows:
		for col in cols:
			var cx := (col + rng.randf()) * cell_w
			var cy := (row + rng.randf()) * cell_h
			var half_len := rng.randf_range(0.12, 0.30) * size
			var half_thick := rng.randf_range(1.5, 3.2)
			var slope := rng.randf_range(-0.05, 0.05)
			for dx in range(-int(half_len), int(half_len) + 1):
				var t := float(dx) / half_len
				var h := half_thick * (1.0 - t * t) # tapers to a point at both ends
				var yc := int(round(dx * slope))
				for dy in range(-int(ceil(half_thick)), int(ceil(half_thick)) + 1):
					if absf(dy) <= h:
						img.set_pixel(posmod(int(cx) + dx, size), posmod(int(cy) + yc + dy, size), Color.WHITE)

	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
