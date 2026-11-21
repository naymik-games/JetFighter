class_name JetWeapons
extends Node
## Missile launching: cooldown, the "wait for the lock to finish" queue, and the spawn.
## Fire requests arrive from JetInput (keyboard or touch) via request_fire().
##
## Missile budget: unlimited by default (missiles_remaining = -1), so the game works outside
## missions. A mission calls set_missiles(count) to give a fixed budget with no resupply.

## remaining is -1 when unlimited. maximum is the budget the mission started with.
signal missiles_changed(remaining: int, maximum: int)
## Fire was pressed with no missiles left (for a HUD flash or a click sound).
signal dry_fire

@export var missile_scene: PackedScene
@export var fire_cooldown: float = 0.5
## Pressing fire while a lock is still building waits up to this long for it to finish, then
## launches a homing missile. 0 = fire immediately (unguided if the lock isn't complete).
@export var fire_queue_time: float = 0.9
## World-space offset from the jet where the missile spawns (was hard-coded).
@export var launch_offset: Vector3 = Vector3(0.0, -1.2, 0.0)

var can_fire: bool = true
## Missiles left to fire. -1 = unlimited.
var missiles_remaining: int = -1
## The budget at the start of the mission. -1 = unlimited.
var missiles_max: int = -1

var _body: CharacterBody3D
var _lock_on: JetLockOn
var _cooldown_left: float = 0.0
var _fire_requested: bool = false
var _fire_pending: bool = false
var _fire_pending_left: float = 0.0
var _in_flight: int = 0


func setup(body: CharacterBody3D, lock_on: JetLockOn) -> void:
	_body = body
	_lock_on = lock_on


func request_fire() -> void:
	_fire_requested = true


## Gives the jet a fixed missile budget (or pass -1 for unlimited).
func set_missiles(count: int) -> void:
	missiles_remaining = count
	missiles_max = count
	missiles_changed.emit(missiles_remaining, missiles_max)


## True when at least one missile can still be fired (always true when unlimited).
func has_missiles() -> bool:
	return missiles_remaining != 0


## True when the jet has a fixed budget.
func is_limited() -> bool:
	return missiles_max >= 0


## Missiles that have been launched and are still flying.
func missiles_in_flight() -> int:
	return _in_flight


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

	if requested and not has_missiles():
		dry_fire.emit()
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
	if not has_missiles():
		_fire_pending = false
		return

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

	if missiles_remaining > 0:
		missiles_remaining -= 1
		missiles_changed.emit(missiles_remaining, missiles_max)

	_in_flight += 1
	missile.tree_exited.connect(_on_missile_gone, CONNECT_ONE_SHOT)


func _on_missile_gone() -> void:
	_in_flight = maxi(_in_flight - 1, 0)
