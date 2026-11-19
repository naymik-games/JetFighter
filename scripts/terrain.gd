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

@export_group("Spawning")
## Leave empty to build a default table from target_scene and sam_turret_scene.
@export var spawn_table: SpawnTable
## Most spawned entities allowed alive at once. The rest wait in a queue.
@export var max_live_targets: int = 60
## Per-frame time budget for instantiating spawned entities.
@export var spawn_budget_ms: float = 2.0

var sampler: TerrainSampler
var planner: SpawnPlanner
var spawn_manager: SpawnManager
var shared_material := StandardMaterial3D.new()

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
	sampler = TerrainSampler.new(config)
	print("Terrain seed: ", sampler.seed_value)

	if spawn_table == null:
		spawn_table = SpawnTable.make_default(target_scene, sam_turret_scene)
	planner = SpawnPlanner.new(spawn_table, sampler)

	shared_material.vertex_color_use_as_albedo = true
	shared_material.roughness = 0.85

	if not target_jet:
		target_jet = get_tree().get_first_node_in_group(GameConst.GROUP_PLAYER)

	spawn_manager = SpawnManager.new()
	spawn_manager.name = "SpawnManager"
	spawn_manager.max_live_targets = max_live_targets
	spawn_manager.spawn_budget_ms = spawn_budget_ms
	spawn_manager.jet = target_jet
	add_child(spawn_manager)


func _process(_delta: float) -> void:
	if not target_jet:
		return

	var current_chunk := _world_to_chunk(target_jet.global_position)

	if current_chunk != last_jet_chunk:
		last_jet_chunk = current_chunk
		_update_chunks(current_chunk)


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
		chunk_node.queue_free()
		active_chunks.erase(coord)


# Runs on a background thread. NEVER modify the SceneTree directly here!
func _build_chunk_threaded(coord: Vector2i) -> void:
	var t_start := Time.get_ticks_usec()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # Low-poly flat normals

	var spacing := config.vertex_spacing
	var size := config.chunk_size
	var grid_count := int(size / spacing)
	var origin_x := coord.x * size
	var origin_z := coord.y * size

	for x in range(grid_count):
		for z in range(grid_count):
			var lx0 := x * spacing
			var lz0 := z * spacing
			var lx1 := (x + 1) * spacing
			var lz1 := (z + 1) * spacing

			var h00 := sampler.height_at(origin_x + lx0, origin_z + lz0)
			var h10 := sampler.height_at(origin_x + lx1, origin_z + lz0)
			var h01 := sampler.height_at(origin_x + lx0, origin_z + lz1)
			var h11 := sampler.height_at(origin_x + lx1, origin_z + lz1)

			var v00 := Vector3(lx0, h00, lz0)
			var v10 := Vector3(lx1, h10, lz0)
			var v01 := Vector3(lx0, h01, lz1)
			var v11 := Vector3(lx1, h11, lz1)

			_add_vertex(st, v00)
			_add_vertex(st, v10)
			_add_vertex(st, v01)

			_add_vertex(st, v10)
			_add_vertex(st, v11)
			_add_vertex(st, v01)

	st.generate_normals()
	var array_mesh: ArrayMesh = st.commit()

	# Pre-build the trimesh collision shape on the worker thread too
	var collision_shape: ConcavePolygonShape3D = array_mesh.create_trimesh_shape()

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

	last_finalize_ms = (Time.get_ticks_usec() - t_start) / 1000.0
	peak_finalize_ms = maxf(peak_finalize_ms, last_finalize_ms)


func _add_vertex(st: SurfaceTool, pos: Vector3) -> void:
	st.set_color(sampler.color_at_height(pos.y))
	st.add_vertex(pos)


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
