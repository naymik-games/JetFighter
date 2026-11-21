class_name NetworkMember
extends Node
## Marks its parent (a SAM turret, a radar-dependent gun...) as part of a defense network.
## When the network goes offline the parent stops firing, turns dark grey and smokes.
## Attached in code by the spawners: NetworkMember.attach(target, &"net_a"). No scene edits.
##
## "Stops firing" works by switching off any child node that has a `missile_scene` property
## (your Turret node), so turret.gd itself does not need to know about networks.

var network_id: StringName = &""

var _is_offline: bool = false

static var _offline_material: StandardMaterial3D = null


static func attach(target: Node, p_network_id: StringName) -> NetworkMember:
	var member := NetworkMember.new()
	member.name = "NetworkMember"
	member.network_id = p_network_id
	target.add_child(member)
	return member


func _ready() -> void:
	DefenseNetworks.join(network_id, self)


func _exit_tree() -> void:
	DefenseNetworks.leave(network_id, self)


func is_offline() -> bool:
	return _is_offline


func go_offline() -> void:
	if _is_offline:
		return
	_is_offline = true
	var parent := get_parent() as Node3D
	if parent == null:
		return

	# 1. Stop it firing and aiming.
	for child in parent.get_children():
		if child != self and "missile_scene" in child:
			child.process_mode = Node.PROCESS_MODE_DISABLED
	if "enemy_missile_scene" in parent:
		parent.set_physics_process(false) # older turrets that fire from the root script

	# 2. Dark grey, so it reads as "dead" next to working ones.
	for mesh in parent.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = _get_offline_material()

	# 3. A thin column of smoke.
	parent.add_child(_make_smoke())


static func _get_offline_material() -> StandardMaterial3D:
	if _offline_material == null:
		_offline_material = StandardMaterial3D.new()
		_offline_material.albedo_color = Color(0.16, 0.16, 0.17)
		_offline_material.roughness = 1.0
	return _offline_material


static func _make_smoke() -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.name = "OfflineSmoke"
	smoke.position = Vector3(0.0, 1.8, 0.0)
	smoke.amount = 10
	smoke.lifetime = 2.6
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.gravity = Vector3.ZERO
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 3.5
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 1.3

	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 6
	puff.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	puff.material = material
	smoke.mesh = puff

	var fade := Gradient.new()
	fade.set_color(0, Color(0.30, 0.30, 0.30, 0.75))
	fade.set_color(1, Color(0.30, 0.30, 0.30, 0.0))
	smoke.color_ramp = fade
	smoke.emitting = true
	return smoke
