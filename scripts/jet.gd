extends CharacterBody3D

@export_group("Flight & Throttle")
@export var cruise_speed: float = 35.0
@export var boost_speed: float = 65.0
@export var brake_speed: float = 18.0
@export var throttle_accel: float = 4.5
@export var turn_speed: float = 1.8
@export var pitch_speed: float = 1.5
@export var max_pitch_angle: float = 55.0

@export_group("Drag Controls")
@export var max_drag_radius: float = 120.0
@export var invert_y: bool = false

@export_group("Weapons & Lock-On")
@export var missile_scene: PackedScene
@export var lock_range: float = 220.0
@export var lock_cone_degrees: float = 28.0
@export var lock_time_required: float = 0.65
@export var fire_cooldown: float = 0.5

@export_group("Arcade Visuals & Camera")
@export var bank_angle: float = 45.0
@export var visual_smoothing: float = 8.0
@export var camera_follow_speed: float = 10.0
@export var base_fov: float = 72.0
@export var boost_fov: float = 92.0
@export var brake_fov: float = 62.0
@export var max_shake_offset: float = 1.4
@export var shake_decay: float = 2.8

@export_group("Wingtip Ribbon Trails")
@export var wingtip_offset: Vector3 = Vector3(2.0, 0.0, 0.3) # Right wingtip local to MeshPivot
@export var trail_max_points: int = 28
@export var trail_width: float = 0.22
@export var trail_color: Color = Color(0.92, 0.96, 1.0, 0.65)

@onready var mesh_pivot: Node3D = $MeshPivot
@onready var camera_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

# Flight & Drag State
var current_speed: float = 35.0
var is_dragging: bool = false
var drag_origin: Vector2 = Vector2.ZERO
var input_vector: Vector2 = Vector2.ZERO
var current_yaw: float = 0.0
var current_pitch: float = 0.0

# Weapons State
var current_target: Node3D = null
var lock_progress: float = 0.0
var can_fire: bool = true

# Camera & Ribbon Trail State
var shake_trauma: float = 0.0
var left_tip_marker: Marker3D
var right_tip_marker: Marker3D
var left_trail_points: Array[Vector3] = []
var right_trail_points: Array[Vector3] = []
var left_trail_mesh := ImmediateMesh.new()
var right_trail_mesh := ImmediateMesh.new()

func _ready() -> void:
	add_to_group("player")
	camera_arm.top_level = true
	current_speed = cruise_speed
	_setup_wingtip_trails()

func _setup_wingtip_trails() -> void:
	# Attach markers to MeshPivot so trails bank with the wings
	right_tip_marker = Marker3D.new()
	right_tip_marker.position = wingtip_offset
	mesh_pivot.add_child(right_tip_marker)
	
	left_tip_marker = Marker3D.new()
	left_tip_marker.position = Vector3(-wingtip_offset.x, wingtip_offset.y, wingtip_offset.z)
	mesh_pivot.add_child(left_tip_marker)
	
	# Create unshaded double-sided ribbon material with vertex alpha fade
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	
	# Spawn top-level MeshInstances so ribbon coordinates stay in world space
	for mesh_res in [left_trail_mesh, right_trail_mesh]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh_res
		mi.material_override = mat
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_origin = event.position
		else:
			is_dragging = false
			input_vector = Vector2.ZERO
			
	elif event is InputEventMouseMotion and is_dragging:
		var delta: Vector2 = event.position - drag_origin
		input_vector = (delta / max_drag_radius).limit_length(1.0)

func _physics_process(delta: float) -> void:
	# 1. Throttle (Boost / Airbrake / Cruise)
	var target_speed := cruise_speed
	var target_fov := base_fov
	
	if Input.is_action_pressed("boost"):
		target_speed = boost_speed
		target_fov = boost_fov
	elif Input.is_action_pressed("brake"):
		target_speed = brake_speed
		target_fov = brake_fov
		
	current_speed = lerp(current_speed, target_speed, throttle_accel * delta)
	if is_instance_valid(camera):
		camera.fov = lerp(camera.fov, target_fov, throttle_accel * delta)
	
	# 2. Steering Inputs
	var turn_input := -input_vector.x
	var pitch_input := input_vector.y if invert_y else -input_vector.y
	
	current_yaw += turn_input * turn_speed * delta
	current_pitch += pitch_input * pitch_speed * delta
	current_pitch = clamp(current_pitch, deg_to_rad(-max_pitch_angle), deg_to_rad(max_pitch_angle))
	
	if not is_dragging:
		current_pitch = lerp(current_pitch, 0.0, 2.5 * delta)
	
	rotation = Vector3(current_pitch, current_yaw, 0.0)
	
	# 3. Move Forward
	var forward_dir := -global_transform.basis.z
	velocity = forward_dir * current_speed
	move_and_slide()
	
	# 4. Visual Banking & Wingtip Trails
	var target_roll := turn_input * deg_to_rad(bank_angle)
	mesh_pivot.rotation.z = lerp(mesh_pivot.rotation.z, target_roll, visual_smoothing * delta)
	_update_wingtip_trails(abs(turn_input))
	
	# 5. Camera, Lock-On & Weapons
	_update_camera(delta)
	_update_target_lock(delta)
	_handle_weapons()

