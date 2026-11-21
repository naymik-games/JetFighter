class_name ObjectiveChain
extends RefCounted
## Turns a MissionConfig into a FIXED list of objective positions.
##
## Same mission seed -> same positions, every run, on every machine. Nothing here depends
## on where the player is or flies. Objective 1 is placed relative to the mission start,
## and each later objective relative to the previous one (the player will be near the
## previous objective when the next is revealed, so legs still feel like 20-40 seconds).
##
## Pure functions over a TerrainSampler: no scene tree, no chunks needed, so objectives
## far outside the loaded area can still be placed.
##
## Each try picks a random spot (seeded). If that spot is not acceptable, a local search
## scans outward in rings around it for the nearest acceptable spot, so terraced terrain
## does not need hundreds of blind tries. The leg length and bearing are then measured from
## the spot actually used, so the search can stretch a leg by up to SEARCH_RADIUS.

## Tries per objective before settling for the least-bad site.
const MAX_ATTEMPTS: int = 80
## After this many failed tries the turn limit is lifted (any direction) to find land.
const WIDEN_AFTER: int = 40
## The ground must be at least this far above sea level everywhere on the footprint.
const MIN_HEIGHT_ABOVE_SEA: float = 1.0
## Largest height difference allowed across the footprint (catches terrace risers).
const FOOTPRINT_MAX_RELIEF: float = 3.0
## Number of points sampled around the footprint ring (plus the centre).
const FOOTPRINT_RING_POINTS: int = 8
## How far from the random spot the local search may look, in world units.
const SEARCH_RADIUS: float = 64.0


## Returns one placement per objective, in mission order.
## Warns (does not fail) when the sampler's seed differs from the mission seed.
static func generate(mission: MissionConfig, sampler: TerrainSampler) -> Array[ObjectivePlacement]:
	var result: Array[ObjectivePlacement] = []
	if mission == null or sampler == null:
		push_error("ObjectiveChain.generate: mission or sampler is null.")
		return result
	if sampler.seed_value != mission.seed_value:
		push_warning("ObjectiveChain: sampler seed (%d) differs from mission seed (%d). Positions will not match the world." % [sampler.seed_value, mission.seed_value])

	var prev_pos := mission.start_position
	var prev_bearing := mission.start_heading_degrees

	for i in mission.objectives.size():
		var obj := mission.objectives[i]
		if obj == null:
			push_error("ObjectiveChain.generate: objective %d is empty, stopping." % (i + 1))
			return result
		var placement := _place(mission, sampler, obj, i, prev_pos, prev_bearing)
		placement.defenders = ObjectiveDefenses.plan(sampler, obj, placement, mission.seed_value)
		result.append(placement)
		# Even a fallback site is used as the next origin, so the chain stays deterministic.
		prev_pos = placement.xz()
		prev_bearing = placement.bearing_degrees
	return result


## Unit direction on the ground plane for a bearing in degrees clockwise from -Z.
## 0 = -Z, 90 = +X, 180 = +Z, 270 = -X.
static func bearing_to_dir(bearing_degrees: float) -> Vector2:
	var r := deg_to_rad(bearing_degrees)
	return Vector2(sin(r), -cos(r))


## Inverse of bearing_to_dir for a ground-plane offset (x, z).
static func offset_to_bearing(offset: Vector2) -> float:
	return rad_to_deg(atan2(offset.x, -offset.y))


## Readable summary of a generated chain, including the turn angle between legs.
static func describe(placements: Array[ObjectivePlacement]) -> String:
	var lines := PackedStringArray()
	var prev_bearing := NAN
	for p in placements:
		var line := p.to_line()
		if not is_nan(prev_bearing):
			line += "  turn=%.1f" % wrapf(p.bearing_degrees - prev_bearing, -180.0, 180.0)
		lines.append(line)
		prev_bearing = p.bearing_degrees
	return "\n".join(lines)


## True when two chains have identical positions (used by the debug check).
static func same_positions(a: Array[ObjectivePlacement], b: Array[ObjectivePlacement]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].position.is_equal_approx(b[i].position):
			return false
	return true


