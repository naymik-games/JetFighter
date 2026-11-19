class_name SpawnManager
extends Node
## Turns chunk spawn plans into real nodes, a few per frame.
##  - Spreads instantiation over frames (time budget) to avoid hitches.
##  - Spawns nearest-to-jet first.
##  - Never exceeds max_live_targets alive at once; the rest wait in the queue.
##  - Remembers destroyed spawn IDs for the session, so a destroyed target does
##    not come back when its chunk unloads and reloads.

@export var max_live_targets: int = 60
## Stop instantiating for this frame once this much time has been spent.
@export var spawn_budget_ms: float = 2.0

## Used to prioritise the nearest spawns. Set by the Terrain node.
var jet: Node3D

var _queue: Array[Dictionary] = []
var _destroyed_ids: Dictionary = {}
var _live_count: int = 0


## Called by the terrain when a chunk finishes building.
## parent is the chunk node; plan positions are world-space.
func queue_plan(parent: Node3D, world_origin: Vector3, plan: Array) -> void:
	for entry in plan:
		var point := entry as SpawnPoint
		if point == null or point.rule == null or point.rule.scene == null:
			continue
		if _destroyed_ids.has(point.id):
			continue
		_queue.append({"point": point, "parent": parent, "origin": world_origin, "dist": 0.0})


func _process(_delta: float) -> void:
	if _queue.is_empty():
		return

	_drop_stale_jobs()
	if _queue.is_empty() or _live_count >= max_live_targets:
		return

	_sort_by_distance()

	var start_usec := Time.get_ticks_usec()
	while not _queue.is_empty() and _live_count < max_live_targets:
		_spawn(_queue.pop_front())
		if (Time.get_ticks_usec() - start_usec) / 1000.0 >= spawn_budget_ms:
			break


# Remove jobs whose chunk has been unloaded (or is about to be)
func _drop_stale_jobs() -> void:
	var kept: Array[Dictionary] = []
	for job in _queue:
		var parent := job["parent"] as Node
		if is_instance_valid(parent) and not parent.is_queued_for_deletion():
			kept.append(job)
	_queue = kept


func _sort_by_distance() -> void:
	if not is_instance_valid(jet):
		jet = get_tree().get_first_node_in_group(GameConst.GROUP_PLAYER) as Node3D
	if not is_instance_valid(jet) or _queue.size() < 2:
		return
	var jet_pos := jet.global_position
	for job in _queue:
		var point: SpawnPoint = job["point"]
		job["dist"] = jet_pos.distance_squared_to(point.position)
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])


func _spawn(job: Dictionary) -> void:
	var point: SpawnPoint = job["point"]
	var parent: Node3D = job["parent"]
	var world_origin: Vector3 = job["origin"]

	var instance := point.rule.scene.instantiate() as Node3D
	if instance == null:
		return

	var orientation := Basis(Vector3.UP, point.yaw)
	if point.rule.align_to_surface:
		orientation = Basis(Quaternion(Vector3.UP, point.normal)) * orientation

	# The chunk mesh sits at world_origin, so convert the world-space plan position to local
	instance.transform = Transform3D(orientation, point.position - world_origin)
	instance.set_meta("spawn_id", point.id)
	parent.add_child(instance)

	_live_count += 1
	# Fires both when destroyed and when the chunk unloads, so the live count stays correct
	instance.tree_exited.connect(_on_instance_exited)

	# Only Targets report destruction; scenery spawned by other rules is skipped.
	var target := instance as Target
	if target != null:
		target.destroyed.connect(_on_target_destroyed.bind(point.id))


func _on_instance_exited() -> void:
	_live_count = maxi(_live_count - 1, 0)


func _on_target_destroyed(_target_position: Vector3, spawn_id: String) -> void:
	_destroyed_ids[spawn_id] = true


func get_stats() -> Dictionary:
	return {
		"queued": _queue.size(),
		"live": _live_count,
		"cap": max_live_targets,
		"destroyed": _destroyed_ids.size(),
	}
