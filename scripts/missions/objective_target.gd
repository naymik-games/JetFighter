class_name ObjectiveTarget
extends Target
## A mission objective in the world: a normal Target (lockable, shootable, scored) plus a
## placeholder model. ObjectiveSpawner creates it, calls configure(), and listens for
## `destroyed` to tell the MissionManager.
##
## Your own models: make a scene whose root script extends ObjectiveTarget, give it a
## CollisionShape3D, and assign it to ObjectiveConfig.target_scene. When the scene already has
## a CollisionShape3D, no placeholder model or collision is added.

## Extra explosion bursts around the target when it dies (needs explosion_scene).
@export var extra_explosions: int = 2
## Radians per second the radar dish turns. Only models with a "Spinner" use it.
@export var spin_speed: float = 0.9

var kind: ObjectiveConfig.Kind = ObjectiveConfig.Kind.FUEL_DEPOT
var objective_index: int = -1
var placement: ObjectivePlacement

var _spinner: Node3D = null


## Call before add_child().
func configure(p_placement: ObjectivePlacement) -> void:
	placement = p_placement
	objective_index = p_placement.index
	var config := p_placement.objective
	kind = config.kind
	team = Team.ENEMY
	points = config.base_points
	if config.health_override > 0:
		max_health = config.health_override
	shake_max_distance = 400.0
	name = "Objective%d_%s" % [objective_index + 1, config.get_display_name().replace(" ", "")]


func _ready() -> void:
	if find_children("*", "CollisionShape3D", false, false).is_empty():
		_build_placeholder()
	set_process(_spinner != null)
	super._ready()


func _process(delta: float) -> void:
	if is_instance_valid(_spinner):
		_spinner.rotate_y(spin_speed * delta)


func _build_placeholder() -> void:
	var built := ObjectiveModels.build(kind)
	var model: Node3D = built["root"]
	add_child(model)

	var hit_size: Vector3 = built["hit_size"]
	var box := BoxShape3D.new()
	box.size = hit_size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(0.0, hit_size.y * 0.5, 0.0)
	add_child(shape)

	aim_offset = Vector3(0.0, built["aim_height"], 0.0)
	_spinner = built["spinner"] as Node3D


func _on_destroyed() -> void:
	if explosion_scene == null or extra_explosions <= 0:
		return
	var scene_root := get_tree().current_scene
	for i in extra_explosions:
		var boom := explosion_scene.instantiate() as Node3D
		if boom == null:
			return
		scene_root.add_child(boom)
		var angle := randf() * TAU
		var radius := randf_range(3.0, 9.0)
		boom.global_position = global_position + Vector3(cos(angle) * radius, randf_range(1.0, 6.0), sin(angle) * radius)
