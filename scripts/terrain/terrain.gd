extends Node3D
## Chunked procedural terrain streaming around the jet.
## All height/color/sea-level data comes from TerrainSampler. What spawns where
## is decided by SpawnPlanner and instantiated by SpawnManager (Phase 3).

@export_group("References")
@export var target_jet: Node3D # Assign your JetFighter node in the Inspector
# These two scenes are only used to build the default SpawnTable when none is assigned
@export var target_scene: PackedScene
@export var sam_turret_scene: PackedScene

@export_group("Config")
## Leave empty to use TerrainConfig defaults.
@export var config: TerrainConfig
## When a mission is selected (MissionSession), use its seed as the world seed so the terrain and
## the mission's objective layout always match. Turn off for a world that ignores missions.
@export var use_mission_seed: bool = true

@export_group("Spawning")
## Leave empty to build a default table from target_scene and sam_turret_scene.
@export var spawn_table: SpawnTable
## Most spawned entities allowed alive at once. The rest wait in a queue.
@export var max_live_targets: int = 60
## Per-frame time budget for instantiating spawned entities.
@export var spawn_budget_ms: float = 2.0

@export_group("Debug")
## Prints land share and height stats at startup. Handy while tuning terrain settings.
@export var print_terrain_summary: bool = true
## The jet's cruise altitude, used only for the "land above" stat.
@export var summary_reference_altitude: float = 50.0

## A chunk finished building and is now in the scene (its children can be added).
signal chunk_ready(coord: Vector2i, chunk: Node3D)
## A chunk is about to be freed (its children go with it).
signal chunk_unloaded(coord: Vector2i)

# Face kinds baked into CUSTOM0.a for the terrain shader (see TerrainMaterial).
const KIND_PLAIN := 0.0
const KIND_TOP := 0.5
const KIND_CLIFF := 1.0

var sampler: TerrainSampler
var planner: SpawnPlanner
var spawn_manager: SpawnManager
var shared_material: Material
var water: TerrainWater

var active_chunks: Dictionary = {}   # { Vector2i: MeshInstance3D }
var pending_chunks: Dictionary = {}  # { Vector2i: int (task_id) }
var needed_chunks: Dictionary = {}   # { Vector2i: true }

var last_jet_chunk := Vector2i(999999, 999999)

# Debug stats (read by DebugOverlay). Written on the main thread only.
var last_build_ms := 0.0
var peak_build_ms := 0.0
var last_finalize_ms := 0.0
var peak_finalize_ms := 0.0


func _ready() -> void:
	add_to_group(GameConst.GROUP_TERRAIN)

	if config == null:
		config = TerrainConfig.new()
	var mission: MissionConfig = null
	if use_mission_seed:
		mission = MissionSession.get_current()
		if mission != null:
			# Work on a copy so the saved .tres is not changed by playing a mission.
			config = config.duplicate() as TerrainConfig
			config.world_seed = mission.seed_value
			print("Terrain seed taken from mission '", mission.id, "'")
	sampler = TerrainSampler.new(config)
	print("Terrain seed: ", sampler.seed_value)
	if print_terrain_summary:
		print("Terrain summary: ", sampler.debug_summary(1500.0, 30.0, summary_reference_altitude))

	if spawn_table == null:
		spawn_table = SpawnTable.make_default(target_scene, sam_turret_scene)
	if mission != null:
		_apply_mission_to_spawning(mission)
	planner = SpawnPlanner.new(spawn_table, sampler)

	shared_material = TerrainMaterial.create(config)

	if not target_jet:
		target_jet = get_tree().get_first_node_in_group(GameConst.GROUP_PLAYER)

	spawn_manager = SpawnManager.new()
	spawn_manager.name = "SpawnManager"
	spawn_manager.max_live_targets = max_live_targets
	spawn_manager.spawn_budget_ms = spawn_budget_ms
	spawn_manager.jet = target_jet
	add_child(spawn_manager)

	water = TerrainWater.new()
	water.setup(config, sampler.sea_level)
	add_child(water)


