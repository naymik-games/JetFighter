class_name DebugOverlay
extends CanvasLayer
## On-screen stats for performance baselines and chunk streaming.
## Toggle with F3 on desktop, or tap the top-right corner on a phone.

@export var visible_on_start: bool = true
@export var refresh_interval: float = 0.25
## Peak values (frame time, chunk build/finalize) reset every this many seconds.
@export var peak_window: float = 5.0
@export var toggle_zone_size: float = 90.0

var _label: Label
var _terrain: Node
var _shown: bool = true
var _refresh_timer: float = 0.0
var _peak_timer: float = 0.0
var _peak_frame_ms: float = 0.0


func _ready() -> void:
	layer = 100
	_shown = visible_on_start

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	# Anchor to the bottom-left corner and grow upward as lines are added
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_left = 12.0
	_label.offset_bottom = -12.0
	_label.visible = _shown


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_toggle()
	elif event is InputEventScreenTouch and event.pressed:
		var vp_size := get_viewport().get_visible_rect().size
		if event.position.x > vp_size.x - toggle_zone_size and event.position.y < toggle_zone_size:
			_toggle()


func _toggle() -> void:
	_shown = not _shown
	_label.visible = _shown


func _process(delta: float) -> void:
	if not _shown:
		return

	_peak_frame_ms = maxf(_peak_frame_ms, delta * 1000.0)
	_peak_timer += delta
	_refresh_timer += delta
	if _refresh_timer < refresh_interval:
		return
	_refresh_timer = 0.0

	_label.text = _build_text(delta)

	if _peak_timer >= peak_window:
		_peak_timer = 0.0
		_peak_frame_ms = 0.0
		if is_instance_valid(_terrain):
			_terrain.call("reset_peak_stats")


func _build_text(delta: float) -> String:
	if not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group(GameConst.GROUP_TERRAIN)

	var lines: PackedStringArray = []
	lines.append("FPS %d   frame %.1f ms   peak %.1f ms" % [
		Engine.get_frames_per_second(), delta * 1000.0, _peak_frame_ms
	])
	lines.append("Draw calls %d   Primitives %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	])

	if is_instance_valid(_terrain) and _terrain.has_method("get_stats"):
		var s: Dictionary = _terrain.call("get_stats")
		lines.append("Chunks %d active   %d pending   %d needed" % [s["active"], s["pending"], s["needed"]])
		lines.append("Build %.1f ms (peak %.1f)   Finalize %.1f ms (peak %.1f)" % [
			s["last_build_ms"], s["peak_build_ms"], s["last_finalize_ms"], s["peak_finalize_ms"]
		])
		lines.append("Seed %d" % s["seed"])
		var sp: Dictionary = s["spawn"]
		lines.append("Spawns %d queued   %d/%d live   %d destroyed" % [sp["queued"], sp["live"], sp["cap"], sp["destroyed"]])
	else:
		lines.append("Terrain: not found")

	lines.append("Targets %d   Enemy missiles %d" % [
		get_tree().get_nodes_in_group(GameConst.GROUP_TARGETS).size(),
		get_tree().get_nodes_in_group(GameConst.GROUP_ENEMY_MISSILES).size()
	])
	return "\n".join(lines)
