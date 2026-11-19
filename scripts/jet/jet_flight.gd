class_name JetFlight
extends Node
## Throttle, steering and movement. Same math as the old jet.gd; it only reads the drag
## vector from JetInput.

@export_group("Throttle")
@export var cruise_speed: float = 35.0
@export var boost_speed: float = 65.0
@export var brake_speed: float = 18.0
@export var throttle_accel: float = 4.5

@export_group("Steering")
@export var turn_speed: float = 1.8
@export var pitch_speed: float = 1.5
@export var max_pitch_angle: float = 55.0
## How fast pitch returns to level when no finger/mouse is dragging (was hard-coded 2.5).
@export var pitch_recenter_speed: float = 2.5

@export_group("Arcade Banking")
@export var bank_angle: float = 45.0
@export var visual_smoothing: float = 8.0

var speed: float = 35.0
var yaw: float = 0.0
var pitch: float = 0.0
## Last frame's turn input (-1..1, already sign-flipped like the old `turn_input`).
var turn_input: float = 0.0

var boost_factor: float:
	get:
		return clampf((speed - cruise_speed) / maxf(boost_speed - cruise_speed, 1.0), 0.0, 1.0)

var _body: CharacterBody3D
var _mesh_pivot: Node3D


func setup(body: CharacterBody3D, mesh_pivot: Node3D) -> void:
	_body = body
	_mesh_pivot = mesh_pivot
	speed = cruise_speed


func update(delta: float, controls: JetInput) -> void:
	# 1. Throttle (boost / airbrake / cruise)
	var target_speed := cruise_speed
	if controls.boost_held:
		target_speed = boost_speed
	elif controls.brake_held:
		target_speed = brake_speed
	speed = lerpf(speed, target_speed, throttle_accel * delta)

	# 2. Steering
	turn_input = -controls.steer.x
	var pitch_input := controls.steer.y if controls.invert_y else -controls.steer.y

	yaw += turn_input * turn_speed * delta
	pitch += pitch_input * pitch_speed * delta
	pitch = clampf(pitch, deg_to_rad(-max_pitch_angle), deg_to_rad(max_pitch_angle))

	if not controls.dragging:
		pitch = lerpf(pitch, 0.0, pitch_recenter_speed * delta)

	_body.rotation = Vector3(pitch, yaw, 0.0)

	# 3. Move forward
	var forward_dir := -_body.global_transform.basis.z
	_body.velocity = forward_dir * speed
	_body.move_and_slide()

	# 4. Visual banking
	var target_roll := turn_input * deg_to_rad(bank_angle)
	_mesh_pivot.rotation.z = lerpf(_mesh_pivot.rotation.z, target_roll, visual_smoothing * delta)
