class_name Missile
extends Area3D
## One missile script for every variant. Behavior comes from `config`.
## Player missiles hit Targets; enemy missiles hit the jet. Both die on terrain.

@export var config: MissileConfig

var target: Node3D = null
var smoke_trail: CPUParticles3D

var _age := 0.0
var _homing := true
var _flying_off := false
var _fly_off_left := 0.0
var _detonated := false
var _counted := false

## Live missile count per MissileConfig.Team, used by turrets to limit clutter.
static var _active: Dictionary = {}


static func active_count(team: MissileConfig.Team) -> int:
	return _active.get(team, 0)


func _ready() -> void:
	if config == null:
		push_warning("Missile has no config; using defaults.")
		config = MissileConfig.new()

	_apply_layers()
	if config.team == MissileConfig.Team.ENEMY:
		add_to_group(GameConst.GROUP_ENEMY_MISSILES)

	_active[config.team] = _active.get(config.team, 0) + 1
	_counted = true

	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	_setup_smoke_trail()


func _exit_tree() -> void:
	if _counted:
		_counted = false
		_active[config.team] = maxi(_active.get(config.team, 1) - 1, 0)


func _apply_layers() -> void:
	if config.team == MissileConfig.Team.PLAYER:
		collision_layer = GameConst.LAYER_PLAYER_MISSILES
		collision_mask = GameConst.LAYER_TERRAIN | GameConst.LAYER_TARGETS
	else:
		collision_layer = GameConst.LAYER_ENEMY_MISSILES
		collision_mask = GameConst.LAYER_TERRAIN | GameConst.LAYER_PLAYER


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= config.lifetime:
		_detonate()
		return

	if _flying_off:
		_fly_off_left -= delta
		if _fly_off_left <= 0.0:
			_detonate()
			return
	elif _homing:
		_steer(delta)

	global_position += -global_transform.basis.z * config.speed * delta


func _steer(delta: float) -> void:
	if not is_instance_valid(target):
		_lose_lock()
		return

	var to_target := _aim_position(target) - global_position
	var dist := to_target.length()
	if dist < 0.001:
		return
	var desired_dir := to_target / dist

	if config.loses_lock_on_miss:
		var forward := -global_transform.basis.z
		var off_nose := forward.angle_to(desired_dir) > deg_to_rad(config.seeker_cone_degrees)
		var too_far := config.lose_lock_range > 0.0 and dist > config.lose_lock_range
		if off_nose or too_far:
			_lose_lock()
			return

	var up := Vector3.UP if absf(desired_dir.y) < 0.99 else Vector3.RIGHT
	var desired_basis := Basis.looking_at(desired_dir, up)
	global_transform.basis = global_transform.basis.slerp(desired_basis, config.turn_rate * delta).orthonormalized()


func _lose_lock() -> void:
	_homing = false
	target = null
	if config.loses_lock_on_miss:
		_flying_off = true
		_fly_off_left = config.fly_off_time


func _on_area_entered(area: Area3D) -> void:
	if config.team != MissileConfig.Team.PLAYER:
		return
	var hit_target := area as Target
	if hit_target != null:
		hit_target.take_damage(config.damage)
		_detonate()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(GameConst.GROUP_PLAYER):
		if config.team == MissileConfig.Team.PLAYER:
			return # never blow up on our own jet
		if body.has_method("take_damage"):
			body.take_damage(config.damage)
		elif body.has_method("add_camera_shake"):
			body.add_camera_shake(0.95)
		_detonate()
		return
	# Terrain. Targets sit on the ground, so the missile often touches terrain and a
	# target in the same physics step, and the signal order isn't guaranteed. Wait one
	# step so a target overlap gets its chance first.
	_terrain_hit.call_deferred()


func _terrain_hit() -> void:
	if _detonated:
		return
	if config.team == MissileConfig.Team.PLAYER:
		for area in get_overlapping_areas():
			var hit_target := area as Target
			if hit_target != null and not hit_target.is_dead():
				hit_target.take_damage(config.damage)
				break
	_detonate()


func _aim_position(node: Node3D) -> Vector3:
	var t := node as Target
	return t.get_aim_position() if t != null else node.global_position


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true
	# Detach smoke so existing puffs finish fading out cleanly
	if is_instance_valid(smoke_trail):
		smoke_trail.emitting = false
		smoke_trail.reparent(get_tree().current_scene)
		get_tree().create_timer(smoke_trail.lifetime).timeout.connect(smoke_trail.queue_free)
	queue_free()


func _setup_smoke_trail() -> void:
	smoke_trail = CPUParticles3D.new()
	smoke_trail.amount = config.smoke_amount
	smoke_trail.lifetime = config.smoke_lifetime
	smoke_trail.local_coords = false # leaves puffs behind in world space

	var puff := SphereMesh.new()
	puff.radial_segments = 5
	puff.rings = 2
	puff.radius = config.smoke_puff_radius
	puff.height = config.smoke_puff_radius * 2.0
	smoke_trail.mesh = puff

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	smoke_trail.material_override = mat

	smoke_trail.direction = Vector3(0, 0, 1) # rear (+Z)
	smoke_trail.spread = config.smoke_spread
	smoke_trail.initial_velocity_min = config.smoke_velocity_min
	smoke_trail.initial_velocity_max = config.smoke_velocity_max
	smoke_trail.gravity = config.smoke_gravity

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, config.smoke_scale_start))
	scale_curve.add_point(Vector2(config.smoke_scale_peak_time, config.smoke_scale_peak))
	scale_curve.add_point(Vector2(1.0, 0.0))
	smoke_trail.scale_amount_curve = scale_curve

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, config.smoke_mid_offset, 1.0])
	grad.colors = PackedColorArray([config.smoke_color_start, config.smoke_color_mid, config.smoke_color_end])
	smoke_trail.color_ramp = grad

	smoke_trail.position = Vector3(0.0, 0.0, 1.2) # rear nozzle
	add_child(smoke_trail)
