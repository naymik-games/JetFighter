class_name JetInput
extends Node
## Player input. The drag-to-steer feel is unchanged (origin = where you press, vector =
## offset / max_drag_radius, clamped to 1). Multi-touch: every pointer (finger or mouse) gets
## a role when it lands - steer or a button - and keeps it until it lifts. So one thumb can
## hold the drag while another taps FIRE or holds BOOST / BRAKE.

signal fire_pressed
signal view_toggled
signal buttons_changed

const BTN_FIRE := &"fire"
const BTN_BOOST := &"boost"
const BTN_BRAKE := &"brake"
const BTN_VIEW := &"view"
const ACTION_VIEW := &"toggle_camera"

const NO_POINTER := -999
const MOUSE_POINTER := -100

@export_group("Drag Controls")
@export var max_drag_radius: float = 120.0
@export var invert_y: bool = false

## Set by the jet: takes a screen position, returns a button id, or &"" if no button is there.
var button_hit_test: Callable = Callable()

var steer: Vector2 = Vector2.ZERO # was `input_vector`
var dragging: bool = false        # was `is_dragging`

var boost_held: bool:
	get:
		return Input.is_action_pressed(&"boost") or is_button_held(BTN_BOOST)
var brake_held: bool:
	get:
		return Input.is_action_pressed(&"brake") or is_button_held(BTN_BRAKE)

var _steer_pointer: int = NO_POINTER
var _drag_origin: Vector2 = Vector2.ZERO
var _pointer_buttons: Dictionary = {} # pointer id -> button id
var _held_counts: Dictionary = {}     # button id -> number of pointers holding it


func _ready() -> void:
	# Keyboard fallback for the camera toggle, so no Project Settings edit is needed.
	if not InputMap.has_action(ACTION_VIEW):
		InputMap.add_action(ACTION_VIEW)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_C
		InputMap.action_add_event(ACTION_VIEW, key)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_pointer_down(event.index, event.position)
		else:
			_pointer_up(event.index)
	elif event is InputEventScreenDrag:
		_pointer_move(event.index, event.position)
	elif event is InputEventMouseButton:
		# Mouse events emulated from touch are skipped: the ScreenTouch already handled them.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pointer_down(MOUSE_POINTER, event.position)
			else:
				_pointer_up(MOUSE_POINTER)
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_pointer_move(MOUSE_POINTER, event.position)
	elif event.is_action_pressed(&"fire_missile") and not event.is_echo():
		fire_pressed.emit()
	elif event.is_action_pressed(ACTION_VIEW) and not event.is_echo():
		view_toggled.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()


func is_button_held(id: StringName) -> bool:
	return int(_held_counts.get(id, 0)) > 0


## Drops every pointer and held button (focus loss, death, pause...).
func release_all() -> void:
	_steer_pointer = NO_POINTER
	dragging = false
	steer = Vector2.ZERO
	_pointer_buttons.clear()
	_held_counts.clear()
	buttons_changed.emit()


func _pointer_down(id: int, pos: Vector2) -> void:
	if id == _steer_pointer or _pointer_buttons.has(id):
		return

	var btn: StringName = &""
	if button_hit_test.is_valid():
		btn = button_hit_test.call(pos)

	if btn != &"":
		_pointer_buttons[id] = btn
		_press_button(btn)
	elif _steer_pointer == NO_POINTER:
		_steer_pointer = id
		_drag_origin = pos
		dragging = true
	# A second finger that lands outside every button is ignored: one steering pointer only.


func _pointer_move(id: int, pos: Vector2) -> void:
	if id == _steer_pointer:
		steer = ((pos - _drag_origin) / max_drag_radius).limit_length(1.0)


func _pointer_up(id: int) -> void:
	if id == _steer_pointer:
		_steer_pointer = NO_POINTER
		dragging = false
		steer = Vector2.ZERO
	elif _pointer_buttons.has(id):
		var btn: StringName = _pointer_buttons[id]
		_pointer_buttons.erase(id)
		_release_button(btn)


func _press_button(id: StringName) -> void:
	_held_counts[id] = int(_held_counts.get(id, 0)) + 1
	if id == BTN_FIRE:
		fire_pressed.emit()
	elif id == BTN_VIEW:
		view_toggled.emit()
	buttons_changed.emit()


func _release_button(id: StringName) -> void:
	var n := int(_held_counts.get(id, 0)) - 1
	if n <= 0:
		_held_counts.erase(id)
	else:
		_held_counts[id] = n
	buttons_changed.emit()
