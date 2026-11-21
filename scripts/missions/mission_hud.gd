class_name MissionHud
extends CanvasLayer
## Mission overlay, kept separate from TargetingHud (which stays about lock-on, gauges and score).
## Draws:
##   - a pointer to the active objective: a marker over it when it is on screen, an edge arrow
##     with the distance when it is off screen or behind you
##   - an objective panel (top right): objective number, name, timer, missiles left
##   - banners: new objective, objective destroyed (briefing and results are MissionScreens)
## It only reads MissionManager, the jet and the spawner. It never changes game state.
## Created and wired by MissionRunner.

@export var edge_margin: float = 56.0
@export var panel_margin: float = 28.0
## World units are shown as metres times this. 1.0 = raw world units.
@export var distance_display_scale: float = 1.0
## Below this many seconds left the timer turns red and pulses.
@export var timer_warning_seconds: float = 10.0

const PANEL_WIDTH := 270.0
const ACCENT := Color(0.35, 0.9, 1.0, 0.95)
const GREEN := Color(0.25, 1.0, 0.45, 0.85)
const GREEN_DIM := Color(0.25, 1.0, 0.45, 0.30)
const AMBER := Color(1.0, 0.82, 0.2, 0.95)
const RED := Color(1.0, 0.2, 0.2, 0.95)
const SHADOW := Color(0.0, 0.0, 0.0, 0.6)

var _manager: MissionManager
var _spawner: ObjectiveSpawner
var _jet: Jet
var _drawer: Control

var _banner_text := ""
var _banner_sub := ""
var _banner_color := ACCENT
var _banner_left := 0.0
var _banner_persistent := false
var _pending_sub := ""
var _dry_flash := 0.0


func _ready() -> void:
	layer = 2
	_drawer = Control.new()
	_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.draw.connect(_on_draw)
	add_child(_drawer)


func setup(manager: MissionManager, spawner: ObjectiveSpawner) -> void:
	_manager = manager
	_spawner = spawner
	_jet = get_tree().get_first_node_in_group(GameConst.GROUP_PLAYER) as Jet

	_manager.mission_started.connect(_on_mission_started)
	_manager.objective_revealed.connect(_on_objective_revealed)
	_manager.objective_completed.connect(_on_objective_completed)
	_manager.network_disabled.connect(_on_network_disabled)
	_manager.mission_succeeded.connect(_on_mission_ended)
	_manager.mission_failed.connect(_on_mission_ended)
	if is_instance_valid(_jet):
		_jet.weapons.dry_fire.connect(func() -> void: _dry_flash = 0.5)


func _process(delta: float) -> void:
	if _banner_left > 0.0 and not _banner_persistent:
		_banner_left -= delta
	_dry_flash = maxf(_dry_flash - delta, 0.0)
	if _drawer != null:
		_drawer.queue_redraw()


# --- Banners ----------------------------------------------------------------

func show_banner(text: String, sub: String, color: Color, seconds: float) -> void:
	_banner_text = text
	_banner_sub = sub
	_banner_color = color
	_banner_persistent = seconds <= 0.0
	_banner_left = maxf(seconds, 1.0)


func _on_mission_started(_mission: MissionConfig) -> void:
	_pending_sub = ""
	_banner_left = 0.0
	_banner_persistent = false


func _on_objective_revealed(_index: int, placement: ObjectivePlacement) -> void:
	var sub := placement.objective.reveal_text
	if sub == "":
		sub = "Destroy the %s." % placement.objective.get_display_name().to_lower()
	show_banner("NEW OBJECTIVE", sub, ACCENT, 3.5)


func _on_objective_completed(_index: int, _placement: ObjectivePlacement, _time_left: float) -> void:
	show_banner("OBJECTIVE DESTROYED", _pending_sub, GREEN, 2.0)
	_pending_sub = ""


func _on_network_disabled(_network_id: StringName) -> void:
	# Arrives just before objective_completed, which shows it as the banner's second line.
	_pending_sub = "SAM network offline"


## Briefing, success and failure are full screens now (MissionScreens), so no banners for them.
func _on_mission_ended(_reason = null) -> void:
	_banner_left = 0.0
	_banner_persistent = false


# --- Drawing ----------------------------------------------------------------

func _on_draw() -> void:
	if _manager == null:
		return
	var font := ThemeDB.fallback_font
	var viewport_size := get_viewport().get_visible_rect().size

	if _manager.state == MissionManager.State.ACTIVE:
		_draw_pointer(font, viewport_size)
	if _manager.is_running():
		_draw_panel(font, viewport_size)
	_draw_banner(font, viewport_size)


