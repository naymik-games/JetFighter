class_name TerrainConfig
extends Resource
## Every tunable terrain setting in one place.
## Leave the Terrain node's Config slot empty to use these defaults, or save a
## .tres of this resource and assign it there to tweak values in the Inspector.
## All heights are in world units (the HUD shows them multiplied by 10).

@export_group("Seed & Noise")
## 0 = pick a random seed every run. Any other value gives a repeatable world.
@export var world_seed: int = 12345
## Island-mask frequency. Lower = bigger landmasses and wider stretches of sea.
@export var noise_frequency: float = 0.003

@export_group("Islands")
## Island-mask value (-1..1) above which there is land. Higher = more sea.
@export_range(-0.6, 0.6, 0.01) var land_threshold: float = 0.05
## How far above the threshold the mask must climb to reach full inland height.
## Smaller = steeper coasts and more of the map at full height.
@export_range(0.1, 1.0, 0.01) var land_range: float = 0.4
## How deep the seabed sits below sea level (hidden once the water plane exists).
@export var seabed_depth: float = 3.0
## Above 1 = wider flat lowlands around coasts before the terraces start rising.
@export_range(0.5, 3.0, 0.05) var inland_curve: float = 1.6

@export_group("Height")
## Hard cap on terrain height (also the scale for the legacy color bands).
@export var height_multiplier: float = 60.0
## World-space height of the water surface.
@export var sea_level_y: float = 0.0
## Height of the lowest land plateau above sea level.
@export var lowland_height: float = 1.5
## How far the island interiors rise above the lowlands before mountains.
@export var base_relief: float = 20.0
## Small bumps that give terrace edges organic outlines.
@export var rolling_amplitude: float = 3.0
@export var rolling_frequency: float = 0.018

@export_group("Mountains")
## Extra height added by ridged mountains inside mountain zones.
@export var mountain_height: float = 34.0
## Ridge frequency. Higher = tighter, busier ridges.
@export var mountain_frequency: float = 0.012
## Frequency of the noise that decides where mountain zones are.
@export var mountain_zone_frequency: float = 0.004
## Zone-mask value above which mountains start. Higher = fewer mountain zones.
@export_range(-0.5, 0.8, 0.01) var mountain_zone_threshold: float = 0.1
## Exponent on the ridge shape. Higher = thinner, sharper crests.
@export_range(1.0, 4.0, 0.1) var ridge_sharpness: float = 1.0

@export_group("Terraces")
## Height of one terrace step. Risers this tall across one 8-unit cell give ~45 degree cliffs.
@export var terrace_step: float = 8.0
## 0 = smooth slopes, close to 1 = hard steps. Used in lowlands.
@export_range(0.0, 0.98, 0.01) var terrace_sharpness_low: float = 0.75
## Same, but used inside mountain zones.
@export_range(0.0, 0.98, 0.01) var terrace_sharpness_high: float = 0.92

@export_group("Biomes & Face Colors")
## Biome-mask frequency. Lower = bigger regions of each biome.
@export var biome_frequency: float = 0.0015
## Mask value above which the Mesa biome is used. Raise it for fewer Mesa regions.
@export_range(-0.6, 0.6, 0.01) var biome_threshold: float = 0.0
## Faces steeper than this count as cliffs (strata colors), flatter ones as tops.
@export_range(10.0, 80.0, 1.0) var cliff_slope_degrees: float = 30.0
## Flat faces lower than this above sea level get the beach color.
@export var beach_height: float = 2.2
@export var meadow_palette: TerrainPalette = TerrainPalette.meadow()
@export var mesa_palette: TerrainPalette = TerrainPalette.mesa()

