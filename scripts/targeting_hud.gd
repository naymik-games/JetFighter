extends CanvasLayer

@export var jet: Jet # Assign JetFighter in Inspector
@export_group("Gauges & Limits")
@export var max_display_altitude: float = 140.0
@export var edge_margin: float = 46.0
## Off-screen arrows only show for enemy targets within this distance of the jet.
@export var arrow_range: float = 450.0
@export var missile_warning_range: float = 240.0

# Lock-on Reticle State
var reticle_pos: Vector2 = Vector2.ZERO
var reticle_visible: bool = false
var is_locked: bool = false
var lock_ratio: float = 0.0

# Score & combo live in ScoreSystem; the HUD only reads them and rolls the display counter.
var score_system: ScoreSystem = null
var displayed_score: float = 0.0

# Off-screen Target Arrows: Array of { "pos": Vector2, "angle": float }
var offscreen_arrows: Array[Dictionary] = []

var incoming_threats: Array[Dictionary] = [] # { "pos": Vector2, "angle": float, "dist": float }
var alert_blink_timer: float = 0.0

@onready var drawer := Control.new()

# Resolved lazily from the node in group "terrain" so sea level has one source of truth
var sampler: TerrainSampler = null

func _ready() -> void:
	add_to_group(GameConst.GROUP_HUD)
	drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.draw.connect(_on_draw_hud)
	add_child(drawer)
	
	if not is_instance_valid(jet):
		jet = get_tree().get_first_node_in_group(GameConst.GROUP_PLAYER) as Jet
	
	score_system = get_tree().get_first_node_in_group(GameConst.GROUP_SCORE) as ScoreSystem
	if score_system == null:
		score_system = ScoreSystem.new()
		score_system.name = "ScoreSystem"
		add_child(score_system)

func _get_sea_level() -> float:
	if sampler == null:
		var terrain := get_tree().get_first_node_in_group(GameConst.GROUP_TERRAIN)
		if terrain != null:
			sampler = terrain.get("sampler") as TerrainSampler
	return sampler.sea_level if sampler != null else 0.0

func _process(delta: float) -> void:
	# Smoothly roll the score counter upward
	var score := score_system.score
	displayed_score = move_toward(displayed_score, float(score), maxf(250.0, abs(score - displayed_score) * 6.0) * delta)
			
	if not is_instance_valid(jet):
		drawer.queue_redraw()
		return
		
	var cam := get_viewport().get_camera_3d()
	if not is_instance_valid(cam):
		return
		
	# 1. Update Active Lock-On Reticle
	var raw_target = jet.lock_on.target
	if is_instance_valid(raw_target):
		var target := raw_target as Node3D
		if cam.is_position_behind(target.global_position):
			reticle_visible = false
		else:
			reticle_visible = true
			reticle_pos = cam.unproject_position(target.global_position)
			lock_ratio = jet.lock_on.progress
			is_locked = lock_ratio >= 1.0
	else:
		reticle_visible = false
		
	# 2. Compute Screen-Edge Arrows for Off-Screen Targets
	_update_offscreen_arrows(cam)
	
	alert_blink_timer += delta
	_update_incoming_threats(cam)
	
	drawer.queue_redraw()

func _update_offscreen_arrows(cam: Camera3D) -> void:
	offscreen_arrows.clear()
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	var bounds := Rect2(Vector2(edge_margin, edge_margin), viewport_size - Vector2(edge_margin * 2.0, edge_margin * 2.0))
	
	if not is_instance_valid(jet):
		return
		
	for tgt in TargetRegistry.query(jet.global_position, arrow_range, TargetRegistry.MASK_ENEMY):
		var screen_pos := cam.unproject_position(tgt.global_position)
		var is_behind := cam.is_position_behind(tgt.global_position)
		
		# If behind the camera, mirror the projected coordinates across screen center
		if is_behind:
			screen_pos = center - (screen_pos - center)
			
		# Only show edge arrow when target lies outside the safe viewport box
		if is_behind or not bounds.has_point(screen_pos):
			var dir := (screen_pos - center).normalized()
			if dir.length_squared() < 0.001:
				dir = Vector2.DOWN
				
			# Raycast from screen center to the padded viewport edge rectangle
			var tx: float = ((bounds.end.x if dir.x > 0.0 else bounds.position.x) - center.x) / dir.x if abs(dir.x) > 0.0001 else INF
			var ty: float = ((bounds.end.y if dir.y > 0.0 else bounds.position.y) - center.y) / dir.y if abs(dir.y) > 0.0001 else INF
			var t := minf(abs(tx), abs(ty))
			var clamped_pos := center + dir * t
			
			offscreen_arrows.append({
				"pos": clamped_pos,
				"angle": dir.angle()
			})


