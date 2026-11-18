extends GroundTarget

@export_group("SAM Launcher")
@export var enemy_missile_scene: PackedScene # Assign EnemyMissile.tscn in Inspector
@export var detection_range: float = 260.0
@export var fire_interval: float = 4.2
@export var turret_turn_speed: float = 2.5

@onready var turret_head: Node3D = $TurretHead
@onready var muzzle: Marker3D = $TurretHead/Muzzle

var player_jet: Node3D = null
var fire_timer: float = 0.0

func _ready() -> void:
	super._ready() # Registers in "targets" group
	points = 250 # Higher score reward than passive ground targets
	fire_timer = randf_range(1.0, fire_interval) # Stagger initial shots across turrets
	player_jet = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player_jet):
		player_jet = get_tree().get_first_node_in_group("player")
		return
		
	var to_player := player_jet.global_position - global_position
	var dist := to_player.length()
	
	if dist > detection_range:
		return
		
	# Rotate turret head smoothly toward the incoming jet
	if is_instance_valid(turret_head):
		var flat_dir := Vector3(to_player.x, 0.0, to_player.z)
		if flat_dir.length_squared() > 0.01:
			var target_basis := Basis.looking_at(flat_dir.normalized(), Vector3.UP)
			turret_head.global_transform.basis = turret_head.global_transform.basis.slerp(target_basis, turret_turn_speed * delta).orthonormalized()
			
	# Fire cooldown
	fire_timer -= delta
	if fire_timer <= 0.0:
		fire_timer = fire_interval
		_launch_sam()

func _launch_sam() -> void:
	if not enemy_missile_scene or not is_instance_valid(player_jet):
		return
		
	var sam := enemy_missile_scene.instantiate()
	get_tree().current_scene.add_child(sam)
	
	var spawn_pos := muzzle.global_position if is_instance_valid(muzzle) else (global_position + Vector3(0, 2.5, 0))
	sam.global_position = spawn_pos
	
	# Launch upward at a 35-degree arc so it clears hills cleanly before pitching onto the jet
	var toward_jet := (player_jet.global_position - spawn_pos).normalized()
	var launch_dir := (toward_jet + Vector3(0.0, 0.65, 0.0)).normalized()
	sam.global_transform.basis = Basis.looking_at(launch_dir, Vector3.UP)
	sam.target = player_jet
