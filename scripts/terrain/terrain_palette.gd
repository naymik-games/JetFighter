class_name TerrainPalette
extends Resource
## Colors for one biome. Flat faces ("tops") are colored by height band,
## steep faces ("cliffs") cycle through strata colors by height.
## All heights are in world units.

@export_group("Tops (flat and gently sloped faces)")
## Flat faces just above the waterline.
@export var beach_color: Color = Color(0.82, 0.78, 0.60)
## Below mid_start.
@export var lowland_color: Color = Color(0.76, 0.82, 0.58)
## From mid_start up to high_start.
@export var mid_color: Color = Color(0.60, 0.74, 0.46)
## From high_start up to peak_start.
@export var high_color: Color = Color(0.46, 0.42, 0.43)
## Above peak_start (snow or bare rock caps).
@export var peak_color: Color = Color(0.90, 0.92, 0.94)
@export var mid_start: float = 13.0
@export var high_start: float = 29.0
## Set very high (9999) to disable peak caps for a biome.
@export var peak_start: float = 46.0

@export_group("Cliffs (steep faces)")
## Strata colors, cycled by height.
@export var cliff_colors: PackedColorArray = PackedColorArray()
## Used instead of cliff_colors above peak_start. Leave empty to keep using cliff_colors.
@export var high_cliff_colors: PackedColorArray = PackedColorArray()
## Height of one strata band.
@export var strata_thickness: float = 3.0
## Color of the thin shader stripe lines drawn over cliffs.
@export var stripe_color: Color = Color(0.45, 0.72, 0.84)
## Used instead of stripe_color above peak_start (when high_cliff_colors is used).
@export var high_stripe_color: Color = Color(0.36, 0.36, 0.42)


func top_color_at(h: float) -> Color:
	if h >= peak_start:
		return peak_color
	if h >= high_start:
		return high_color
	if h >= mid_start:
		return mid_color
	return lowland_color


func stripe_color_at(h: float) -> Color:
	if h >= peak_start and not high_cliff_colors.is_empty():
		return high_stripe_color
	return stripe_color


func cliff_color_at(h: float) -> Color:
	var colors := cliff_colors
	if h >= peak_start and not high_cliff_colors.is_empty():
		colors = high_cliff_colors
	if colors.is_empty():
		return high_color
	var band := int(floorf(h / maxf(strata_thickness, 0.01)))
	return colors[posmod(band, colors.size())]


## Light green tops, olive and teal strata, gray rock and snowy peaks.
static func meadow() -> TerrainPalette:
	var p := TerrainPalette.new()
	p.beach_color = Color(0.82, 0.78, 0.60)
	p.lowland_color = Color(0.76, 0.82, 0.58)
	p.mid_color = Color(0.60, 0.74, 0.46)
	p.high_color = Color(0.46, 0.42, 0.43)
	p.peak_color = Color(0.90, 0.92, 0.94)
	p.mid_start = 13.0
	p.high_start = 29.0
	p.peak_start = 46.0
	p.cliff_colors = PackedColorArray([
		Color(0.68, 0.78, 0.52),
		Color(0.52, 0.72, 0.74),
		Color(0.60, 0.73, 0.48),
	])
	p.high_cliff_colors = PackedColorArray([
		Color(0.56, 0.56, 0.60),
		Color(0.46, 0.46, 0.50),
		Color(0.64, 0.64, 0.66),
	])
	p.strata_thickness = 3.0
	p.stripe_color = Color(0.45, 0.72, 0.84)
	p.high_stripe_color = Color(0.36, 0.36, 0.42)
	return p


## Brown lowlands, orange mesa tops, red-brown strata. No peak caps.
static func mesa() -> TerrainPalette:
	var p := TerrainPalette.new()
	p.beach_color = Color(0.80, 0.68, 0.50)
	p.lowland_color = Color(0.72, 0.50, 0.38)
	p.mid_color = Color(0.80, 0.56, 0.34)
	p.high_color = Color(0.92, 0.66, 0.30)
	p.peak_color = Color(0.92, 0.66, 0.30)
	p.mid_start = 13.0
	p.high_start = 29.0
	p.peak_start = 9999.0
	p.cliff_colors = PackedColorArray([
		Color(0.60, 0.28, 0.28),
		Color(0.42, 0.22, 0.24),
		Color(0.52, 0.40, 0.40),
	])
	p.strata_thickness = 3.0
	p.stripe_color = Color(0.80, 0.32, 0.30)
	p.high_stripe_color = Color(0.80, 0.32, 0.30)
	return p