func _update_incoming_threats(cam: Camera3D) -> void:
	incoming_threats.clear()
	if not is_instance_valid(jet):
		return
		
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	var bounds := Rect2(Vector2(edge_margin, edge_margin), viewport_size - Vector2(edge_margin * 2.0, edge_margin * 2.0))
	
	for node in get_tree().get_nodes_in_group(GameConst.GROUP_ENEMY_MISSILES):
		if not is_instance_valid(node):
			continue
		var sam := node as Node3D
		var dist := jet.global_position.distance_to(sam.global_position)
		if dist > missile_warning_range:
			continue
			
		var screen_pos := cam.unproject_position(sam.global_position)
		var is_behind := cam.is_position_behind(sam.global_position)
		if is_behind:
			screen_pos = center - (screen_pos - center)
			
		var dir := (screen_pos - center).normalized()
		if dir.length_squared() < 0.001:
			dir = Vector2.DOWN
			
		var indicator_pos := screen_pos
		if is_behind or not bounds.has_point(screen_pos):
			var tx: float = ((bounds.end.x if dir.x > 0.0 else bounds.position.x) - center.x) / dir.x if abs(dir.x) > 0.0001 else INF
			var ty: float = ((bounds.end.y if dir.y > 0.0 else bounds.position.y) - center.y) / dir.y if abs(dir.y) > 0.0001 else INF
			var t := minf(abs(tx), abs(ty))
			indicator_pos = center + dir * t
			
		incoming_threats.append({
			"pos": indicator_pos,
			"angle": dir.angle(),
			"dist": dist
		})




