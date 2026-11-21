class_name ObjectiveModels
extends RefCounted
## Placeholder models for the four objective kinds, built from primitive meshes in code.
## Each model sits with its origin on the ground (y = 0 is the surface) and fits inside the
## default 14-unit placement footprint. To use your own model later, assign a scene to
## ObjectiveConfig.target_scene (see ObjectiveTarget); these are only used when it is empty.

const PAD := Color(0.34, 0.34, 0.32)
const CONCRETE := Color(0.62, 0.62, 0.60)
const DARK_GREY := Color(0.30, 0.32, 0.35)
const OLIVE := Color(0.32, 0.38, 0.26)
const TANK_ORANGE := Color(0.86, 0.45, 0.18)
const TANK_CAP := Color(0.55, 0.28, 0.12)
const RED := Color(0.80, 0.14, 0.12)
const WHITE := Color(0.92, 0.92, 0.90)
const DISH := Color(0.80, 0.82, 0.85)

## Top of the foundation pad above the ground point. Everything stands on it.
const PAD_TOP := 0.5

static var _materials: Dictionary = {}


## Returns { root: Node3D, hit_size: Vector3, aim_height: float, spinner: Node3D (or null) }.
## hit_size is the box missiles collide with (centred over the ground point);
## aim_height is where lock-on aims, above the ground point.
static func build(kind: ObjectiveConfig.Kind) -> Dictionary:
	match kind:
		ObjectiveConfig.Kind.RADIO_TOWER:
			return _radio_tower()
		ObjectiveConfig.Kind.RADAR_STATION:
			return _radar_station()
		ObjectiveConfig.Kind.HEADQUARTERS:
			return _headquarters()
	return _fuel_depot()


static func _fuel_depot() -> Dictionary:
	var root := Node3D.new()
	root.name = "Model"
	_pad(root, 13.0)
	for p in [Vector2(-6.0, -3.0), Vector2(6.0, -3.0), Vector2(0.0, 6.0)]:
		_cylinder(root, 4.2, 4.2, 6.0, Vector3(p.x, PAD_TOP + 3.0, p.y), TANK_ORANGE)
		_cylinder(root, 3.2, 4.4, 0.8, Vector3(p.x, PAD_TOP + 6.4, p.y), TANK_CAP)
	_box(root, Vector3(6.0, 3.0, 4.0), Vector3(0.0, PAD_TOP + 1.5, -9.5), CONCRETE)
	return {"root": root, "hit_size": Vector3(22.0, 8.0, 22.0), "aim_height": 3.5, "spinner": null}


static func _radio_tower() -> Dictionary:
	var root := Node3D.new()
	root.name = "Model"
	_pad(root, 9.0)
	_box(root, Vector3(5.0, 3.0, 4.0), Vector3(5.5, PAD_TOP + 1.5, 3.0), CONCRETE)
	# Mast: five tapering segments in alternating red and white, 40 units tall.
	var segments := 5
	var seg_h := 8.0
	for i in segments:
		var bottom_r := lerpf(1.4, 0.6, float(i) / float(segments))
		var top_r := lerpf(1.4, 0.6, float(i + 1) / float(segments))
		var color := RED if i % 2 == 0 else WHITE
		_cylinder(root, top_r, bottom_r, seg_h, Vector3(0.0, PAD_TOP + seg_h * i + seg_h * 0.5, 0.0), color)
	_box(root, Vector3(7.0, 0.5, 0.5), Vector3(0.0, PAD_TOP + 32.0, 0.0), DARK_GREY)
	_box(root, Vector3(0.5, 0.5, 7.0), Vector3(0.0, PAD_TOP + 26.0, 0.0), DARK_GREY)
	var beacon := _sphere(root, 1.1, Vector3(0.0, PAD_TOP + 41.0, 0.0), RED, true)
	beacon.name = "Beacon"
	return {"root": root, "hit_size": Vector3(8.0, 42.0, 8.0), "aim_height": 20.0, "spinner": null}


static func _radar_station() -> Dictionary:
	var root := Node3D.new()
	root.name = "Model"
	_pad(root, 11.0)
	_box(root, Vector3(12.0, 4.0, 9.0), Vector3(0.0, PAD_TOP + 2.0, 0.0), DARK_GREY)
	_cylinder(root, 1.0, 1.2, 6.0, Vector3(0.0, PAD_TOP + 7.0, 0.0), CONCRETE)

	var spinner := Node3D.new()
	spinner.name = "Spinner"
	spinner.position = Vector3(0.0, PAD_TOP + 10.5, 0.0)
	root.add_child(spinner)

	var tilt := Node3D.new()
	tilt.rotation_degrees = Vector3(-55.0, 0.0, 0.0)
	spinner.add_child(tilt)

	# Dish: a flattened sphere, tilted up and forward, with a feed arm sticking out of it.
	var dish := _sphere(tilt, 5.0, Vector3.ZERO, DISH, false)
	dish.scale = Vector3(1.0, 0.3, 1.0)
	_cylinder(tilt, 0.3, 0.3, 5.0, Vector3(0.0, 2.6, 0.0), DARK_GREY)
	return {"root": root, "hit_size": Vector3(14.0, 15.0, 14.0), "aim_height": 7.0, "spinner": spinner}


static func _headquarters() -> Dictionary:
	var root := Node3D.new()
	root.name = "Model"
	_pad(root, 14.0)
	_box(root, Vector3(18.0, 7.0, 12.0), Vector3(0.0, PAD_TOP + 3.5, 0.0), OLIVE)
	_box(root, Vector3(19.5, 1.0, 13.5), Vector3(0.0, PAD_TOP + 7.5, 0.0), CONCRETE)
	_box(root, Vector3(7.0, 4.0, 7.0), Vector3(-10.0, PAD_TOP + 2.0, 6.0), OLIVE)
	_box(root, Vector3(7.0, 4.0, 7.0), Vector3(10.0, PAD_TOP + 2.0, 6.0), OLIVE)
	# Flagpole with a red flag on the roof.
	_cylinder(root, 0.25, 0.25, 12.0, Vector3(-7.0, PAD_TOP + 14.0, 0.0), CONCRETE)
	_box(root, Vector3(3.0, 2.0, 0.2), Vector3(-5.5, PAD_TOP + 18.5, 0.0), RED)
	return {"root": root, "hit_size": Vector3(26.0, 14.0, 22.0), "aim_height": 4.5, "spinner": null}


# --- Primitive helpers ---------------------------------------------------------

## Foundation disc. It reaches below the ground so uneven terrain cannot show gaps under it.
static func _pad(parent: Node3D, radius: float) -> void:
	_cylinder(parent, radius, radius, 4.0, Vector3(0.0, PAD_TOP - 2.0, 0.0), PAD)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(parent, mesh, pos, color, false)


static func _cylinder(parent: Node3D, top_radius: float, bottom_radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	return _add_mesh(parent, mesh, pos, color, false)


static func _sphere(parent: Node3D, radius: float, pos: Vector3, color: Color, glow: bool) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	return _add_mesh(parent, mesh, pos, color, glow)


static func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, glow: bool) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.material_override = _material(color, glow)
	parent.add_child(instance)
	return instance


static func _material(color: Color, glow: bool) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), glow]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if glow:
		material.emission_enabled = true
		material.emission = color
	_materials[key] = material
	return material
