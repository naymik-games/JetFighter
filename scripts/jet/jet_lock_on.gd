class_name JetLockOn
extends Node
## Target acquisition and lock progress. Logic is the old jet.gd lock code, unchanged.

@export var lock_range: float = 220.0
@export var lock_cone_degrees: float = 28.0
@export var lock_time_required: float = 0.65
## A new target must be this many degrees closer to the nose than the current one to steal the lock.
@export var lock_hysteresis_degrees: float = 4.0
## Which teams the lock-on can pick. Default: enemies only (neutrals are never locked).
@export_flags("Enemy", "Neutral", "Friendly") var lockable_teams: int = 1

var target: Node3D = null # was `current_target`
var progress: float = 0.0 # was `lock_progress`

var _body: CharacterBody3D


func setup(body: CharacterBody3D) -> void:
	_body = body


func has_lock() -> bool:
	return is_instance_valid(target) and progress >= 1.0


func clear() -> void:
	target = null
	progress = 0.0


func update(delta: float) -> void:
	if not is_instance_valid(target):
		target = null
		progress = 0.0

	var forward := -_body.global_transform.basis.z
	var cone := deg_to_rad(lock_cone_degrees)
	var best: Node3D = TargetRegistry.best_in_cone(
		_body.global_position, forward, lock_range, cone, lockable_teams, _can_see_target)

	# Keep the current lock unless it became invalid or something is clearly better,
	# so the lock doesn't flicker between targets and keep resetting.
	var chosen: Node3D = best
	if target != null and _still_lockable(target, forward, cone * 1.15):
		chosen = target
		if best != null and best != target \
				and _angle_to(best, forward) + deg_to_rad(lock_hysteresis_degrees) < _angle_to(target, forward):
			chosen = best

	if chosen != target:
		target = chosen
		progress = 0.0

	if is_instance_valid(target):
		progress = minf(progress + (delta / lock_time_required), 1.0)
	else:
		progress = 0.0


func _angle_to(node: Node3D, forward: Vector3) -> float:
	return forward.angle_to((node.global_position - _body.global_position).normalized())


func _still_lockable(node: Node3D, forward: Vector3, max_angle: float) -> bool:
	var t := node as Target
	if t == null or t.is_dead():
		return false
	if (Target.team_bit(t.team) & lockable_teams) == 0:
		return false
	if _body.global_position.distance_to(t.global_position) > lock_range:
		return false
	if _angle_to(t, forward) > max_angle:
		return false
	return _can_see_target(t)


## True if no terrain sits between the jet and the target.
func _can_see_target(t: Target) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_body.global_position, t.get_aim_position(), GameConst.LAYER_TERRAIN)
	q.exclude = [_body.get_rid()] # the jet shares layer 1 with terrain for now
	q.collide_with_areas = false
	return _body.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
