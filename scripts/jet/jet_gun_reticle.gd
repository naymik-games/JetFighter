class_name JetGunReticle
extends CanvasLayer
## Gun reticle: a small ring drawn where the rounds will actually go (in chase view that is
## not the screen centre), a heat arc around it, and corner brackets on the aim-assist target.
## Separate from the targeting HUD so that file stays untouched.

@export var aim_distance: float = 150.0
@export var radius: float = 15.0
@export var line_width: float = 2.0
@export var ready_color: Color = Color(0.25, 1.0, 0.45, 0.85)
@export var assist_color: Color = Color(1.0, 0.78, 0.15, 0.95)
@export var hot_color: Color = Color(1.0, 0.2, 0.2, 0.95)

var _gun: JetGun
var _jet: Jet
var _canvas := Control.new()
var _distance: float = 150.0
var _denied: float = 0.0


func _ready() -> void:
	layer = 1
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_reticle)
	add_child(_canvas)
	_distance = aim_distance


func setup(gun: JetGun) -> void:
	_gun = gun
	_jet = gun.get_parent() as Jet
	if not gun.fire_denied.is_connected(_on_fire_denied):
		gun.fire_denied.connect(_on_fire_denied)


func _on_fire_denied(_reason: StringName) -> void:
	_denied = 1.0


func _process(delta: float) -> void:
	_denied = maxf(_denied - delta * 3.0, 0.0)
	if _gun != null:
		# Rounds fly at the target when assisted, so the ring sits at the target's depth.
		var goal := aim_distance
		if _gun.is_assisting():
			goal = _gun.get_muzzle_position().distance_to(_gun.assist_target.get_aim_position())
		_distance = lerpf(_distance, goal, 1.0 - exp(-12.0 * delta))
	_canvas.queue_redraw()


func _heat_color(h: float) -> Color:
	var amber := Color(1.0, 0.78, 0.15, 0.95)
	if h < 0.5:
		return ready_color.lerp(amber, h * 2.0)
	return amber.lerp(hot_color, (h - 0.5) * 2.0)


func _draw_reticle() -> void:
	if _gun == null:
		return
	if is_instance_valid(_jet) and _jet.is_dead:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var world := _gun.get_muzzle_position() + _gun.aim_direction * _distance
	if cam.is_position_behind(world):
		return
	var p := cam.unproject_position(world)

	var assisting := _gun.is_assisting()
	var col := ready_color
	if _gun.is_overheated:
		col = hot_color
	elif assisting:
		col = assist_color

	var r := radius * (1.18 if _gun.is_bursting else 1.0)
	_canvas.draw_arc(p, r, 0.0, TAU, 28, col, line_width)
	_canvas.draw_circle(p, 2.0, col)

	# Heat arc, filling clockwise from the top.
	if _gun.heat > 0.01:
		var hr := r + 6.0
		var track := Color(col.r, col.g, col.b, 0.18)
		_canvas.draw_arc(p, hr, 0.0, TAU, 40, track, 3.0)
		var sweep := TAU * _gun.heat
		_canvas.draw_arc(p, hr, -PI * 0.5, -PI * 0.5 + sweep,
			maxi(int(40.0 * _gun.heat), 2), _heat_color(_gun.heat), 3.0)

	# Flash when a press was refused (overheated / cooling down).
	if _denied > 0.0:
		_canvas.draw_arc(p, r + 13.0, 0.0, TAU, 32, Color(1.0, 0.3, 0.3, _denied), 2.5)

	# Brackets on the assist target.
	if assisting:
		var tw := _gun.assist_target.get_aim_position()
		if not cam.is_position_behind(tw):
			_draw_brackets(cam.unproject_position(tw), 30.0, 10.0, assist_color)


func _draw_brackets(c: Vector2, half: float, arm: float, col: Color) -> void:
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := c + Vector2(half * sx, half * sy)
			_canvas.draw_line(corner, corner - Vector2(arm * sx, 0.0), col, 2.0)
			_canvas.draw_line(corner, corner - Vector2(0.0, arm * sy), col, 2.0)
