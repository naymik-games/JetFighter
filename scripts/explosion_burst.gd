extends Node3D

@export var auto_cleanup: bool = true

func _ready() -> void:
	_spawn_fireball_particles()
	_spawn_debris_particles()
	
	if auto_cleanup:
		get_tree().create_timer(1.8).timeout.connect(queue_free)

func _spawn_fireball_particles() -> void:
	var particles := CPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.amount = 22
	particles.lifetime = 0.75
	
	# Low-poly faceted sphere mesh for each puff
	var sphere := SphereMesh.new()
	sphere.radial_segments = 6
	sphere.rings = 3
	sphere.radius = 1.2
	sphere.height = 2.4
	particles.mesh = sphere
	
	# Unshaded material so vertex color gradient glows brightly
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	particles.material_override = mat
	
	# Burst outward in all directions
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 6.0
	particles.initial_velocity_max = 18.0
	particles.gravity = Vector3(0.0, 4.0, 0.0) # Slight upward rise
	particles.damping_min = 6.0
	particles.damping_max = 10.0
	
	# Shrink from full size down to zero
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(0.2, 1.35))
	scale_curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = scale_curve
	
	# White-yellow -> bright orange -> dark smoke red
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.6))
	grad.add_point(0.35, Color(1.0, 0.42, 0.08))
	grad.set_color(1, Color(0.25, 0.08, 0.05))
	particles.color_ramp = grad
	
	add_child(particles)

func _spawn_debris_particles() -> void:
	var debris := CPUParticles3D.new()
	debris.emitting = true
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.amount = 14
	debris.lifetime = 1.3
	
	# Angular low-poly box shards
	var box := BoxMesh.new()
	box.size = Vector3(0.65, 0.35, 0.85)
	debris.mesh = box
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.20, 0.19)
	mat.roughness = 0.9
	debris.material_override = mat
	
	debris.direction = Vector3.UP
	debris.spread = 75.0
	debris.initial_velocity_min = 14.0
	debris.initial_velocity_max = 28.0
	debris.gravity = Vector3(0.0, -24.0, 0.0)
	debris.angular_velocity_min = -360.0
	debris.angular_velocity_max = 360.0
	
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.75, 0.8))
	scale_curve.add_point(Vector2(1.0, 0.0))
	debris.scale_amount_curve = scale_curve
	
	add_child(debris)