func _draw_pointer(font: Font, viewport_size: Vector2) -> void:
	var placement := _manager.current_placement()
	var cam := get_viewport().get_camera_3d()
	if placement == null or not is_instance_valid(cam):
		return

	# Aim at the real target when it exists (its aim point), otherwise a point above the site.
	var world := placement.position + Vector3.UP * 8.0
	var live: ObjectiveTarget = null
	if _spawner != null:
		live = _spawner.current_instance()
	if live != null:
		world = live.global_position + live.aim_offset

	var info := _project(cam, world, viewport_size)
	var pos: Vector2 = info["pos"]
	var angle: float = info["angle"]

	var label := placement.objective.get_display_name().to_upper()
	if is_instance_valid(_jet):
		label += "  %d m" % int(_jet.global_position.distance_to(world) * distance_display_scale)

	if info["on_screen"]:
		# Diamond with a small pointer above the target, so it never covers the lock reticle.
		var marker := pos + Vector2(0.0, -48.0)
		_draw_diamond(marker, 11.0, ACCENT)
		_draw_polygon_with_shadow(PackedVector2Array([marker + Vector2(-7, 18), marker + Vector2(7, 18), marker + Vector2(0, 28)]), ACCENT)
		_draw_text_centered(font, marker + Vector2(0.0, -20.0), label, 15, ACCENT, viewport_size)
	else:
		var tip := pos + Vector2.RIGHT.rotated(angle) * 16.0
		var wing_l := pos + Vector2.RIGHT.rotated(angle + 2.5) * 15.0
		var wing_r := pos + Vector2.RIGHT.rotated(angle - 2.5) * 15.0
		_draw_polygon_with_shadow(PackedVector2Array([tip, wing_l, wing_r]), ACCENT)
		var label_pos := pos - Vector2.RIGHT.rotated(angle) * 40.0
		_draw_text_centered(font, label_pos, label, 15, ACCENT, viewport_size)


func _draw_panel(font: Font, viewport_size: Vector2) -> void:
	var x := viewport_size.x - panel_margin - PANEL_WIDTH
	var y := 42.0
	var active := _manager.state == MissionManager.State.ACTIVE
	var placement := _manager.current_placement()

	# Header and name.
	var header := "OBJECTIVE %d / %d" % [_manager.current_index() + 1, _manager.objective_total()]
	if not active:
		header = "OBJECTIVE %d / %d COMPLETE" % [_manager.objectives_completed(), _manager.objective_total()]
	_draw_text_right(font, x, y, header, 16, GREEN)
	if placement != null:
		_draw_text_right(font, x, y + 26.0, placement.objective.get_display_name().to_upper(), 22, ACCENT)

	# Timer.
	var ty := y + 62.0
	if active and _manager.is_timed():
		var left := _manager.time_left()
		var ratio := clampf(left / maxf(_manager.time_limit(), 0.001), 0.0, 1.0)
		var col := GREEN
		if ratio <= 0.5:
			col = AMBER
		if left <= timer_warning_seconds:
			var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.014)
			col = Color(RED.r, RED.g, RED.b, lerpf(0.45, 1.0, pulse))
		_draw_text_right(font, x, ty, "TIME  " + _format_time(left), 22, col)
		_draw_bar(x + PANEL_WIDTH - 170.0, ty + 8.0, 170.0, ratio, col)
	elif active:
		_draw_text_right(font, x, ty, "NO TIME LIMIT", 16, GREEN_DIM)

	# Missiles.
	if is_instance_valid(_jet) and _jet.weapons.is_limited():
		var weapons := _jet.weapons
		var my := ty + 52.0
		var mratio := float(weapons.missiles_remaining) / maxf(float(weapons.missiles_max), 1.0)
		var mcol := GREEN
		if mratio <= 0.25:
			mcol = AMBER
		if weapons.missiles_remaining == 0 or _dry_flash > 0.0:
			mcol = RED
		_draw_text_right(font, x, my, "MISSILES  %d / %d" % [weapons.missiles_remaining, weapons.missiles_max], 18, mcol)
		_draw_bar(x + PANEL_WIDTH - 170.0, my + 8.0, 170.0, mratio, mcol)


