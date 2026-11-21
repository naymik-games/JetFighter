class_name DefenderSpawn
extends RefCounted
## One planned defender (tank, SAM...) guarding an objective. Pure data, made by
## ObjectiveDefenses at mission start and spawned by ObjectiveSpawner when its chunk exists.

## Stable id, e.g. "d2_3" (objective 2, defender 3). Used to remember destroyed defenders.
var id: String = ""
## Name of the SpawnRule whose scene is used (&"tank", &"sam_turret").
var kind: StringName = &""
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var yaw: float = 0.0
## Defense network this defender belongs to (empty = none).
var network: StringName = &""
