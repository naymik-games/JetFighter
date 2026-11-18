extends Area3D

@export var speed: float = 85.0
@export var turn_rate: float = 4.5
@export var lifetime: float = 5.0

var target: Node3D = null
var smoke_trail: CPUParticles3D

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_detonate)
	_setup_smoke_trail()

func _setup_smoke_trail() -> void:
	smoke_trail = CPUParticles3D.new()
	smoke_trail.amount = 36
	smoke_trail.lifetime = 0.85
	smoke_trail.local_coords = false # Leaves puffs behind in world space!
	
	var puff_mesh := SphereMesh.new()
	puff_mesh.radial_segments = 5
	puff_mesh.rings = 2
	puff_mesh.radius = 0.35
	puff_mesh.height = 0.7
	smoke_trail.mesh = puff_mesh
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	smoke_trail.material_override = mat
	
	smoke_trail.direction = Vector3(0, 0, 1) # Rear (+Z)
	smoke_trail.spread = 12.0
	smoke_trail.initial_velocity_min = 2.0
	smoke_trail.initial_velocity_max = 5.0
	smoke_trail.gravity = Vector3(0.0, 1.2, 0.0)
	
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.4))
	scale_curve.add_point(Vector2(0.3, 1.1))
	scale_curve.add_point(Vector2(1.0, 0.0))
	smoke_trail.scale_amount_curve = scale_curve
	
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.45)) # Exhaust flash near nozzle
	grad.add_point(0.15, Color(0.92, 0.92, 0.94)) # Thick white smoke
	grad.set_color(1, Color(0.55, 0.58, 0.62)) # Cool gray tail
	smoke_trail.color_ramp = grad
	
	# Place at the rear nozzle of the missile
	smoke_trail.position = Vector3(0.0, 0.0, 1.2)
	add_child(smoke_trail)

func _physics_process(delta: float) -> void:
	if is_instance_valid(target):
		var to_target := (target.global_position - global_position).normalized()
		var target_basis := Basis.looking_at(to_target, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_basis, turn_rate * delta).orthonormalized()
	
	global_position += -global_transform.basis.z * speed * delta

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("targets") and area.has_method("hit"):
		area.hit()
		_detonate()

func _on_body_entered(_body: Node3D) -> void:
	_detonate()

func _detonate() -> void:
	# Detach smoke trail so existing smoke puffs finish fading out cleanly
	if is_instance_valid(smoke_trail):
		smoke_trail.emitting = false
		smoke_trail.reparent(get_tree().current_scene)
		get_tree().create_timer(smoke_trail.lifetime).timeout.connect(smoke_trail.queue_free)
	queue_free()
