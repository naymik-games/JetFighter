class_name TerrainMaterial
extends RefCounted
## Builds the one material shared by every terrain chunk.
## Vertex color stays the base color. The shader adds, using world-space data only
## (so nothing changes at chunk borders):
##   - thin strata stripes by world Y on steep faces
##   - mottled blotches on flat faces from a tiling noise texture
##   - optional stepped (cel) sunlight
## Each vertex carries CUSTOM0 = (stripe color rgb, face kind in alpha), baked by Terrain.
## Face kind: 0.0 = plain (foam), 0.5 = top, 1.0 = cliff.

const SHADER_CODE := """
shader_type spatial;
render_mode specular_disabled;

uniform sampler2D blotch_tex : filter_linear_mipmap, repeat_enable;
uniform float blotch_tile = 96.0;
uniform float blotch_threshold = 0.55;
uniform float blotch_darkness = 0.9;
uniform float blotch_fade_start = 250.0;
uniform float blotch_fade_end = 550.0;

uniform float stripe_period = 2.5;
uniform float stripe_width = 0.08;
uniform float stripe_strength = 0.85;
uniform float band_tone = 0.08;

uniform float shade_softness = 0.5;
uniform float cel_steps = 0.0;
uniform float cel_strength = 0.5;

varying vec3 v_stripe_color;
varying float v_kind;
varying vec2 v_blotch_uv;
varying float v_world_y;

float hash11(float p) {
	return fract(sin(p * 12.9898) * 43758.5453);
}

void vertex() {
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	// Chunk origins are multiples of the chunk size, so wrapping them by the tile size
	// keeps the noise a pure function of world position while the numbers stay small.
	vec2 origin = mod(MODEL_MATRIX[3].xz, blotch_tile);
	v_blotch_uv = (VERTEX.xz + origin) / blotch_tile;
	v_stripe_color = CUSTOM0.rgb;
	v_kind = CUSTOM0.a;
}

void fragment() {
	vec3 albedo = COLOR.rgb;
	float cliff = step(0.75, v_kind);
	float top = step(0.25, v_kind) - cliff;

	// Strata stripes: thin lines at fixed world heights, plus a faint tone shift per band.
	float u = v_world_y / stripe_period;
	float aa = fwidth(u);
	float nearest = floor(u + 0.5);
	float line_w = stripe_width * (0.5 + hash11(nearest));
	float line = 1.0 - smoothstep(line_w - aa, line_w + aa, abs(u - nearest));
	line *= 1.0 - clamp(aa * 2.0, 0.0, 1.0); // fade out when lines get sub-pixel
	float band_shift = (hash11(floor(u) + 3.0) - 0.5) * 2.0 * band_tone;
	vec3 cliff_col = albedo * (1.0 + band_shift);
	cliff_col = mix(cliff_col, v_stripe_color, line * stripe_strength);

	// Top blotches: hard-edged dark patches, faded with distance.
	float n = texture(blotch_tex, v_blotch_uv).r;
	float m = smoothstep(blotch_threshold - 0.03, blotch_threshold + 0.03, n);
	m *= 1.0 - smoothstep(blotch_fade_start, blotch_fade_end, length(VERTEX));
	vec3 top_col = albedo * mix(1.0, blotch_darkness, m);

	albedo = mix(albedo, cliff_col, cliff);
	albedo = mix(albedo, top_col, top);

	ALBEDO = albedo;
	ROUGHNESS = 0.85;
	SPECULAR = 0.0;
}

void light() {
	// Wrapped lambert: lets light reach slightly past the terminator so faces differ less.
	float ndl = clamp((dot(NORMAL, LIGHT) + shade_softness) / (1.0 + shade_softness), 0.0, 1.0);
	float steps = max(cel_steps, 2.0);
	float stepped = min(floor(ndl * steps) / (steps - 1.0), 1.0);
	float l = mix(ndl, stepped, cel_strength * step(1.5, cel_steps));
	DIFFUSE_LIGHT += l * ATTENUATION * LIGHT_COLOR / PI;
}
"""


static func create(config: TerrainConfig) -> Material:
	if not config.shader_enabled:
		var plain := StandardMaterial3D.new()
		plain.vertex_color_use_as_albedo = true
		plain.roughness = 0.85
		return plain

	var shader := Shader.new()
	shader.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("blotch_tex", make_blotch_texture(config.world_seed))
	mat.set_shader_parameter("blotch_tile", maxf(config.blotch_tile_size, 1.0))
	mat.set_shader_parameter("blotch_threshold", config.blotch_threshold)
	mat.set_shader_parameter("blotch_darkness", config.blotch_darkness)
	mat.set_shader_parameter("blotch_fade_start", config.blotch_fade_start)
	mat.set_shader_parameter("blotch_fade_end", maxf(config.blotch_fade_end, config.blotch_fade_start + 1.0))
	mat.set_shader_parameter("stripe_period", maxf(config.stripe_period, 0.05))
	mat.set_shader_parameter("stripe_width", config.stripe_width)
	mat.set_shader_parameter("stripe_strength", config.stripe_strength)
	mat.set_shader_parameter("band_tone", config.stripe_band_tone)
	mat.set_shader_parameter("shade_softness", config.shade_softness)
	mat.set_shader_parameter("cel_steps", float(config.cel_steps))
	mat.set_shader_parameter("cel_strength", config.cel_strength)
	return mat


## Seamless fractal noise (red channel), mipmapped. The seed only changes the pattern.
static func make_blotch_texture(world_seed: int) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed + 505
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.035
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var img := noise.get_seamless_image(256, 256)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
