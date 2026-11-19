class_name JetWeapons
extends Node
## Missile launching: cooldown, the "wait for the lock to finish" queue, and the spawn.
## Fire requests arrive from JetInput (keyboard or touch) via request_fire().

@export var missile_scene: PackedScene
@export var fire_cooldown: float = 0.5
## Pressing fire while a lock is still building waits up to this long for it to finish, then
## launches a homing missile. 0 = fire immediately (unguided if the lock isn't complete).
@export var fire_queue_time: float = 0.9
## World-space offset from the jet where the missile spawns (was hard-coded).
@export var launch_offset: Vector3 = Vector3(0.0, -1.2, 0.0)

var can_fire: bool = true

var _body: CharacterBody3D
var _lock_on: JetLockOn
var _cooldown_left: float = 0.0
var _fire_requested: bool = false
var _fire_pending: bool = false
var _fire_pending_left: float = 0.0


func setup(body: CharacterBody3D, lock_on: JetLockOn) -> void:
	_body = body
	_lock_on = lock_on


func request_fire() -> void:
	_fire_requested = true


func update(delta: float) -> void:
	# Cooldown is a plain countdown (no SceneTreeTimer), so it can't outlive the jet.
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
		if _cooldown_left <= 0.0:
			can_fire = true

	var requested := _fire_requested
	_fire_requested = false

	if missile_scene == null:
		return

	if requested and can_fire:
		var lock_building := is_instance_valid(_lock_on.target) and _lock_on.progress < 1.0
		if lock_building and fire_queue_time > 0.0:
			_fire_pending = true
			_fire_pending_left = fire_queue_time
		else:
			_fire_missile()

	if _fire_pending and can_fire:
		_fire_pending_left -= delta
		var locked := _lock_on.has_lock()
		if locked or not is_instance_valid(_lock_on.target) or _fire_pending_left <= 0.0:
			_fire_pending = false
			_fire_missile() # homing if the lock completed, unguided otherwise


func _fire_missile() -> void:
	var missile := missile_scene.instantiate() as Missile
	if missile == null:
		push_error("JetWeapons.missile_scene must use missile.gd.")
		return

	can_fire = false
	_cooldown_left = fire_cooldown
	get_tree().current_scene.add_child(missile)

	missile.global_position = _body.global_position + launch_offset
	missile.global_transform.basis = _body.global_transform.basis

	if _lock_on.has_lock():
		missile.target = _lock_on.target
