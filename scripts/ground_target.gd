extends Area3D
class_name GroundTarget
signal destroyed(target_position: Vector3)

@export var explosion_scene: PackedScene # Assign ExplosionBurst.tscn in Inspector
@export var points: int = 100
@export var shake_max_distance: float = 240.0

func _ready() -> void:
	add_to_group("targets")

func hit() -> void:
	destroyed.emit(global_position)
	
	# Award points to the HUD
	get_tree().call_group("hud", "add_score", points)
	
	# 1. Spawn low-poly explosion burst
	if explosion_scene:
		var boom := explosion_scene.instantiate()
		get_tree().current_scene.add_child(boom)
		boom.global_position = global_position
		
	# 2. Trigger camera shake on the player jet scaled by distance
	var jet := get_tree().get_first_node_in_group("player")
	if is_instance_valid(jet) and jet.has_method("add_camera_shake"):
		var dist := global_position.distance_to(jet.global_position)
		var falloff: float = clamp(1.0 - (dist / shake_max_distance), 0.15, 1.0)
		jet.add_camera_shake(0.85 * falloff)
		
	queue_free()
