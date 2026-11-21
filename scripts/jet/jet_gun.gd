class_name JetGun
extends Node
## Machine gun: a timed burst, a heat meter, and a hitscan shot per round. Independent of
## JetWeapons (missiles) and JetLockOn: the gun never reads the missile lock.
## Fire requests arrive from JetInput (keyboard or touch) via request_fire().
##
## Build steps covered here: 1 (config + burst/heat/overheat state) and 2 (hitscan with
## target damage and ground hits). Tracers, aim assist and the HUD hook into the signals
## and the aim seam below.

## Emitted once per round. `end_point` is where the shot stopped (impact, or max range).
## Tracers and impact effects (step 3) listen to this.
signal shot_fired(origin: Vector3, end_point: Vector3, hit_kind: int)
signal burst_started
signal burst_ended(shots: int)
signal overheated_changed(is_overheated: bool)
## `reason` is &"overheated" or &"cooldown". The HUD can use it to flash the heat ring.
signal fire_denied(reason: StringName)

enum HitKind { NONE, GROUND, TARGET }

@export var config: GunConfig
## Local to the jet: where rounds leave from.
@export var muzzle_offset: Vector3 = Vector3(0.0, -0.2, -1.5)

@export_group("Debug")
## Burst summaries, overheat changes and kills.
@export var debug_log: bool = true
## A short-lived sphere at each impact: red = target, yellow = ground.
@export var debug_markers: bool = true

## 0..1. Reaching 1.0 overheats the gun.
var heat: float = 0.0
var is_bursting: bool = false
var is_overheated: bool = false
## Direction the next round will fly. Refreshed every tick so the HUD can read it.
var aim_direction: Vector3 = Vector3.FORWARD

var _body: CharacterBody3D
var _fire_requested: bool = false
var _burst_left: float = 0.0
var _cooldown_left: float = 0.0
var _shot_accum: float = 0.0
var _since_last_shot: float = 999.0

# Per-burst stats for the debug summary.
var _burst_shots: int = 0
var _burst_target_hits: int = 0
var _burst_ground_hits: int = 0
var _burst_kills: int = 0

static var _marker_mesh: SphereMesh = null
static var _marker_mats: Dictionary = {}


func setup(body: CharacterBody3D) -> void:
	_body = body
	if config == null:
		config = GunConfig.new()
	aim_direction = _compute_aim_direction()


func request_fire() -> void:
	_fire_requested = true


## Stops any burst right away (jet death, pause...). Heat is left as it is.
func cease_fire() -> void:
	_fire_requested = false
	if is_bursting:
		_end_burst()


## World position rounds leave from.
func get_muzzle_position() -> Vector3:
	return _body.global_transform * muzzle_offset


## A point `distance` ahead of the muzzle along the aim direction. The HUD will project this
## to draw the gun reticle (in chase view the screen centre is not where the nose points).
func get_aim_point(distance: float) -> Vector3:
	return get_muzzle_position() + aim_direction * distance


func update(delta: float) -> void:
	aim_direction = _compute_aim_direction()

	var requested := _fire_requested
	_fire_requested = false
	if requested:
		_handle_press()

	if is_bursting:
		_tick_burst(delta)
	elif _cooldown_left > 0.0:
		_cooldown_left -= delta

	_tick_heat(delta)


## The aim seam. Plain jet nose for now; build step 4 (reticle snapping toward a candidate
## target) replaces the body of this and nothing else has to change.
func _compute_aim_direction() -> Vector3:
	return -_body.global_transform.basis.z


func _handle_press() -> void:
	if is_overheated:
		fire_denied.emit(&"overheated")
		return
	if is_bursting:
		if config.press_extends_burst:
			_burst_left = config.burst_duration
		return
	if _cooldown_left > 0.0:
		fire_denied.emit(&"cooldown")
		return
	_start_burst()


func _start_burst() -> void:
	is_bursting = true
	_burst_left = config.burst_duration
	_shot_accum = 1.0 / maxf(config.shots_per_second, 0.1) # first round goes out this tick
	_burst_shots = 0
	_burst_target_hits = 0
	_burst_ground_hits = 0
	_burst_kills = 0
	burst_started.emit()