func _process(delta: float) -> void:
	if not target_jet:
		return

	water.follow(target_jet.global_position, delta)

	var current_chunk := _world_to_chunk(target_jet.global_position)

	if current_chunk != last_jet_chunk:
		last_jet_chunk = current_chunk
		_update_chunks(current_chunk)


## Mission rules for the random spawns. Runs before any chunk is planned.
func _apply_mission_to_spawning(mission: MissionConfig) -> void:
	DefenseNetworks.reset()
	# Open-world spawns join the mission's networks (always assigned, so nothing stale is kept).
	for rule in spawn_table.rules:
		if rule != null:
			rule.network_id = StringName(mission.world_networks.get(rule.rule_name, &""))
	# Keep random tanks and SAMs off the objective sites.
	var zones: Array[Vector3] = []
	for placement in MissionSession.chain_for(mission, sampler):
		zones.append(Vector3(placement.position.x, placement.position.z, ObjectiveDefenses.EXCLUSION_RADIUS))
	spawn_table.exclusions = zones


## Which chunk a world position falls in.
func chunk_coord_at(world_pos: Vector3) -> Vector2i:
	return _world_to_chunk(world_pos)


## World position of a chunk's corner (its node sits here).
func chunk_origin(coord: Vector2i) -> Vector3:
	return Vector3(coord.x * config.chunk_size, 0.0, coord.y * config.chunk_size)


## The chunk node for a coordinate, or null when that chunk is not built (yet).
func get_chunk(coord: Vector2i) -> Node3D:
	return active_chunks.get(coord) as Node3D


func _world_to_chunk(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / config.chunk_size),
		floori(world_pos.z / config.chunk_size)
	)


func _update_chunks(center_chunk: Vector2i) -> void:
	needed_chunks.clear()
	var r := config.render_distance

	# 1. Queue missing chunks on worker threads
	for x in range(center_chunk.x - r, center_chunk.x + r + 1):
		for z in range(center_chunk.y - r, center_chunk.y + r + 1):
			var coord := Vector2i(x, z)
			needed_chunks[coord] = true

			if not active_chunks.has(coord) and not pending_chunks.has(coord):
				var task_id := WorkerThreadPool.add_task(_build_chunk_threaded.bind(coord))
				pending_chunks[coord] = task_id

	# 2. Unload active chunks outside render_distance
	var coords_to_remove: Array[Vector2i] = []
	for coord: Vector2i in active_chunks.keys():
		if not needed_chunks.has(coord):
			coords_to_remove.append(coord)

	for coord in coords_to_remove:
		var chunk_node: Node3D = active_chunks[coord]
		chunk_unloaded.emit(coord)
		chunk_node.queue_free()
		active_chunks.erase(coord)


