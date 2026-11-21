class_name Jet
extends CharacterBody3D
## Player jet. A thin coordinator: it owns the components and ticks them in a fixed order
## (flight -> trails -> camera -> lock-on -> weapons -> gun), exactly like the old monolithic script.

signal health_changed(current: float, maximum: float)
signal died

@export_group("Death")
## Seconds after death before the scene reloads. 0 or less = just emit `died` and freeze.
@export var respawn_delay: float = 2.0

@onready var mesh_pivot: Node3D = $MeshPivot
@onready var flight: JetFlight = $Flight
@onready var controls: JetInput = $Controls
@onready var lock_on: JetLockOn = $LockOn
@onready var weapons: JetWeapons = $Weapons
@onready var health: JetHealth = $Health
@onready var trails: JetTrails = $Trails
@onready var camera_rig: JetCameraRig = $CameraRig
@onready var touch_controls: JetTouchControls = get_node_or_null("TouchControls") as JetTouchControls

## Machine gun. Found at $Gun if the scene has one, otherwise created in _ready().
var gun: JetGun
var is_dead: bool = false

# --- Compatibility shims: other scripts may still read these off the jet. ---
var current_speed: float:
	get:
		return flight.speed
var current_target: Node3D:
	get:
		return lock_on.target
var lock_progress: float:
	get:
		return lock_on.progress


func _ready() -> void:
	add_to_group("player")

	gun = get_node_or_null("Gun") as JetGun
	if gun == null:
		gun = JetGun.new()
		gun.name = "Gun"
		add_child(gun)

	flight.setup(self, mesh_pivot)
	lock_on.setup(self)
	weapons.setup(self, lock_on)
	gun.setup(self)
	trails.setup(mesh_pivot, flight)
	camera_rig.setup(self, mesh_pivot, flight, controls)

	if touch_controls != null:
		controls.button_hit_test = touch_controls.button_at
		touch_controls.setup(controls)

	controls.fire_pressed.connect(weapons.request_fire)
	controls.gun_pressed.connect(gun.request_fire)
	controls.view_toggled.connect(camera_rig.toggle_view)

	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.changed.connect(health_changed.emit)


func _physics_process(delta: float) -> void:
	if is_dead:
		camera_rig.update(delta)
		return

	flight.update(delta, controls)
	trails.update(delta)
	camera_rig.update(delta)
	lock_on.update(delta)
	weapons.update(delta)
	gun.update(delta)


## Called by missiles / turrets. `amount < 0` uses JetHealth.default_damage.
func take_damage(amount: float = -1.0, source: Node = null) -> void:
	health.take_damage(amount, source)


func add_camera_shake(amount: float) -> void:
	camera_rig.add_shake(amount)


func _on_damaged(_amount: float, _source: Node) -> void:
	camera_rig.add_shake(health.hit_shake)


func _on_died() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	controls.release_all()
	gun.cease_fire()
	lock_on.clear()
	trails.clear()
	mesh_pivot.hide()
	camera_rig.on_jet_died()
	camera_rig.add_shake(1.0)
	died.emit()
	if respawn_delay > 0.0:
		get_tree().create_timer(respawn_delay).timeout.connect(_respawn)


func _respawn() -> void:
	get_tree().reload_current_scene()
