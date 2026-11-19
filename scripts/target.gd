class_name Target
extends Area3D
## Base class for anything that can be shot: tanks, SAM turrets, and neutral
## targets you should avoid. Emits `destroyed` (signature unchanged) so the
## SpawnManager can record destroyed IDs and the ScoreSystem can award points.
## Registers itself with TargetRegistry while in the tree.

signal destroyed(target_position: Vector3)

## Order matters: TargetRegistry.MASK_* are 1 << these values.
enum Team { ENEMY, NEUTRAL, FRIENDLY }

@export var team: Team = Team.ENEMY
@export var max_health: int = 1
## Negative values are penalties (use for neutral targets).
@export var points: int = 100
@export var explosion_scene: PackedScene # Assign ExplosionBurst.tscn in Inspector
@export var shake_max_distance: float = 240.0
## Where missiles aim, relative to the target's origin (its origin is on the ground).
@export var aim_offset: Vector3 = Vector3(0.0, 1.0, 0.0)

var health: int = 1
var _dead := false


func _ready() -> void:
	health = max_health
	collision_layer = GameConst.LAYER_TARGETS
	collision_mask = 0
	add_to_group(GameConst.GROUP_TARGETS) # kept for compatibility; nothing in Phase 4 scans it
	TargetRegistry.register(self)


func _exit_tree() -> void:
	TargetRegistry.unregister(self)


static func team_bit(t: Team) -> int:
	return 1 << t


func get_aim_position() -> Vector3:
	return global_transform * aim_offset


func is_hostile() -> bool:
	return team == Team.ENEMY


func is_dead() -> bool:
	return _dead


func take_damage(amount: int) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0:
		_destroy()


## Legacy entry point: always lethal.
func hit() -> void:
	take_damage(maxi(health, 1))


func _destroy() -> void:
	_dead = true
	TargetRegistry.unregister(self) # stop being lockable this frame
	destroyed.emit(global_position)
	_on_destroyed()
	_spawn_explosion()
	_shake_camera()
	queue_free()


## Override in subclasses for extra death behavior (debris, chain explosions...).
func _on_destroyed() -> void:
	pass


func _spawn_explosion() -> void:
	if explosion_scene == null:
		return
	var boom := explosion_scene.instantiate()
	get_tree().current_scene.add_child(boom)
	boom.global_position = global_position


func _shake_camera() -> void:
	var jet := get_tree().get_first_node_in_group(GameConst.GROUP_PLAYER)
	if is_instance_valid(jet) and jet.has_method("add_camera_shake"):
		var dist := global_position.distance_to(jet.global_position)
		var falloff: float = clamp(1.0 - (dist / shake_max_distance), 0.15, 1.0)
		jet.add_camera_shake(0.85 * falloff)