func _end_burst() -> void:
	is_bursting = false
	_cooldown_left = config.burst_cooldown
	burst_ended.emit(_burst_shots)
	if debug_log:
		print("[Gun] burst: %d rounds, %d target hits, %d ground hits, %d kills | heat %.2f%s" % [
			_burst_shots, _burst_target_hits, _burst_ground_hits, _burst_kills, heat,
			" OVERHEATED" if is_overheated else ""])


func _tick_burst(delta: float) -> void:
	_burst_left -= delta
	_shot_accum += delta
	var interval := 1.0 / maxf(config.shots_per_second, 0.1)
	# A while loop so a high fire rate (or a long frame) still delivers every round.
	while is_bursting and _shot_accum >= interval:
		_shot_accum -= interval
		_fire_round()
	if is_bursting and _burst_left <= 0.0:
		_end_burst()


func _tick_heat(delta: float) -> void:
	_since_last_shot += delta
	if is_bursting or _since_last_shot < config.cool_delay:
		return
	heat = maxf(heat - config.cool_rate * delta, 0.0)
	if is_overheated and heat <= config.overheat_resume:
		_set_overheated(false)


func _set_overheated(value: bool) -> void:
	if is_overheated == value:
		return
	is_overheated = value
	overheated_changed.emit(value)
	if debug_log:
		print("[Gun] %s (heat %.2f)" % ["OVERHEATED" if value else "cooled, ready", heat])


func _fire_round() -> void:
	heat = minf(heat + config.heat_per_shot, 1.0)
	_since_last_shot = 0.0
	_burst_shots += 1

	var origin := get_muzzle_position()
	var result := _hitscan(origin, aim_direction)
	var end_point: Vector3 = result["end"]
	var kind: int = result["kind"]
	shot_fired.emit(origin, end_point, kind)

	if debug_markers and kind != HitKind.NONE:
		_spawn_marker(end_point, kind)

	if heat >= 1.0:
		_set_overheated(true)
		_end_burst()


## One ray from the muzzle. The first thing it touches is what it hits: a Target (an Area3D
## on the targets layer) or terrain. The jet itself is excluded because it shares layer 1
## with the terrain for now.
func _hitscan(origin: Vector3, dir: Vector3) -> Dictionary:
	var end_point := origin + dir * config.max_range
	var query := PhysicsRayQueryParameters3D.create(
		origin, end_point, GameConst.LAYER_TERRAIN | GameConst.LAYER_TARGETS)
	query.exclude = [_body.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit := _body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"kind": HitKind.NONE, "end": end_point}

	var point: Vector3 = hit["position"]
	var target := hit["collider"] as Target
	if target != null:
		_damage_target(target)
		_burst_target_hits += 1
		return {"kind": HitKind.TARGET, "end": point}

	_burst_ground_hits += 1
	_ground_splash(point)
	return {"kind": HitKind.GROUND, "end": point}


## Terrain impact: hurt the single nearest Target within the splash radius, if any.
func _ground_splash(point: Vector3) -> void:
	if config.ground_splash_radius <= 0.0:
		return
	var nearest: Target = null
	var nearest_sq := INF
	for t in TargetRegistry.query(point, config.ground_splash_radius, TargetRegistry.MASK_ALL):
		var d_sq := point.distance_squared_to(t.global_position)
		if d_sq < nearest_sq:
			nearest_sq = d_sq
			nearest = t
	if nearest != null:
		_damage_target(nearest)


func _damage_target(target: Target) -> void:
	if target.is_dead():
		return
	target.take_damage(config.damage)
	if target.is_dead():
		_burst_kills += 1
		if debug_log:
			print("[Gun] killed %s" % target.name)


func _spawn_marker(pos: Vector3, kind: int) -> void:
	if _marker_mesh == null:
		_marker_mesh = SphereMesh.new()
		_marker_mesh.radius = 0.4
		_marker_mesh.height = 0.8
		_marker_mesh.radial_segments = 6
		_marker_mesh.rings = 3
	if not _marker_mats.has(kind):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.2, 0.2) if kind == HitKind.TARGET else Color(1.0, 0.85, 0.2)
		_marker_mats[kind] = mat

	var marker := MeshInstance3D.new()
	marker.mesh = _marker_mesh
	marker.material_override = _marker_mats[kind]
	get_tree().current_scene.add_child(marker)
	marker.global_position = pos
	get_tree().create_timer(0.35).timeout.connect(marker.queue_free)