func _draw_banner(font: Font, viewport_size: Vector2) -> void:
	if _banner_text == "" or (_banner_left <= 0.0 and not _banner_persistent):
		return
	var alpha := 1.0
	if not _banner_persistent:
		alpha = clampf(_banner_left / 0.6, 0.0, 1.0)

	var center := Vector2(viewport_size.x * 0.5, viewport_size.y * 0.24)
	var main_col := Color(_banner_color.r, _banner_color.g, _banner_color.b, _banner_color.a * alpha)
	var width := maxf(font.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x, font.get_string_size(_banner_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x) + 48.0
	var height := 60.0 if _banner_sub != "" else 42.0
	var rect := Rect2(center - Vector2(width * 0.5, 26.0), Vector2(width, height))
	_drawer.draw_rect(rect, Color(0.0, 0.0, 0.0, 0.45 * alpha), true)
	_drawer.draw_rect(rect, main_col, false, 2.0)
	_draw_text_centered(font, center + Vector2(0.0, 6.0), _banner_text, 30, main_col, viewport_size)
	if _banner_sub != "":
		_draw_text_centered(font, center + Vector2(0.0, 32.0), _banner_sub, 18, Color(1.0, 1.0, 1.0, 0.9 * alpha), viewport_size)


# --- Helpers ----------------------------------------------------------------

## Screen position for a world point: the point itself when it is on screen, otherwise the
## spot on the screen edge in its direction (mirrored when it is behind the camera).
func _project(cam: Camera3D, world: Vector3, viewport_size: Vector2) -> Dictionary:
	var center := viewport_size * 0.5
	var bounds := Rect2(Vector2(edge_margin, edge_margin), viewport_size - Vector2(edge_margin, edge_margin) * 2.0)
	var behind := cam.is_position_behind(world)
	var screen := cam.unproject_position(world)
	if behind:
		screen = center - (screen - center)

	var dir := screen - center
	if dir.length_squared() < 0.001:
		dir = Vector2.DOWN
	dir = dir.normalized()

	if not behind and bounds.has_point(screen):
		return {"pos": screen, "on_screen": true, "angle": dir.angle()}

	var tx := INF
	var ty := INF
	if absf(dir.x) > 0.0001:
		tx = absf(((bounds.end.x if dir.x > 0.0 else bounds.position.x) - center.x) / dir.x)
	if absf(dir.y) > 0.0001:
		ty = absf(((bounds.end.y if dir.y > 0.0 else bounds.position.y) - center.y) / dir.y)
	return {"pos": center + dir * minf(tx, ty), "on_screen": false, "angle": dir.angle()}


func _format_time(seconds: float) -> String:
	if seconds < 10.0:
		return "%.1f" % maxf(seconds, 0.0)
	var whole := int(ceil(seconds))
	return "%d:%02d" % [int(whole / 60.0), whole % 60]


func _draw_bar(x: float, y: float, width: float, ratio: float, col: Color) -> void:
	_drawer.draw_rect(Rect2(x, y, width, 4.0), Color(col.r, col.g, col.b, 0.22), true)
	_drawer.draw_rect(Rect2(x, y, width * clampf(ratio, 0.0, 1.0), 4.0), col, true)


func _draw_diamond(center: Vector2, radius: float, col: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius, 0),
		center + Vector2(0, radius), center + Vector2(-radius, 0), center + Vector2(0, -radius)])
	_drawer.draw_polyline(points, SHADOW, 4.5)
	_drawer.draw_polyline(points, col, 2.5)


func _draw_polygon_with_shadow(points: PackedVector2Array, col: Color) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	_drawer.draw_polyline(closed, SHADOW, 4.5)
	_drawer.draw_colored_polygon(points, col)


func _draw_text_right(font: Font, x: float, baseline_y: float, text: String, size: int, col: Color) -> void:
	_drawer.draw_string(font, Vector2(x + 1.0, baseline_y + 1.0), text, HORIZONTAL_ALIGNMENT_RIGHT, PANEL_WIDTH, size, SHADOW)
	_drawer.draw_string(font, Vector2(x, baseline_y), text, HORIZONTAL_ALIGNMENT_RIGHT, PANEL_WIDTH, size, col)


## Draws text centred on a point, nudged to stay fully inside the screen.
func _draw_text_centered(font: Font, center: Vector2, text: String, size: int, col: Color, viewport_size: Vector2) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := clampf(center.x - width * 0.5, 8.0, maxf(viewport_size.x - width - 8.0, 8.0))
	var y := clampf(center.y, float(size) + 4.0, viewport_size.y - 8.0)
	_drawer.draw_string(font, Vector2(x + 1.0, y + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, SHADOW)
	_drawer.draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
