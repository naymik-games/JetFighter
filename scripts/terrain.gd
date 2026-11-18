extends Node3D

@export_group("Target & Streaming")
@export var target_jet: Node3D # Assign your JetFighter node in the Inspector
@export var render_distance: int = 3 # Radius of chunks around the jet (3 = 7x7 grid)
@export var target_scene: PackedScene
@export var sam_turret_scene: PackedScene
@export_group("Chunk Geometry")
@export var chunk_size: float = 160.0
@export var vertex_spacing: float = 8.0
@export var height_multiplier: float = 32.0
@export var noise_frequency: float = 0.008

var noise := FastNoiseLite.new()
var shared_material := StandardMaterial3D.new()

# Thread-safe tracking dictionaries
var active_chunks: Dictionary = {}   # { Vector2i: MeshInstance3D }
var pending_chunks: Dictionary = {}  # { Vector2i: int (task_id) }
var needed_chunks: Dictionary = {}   # { Vector2i: true }

var last_jet_chunk := Vector2i(999999, 999999)

func _ready() -> void:
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = noise_frequency
	
	shared_material.vertex_color_use_as_albedo = true
	shared_material.roughness = 0.85
	
	if not target_jet:
		target_jet = get_tree().get_first_node_in_group("player")

func _process(_delta: float) -> void:
	if not target_jet:
		return
		
	var current_chunk := _world_to_chunk(target_jet.global_position)
	
	if current_chunk != last_jet_chunk:
		last_jet_chunk = current_chunk
		_update_chunks(current_chunk)

func _world_to_chunk(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / chunk_size),
		floori(world_pos.z / chunk_size)
	)

func _update_chunks(center_chunk: Vector2i) -> void:
	needed_chunks.clear()
	
	# 1. Queue missing chunks on worker threads
	for x in range(center_chunk.x - render_distance, center_chunk.x + render_distance + 1):
		for z in range(center_chunk.y - render_distance, center_chunk.y + render_distance + 1):
			var coord := Vector2i(x, z)
			needed_chunks[coord] = true
			
			if not active_chunks.has(coord) and not pending_chunks.has(coord):
				# Dispatch heavy mesh + collision math to a background worker thread
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

# Runs on a background thread — NEVER modify the SceneTree directly here!
func _build_chunk_threaded(coord: Vector2i) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # Low-poly flat normals
	
	var grid_count := int(chunk_size / vertex_spacing)
	var world_origin_x := coord.x * chunk_size
	var world_origin_z := coord.y * chunk_size
	
	for x in range(grid_count):
		for z in range(grid_count):
			var lx0 := x * vertex_spacing
			var lz0 := z * vertex_spacing
			var lx1 := (x + 1) * vertex_spacing
			var lz1 := (z + 1) * vertex_spacing
			
			var h00 := _get_height(world_origin_x + lx0, world_origin_z + lz0)
			var h10 := _get_height(world_origin_x + lx1, world_origin_z + lz0)
			var h01 := _get_height(world_origin_x + lx0, world_origin_z + lz1)
			var h11 := _get_height(world_origin_x + lx1, world_origin_z + lz1)
			
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
	
	# Pre-build the trimesh collision shape on the worker thread too!
	var collision_shape: ConcavePolygonShape3D = array_mesh.create_trimesh_shape()
	
	# Hand the finished resources back to the main thread safely
	_finalize_chunk_on_main.call_deferred(coord, array_mesh, collision_shape)

# Runs safely on the main thread
func _finalize_chunk_on_main(coord: Vector2i, array_mesh: ArrayMesh, collision_shape: ConcavePolygonShape3D) -> void:
	pending_chunks.erase(coord)
	
	# If the jet already flew past this chunk while it was generating, discard it
	if not needed_chunks.has(coord):
		return
		
	var world_origin := Vector3(coord.x * chunk_size, 0.0, coord.y * chunk_size)
	
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	mesh_instance.material_override = shared_material
	mesh_instance.position = world_origin
	
	# Attach pre-built collision shape without stalling the main thread
	var static_body := StaticBody3D.new()
	var col_node := CollisionShape3D.new()
	col_node.shape = collision_shape
	static_body.add_child(col_node)
	mesh_instance.add_child(static_body)
	
	add_child(mesh_instance)
	
	if target_scene and randf() < 0.75:
		var rx := world_origin.x + randf_range(20.0, chunk_size - 20.0)
		var rz := world_origin.z + randf_range(20.0, chunk_size - 20.0)
		var ry := _get_height(rx, rz)
		if ry > 1.0: # Only spawn on land, not water
			var tgt := target_scene.instantiate()
			tgt.position = Vector3(rx, ry, rz) #Vector3(rx, ry + 1.5, rz)
			mesh_instance.add_child(tgt) # Automatically frees when chunk unloads!
	if sam_turret_scene and randf() < 0.35:
		var rx := world_origin.x + randf_range(20.0, chunk_size - 20.0)
		var rz := world_origin.z + randf_range(20.0, chunk_size - 20.0)
		var ry := _get_height(rx, rz)
		if ry > 1.0: # Only spawn on land, not water
			var sm := sam_turret_scene.instantiate()
			sm.position = Vector3(rx, ry, rz) #Vector3(rx, ry + 1.5, rz)
			mesh_instance.add_child(sm) # Automatically frees when chunk unloads!
	active_chunks[coord] = mesh_instance

func _get_height(world_x: float, world_z: float) -> float:
	var raw := noise.get_noise_2d(world_x, world_z)
	return max(raw, -0.05) * height_multiplier

func _add_vertex(st: SurfaceTool, pos: Vector3) -> void:
	var h := pos.y / height_multiplier
	var color: Color
	
	if h <= -0.04:
		color = Color(0.16, 0.45, 0.78) # Water
	elif h < 0.08:
		color = Color(0.84, 0.78, 0.55) # Sand
	elif h < 0.45:
		color = Color(0.28, 0.58, 0.26) # Grass
	elif h < 0.72:
		color = Color(0.42, 0.40, 0.38) # Rock
	else:
		color = Color(0.95, 0.96, 0.98) # Snow
		
	st.set_color(color)
	st.add_vertex(pos)

func _exit_tree() -> void:
	# Cleanly wait for any running worker tasks when closing or reloading the scene
	for task_id: int in pending_chunks.values():
		WorkerThreadPool.wait_for_task_completion(task_id)
