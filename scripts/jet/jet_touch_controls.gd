class_name JetTouchControls
extends CanvasLayer
## On-screen buttons. Left: FIRE (missiles) with a smaller GUN button above it. Right: BOOST
## and BRAKE stacked, plus a camera toggle top-right. This layer only draws and does
## hit-testing; JetInput owns the actual multi-touch bookkeeping. It is separate from the
## targeting HUD, so the HUD's look is untouched.
##
## The GUN button shows the gun's heat as a ring around it and turns red (HOT) when the gun
## is overheated. That needs the gun passed to setup(); without it the button still works.

enum ShowMode { AUTO, ALWAYS, NEVER }

const GREEN := Color(0.25, 1.0, 0.45)
const AMBER := Color(1.0, 0.78, 0.15)
const RED := Color(1.0, 0.2, 0.2)

## ALWAYS is handy while testing with a mouse. Switch to AUTO for release builds.
@export var show_mode: ShowMode = ShowMode.ALWAYS
@export var edge_margin: float = 44.0
@export var hit_padding: float = 14.0
@export var button_scale: float = 1.0
@export var idle_color: Color = Color(0.25, 1.0, 0.45, 0.35)
@export var pressed_color: Color = Color(0.25, 1.0, 0.45, 0.9)

var _controls: JetInput
var _gun: JetGun
var _canvas := Control.new()
var _buttons: Array[Dictionary] = [] # { id, label, center, radius }
var _ui_scale: float = 1.0

var _last_heat: float = -1.0
var _last_bursting: bool = false


func _ready() -> void:
	layer = 2
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_buttons)
	add_child(_canvas)
	get_viewport().size_changed.connect(_layout)
	visible = _should_show()
	_layout()


func setup(controls: JetInput, gun: JetGun = null) -> void:
	_controls = controls
	_gun = gun
	_controls.buttons_changed.connect(_canvas.queue_redraw)


func _process(_delta: float) -> void:
	# The ring follows the gun's heat, which changes without any button event.
	if _gun == null or not visible:
		return
	if absf(_gun.heat - _last_heat) > 0.003 or _gun.is_bursting != _last_bursting or _gun.is_overheated:
		_last_heat = _gun.heat
		_last_bursting = _gun.is_bursting
		_canvas.queue_redraw()


## Returns the id of the button under `pos` (screen coordinates), or &"" if none.
func button_at(pos: Vector2) -> StringName:
	if not visible:
		return &""
	var best: StringName = &""
	var best_gap := INF
	for b in _buttons:
		var gap: float = pos.distance_to(b["center"]) - float(b["radius"])
		if gap <= hit_padding and gap < best_gap:
			best = b["id"]
			best_gap = gap
	return best


func _should_show() -> bool:
	match show_mode:
		ShowMode.ALWAYS:
			return true
		ShowMode.NEVER:
			return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


func _add_button(id: StringName, label: String, center: Vector2, radius: float) -> void:
	_buttons.append({"id": id, "label": label, "center": center, "radius": radius})


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var u := clampf(vp.y / 720.0, 0.7, 1.6) * button_scale
	_ui_scale = u
	var m := edge_margin * u
	var gap := 16.0 * u

	var fire_r := 64.0 * u
	var gun_r := 40.0 * u
	var small_r := 44.0 * u
	var view_r := 30.0 * u

	# Left: FIRE (missiles) in the corner, GUN stacked above it.
	var fire_c := Vector2(m + fire_r, vp.y - m - fire_r)
	var gun_c := Vector2(fire_c.x, fire_c.y - fire_r - gun_r - gap)

	# Right: BOOST in the corner, BRAKE stacked above it.
	var boost_c := Vector2(vp.x - m - small_r, vp.y - m - small_r)
	var brake_c := Vector2(boost_c.x, boost_c.y - small_r * 2.0 - gap)

	var view_c := Vector2(vp.x - m - view_r, m + view_r)

	_buttons.clear()
	_add_button(JetInput.BTN_FIRE, "FIRE", fire_c, fire_r)
	_add_button(JetInput.BTN_GUN, "GUN", gun_c, gun_r)
	_add_button(JetInput.BTN_BOOST, "BOOST", boost_c, small_r)
	_add_button(JetInput.BTN_BRAKE, "BRAKE", brake_c, small_r)
	_add_button(JetInput.BTN_VIEW, "CAM", view_c, view_r)
	_canvas.queue_redraw()


func _heat_color(h: float) -> Color:
	if h < 0.5:
		return GREEN.lerp(AMBER, h * 2.0)
	return AMBER.lerp(RED, (h - 0.5) * 2.0)


func _draw_buttons() -> void:
	var font := ThemeDB.fallback_font
	for b in _buttons:
		var id: StringName = b["id"]
		var is_gun := id == JetInput.BTN_GUN and _gun != null
		var held := _controls != null and _controls.is_button_held(id)
		# A tap starts a timed burst, so keep the button lit for as long as it lasts.
		if is_gun and _gun.is_bursting:
			held = true
		var hot := is_gun and _gun.is_overheated

		var col := pressed_color if held else idle_color
		if hot:
			col = Color(RED.r, RED.g, RED.b, col.a)
		var c: Vector2 = b["center"]
		var r: float = b["radius"]

		_canvas.draw_circle(c, r, Color(col.r, col.g, col.b, 0.28 if held else 0.08))
		_canvas.draw_arc(c, r, 0.0, TAU, 40, col, 2.5)

		if is_gun and (_gun.heat > 0.01 or hot):
			_draw_heat_ring(c, r + 7.0 * _ui_scale, hot)

		var label: String = "HOT" if hot else b["label"]
		var fs := int(maxf(r * 0.32, 13.0))
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_canvas.draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_heat_ring(c: Vector2, radius: float, hot: bool) -> void:
	var width := 4.0 * _ui_scale
	_canvas.draw_arc(c, radius, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.12), width)
	if hot:
		# Full red ring, pulsing, until the gun has cooled enough to resume.
		var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
		_canvas.draw_arc(c, radius, 0.0, TAU, 48, Color(RED.r, RED.g, RED.b, pulse), width)
		return
	var sweep := TAU * _gun.heat
	_canvas.draw_arc(c, radius, -PI * 0.5, -PI * 0.5 + sweep,
		maxi(int(48.0 * _gun.heat), 2), _heat_color(_gun.heat), width)