func _on_draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	var hud_green := Color(0.25, 1.0, 0.45, 0.85)
	var hud_dim := Color(0.25, 1.0, 0.45, 0.25)
	
	# --- 1. Boresight Crosshair ---
	drawer.draw_arc(center, 14.0, 0.0, TAU, 24, hud_green, 1.5)
	drawer.draw_line(center - Vector2(22, 0), center - Vector2(8, 0), hud_green, 1.5)
	drawer.draw_line(center + Vector2(8, 0), center + Vector2(22, 0), hud_green, 1.5)
	
	# --- 2. Score & Combo Counter (Top-Left) ---
	var score_text := "SCORE  %07d" % int(round(displayed_score))
	drawer.draw_string(font, Vector2(28, 42), score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, hud_green)
	
	var combo := score_system.combo
	if combo > 1:
		var combo_col := Color(1.0, 0.82, 0.2, 0.95)
		drawer.draw_string(font, Vector2(28, 68), "COMBO  x%d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, combo_col)
		# Shrinking combo timer bar
		var bar_w := 110.0 * clampf(score_system.combo_timer / score_system.combo_duration, 0.0, 1.0)
		drawer.draw_rect(Rect2(28, 76, bar_w, 4), combo_col, true)
	
	# --- 3. Speed & Altitude Gauges ---
	if is_instance_valid(jet):
		var cur_spd: float = jet.flight.speed
		var min_spd: float = jet.flight.brake_speed
		var max_spd: float = jet.flight.boost_speed
		var spd_ratio := clampf((cur_spd - min_spd) / maxf(max_spd - min_spd, 1.0), 0.0, 1.0)
		
		var alt: float = maxf(jet.global_position.y - _get_sea_level(), 0.0)
		var alt_ratio := clampf(alt / max_display_altitude, 0.0, 1.0)
		
		var gauge_h := 190.0
		var gauge_top := center.y - (gauge_h * 0.5)
		
		# Left Gauge: Airspeed (Knots-style readout)
		var spd_x := center.x - 190.0
		_draw_vertical_gauge(font, spd_x, gauge_top, gauge_h, spd_ratio, "SPD", "%03d" % int(cur_spd * 10.0), hud_green, hud_dim, true)
		
		# Right Gauge: Altitude (Feet/Meters readout)
		var alt_x := center.x + 190.0
		_draw_vertical_gauge(font, alt_x, gauge_top, gauge_h, alt_ratio, "ALT", "%04d" % int(alt * 10.0), hud_green, hud_dim, false)
	
	# --- 4. Off-Screen Target Directional Arrows ---
	var arrow_col := Color(1.0, 0.45, 0.15, 0.9)
	for arrow in offscreen_arrows:
		var pos: Vector2 = arrow["pos"]
		var ang: float = arrow["angle"]
		var tip := pos + Vector2.RIGHT.rotated(ang) * 12.0
		var wing_l := pos + Vector2.RIGHT.rotated(ang + 2.45) * 11.0
		var wing_r := pos + Vector2.RIGHT.rotated(ang - 2.45) * 11.0
		drawer.draw_colored_polygon(PackedVector2Array([tip, wing_l, wing_r]), arrow_col)
		
	# --- 5. Active 3D Lock-On Reticle ---
	if reticle_visible:
		var box_half: float = lerp(46.0, 22.0, lock_ratio)
		var lock_col := Color(1.0, 0.2, 0.2, 0.95) if is_locked else Color(1.0, 0.78, 0.15, 0.85)
		var rect := Rect2(reticle_pos - Vector2(box_half, box_half), Vector2(box_half * 2.0, box_half * 2.0))
		drawer.draw_rect(rect, lock_col, false, 2.5)
		
		if is_locked:
			var diamond := PackedVector2Array([
				reticle_pos + Vector2(0, -14),
				reticle_pos + Vector2(14, 0),
				reticle_pos + Vector2(0, 14),
				reticle_pos + Vector2(-14, 0),
				reticle_pos + Vector2(0, -14)
			])
			drawer.draw_polyline(diamond, lock_col, 2.0)
	
	if not incoming_threats.is_empty():
		# Faster blink rate as the closest missile gets nearer
		var closest_dist: float = incoming_threats[0]["dist"]
		for threat in incoming_threats:
			closest_dist = minf(closest_dist, threat["dist"])
			
		var blink_hz := lerpf(16.0, 5.0, clampf(closest_dist / missile_warning_range, 0.0, 1.0))
		var pulse := 0.5 + 0.5 * sin(alert_blink_timer * blink_hz)
		var warn_col := Color(1.0, 0.15, 0.15, lerpf(0.35, 1.0, pulse))
		
		# Top-Center Flashing Banner
		var banner_pos := Vector2(center.x - 115.0, 56.0)
		drawer.draw_rect(Rect2(banner_pos - Vector2(12, 22), Vector2(254, 30)), Color(0.2, 0.0, 0.0, 0.65 * pulse), true)
		drawer.draw_rect(Rect2(banner_pos - Vector2(12, 22), Vector2(254, 30)), warn_col, false, 2.0)
		drawer.draw_string(font, banner_pos, "! MISSILE ALERT !", HORIZONTAL_ALIGNMENT_CENTER, 230, 20, warn_col)
		
		# Threat Diamond & Directional Chevron for each incoming SAM
		for threat in incoming_threats:
			var t_pos: Vector2 = threat["pos"]
			var t_ang: float = threat["angle"]
			
			# Pulsing red warning diamond
			var d_pts := PackedVector2Array([
				t_pos + Vector2(0, -14),
				t_pos + Vector2(14, 0),
				t_pos + Vector2(0, 14),
				t_pos + Vector2(-14, 0),
				t_pos + Vector2(0, -14)
			])
			drawer.draw_polyline(d_pts, warn_col, 2.5)
			
			# Outer chevron pointing toward the missile
			var tip := t_pos + Vector2.RIGHT.rotated(t_ang) * 22.0
			var c_left := t_pos + Vector2.RIGHT.rotated(t_ang + 0.55) * 15.0
			var c_right := t_pos + Vector2.RIGHT.rotated(t_ang - 0.55) * 15.0
			drawer.draw_polyline(PackedVector2Array([c_left, tip, c_right]), warn_col, 2.5)
			
			

func _draw_vertical_gauge(font: Font, x: float, top: float, height: float, ratio: float, label: String, value_str: String, col: Color, bg_col: Color, is_left: bool) -> void:
	var dir := -1.0 if is_left else 1.0
	var fill_h := height * ratio
	var fill_y := top + height - fill_h
	
	# Track & active fill bar
	drawer.draw_rect(Rect2(x - 3.0, top, 6.0, height), bg_col, true)
	drawer.draw_rect(Rect2(x - 3.0, fill_y, 6.0, fill_h), col, true)
	
	# Tick marks
	for i in range(5):
		var ty := top + (height * (float(i) / 4.0))
		drawer.draw_line(Vector2(x, ty), Vector2(x + (10.0 * dir), ty), col, 1.5)
		
	# Pointer caret & numeric readout
	var caret_x := x + (14.0 * dir)
	var text_offset := -58.0 if is_left else 16.0
	drawer.draw_string(font, Vector2(x - 16.0, top - 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	drawer.draw_string(font, Vector2(caret_x + text_offset, fill_y + 5.0), value_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