@export_group("Water & Shoreline")
## Take the water color from the scene's fog (Camera or WorldEnvironment) so the sea melts into the horizon.
## If no fog is found, or this is off, the water_color further down is used instead.
@export var water_match_fog: bool = true
## Color of the drifting streaks on the water.
@export var water_streak_color: Color = Color(0.96, 0.94, 0.84)
## How strongly the streaks show (0 = invisible, 1 = solid).
@export_range(0.0, 1.0, 0.01) var water_streak_opacity: float = 0.75
## World size of one streak-texture tile. Bigger = larger, sparser-looking streaks.
@export var water_tile_size: float = 200.0
## Streaks per tile (rounded up to fill a regular grid).
@export_range(4, 64, 1) var water_streak_count: int = 20
## How fast the streaks drift along the world X axis, in units per second.
@export var water_drift_speed: float = 3.0
## Side length of the square water plane. Must reach past the camera far plane / fog end.
@export var water_plane_size: float = 8000.0
## The plane follows the jet in jumps of this many units.
@export var water_snap: float = 64.0
## Bake a cream outline ribbon wherever terrain crosses sea level.
@export var foam_enabled: bool = true
@export var foam_color: Color = Color(0.97, 0.94, 0.82)
## Width of the ribbon, measured outward from the waterline (world units).
@export var foam_width: float = 1.6
## Lift of the ribbon above the water plane. Raise it if you see flicker at long range.
@export var foam_height: float = 0.15

@export_group("Shader Polish")
## Use the terrain shader (thin strata stripes, top blotches, cel steps). Off = plain vertex-color
## material, the cheapest option for weak devices.
@export var shader_enabled: bool = false
@export_subgroup("Strata stripes (steep faces)")
## World-space height between stripe lines.
@export var stripe_period: float = 2.5
## Line thickness as a fraction of the period (each line varies 0.5x to 1.5x).
@export_range(0.01, 0.4, 0.005) var stripe_width: float = 0.08
## 0 = no lines, 1 = lines fully take the palette's stripe color.
@export_range(0.0, 1.0, 0.01) var stripe_strength: float = 0.85
## Subtle light/dark variation between neighbouring bands.
@export_range(0.0, 0.3, 0.005) var stripe_band_tone: float = 0.08
@export_subgroup("Top blotches (flat faces)")
## World size of one noise tile. Bigger = larger blotches.
@export var blotch_tile_size: float = 96.0
## Noise value above which a spot is blotched. Higher = fewer, smaller blotches.
@export_range(0.3, 0.8, 0.01) var blotch_threshold: float = 0.55
## Brightness of a blotch (1 = invisible, lower = darker).
@export_range(0.5, 1.0, 0.01) var blotch_darkness: float = 0.90
## Blotches fade out between these camera distances (they would shimmer far away).
@export var blotch_fade_start: float = 250.0
@export var blotch_fade_end: float = 550.0
@export_subgroup("Lighting")
## Softens how much brighter sun-facing triangles are than the others (wrapped lighting).
## 0 = normal, 1 = very flat. Raise it if neighbouring triangles still look too different.
@export_range(0.0, 1.0, 0.01) var shade_softness: float = 0.5
## Number of light bands for the sun. 0 or 1 = smooth lighting (default).
## Stepped light makes neighbouring triangles contrast harder, so it is off by default.
@export_range(0, 5, 1) var cel_steps: int = 0
## 0 = smooth, 1 = fully stepped.
@export_range(0.0, 1.0, 0.01) var cel_strength: float = 0.5

@export_group("Chunks")
@export var chunk_size: float = 160.0
@export var vertex_spacing: float = 8.0
## Radius of chunks around the jet (3 = 7x7 grid).
@export var render_distance: int = 3

@export_group("Legacy (replaced in later Phase 6 steps)")
## No longer used by the height function. Kept so existing references still compile.
@export var water_floor: float = -0.05

@export_group("Legacy Color Bands (normalized height, replaced by palettes)")
@export var water_max: float = 0.01
@export var sand_max: float = 0.06
@export var grass_max: float = 0.45
@export var rock_max: float = 0.75

@export_group("Colors (water_color is the fallback sea color; the rest is legacy)")
@export var water_color: Color = Color(0.482, 0.596, 0.561)
@export var sand_color: Color = Color(0.74, 0.675, 0.427, 1.0)
@export var grass_color: Color = Color(0.247, 0.515, 0.229, 1.0)
@export var rock_color: Color = Color(0.42, 0.40, 0.38)
@export var snow_color: Color = Color(0.95, 0.96, 0.98)


func palette_for(biome: int) -> TerrainPalette:
	return mesa_palette if biome == 1 else meadow_palette


## World-space height of the water surface.
func sea_level() -> float:
	return sea_level_y


func color_for_normalized_height(h: float) -> Color:
	if h <= water_max:
		return water_color
	elif h < sand_max:
		return sand_color
	elif h < grass_max:
		return grass_color
	elif h < rock_max:
		return rock_color
	return snow_color
