extends Area3D

@export var speed: float = 54.0
@export var turn_rate: float = 1.65 # Tuned so sharp banks / boost can out-turn it
@export var lifetime: float = 6.5
@export var damage: int = 25

var target: Node3D = null
var smoke_trail: CPUParticles3D

func _ready() -> void:
	add_to_group("enemy_missiles")
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_detonate)
	_setup_threat_trail()

func _setup_threat_trail() -> void:
	smoke_trail = CPUParticles3D.new()
	smoke_trail.amount = 36
	smoke_trail.lifetime = 0.85
	smoke_trail.local_coords = false
	
	var puff := SphereMesh.new()
	puff.radial_segments = 5
	puff.rings = 2
	puff.radius = 0.4
	puff.height = 0.8
	smoke_trail.mesh = puff
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	smoke_trail.material_override = mat
	
	smoke_trail.direction = Vector3(0, 0, 1)
	smoke_trail.spread = 10.0
	smoke_trail.initial_velocity_min = 2.0
	smoke_trail.initial_velocity_max = 4.0
	
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(0.25, 1.2))
	scale_curve.add_point(Vector2(1.0, 0.0))
	smoke_trail.scale_amount_curve = scale_curve
	
	# Crimson-orange threat smoke so player can visually spot incoming SAMs
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.25, 0.15))
	grad.add_point(0.3, Color(0.95, 0.45, 0.2))
	grad.set_color(1, Color(0.35, 0.32, 0.35))
	smoke_trail.color_ramp = grad
	
	smoke_trail.position = Vector3(0.0, 0.0, 1.2)
	add_child(smoke_trail)

func _physics_process(delta: float) -> void:
	if is_instance_valid(target):
		var to_target := (target.global_position - global_position).normalized()
		var desired_basis := Basis.looking_at(to_target, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(desired_basis, turn_rate * delta).orthonormalized()
		
	global_position += -global_transform.basis.z * speed * delta

func _on_body_entered(body: Node3D) -> void:
	# Hit the player jet
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		elif body.has_method("add_camera_shake"):
			body.add_camera_shake(0.95)
		_detonate()
	else:
		# Hit terrain
		_detonate()

func _detonate() -> void:
	if is_instance_valid(smoke_trail):
		smoke_trail.emitting = false
		smoke_trail.reparent(get_tree().current_scene)
		get_tree().create_timer(smoke_trail.lifetime).timeout.connect(smoke_trail.queue_free)
	queue_free()
