class_name TerrainConfig
extends Resource
## Every tunable terrain setting in one place.
## Leave the Terrain node's Config slot empty to use these defaults, or save a
## .tres of this resource and assign it there to tweak values in the Inspector.

@export_group("Seed & Noise")
## 0 = pick a random seed every run. Any other value gives a repeatable world.
@export var world_seed: int = 12345
@export var noise_frequency: float = 0.008

@export_group("Height")
@export var height_multiplier: float = 14.0
## Normalized noise value below which terrain is flattened to sea level.
@export var water_floor: float = -0.05

@export_group("Chunks")
@export var chunk_size: float = 160.0
@export var vertex_spacing: float = 8.0
## Radius of chunks around the jet (3 = 7x7 grid).
@export var render_distance: int = 3

@export_group("Color Bands (normalized height)")
@export var water_max: float = -0.04
@export var sand_max: float = 0.08
@export var grass_max: float = 0.45
@export var rock_max: float = 0.72

@export_group("Colors")
@export var water_color: Color = Color(0.16, 0.45, 0.78)
@export var sand_color: Color = Color(0.74, 0.675, 0.427, 1.0)
@export var grass_color: Color = Color(0.247, 0.515, 0.229, 1.0)
@export var rock_color: Color = Color(0.42, 0.40, 0.38)
@export var snow_color: Color = Color(0.95, 0.96, 0.98)


## World-space height of the water surface.
func sea_level() -> float:
	return water_floor * height_multiplier


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
