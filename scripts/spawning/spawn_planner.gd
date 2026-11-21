class_name SpawnPlanner
extends RefCounted
## Decides what spawns where on a chunk. Deterministic: the same world seed and
## chunk coordinate always give the same plan, so reloading a chunk reproduces it.
## Only reads data (sampler, table), so it is safe to call from worker threads.

var _table: SpawnTable
var _sampler: TerrainSampler


func _init(table: SpawnTable, sampler: TerrainSampler) -> void:
	_table = table
	_sampler = sampler


func plan_chunk(coord: Vector2i) -> Array[SpawnPoint]:
	var points: Array[SpawnPoint] = []
	var size := _sampler.config.chunk_size
	var origin := Vector2(coord.x * size, coord.y * size)
	var center_dist := (origin + Vector2(size, size) * 0.5 - _table.origin).length()
	var rng := RandomNumberGenerator.new()

	for rule_index in _table.rules.size():
		var rule: SpawnRule = _table.rules[rule_index]
		if rule == null or rule.scene == null:
			continue

		# Each rule has its own RNG stream, so editing one rule never reshuffles the others
		rng.seed = hash(Vector4i(_sampler.seed_value, coord.x, coord.y, rule_index))

		var chance := clampf(
			rule.chance_per_chunk + rule.chance_growth_per_1000 * center_dist / 1000.0, 0.0, 1.0
		)
		if rng.randf() >= chance:
			continue

		var count := rng.randi_range(rule.min_count, maxi(rule.min_count, rule.max_count))
		var anchor := Vector2.INF

		for n in count:
			if points.size() >= _table.max_spawns_per_chunk:
				break

			var xz := _find_xz(rule, origin, anchor, rng, points)
			if not xz.is_finite():
				continue
			if rule.cluster_radius > 0.0 and not anchor.is_finite():
				anchor = xz

			var point := SpawnPoint.new()
			point.id = "%d_%d_%d_%d" % [coord.x, coord.y, rule_index, n]
			point.rule = rule
			point.position = Vector3(
				xz.x,
				_sampler.surface_height_at(xz.x, xz.y) + rule.ground_offset,
				xz.y
			)
			point.normal = _sampler.surface_normal_at(xz.x, xz.y)
			point.yaw = rng.randf() * TAU if rule.random_yaw else 0.0
			points.append(point)

	return points


# Returns a valid world X/Z for this rule, or Vector2.INF if no attempt succeeded.
func _find_xz(rule: SpawnRule, origin: Vector2, anchor: Vector2, rng: RandomNumberGenerator, existing: Array[SpawnPoint]) -> Vector2:
	var size := _sampler.config.chunk_size
	var margin := _table.edge_margin

	for attempt in rule.max_attempts:
		var xz: Vector2
		if rule.cluster_radius > 0.0 and anchor.is_finite():
			var angle := rng.randf() * TAU
			var dist := sqrt(rng.randf()) * rule.cluster_radius
			xz = anchor + Vector2(cos(angle), sin(angle)) * dist
		else:
			xz = origin + Vector2(
				rng.randf_range(margin, size - margin),
				rng.randf_range(margin, size - margin)
			)

		# Stay inside this chunk's margin
		if xz.x < origin.x + margin or xz.x > origin.x + size - margin:
			continue
		if xz.y < origin.y + margin or xz.y > origin.y + size - margin:
			continue

		if (xz - _table.origin).length() < rule.min_distance_from_origin:
			continue

		var altitude := _sampler.surface_height_at(xz.x, xz.y) - _sampler.sea_level
		if altitude < rule.min_altitude or altitude > rule.max_altitude:
			continue

		if _sampler.surface_slope_degrees_at(xz.x, xz.y) > rule.max_slope_degrees:
			continue

		if _in_exclusion(xz):
			continue

		if _too_close(xz, rule.min_spacing, existing):
			continue

		return xz

	return Vector2.INF


func _in_exclusion(xz: Vector2) -> bool:
	for zone in _table.exclusions:
		if Vector2(zone.x, zone.y).distance_to(xz) < zone.z:
			return true
	return false


func _too_close(xz: Vector2, min_spacing: float, existing: Array[SpawnPoint]) -> bool:
	for other in existing:
		if Vector2(other.position.x, other.position.z).distance_to(xz) < min_spacing:
			return true
	return false
