class_name JetTouchControls
extends CanvasLayer
## On-screen buttons: FIRE, BOOST, BRAKE and a camera toggle. This layer only draws and does
## hit-testing; JetInput owns the actual multi-touch bookkeeping. It is separate from the
## targeting HUD, so the HUD's look is untouched.

enum ShowMode { AUTO, ALWAYS, NEVER }

## ALWAYS is handy while testing with a mouse. Switch to AUTO for release builds.
@export var show_mode: ShowMode = ShowMode.ALWAYS
@export var edge_margin: float = 44.0
@export var hit_padding: float = 14.0
@export var button_scale: float = 1.0
@export var idle_color: Color = Color(0.25, 1.0, 0.45, 0.35)
@export var pressed_color: Color = Color(0.25, 1.0, 0.45, 0.9)

var _controls: JetInput
var _canvas := Control.new()
var _buttons: Array[Dictionary] = [] # { id, label, center, radius }


func _ready() -> void:
	layer = 2
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_buttons)
	add_child(_canvas)
	get_viewport().size_changed.connect(_layout)
	visible = _should_show()
	_layout()


func setup(controls: JetInput) -> void:
	_controls = controls
	_controls.buttons_changed.connect(_canvas.queue_redraw)


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
	var m := edge_margin * u

	var fire_r := 64.0 * u
	var small_r := 44.0 * u
	var view_r := 30.0 * u

	var fire_c := Vector2(vp.x - m - fire_r, vp.y - m - fire_r)
	var boost_c := Vector2(fire_c.x - fire_r - small_r - 16.0 * u, vp.y - m - small_r)
	var brake_c := Vector2(boost_c.x, boost_c.y - small_r * 2.0 - 16.0 * u)
	var view_c := Vector2(vp.x - m - view_r, m + view_r)

	_buttons.clear()
	_add_button(JetInput.BTN_FIRE, "FIRE", fire_c, fire_r)
	_add_button(JetInput.BTN_BOOST, "BOOST", boost_c, small_r)
	_add_button(JetInput.BTN_BRAKE, "BRAKE", brake_c, small_r)
	_add_button(JetInput.BTN_VIEW, "CAM", view_c, view_r)
	_canvas.queue_redraw()


func _draw_buttons() -> void:
	var font := ThemeDB.fallback_font
	for b in _buttons:
		var held := _controls != null and _controls.is_button_held(b["id"])
		var col := pressed_color if held else idle_color
		var c: Vector2 = b["center"]
		var r: float = b["radius"]

		_canvas.draw_circle(c, r, Color(col.r, col.g, col.b, 0.28 if held else 0.08))
		_canvas.draw_arc(c, r, 0.0, TAU, 40, col, 2.5)

		var label: String = b["label"]
		var fs := int(maxf(r * 0.32, 13.0))
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_canvas.draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
