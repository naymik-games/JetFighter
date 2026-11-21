class_name JetGunTracers
extends Node3D
## Visual tracers and impact flashes for the machine gun. Purely cosmetic: damage was already
## dealt by the hitscan. Listens to JetGun.shot_fired, so the gun never knows this exists.
##
## Each round becomes a short glowing streak that flies from the muzzle to where the hitscan
## ended, at `speed`. Only every `tracer_every`-th round gets a streak (the first round of a
## burst always does); every hit still gets its impact flash when the round arrives.
## Meshes are pooled, so firing doesn't allocate.

@export var enabled: bool = true
## 1 = every round, 2 = every other round...
@export var tracer_every: int = 2
@export var speed: float = 450.0
@export var length: float = 7.0
@export var width: float = 0.14
@export var color: Color = Color(1.0, 0.82, 0.25)
## Safety cap on rounds in flight at once.
@export var max_in_flight: int = 48

@export_group("Impacts")
@export var impact_effects: bool = true
@export var impact_size: float = 1.0
@export var impact_time: float = 0.16
@export var target_impact_color: Color = Color(1.0, 0.55, 0.2)
@export var ground_impact_color: Color = Color(0.95, 0.85, 0.5)

var _gun: JetGun
var _count: int = 0

# Rounds in flight: { node (MeshInstance3D or null), origin, dir, dist, head, kind }
var _rounds: Array[Dictionary] = []
var _free_tracers: Array[MeshInstance3D] = []
var _flashes: Array[Dictionary] = [] # { node, age }
var _free_flashes: Array[MeshInstance3D] = []

var _tracer_mesh: BoxMesh
var _tracer_mat: StandardMaterial3D
var _flash_mesh: SphereMesh
var _flash_mat_target: StandardMaterial3D
var _flash_mat_ground: StandardMaterial3D


func _ready() -> void:
	# World space, whatever this node ends up parented to.
	top_level = true
	transform = Transform3D.IDENTITY

	_tracer_mesh = BoxMesh.new()
	_tracer_mesh.size = Vector3(width, width, 1.0) # Z is stretched per tracer
	_tracer_mat = _make_mat(color, 2.0)

	_flash_mesh = SphereMesh.new()
	_flash_mesh.radius = 0.6
	_flash_mesh.height = 1.2
	_flash_mesh.radial_segments = 8
	_flash_mesh.rings = 4
	_flash_mat_target = _make_mat(target_impact_color, 2.5)
	_flash_mat_ground = _make_mat(ground_impact_color, 1.5)


func setup(gun: JetGun) -> void:
	_gun = gun
	if not gun.shot_fired.is_connected(_on_shot_fired):
		gun.shot_fired.connect(_on_shot_fired)
		gun.burst_started.connect(_on_burst_started)


func _make_mat(col: Color, glow: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = glow
	return mat


func _on_burst_started() -> void:
	_count = 0


func _on_shot_fired(origin: Vector3, end_point: Vector3, kind: int) -> void:
	var show_tracer := enabled and (_count % maxi(tracer_every, 1) == 0)
	_count += 1

	var to := end_point - origin
	var dist := to.length()
	if dist < 0.01 or _rounds.size() >= max_in_flight:
		return
	var wants_impact := impact_effects and kind != JetGun.HitKind.NONE
	if not show_tracer and not wants_impact:
		return

	var node: MeshInstance3D = null
	if show_tracer:
		node = _take_tracer()
	_rounds.append({
		"node": node, "origin": origin, "dir": to / dist,
		"dist": dist, "head": 0.0, "kind": kind,
	})


func _process(delta: float) -> void:
	_update_rounds(delta)
	_update_flashes(delta)


func _update_rounds(delta: float) -> void:
	var step := speed * delta
	var i := _rounds.size() - 1
	while i >= 0:
		var r := _rounds[i]
		r["head"] = float(r["head"]) + step
		var head: float = r["head"]
		var dist: float = r["dist"]
		var dir: Vector3 = r["dir"]
		var origin: Vector3 = r["origin"]
		var node: MeshInstance3D = r["node"]

		if head >= dist:
			if node != null:
				_release_tracer(node)
			var kind: int = r["kind"]
			if impact_effects and kind != JetGun.HitKind.NONE:
				_spawn_flash(origin + dir * dist, kind)
			_rounds.remove_at(i)
		elif node != null:
			# The tail trails the head by `length`, but never starts behind the muzzle, so
			# the streak grows out of the gun.
			var tail := maxf(head - length, 0.0)
			var seg := head - tail
			var mid := origin + dir * (tail + seg * 0.5)
			node.transform = Transform3D(
				_basis_along(dir) * Basis.from_scale(Vector3(1.0, 1.0, seg)), mid)
		i -= 1


func _basis_along(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(dir, up)


func _take_tracer() -> MeshInstance3D:
	var node: MeshInstance3D
	if _free_tracers.is_empty():
		node = MeshInstance3D.new()
		node.mesh = _tracer_mesh
		node.material_override = _tracer_mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	else:
		node = _free_tracers.pop_back()
	# Placed on its first update; hidden until then so it can't flash at the old position.
	node.visible = true
	return node


func _release_tracer(node: MeshInstance3D) -> void:
	node.visible = false
	_free_tracers.append(node)


func _spawn_flash(pos: Vector3, kind: int) -> void:
	var node: MeshInstance3D
	if _free_flashes.is_empty():
		node = MeshInstance3D.new()
		node.mesh = _flash_mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	else:
		node = _free_flashes.pop_back()
	node.material_override = _flash_mat_target if kind == JetGun.HitKind.TARGET else _flash_mat_ground
	node.transform = Transform3D(Basis.from_scale(Vector3.ONE * impact_size), pos)
	node.visible = true
	_flashes.append({"node": node, "age": 0.0})


func _update_flashes(delta: float) -> void:
	var i := _flashes.size() - 1
	while i >= 0:
		var f := _flashes[i]
		f["age"] = float(f["age"]) + delta
		var node: MeshInstance3D = f["node"]
		var k := 1.0 - float(f["age"]) / maxf(impact_time, 0.01)
		if k <= 0.0:
			node.visible = false
			_free_flashes.append(node)
			_flashes.remove_at(i)
		else:
			node.transform = Transform3D(
				Basis.from_scale(Vector3.ONE * impact_size * k), node.position)
		i -= 1
