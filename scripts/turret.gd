class_name Turret
extends Node
## Missile-launcher behavior. Add as a child of a Target (e.g. the SAM turret).
## Only fires when ALL of these hold:
##   - the jet is inside fire_range (and outside min_fire_range)
##   - the head is aimed at the jet
##   - line of sight to the jet is clear (optional, on by default)
##   - the spawn point is verified to be above terrain, with a clear launch corridor
##   - this turret and the world are under their active-missile caps

@export_group("Nodes")
@export var head: Node3D
@export var muzzle: Marker3D

@export_group("Weapon")
@export var missile_scene: PackedScene
## Optional override; leave empty to use the config on the missile scene.
@export var missile_config: MissileConfig
@export var fire_interval: float = 5.0
@export var max_active_missiles: int = 1
## Upward bias on the launch direction so the missile clears hills before pitching over.
@export var launch_elevation: float = 0.65

@export_group("Awareness")
## Turret tracks the jet inside this range but does not fire.
@export var detection_range: float = 260.0
@export var fire_range: float = 200.0
@export var min_fire_range: float = 40.0
@export var turn_speed: float = 2.5
@export_range(1.0, 90.0) var aim_tolerance_degrees: float = 20.0

@export_group("Safety Checks")
@export var requires_line_of_sight: bool = true
## Muzzle is lifted to at least this far above terrain.
@export var muzzle_clearance: float = 1.0
## Launch is refused if terrain blocks the first this-many units of the flight path.
@export var launch_clear_distance: float = 14.0
@export var ground_probe_up: float = 120.0
@export var ground_probe_down: float = 200.0
## Wait this long before re-checking after a blocked or refused shot.
@export var retry_delay: float = 0.75

var _body: Target
var _jet: Node3D
var _cooldown: float = 0.0
var _missiles: Array[Missile] = []
var _warned_no_ground := false


func _ready() -> void:
	_body = get_parent() as Target
	if _body == null:
		push_warning("Turret must be a child of a Target.")
		set_physics_process(false)
		return
	_cooldown = randf_range(1.0, fire_interval) # stagger turrets
	_jet = get_tree().get_first_node_in_group(GameConst.GROUP_PLAYER) as Node3D


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_jet):
		_jet = get_tree().get_first_node_in_group(GameConst.GROUP_PLAYER) as Node3D
		return

	var to_jet := _jet.global_position - _body.global_position
	var dist_sq := to_jet.length_squared()
	if dist_sq > detection_range * detection_range:
		return

	_track(to_jet, delta)

	if dist_sq > fire_range * fire_range or dist_sq < min_fire_range * min_fire_range:
		return

	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if not _is_aimed(to_jet):
		return

	if not _has_missile_budget():
		_cooldown = retry_delay
		return

	var launch := _plan_launch()
	if launch.is_empty():
		_cooldown = retry_delay
		return

	_launch(launch["position"], launch["direction"])
	_cooldown = fire_interval


func _track(to_jet: Vector3, delta: float) -> void:
	if not is_instance_valid(head):
		return
	var flat := Vector3(to_jet.x, 0.0, to_jet.z)
	if flat.length_squared() < 0.01:
		return
	var desired := Basis.looking_at(flat.normalized(), Vector3.UP)
	head.global_transform.basis = head.global_transform.basis.slerp(desired, turn_speed * delta).orthonormalized()


func _is_aimed(to_jet: Vector3) -> bool:
	if not is_instance_valid(head):
		return true
	var flat := Vector3(to_jet.x, 0.0, to_jet.z)
	if flat.length_squared() < 0.01:
		return true
	var head_fwd := -head.global_transform.basis.z
	head_fwd.y = 0.0
	return head_fwd.normalized().angle_to(flat.normalized()) <= deg_to_rad(aim_tolerance_degrees)


func _has_missile_budget() -> bool:
	_missiles.assign(_missiles.filter(func(m) -> bool: return is_instance_valid(m)))
	if _missiles.size() >= max_active_missiles:
		return false
	return Missile.active_count(MissileConfig.Team.ENEMY) < GameConst.MAX_ACTIVE_ENEMY_MISSILES


## Returns {position, direction} or an empty Dictionary if the shot is not safe.
func _plan_launch() -> Dictionary:
	if missile_scene == null:
		return {}

	var space := _body.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if _jet is CollisionObject3D:
		exclude.append((_jet as CollisionObject3D).get_rid())

	var spawn_pos := muzzle.global_position if is_instance_valid(muzzle) \
		else _body.global_position + Vector3(0.0, 2.5, 0.0)

	# 1. Spawn point must be above verified terrain.
	var ground_y := _ground_height(space, spawn_pos, exclude)
	if is_nan(ground_y):
		if not _warned_no_ground:
			_warned_no_ground = true
			push_warning("Turret %s found no terrain under its muzzle; not firing. Is terrain on LAYER_TERRAIN?" % _body.name)
		return {}
	spawn_pos.y = maxf(spawn_pos.y, ground_y + muzzle_clearance)

	# 2. Optional line of sight to the jet.
	var aim_point := _jet.global_position
	if requires_line_of_sight and not _ray(space, spawn_pos, aim_point, exclude).is_empty():
		return {}

	# 3. First stretch of the flight path must be clear of terrain.
	var toward := (aim_point - spawn_pos).normalized()
	var dir := (toward + Vector3(0.0, launch_elevation, 0.0)).normalized()
	if not _ray(space, spawn_pos, spawn_pos + dir * launch_clear_distance, exclude).is_empty():
		return {}

	return {"position": spawn_pos, "direction": dir}


func _ground_height(space: PhysicsDirectSpaceState3D, pos: Vector3, exclude: Array[RID]) -> float:
	var hit := _ray(space, pos + Vector3.UP * ground_probe_up, pos - Vector3.UP * ground_probe_down, exclude)
	return NAN if hit.is_empty() else (hit["position"] as Vector3).y


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, GameConst.LAYER_TERRAIN)
	q.exclude = exclude # the jet shares layer 1 with terrain for now
	q.collide_with_areas = false
	return space.intersect_ray(q)


func _launch(pos: Vector3, dir: Vector3) -> void:
	var missile := missile_scene.instantiate() as Missile
	if missile == null:
		push_error("Turret.missile_scene must use missile.gd.")
		return
	if missile_config != null:
		missile.config = missile_config
	missile.target = _jet
	get_tree().current_scene.add_child(missile)
	missile.global_position = pos
	missile.global_transform.basis = Basis.looking_at(dir, Vector3.UP)
	_missiles.append(missile)
