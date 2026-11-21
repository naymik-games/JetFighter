class_name ObjectiveSpawner
extends Node
## Turns the MissionManager's active objective into a real ObjectiveTarget.
##
## The objective position is just data, usually far outside the loaded terrain. The target is
## created as a child of the terrain chunk that contains it, as soon as that chunk exists, so it
## streams in and out with the terrain exactly like your other targets. If the player flies away
## and comes back while the objective is still alive, it is created again. A destroyed objective
## never returns, because the manager moves on and only the ACTIVE objective is ever spawned.
##
## Only the active objective exists in the world; later ones are not spawned until revealed.
##
## Its defenders (tanks and SAMs planned by ObjectiveDefenses) are spawned the same way, each in
## the chunk that contains it, and come back after a chunk reload unless they were destroyed.
## Defenders that are still alive when the objective is destroyed simply stay where they are.

var explosion_scene: PackedScene

var _manager: MissionManager
var _terrain: Node
var _active: ObjectivePlacement = null
var _instance: ObjectiveTarget = null
var _defenders: Array[DefenderSpawn] = []
var _defender_destroyed: Dictionary = {} # id -> true, never respawn these
var _defender_live: Dictionary = {} # id -> true while the node exists


func setup(manager: MissionManager, terrain: Node) -> void:
	_manager = manager
	_terrain = terrain
	_manager.objective_revealed.connect(_on_objective_revealed)
	_manager.objective_completed.connect(_on_objective_completed)
	_manager.state_changed.connect(_on_state_changed)
	_terrain.chunk_ready.connect(_on_chunk_ready)


## The objective target currently alive in the world, or null.
func current_instance() -> ObjectiveTarget:
	return _instance if is_instance_valid(_instance) else null


func _on_objective_revealed(_index: int, placement: ObjectivePlacement) -> void:
	_active = placement
	_defenders = placement.defenders
	_try_spawn()
	_try_spawn_defenders()


func _on_objective_completed(_index: int, _placement: ObjectivePlacement, _time_left: float) -> void:
	_active = null
	_defenders = []


func _on_state_changed(new_state: MissionManager.State, _old_state: MissionManager.State) -> void:
	# A failed, restarted or finished mission leaves nothing behind.
	if new_state == MissionManager.State.FAILED or new_state == MissionManager.State.BRIEFING or new_state == MissionManager.State.IDLE:
		_active = null
		_defenders = []
		if is_instance_valid(_instance):
			_instance.queue_free()
		_instance = null


func _on_chunk_ready(coord: Vector2i, _chunk: Node3D) -> void:
	if _active != null and coord == _terrain.chunk_coord_at(_active.position):
		_try_spawn()
	_try_spawn_defenders()


func _try_spawn() -> void:
	if _active == null:
		return
	# A target for this same objective is already alive. (A dying target of the previous
	# objective does not block the next spawn.)
	if is_instance_valid(_instance) and _instance.objective_index == _active.index and not _instance.is_dead():
		return
	var coord: Vector2i = _terrain.chunk_coord_at(_active.position)
	var chunk: Node3D = _terrain.get_chunk(coord)
	if chunk == null:
		return # Not built yet. _on_chunk_ready will call us when it is.
	_spawn_in_chunk(chunk, coord)


func _spawn_in_chunk(chunk: Node3D, coord: Vector2i) -> void:
	var placement := _active
	var target := _make_target(placement)
	target.configure(placement)
	target.explosion_scene = explosion_scene

	# Same convention as SpawnManager: chunk-local transform, chunk frees it on unload.
	var chunk_origin: Vector3 = _terrain.chunk_origin(coord)
	target.transform = Transform3D(Basis(Vector3.UP, placement.yaw), placement.position - chunk_origin)

	target.destroyed.connect(_on_target_destroyed.bind(placement.index))
	chunk.add_child(target)
	_instance = target
	target.tree_exited.connect(_on_target_exited.bind(target))
	print("[ObjectiveSpawner] spawned #%d %s at %s" % [placement.index + 1, placement.objective.get_display_name(), placement.position])


# --- Defenders ----------------------------------------------------------------

## Spawns every planned defender whose chunk is built and that is not already alive or destroyed.
func _try_spawn_defenders() -> void:
	for defender in _defenders:
		if _defender_destroyed.has(defender.id) or _defender_live.has(defender.id):
			continue
		var coord: Vector2i = _terrain.chunk_coord_at(defender.position)
		var chunk: Node3D = _terrain.get_chunk(coord)
		if chunk == null:
			continue
		_spawn_defender(defender, chunk, coord)


func _spawn_defender(defender: DefenderSpawn, chunk: Node3D, coord: Vector2i) -> void:
	var rule := _rule_for(defender.kind)
	if rule == null or rule.scene == null:
		push_warning("ObjectiveSpawner: no spawn rule named '%s' with a scene, so defender %s is skipped." % [defender.kind, defender.id])
		_defender_destroyed[defender.id] = true # stop trying
		return

	var instance := rule.scene.instantiate() as Node3D
	if instance == null:
		return
	var orientation := Basis(Vector3.UP, defender.yaw)
	if rule.align_to_surface:
		orientation = Basis(Quaternion(Vector3.UP, defender.normal)) * orientation
	instance.transform = Transform3D(orientation, defender.position - _terrain.chunk_origin(coord))
	instance.set_meta("spawn_id", defender.id)
	chunk.add_child(instance)
	if defender.network != &"":
		NetworkMember.attach(instance, defender.network)

	_defender_live[defender.id] = true
	instance.tree_exited.connect(_on_defender_exited.bind(defender.id))
	var target := instance as Target
	if target != null:
		target.destroyed.connect(_on_defender_destroyed.bind(defender.id))


func _rule_for(kind: StringName) -> SpawnRule:
	var table: SpawnTable = _terrain.spawn_table
	if table == null:
		return null
	for rule in table.rules:
		if rule != null and rule.rule_name == kind:
			return rule
	return null


func _on_defender_destroyed(_target_position: Vector3, id: String) -> void:
	_defender_destroyed[id] = true


func _on_defender_exited(id: String) -> void:
	_defender_live.erase(id)


func _make_target(placement: ObjectivePlacement) -> ObjectiveTarget:
	var scene := placement.objective.target_scene
	if scene != null:
		var custom := scene.instantiate() as ObjectiveTarget
		if custom != null:
			return custom
		push_warning("ObjectiveSpawner: target_scene for objective %d does not extend ObjectiveTarget; using the placeholder." % (placement.index + 1))
	return ObjectiveTarget.new()


func _on_target_destroyed(_target_position: Vector3, index: int) -> void:
	if is_instance_valid(_manager):
		_manager.report_objective_destroyed(index)


func _on_target_exited(target: ObjectiveTarget) -> void:
	if _instance == target:
		_instance = null
