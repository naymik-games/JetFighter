class_name JetCameraRig
extends Node3D
## One Camera3D, two views, blended. CHASE is the old SpringArm rig's math (the arm had
## spring_length 0, so it did nothing but hold the camera); COCKPIT sits at the canopy,
## locked to the jet's heading and pitch with part of the banking roll.

enum View { CHASE, COCKPIT }

@export var start_view: View = View.CHASE

@export_group("Chase Camera")
@export var chase_offset: Vector3 = Vector3(0.0, 5.5, 7.0)
@export var follow_speed: float = 10.0
@export var look_ahead: float = 12.0
@export var look_drop: float = 2.0

@export_group("Cockpit Camera")
## Local to the jet. The default is derived from the canopy mesh bounds - nudge to taste.
@export var cockpit_offset: Vector3 = Vector3(0.0, 0.12, -0.5)
## How much of the visual bank roll the cockpit camera copies (0 = level horizon).
@export_range(0.0, 1.0) var cockpit_roll_factor: float = 0.6
@export_range(0.0, 1.0) var cockpit_shake_scale: float = 0.12
@export var view_transition_time: float = 0.35
@export var hide_jet_in_cockpit: bool = true

@export_group("Lens")
@export var base_fov: float = 72.0
@export var boost_fov: float = 92.0
@export var brake_fov: float = 62.0
@export var fov_lerp_speed: float = 4.5

@export_group("Shake")
@export var max_shake_offset: float = 1.4
@export var shake_decay: float = 2.8

@onready var _camera: Camera3D = $Camera3D

var _body: CharacterBody3D
var _mesh_pivot: Node3D
var _flight: JetFlight
var _controls: JetInput

var _view: View = View.CHASE
var _blend: float = 0.0 # 0 = chase, 1 = cockpit
var _chase_pos: Vector3 = Vector3.ZERO
var _chase_ready: bool = false
var _trauma: float = 0.0
var _dead: bool = false


func _ready() -> void:
	top_level = true
	_view = start_view
	_blend = 1.0 if start_view == View.COCKPIT else 0.0


func setup(body: CharacterBody3D, mesh_pivot: Node3D, flight: JetFlight, controls: JetInput) -> void:
	_body = body
	_mesh_pivot = mesh_pivot
	_flight = flight
	_controls = controls
	_camera.fov = base_fov
	_camera.make_current()


func toggle_view() -> void:
	set_view(View.COCKPIT if _view == View.CHASE else View.CHASE)


func set_view(view: View) -> void:
	_view = view


func is_cockpit() -> bool:
	return _view == View.COCKPIT


func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func on_jet_died() -> void:
	_dead = true


func update(delta: float) -> void:
	var flat_basis := Basis(Vector3.UP, _flight.yaw)
	var body_pos := _body.global_position

	# --- Chase rig (same math as before) ---
	var chase_target := body_pos + flat_basis * chase_offset
	if not _chase_ready:
		_chase_pos = chase_target
		_chase_ready = true
	_chase_pos = _chase_pos.lerp(chase_target, minf(follow_speed * delta, 1.0))

	# Subtle continuous rumble while boosting + explosion trauma shake
	var boost_rumble := 0.08 if _controls.boost_held else 0.0
	var total_trauma := maxf(_trauma, boost_rumble)
	if _trauma > 0.0:
		_trauma = maxf(_trauma - shake_decay * delta, 0.0)

	var jitter := Vector3.ZERO
	if total_trauma > 0.0:
		var shake_power := total_trauma * total_trauma
		jitter = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * max_shake_offset * shake_power
		_chase_pos += jitter # baked into the smoothed position, like the old rig

	var look_target := body_pos + (-flat_basis.z * look_ahead) + Vector3(0.0, -look_drop, 0.0)
	var chase_xf := Transform3D(Basis.looking_at(look_target - _chase_pos, Vector3.UP), _chase_pos)

	# --- Cockpit rig (no lag: rigid to the jet) ---
	var roll := _mesh_pivot.rotation.z * cockpit_roll_factor
	var cockpit_basis := _body.global_transform.basis * Basis(Vector3.BACK, roll)
	var cockpit_pos := _body.global_transform * cockpit_offset + jitter * cockpit_shake_scale
	var cockpit_xf := Transform3D(cockpit_basis, cockpit_pos)

	# --- Blend between the two ---
	var goal := 1.0 if _view == View.COCKPIT else 0.0
	_blend = move_toward(_blend, goal, delta / maxf(view_transition_time, 0.01))
	global_transform = chase_xf.interpolate_with(cockpit_xf, smoothstep(0.0, 1.0, _blend))

	_mesh_pivot.visible = not _dead and not (hide_jet_in_cockpit and _blend > 0.6)

	# --- Speed FOV ---
	var target_fov := base_fov
	if _controls.boost_held:
		target_fov = boost_fov
	elif _controls.brake_held:
		target_fov = brake_fov
	_camera.fov = lerpf(_camera.fov, target_fov, minf(fov_lerp_speed * delta, 1.0))