func _update_wingtip_trails(turn_intensity: float) -> void:
	# Trails become thicker and brighter during hard turns or afterburner boost
	var boost_factor := clampf((current_speed - cruise_speed) / maxf(boost_speed - cruise_speed, 1.0), 0.0, 1.0)
	var active_alpha := clampf(0.25 + (turn_intensity * 0.55) + (boost_factor * 0.45), 0.0, 0.9)
	
	left_trail_points.push_front(left_tip_marker.global_position)
	right_trail_points.push_front(right_tip_marker.global_position)
	
	if left_trail_points.size() > trail_max_points:
		left_trail_points.pop_back()
	if right_trail_points.size() > trail_max_points:
		right_trail_points.pop_back()
		
	_rebuild_ribbon(left_trail_mesh, left_trail_points, active_alpha)
	_rebuild_ribbon(right_trail_mesh, right_trail_points, active_alpha)

func _rebuild_ribbon(im_mesh: ImmediateMesh, points: Array[Vector3], max_alpha: float) -> void:
	im_mesh.clear_surfaces()
	if points.size() < 2:
		return
		
	var wing_right := mesh_pivot.global_transform.basis.x
	im_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	for i in range(points.size()):
		var t := float(i) / float(points.size() - 1) # 0.0 at wingtip -> 1.0 at tail
		var half_w := trail_width * (1.0 - t) # Tapering width
		
		var col := trail_color
		col.a = max_alpha * (1.0 - t) * (1.0 - t) # Smooth quadratic alpha fade
		
		im_mesh.surface_set_color(col)
		im_mesh.surface_add_vertex(points[i] - wing_right * half_w)
		
		im_mesh.surface_set_color(col)
		im_mesh.surface_add_vertex(points[i] + wing_right * half_w)
		
	im_mesh.surface_end()

func add_camera_shake(amount: float) -> void:
	shake_trauma = clamp(shake_trauma + amount, 0.0, 1.0)

func _update_camera(delta: float) -> void:
	var flat_basis := Basis(Vector3.UP, current_yaw)
	var offset := flat_basis * Vector3(0.0, 5.5, 11.0)
	var target_pos := global_position + offset
	
	camera_arm.global_position = camera_arm.global_position.lerp(target_pos, camera_follow_speed * delta)
	
	# Subtle continuous rumble while boosting + explosion trauma shake
	var boost_rumble := 0.08 if Input.is_action_pressed("boost") else 0.0
	var total_trauma := maxf(shake_trauma, boost_rumble)
	
	if shake_trauma > 0.0:
		shake_trauma = max(shake_trauma - shake_decay * delta, 0.0)
		
	if total_trauma > 0.0:
		var shake_power := total_trauma * total_trauma
		var jitter := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * max_shake_offset * shake_power
		camera_arm.global_position += jitter
	
	var look_target := global_position + (-flat_basis.z * 12.0) + Vector3(0.0, -2.0, 0.0)
	camera_arm.look_at(look_target, Vector3.UP)

func _update_target_lock(delta: float) -> void:
	if not is_instance_valid(current_target):
		current_target = null
		lock_progress = 0.0
		
	var best_target: Node3D = null
	var best_angle := deg_to_rad(lock_cone_degrees)
	var forward := -global_transform.basis.z
	
	for node in get_tree().get_nodes_in_group("targets"):
		if not is_instance_valid(node):
			continue
		var to_target: Vector3 = node.global_position - global_position
		var dist := to_target.length()
		if dist > lock_range:
			continue
			
		var angle := forward.angle_to(to_target.normalized())
		if angle < best_angle:
			best_angle = angle
			best_target = node
			
	if best_target != current_target:
		current_target = best_target
		lock_progress = 0.0
		
	if is_instance_valid(current_target):
		lock_progress = min(lock_progress + (delta / lock_time_required), 1.0)
	else:
		lock_progress = 0.0

func _handle_weapons() -> void:
	if Input.is_action_just_pressed("fire_missile") and can_fire and missile_scene:
		_fire_missile()

func _fire_missile() -> void:
	can_fire = false
	var missile := missile_scene.instantiate()
	get_tree().current_scene.add_child(missile)
	
	missile.global_position = global_position + Vector3(0.0, -1.2, 0.0)
	missile.global_transform.basis = global_transform.basis
	
	if is_instance_valid(current_target) and lock_progress >= 1.0:
		missile.target = current_target
		
	get_tree().create_timer(fire_cooldown).timeout.connect(func(): can_fire = true)