# Runs on a background thread. NEVER modify the SceneTree directly here!
func _build_chunk_threaded(coord: Vector2i) -> void:
	var t_start := Time.get_ticks_usec()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # Low-poly flat normals
	if config.shader_enabled:
		# Per-vertex data for the terrain shader: stripe color (rgb) + face kind (a).
		st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA8_UNORM)

	var spacing := config.vertex_spacing
	var size := config.chunk_size
	var grid_count := int(size / spacing)
	var origin_x := coord.x * size
	var origin_z := coord.y * size
	var sea := sampler.sea_level

	# Sample every grid point once (instead of 4x per cell corner).
	var heights := sampler.sample_grid(origin_x, origin_z, grid_count)
	var stride := grid_count + 1

	# Collision keeps every triangle (including the seabed); the visible mesh skips
	# anything fully under water because the water plane covers it.
	var faces := PackedVector3Array()
	var has_geometry := false

	for x in range(grid_count):
		for z in range(grid_count):
			var lx0 := x * spacing
			var lz0 := z * spacing
			var lx1 := (x + 1) * spacing
			var lz1 := (z + 1) * spacing

			var v00 := Vector3(lx0, heights[x * stride + z], lz0)
			var v10 := Vector3(lx1, heights[(x + 1) * stride + z], lz0)
			var v01 := Vector3(lx0, heights[x * stride + z + 1], lz1)
			var v11 := Vector3(lx1, heights[(x + 1) * stride + z + 1], lz1)

			# Same triangulation as TerrainSampler._surface_cell
			faces.append(v00)
			faces.append(v10)
			faces.append(v01)
			faces.append(v10)
			faces.append(v11)
			faces.append(v01)

			# Open-water cell: nothing to draw, and no need to sample the biome either.
			if maxf(maxf(v00.y, v10.y), maxf(v01.y, v11.y)) <= sea:
				continue

			# One biome per cell, taken at the cell center.
			var biome := sampler.biome_at(origin_x + lx0 + spacing * 0.5, origin_z + lz0 + spacing * 0.5)

			# Both triangles of a cell pick their palette color from the same height,
			# so a cell never splits into two different strata/height colors.
			var cell_y := (v00.y + v10.y + v01.y + v11.y) * 0.25
			if _add_triangle(st, v00, v10, v01, biome, cell_y):
				has_geometry = true
			if _add_triangle(st, v10, v11, v01, biome, cell_y):
				has_geometry = true

	# Chunks that are entirely open sea have no visible mesh at all.
	var array_mesh: ArrayMesh = null
	if has_geometry:
		st.generate_normals()
		array_mesh = st.commit()

	# Collision is built from the raw faces so the foam ribbon never becomes solid.
	var collision_shape := ConcavePolygonShape3D.new()
	collision_shape.set_faces(faces)

	# Hand the finished resources back to the main thread safely
	# Decide what spawns on this chunk (pure data, deterministic per chunk)
	var spawn_plan := planner.plan_chunk(coord)

	var build_ms := (Time.get_ticks_usec() - t_start) / 1000.0
	_finalize_chunk_on_main.call_deferred(coord, array_mesh, collision_shape, spawn_plan, build_ms)


# Runs safely on the main thread
func _finalize_chunk_on_main(coord: Vector2i, array_mesh: ArrayMesh, collision_shape: ConcavePolygonShape3D, spawn_plan: Array, build_ms: float) -> void:
	pending_chunks.erase(coord)
	last_build_ms = build_ms
	peak_build_ms = maxf(peak_build_ms, build_ms)

	# If the jet already flew past this chunk while it was generating, discard it
	if not needed_chunks.has(coord):
		return

	var t_start := Time.get_ticks_usec()
	var world_origin := Vector3(coord.x * config.chunk_size, 0.0, coord.y * config.chunk_size)

	var mesh_instance := MeshInstance3D.new()
	# The Terrain node may keep streaming while the game is paused (briefing and result screens),
	# but everything that lives on a chunk (targets, turrets) must freeze with the rest of the world.
	mesh_instance.process_mode = Node.PROCESS_MODE_PAUSABLE
	mesh_instance.mesh = array_mesh
	mesh_instance.material_override = shared_material
	mesh_instance.position = world_origin

	var static_body := StaticBody3D.new()
	var col_node := CollisionShape3D.new()
	col_node.shape = collision_shape
	static_body.add_child(col_node)
	mesh_instance.add_child(static_body)

	add_child(mesh_instance)

	# Children are freed automatically when the chunk unloads
	spawn_manager.queue_plan(mesh_instance, world_origin, spawn_plan)

	active_chunks[coord] = mesh_instance
	chunk_ready.emit(coord, mesh_instance)

	last_finalize_ms = (Time.get_ticks_usec() - t_start) / 1000.0
	peak_finalize_ms = maxf(peak_finalize_ms, last_finalize_ms)


