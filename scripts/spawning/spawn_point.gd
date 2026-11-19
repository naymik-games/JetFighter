class_name SpawnPoint
extends RefCounted
## One planned spawn: pure data, safe to create on a worker thread.

## Stable ID: "<chunk x>_<chunk z>_<rule index>_<n>". Used in Step 5 to remember destroyed targets.
var id: String = ""
var rule: SpawnRule
## World-space position on the terrain surface.
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var yaw: float = 0.0
