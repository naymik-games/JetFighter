class_name JetGun
extends Node
## Machine gun: a timed burst, a heat meter, and a hitscan shot per round. Independent of
## JetWeapons (missiles) and JetLockOn: the gun never reads the missile lock.
## Fire requests arrive from JetInput (keyboard or touch) via request_fire().
##
## Build steps covered here: 1 (config + burst/heat/overheat state), 2 (hitscan with target
## damage and ground hits), 3 (tracers + impact flashes, see JetGunTracers) and 4 (aim assist).
## The reticle and heat ring live in JetGunReticle; the touch button lives in JetTouchControls.

## Emitted once per round. `end_point` is where the shot stopped (impact, or max range).
## Tracers and impact effects listen to this.
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

@export_group("Aim Assist")
@export var assist_enabled: bool = true
## Targets farther than this (from the muzzle) are never assisted.
@export var assist_range: float = 180.0
## Half-angle around the nose. Generous on purpose; dial it down once it feels too sticky.
@export var assist_cone_degrees: float = 14.0
## 0 = no pull, 1 = rounds fly straight at the target once the blend settles.
@export_range(0.0, 1.0) var assist_strength: float = 1.0
## How fast the aim glides onto (and off) a target. Higher = snappier.
@export var assist_snap_speed: float = 12.0
## The current assist target is kept until it leaves cone * this factor.
@export var assist_hold_factor: float = 1.35
## A new candidate must be this many degrees closer to the nose to steal the assist.
@export var assist_switch_degrees: float = 3.0
@export_flags("Enemy", "Neutral", "Friendly") var assist_teams: int = 1

@export_group("Effects")
## Creates the tracer and reticle nodes ($Tracers, $Reticle) if the scene doesn't have them.
@export var auto_create_effects: bool = true

@export_group("Debug")
## Burst summaries, overheat changes and kills.
@export var debug_log: bool = true
## A short-lived sphere at each impact: red = target, yellow = ground. Off now that tracers
## and impact flashes show the same thing.
@export var debug_markers: bool = false

## 0..1. Reaching 1.0 overheats the gun.
var heat: float = 0.0
var is_bursting: bool = false
var is_overheated: bool = false
## Direction the next round will fly. Refreshed every tick so the HUD can read it.
var aim_direction: Vector3 = Vector3.FORWARD
## The target the aim is currently pulled toward, or null.
var assist_target: Target = null

var _body: CharacterBody3D
var _fire_requested: bool = false
var _burst_left: float = 0.0
var _cooldown_left: float = 0.0
var _shot_accum: float = 0.0
var _since_last_shot: float = 999.0

# Aim assist state. The blend eases between the jet nose (0) and the target direction (1), so
# with no target the aim is exactly the nose with no lag.
var _assist_blend: float = 0.0
var _assist_desired: Vector3 = Vector3.FORWARD

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
	aim_direction = _nose_direction()
	_assist_desired = aim_direction
	_ensure_effects()


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


## A point `distance` ahead of the muzzle along the aim direction.
func get_aim_point(distance: float) -> Vector3:
	return get_muzzle_position() + aim_direction * distance


## True while the aim is being pulled toward a target.
func is_assisting() -> bool:
	return is_instance_valid(assist_target)


func update(delta: float) -> void:
	aim_direction = _compute_aim_direction(delta)

	var requested := _fire_requested
	_fire_requested = false
	if requested:
		_handle_press()

	if is_bursting:
		_tick_burst(delta)
	elif _cooldown_left > 0.0:
		_cooldown_left -= delta

	_tick_heat(delta)


func _ensure_effects() -> void:
	var tracers := get_node_or_null("Tracers") as JetGunTracers
	if tracers == null and auto_create_effects:
		tracers = JetGunTracers.new()
		tracers.name = "Tracers"
		add_child(tracers)
	if tracers != null:
		tracers.setup(self)

	var reticle := get_node_or_null("Reticle") as JetGunReticle
	if reticle == null and auto_create_effects:
		reticle = JetGunReticle.new()
		reticle.name = "Reticle"
		add_child(reticle)
	if reticle != null:
		reticle.setup(self)


func _nose_direction() -> Vector3:
	return (-_body.global_transform.basis.z).normalized()


## The aim seam. Nose direction, pulled toward the assist target when there is one.
func _compute_aim_direction(delta: float) -> Vector3:
	var nose := _nose_direction()
	if not assist_enabled:
		assist_target = null
		_assist_blend = 0.0
		return nose

	_update_assist_target(nose)

	var goal := 0.0
	if is_instance_valid(assist_target):
		goal = assist_strength
		# Kept after the target is lost so the aim eases back to the nose instead of jumping.
		_assist_desired = (assist_target.get_aim_position() - get_muzzle_position()).normalized()

	_assist_blend = lerpf(_assist_blend, goal, 1.0 - exp(-assist_snap_speed * delta))
	if _assist_blend < 0.002:
		_assist_blend = 0.0
		return nose
	return nose.slerp(_assist_desired, _assist_blend).normalized()


func _update_assist_target(nose: Vector3) -> void:
	if not is_instance_valid(assist_target):
		assist_target = null

	var origin := get_muzzle_position()
	var cone := deg_to_rad(assist_cone_degrees)
	var best := TargetRegistry.best_in_cone(
		origin, nose, assist_range, cone, assist_teams, _assist_can_see) as Target

	var chosen: Target = best
	if assist_target != null and _assist_still_valid(assist_target, origin, nose, cone * assist_hold_factor):
		chosen = assist_target
		if best != null and best != assist_target \
				and _angle_to(best, origin, nose) + deg_to_rad(assist_switch_degrees) < _angle_to(assist_target, origin, nose):
			chosen = best
	assist_target = chosen


func _angle_to(t: Target, origin: Vector3, nose: Vector3) -> float:
	return nose.angle_to((t.get_aim_position() - origin).normalized())


func _assist_still_valid(t: Target, origin: Vector3, nose: Vector3, max_angle: float) -> bool:
	if t.is_dead():
		return false
	if (Target.team_bit(t.team) & assist_teams) == 0:
		return false
	if origin.distance_to(t.get_aim_position()) > assist_range * 1.1:
		return false
	if _angle_to(t, origin, nose) > max_angle:
		return false
	return _assist_can_see(t)


## True if no terrain sits between the muzzle and the target.
func _assist_can_see(t: Target) -> bool:
	var q := PhysicsRayQueryParameters3D.create(
		get_muzzle_position(), t.get_aim_position(), GameConst.LAYER_TERRAIN)
	q.exclude = [_body.get_rid()] # the jet shares layer 1 with terrain for now
	q.collide_with_areas = false
	return _body.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


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