# One flat color per triangle: tops vs cliffs, by height, per biome.
# Returns false when the triangle is entirely at or below sea level and was skipped.
# Triangles that cross sea level also get a foam ribbon along the waterline.
func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, biome: int, color_y: float) -> bool:
	var sea := sampler.sea_level
	var min_y := minf(a.y, minf(b.y, c.y))
	var max_y := maxf(a.y, maxf(b.y, c.y))
	if max_y <= sea:
		return false

	var n := (b - a).cross(c - a)
	var normal_y := absf(n.y) / maxf(n.length(), 0.0001)
	var color := sampler.triangle_color(normal_y, min_y, color_y, biome)

	# Shader data: shoreline ramps and flat faces are "tops" (blotches), steep faces
	# above the beach are "cliffs" (stripes).
	var is_cliff := min_y >= sea and sampler.is_cliff_face(normal_y)
	var stripe := config.palette_for(biome).stripe_color_at(color_y)
	var custom := Color(stripe.r, stripe.g, stripe.b, KIND_CLIFF if is_cliff else KIND_TOP)
	_emit_vertex(st, a, color, custom)
	_emit_vertex(st, b, color, custom)
	_emit_vertex(st, c, color, custom)

	if config.foam_enabled and min_y < sea and max_y > sea:
		_add_shore_foam(st, a, b, c)
	return true


# Adds a thin flat cream ribbon along the line where this triangle crosses sea level,
# on the water side. Hard-edged, vertex-colored, part of the same surface as the terrain.
func _add_shore_foam(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var sea := sampler.sea_level
	var corners := [a, b, c]
	var crossings: Array[Vector3] = []
	var water_sum := Vector3.ZERO
	var water_count := 0

	for i in 3:
		var p: Vector3 = corners[i]
		var q: Vector3 = corners[(i + 1) % 3]
		var p_above := p.y > sea
		if p_above != (q.y > sea):
			crossings.append(p.lerp(q, (sea - p.y) / (q.y - p.y)))
		if not p_above:
			water_sum += p
			water_count += 1
	if crossings.size() != 2 or water_count == 0:
		return

	var p0 := crossings[0]
	var p1 := crossings[1]
	var along := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
	if along.length_squared() < 0.0001:
		return
	var tangent := along.normalized()

	# Horizontal direction pointing from the land toward the water side.
	var outward := Vector3(-tangent.z, 0.0, tangent.x)
	var water_center := water_sum / water_count
	if outward.dot(Vector3(water_center.x - p0.x, 0.0, water_center.z - p0.z)) < 0.0:
		outward = -outward

	var w := config.foam_width
	var y := sea + config.foam_height
	var inset := 0.25 # tucks under the land so there is no seam
	var overhang := w * 0.35 # overlaps neighbouring segments so corners have no gaps
	var q0 := p0 - tangent * overhang - outward * inset
	var q1 := p1 + tangent * overhang - outward * inset
	var q2 := p1 + tangent * overhang + outward * w
	var q3 := p0 - tangent * overhang + outward * w
	q0.y = y
	q1.y = y
	q2.y = y
	q3.y = y

	_add_flat_triangle(st, q0, q1, q2, config.foam_color)
	_add_flat_triangle(st, q0, q2, q3, config.foam_color)


# Adds a triangle wound the same way as the terrain triangles (front face up).
func _add_flat_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).y > 0.0:
		var tmp := b
		b = c
		c = tmp
	var plain := Color(0.0, 0.0, 0.0, KIND_PLAIN)
	_emit_vertex(st, a, color, plain)
	_emit_vertex(st, b, color, plain)
	_emit_vertex(st, c, color, plain)


func _emit_vertex(st: SurfaceTool, v: Vector3, color: Color, custom: Color) -> void:
	st.set_color(color)
	if config.shader_enabled:
		st.set_custom(0, custom)
	st.add_vertex(v)


func get_stats() -> Dictionary:
	return {
		"seed": sampler.seed_value,
		"active": active_chunks.size(),
		"pending": pending_chunks.size(),
		"needed": needed_chunks.size(),
		"last_build_ms": last_build_ms,
		"peak_build_ms": peak_build_ms,
		"last_finalize_ms": last_finalize_ms,
		"peak_finalize_ms": peak_finalize_ms,
		"spawn": spawn_manager.get_stats(),
	}


func reset_peak_stats() -> void:
	peak_build_ms = 0.0
	peak_finalize_ms = 0.0


func _exit_tree() -> void:
	# Cleanly wait for any running worker tasks when closing or reloading the scene
	for task_id: int in pending_chunks.values():
		WorkerThreadPool.wait_for_task_completion(task_id)
