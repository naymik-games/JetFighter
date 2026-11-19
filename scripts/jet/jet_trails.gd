class_name JetTrails
extends Node3D
## Wingtip ribbon trails. Same rendering as before; markers ride on MeshPivot so the ribbons
## bank with the wings, and the ribbon meshes live in world space.

## Right wingtip, local to MeshPivot. Default matches the value jet.tscn was already overriding.
@export var wingtip_offset: Vector3 = Vector3(5.0, 0.0, 2.0)
@export var trail_max_points: int = 28
@export var trail_width: float = 0.22
@export var trail_color: Color = Color(0.92, 0.96, 1.0, 0.65)

var _mesh_pivot: Node3D
var _flight: JetFlight
var _left_tip: Marker3D
var _right_tip: Marker3D
var _left_points: Array[Vector3] = []
var _right_points: Array[Vector3] = []
var _left_mesh := ImmediateMesh.new()
var _right_mesh := ImmediateMesh.new()


func setup(mesh_pivot: Node3D, flight: JetFlight) -> void:
	_mesh_pivot = mesh_pivot
	_flight = flight

	_right_tip = Marker3D.new()
	_right_tip.position = wingtip_offset
	_mesh_pivot.add_child(_right_tip)

	_left_tip = Marker3D.new()
	_left_tip.position = Vector3(-wingtip_offset.x, wingtip_offset.y, wingtip_offset.z)
	_mesh_pivot.add_child(_left_tip)

	# Unshaded double-sided ribbon material with vertex alpha fade
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true

	for mesh_res in [_left_mesh, _right_mesh]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh_res
		mi.material_override = mat
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func clear() -> void:
	_left_points.clear()
	_right_points.clear()
	_left_mesh.clear_surfaces()
	_right_mesh.clear_surfaces()


func update(_delta: float) -> void:
	# Trails become thicker and brighter during hard turns or afterburner boost
	var active_alpha := clampf(0.25 + (absf(_flight.turn_input) * 0.55) + (_flight.boost_factor * 0.45), 0.0, 0.9)

	_left_points.push_front(_left_tip.global_position)
	_right_points.push_front(_right_tip.global_position)

	if _left_points.size() > trail_max_points:
		_left_points.pop_back()
	if _right_points.size() > trail_max_points:
		_right_points.pop_back()

	_rebuild_ribbon(_left_mesh, _left_points, active_alpha)
	_rebuild_ribbon(_right_mesh, _right_points, active_alpha)


func _rebuild_ribbon(im_mesh: ImmediateMesh, points: Array[Vector3], max_alpha: float) -> void:
	im_mesh.clear_surfaces()
	if points.size() < 2:
		return

	var wing_right := _mesh_pivot.global_transform.basis.x
	im_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	for i in range(points.size()):
		var t := float(i) / float(points.size() - 1) # 0.0 at wingtip -> 1.0 at tail
		var half_w := trail_width * (1.0 - t)         # tapering width

		var col := trail_color
		col.a = max_alpha * (1.0 - t) * (1.0 - t)     # smooth quadratic alpha fade

		im_mesh.surface_set_color(col)
		im_mesh.surface_add_vertex(points[i] - wing_right * half_w)

		im_mesh.surface_set_color(col)
		im_mesh.surface_add_vertex(points[i] + wing_right * half_w)

	im_mesh.surface_end()