static func _place(mission: MissionConfig, sampler: TerrainSampler, obj: ObjectiveConfig, index: int, prev_pos: Vector2, prev_bearing: float) -> ObjectivePlacement:
	var dist_range := obj.leg_distance_range(mission.cruise_speed)

	var best: ObjectivePlacement = null
	var best_penalty := INF

	for attempt in MAX_ATTEMPTS:
		# Every (mission seed, objective, attempt) triple has its own random stream, so an
		# objective's result never depends on how many random numbers other code consumed.
		var rng := RandomNumberGenerator.new()
		rng.seed = mix_seed(mission.seed_value, index, attempt)

		var turn_limit := obj.max_turn_degrees if attempt < WIDEN_AFTER else 180.0
		var leg := rng.randf_range(dist_range.x, dist_range.y)
		var bearing := prev_bearing + rng.randf_range(-turn_limit, turn_limit)
		var yaw := rng.randf_range(0.0, TAU)

		var wanted := prev_pos + bearing_to_dir(bearing) * leg
		var found := _find_site(sampler, obj, wanted)
		var site: Vector2 = found["site"]
		var fit: Dictionary = found["fit"]

		# Measure the leg from where the objective really ended up.
		var offset := site - prev_pos

		var candidate := ObjectivePlacement.new()
		candidate.index = index
		candidate.objective = obj
		candidate.position = Vector3(site.x, fit["center_height"], site.y)
		candidate.normal = sampler.surface_normal_at(site.x, site.y)
		candidate.yaw = yaw
		candidate.bearing_degrees = offset_to_bearing(offset)
		candidate.leg_distance = offset.length()
		candidate.time_limit = obj.time_limit_for_leg(candidate.leg_distance, mission)
		candidate.attempts_used = attempt
		candidate.moved = site.distance_to(wanted)
		candidate.valid = fit["ok"]
		candidate.max_slope_degrees = fit["max_slope"]
		candidate.relief = fit["relief"]

		if candidate.valid:
			return candidate
		if fit["penalty"] < best_penalty:
			best_penalty = fit["penalty"]
			best = candidate

	push_warning("ObjectiveChain: no good site for objective %d (%s) after %d tries; using the least-bad one." % [index + 1, obj.get_display_name(), MAX_ATTEMPTS])
	return best


## Tests the wanted spot; if it fails, scans rings of growing radius around it and returns the
## first acceptable spot (so the nearest one, in a fixed scan order). When nothing passes it
## returns the least-bad spot it saw. Returns { site: Vector2, fit: Dictionary }.
static func _find_site(sampler: TerrainSampler, obj: ObjectiveConfig, wanted: Vector2) -> Dictionary:
	var best_site := wanted
	var best_fit := _evaluate_site(sampler, obj, wanted, false)
	if best_fit["ok"]:
		return {"site": best_site, "fit": best_fit}

	var min_land := sampler.sea_level + MIN_HEIGHT_ABOVE_SEA
	var step := maxf(sampler.config.vertex_spacing, 4.0)
	var r := step
	while r <= SEARCH_RADIUS:
		var count := maxi(8, int(ceil(TAU * r / step)))
		for k in count:
			var a := TAU * float(k) / float(count)
			var s := wanted + Vector2(cos(a), sin(a)) * r
			# Cheap rejection first: one height sample tells us whether this is even land.
			if sampler.height_at(s.x, s.y) <= min_land:
				continue
			var f := _evaluate_site(sampler, obj, s, true)
			if f["ok"]:
				return {"site": s, "fit": f}
			if f["penalty"] < best_fit["penalty"]:
				best_site = s
				best_fit = f
		r += step
	return {"site": best_site, "fit": best_fit}


## Checks the site centre plus a ring of points around it.
## early_out stops at the first failing point (much cheaper; the penalty is then only a
## rough ranking). Returns { ok, penalty, center_height, max_slope, relief }.
static func _evaluate_site(sampler: TerrainSampler, obj: ObjectiveConfig, site: Vector2, early_out: bool) -> Dictionary:
	var min_land := sampler.sea_level + MIN_HEIGHT_ABOVE_SEA
	var center_h := sampler.surface_height_at(site.x, site.y)
	var min_h := center_h
	var max_h := center_h
	var max_slope := sampler.surface_slope_degrees_at(site.x, site.y)
	var all_land := center_h > min_land

	for k in FOOTPRINT_RING_POINTS:
		if early_out and (not all_land or max_slope > obj.max_slope_degrees or (max_h - min_h) > FOOTPRINT_MAX_RELIEF):
			break
		var a := TAU * float(k) / float(FOOTPRINT_RING_POINTS)
		var q := site + Vector2(cos(a), sin(a)) * obj.footprint_radius
		var h := sampler.surface_height_at(q.x, q.y)
		if h <= min_land:
			all_land = false
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
		max_slope = maxf(max_slope, sampler.surface_slope_degrees_at(q.x, q.y))

	var relief := max_h - min_h
	var ok := all_land and max_slope <= obj.max_slope_degrees and relief <= FOOTPRINT_MAX_RELIEF

	# Used only to pick the least-bad site when nothing passes: water is far worse than a slope.
	var penalty := max_slope + relief
	if not all_land:
		penalty += 1000.0

	return {
		"ok": ok,
		"penalty": penalty,
		"center_height": center_h,
		"max_slope": max_slope,
		"relief": relief,
	}


## Deterministic integer mixer (splitmix-style). Public so ObjectiveDefenses can share it. Does not rely on Godot's hash(), whose
## output is not guaranteed to be stable between engine versions.
static func mix_seed(a: int, b: int, c: int) -> int:
	var h: int = a * 0x9E3779B1 + b * 0x85EBCA6B + c * 0xC2B2AE35 + 0x27D4EB2F
	h = (h ^ (h >> 15)) * 0x2C1B3C6D
	h = (h ^ (h >> 12)) * 0x297A2D39
	h = h ^ (h >> 15)
	return h & 0x7FFFFFFFFFFFFFFF
