class_name MissionScreens
extends CanvasLayer
## Full-screen mission panels: the briefing (with a Start button) and the success / failure
## results (with a Retry button). They hold until the player taps; nothing reloads by itself.
## Success shows the score breakdown (MissionScore) and saves progress; failure shows no score.
## Buttons: the main one (Start / Retry / Play again), NEXT MISSION after a win, and MENU.
##
## While a panel is up the whole scene tree is paused, so the jet, turrets, missiles and the
## mission timer all freeze. This node (and its buttons) keeps running because it is set to
## PROCESS_MODE_ALWAYS. MissionRunner un-pauses when the player taps Start.
##
## Built entirely in code so no scene editing is needed. Menu navigation comes in Step 9.

## Seconds between the jet being destroyed and the failure panel appearing (lets the
## explosion play before everything freezes).
@export var delay_jet_destroyed: float = 1.6
## Same, for every other way the mission ends.
@export var delay_other: float = 0.6

const ACCENT := Color(0.35, 0.9, 1.0, 1.0)
const GOOD := Color(0.35, 1.0, 0.5, 1.0)
const BAD := Color(1.0, 0.3, 0.25, 1.0)
const TEXT := Color(0.92, 0.95, 0.95, 1.0)
const TEXT_DIM := Color(0.65, 0.72, 0.74, 1.0)

enum Mode { NONE, BRIEFING, SUCCESS, FAILURE }

var _manager: MissionManager
var _jet: Jet
var _score_system: ScoreSystem
var _mode: Mode = Mode.NONE

var _backdrop: ColorRect
var _panel: PanelContainer
var _title: Label
var _body: Label
var _stats: Label
var _score_grid: GridContainer
var _button: Button
var _next_button: Button
var _menu_button: Button
var _next_mission: MissionConfig = null


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_backdrop.visible = false


func setup(manager: MissionManager, jet: Jet) -> void:
	_manager = manager
	_jet = jet
	_score_system = get_tree().get_first_node_in_group(GameConst.GROUP_SCORE) as ScoreSystem
	_manager.mission_succeeded.connect(_on_succeeded)
	_manager.mission_failed.connect(_on_failed)


## Pauses the game and shows the briefing for the mission that is waiting in BRIEFING.
func show_briefing() -> void:
	var mission := _manager.mission
	if mission == null:
		return
	_mode = Mode.BRIEFING
	_title.text = mission.display_name.to_upper()
	_title.add_theme_color_override("font_color", ACCENT)
	_body.text = mission.briefing if mission.briefing != "" else "Destroy every objective."
	var lines := PackedStringArray()
	lines.append("Objectives:  %d" % mission.objectives.size())
	if mission.starting_missiles > 0:
		lines.append("Missiles:  %d" % mission.starting_missiles)
	_stats.text = "\n".join(lines)
	_button.text = "START"
	_score_grid.visible = false
	_next_button.visible = false
	_menu_button.visible = _menu_available()
	_open()


# --- Results ------------------------------------------------------------------

func _on_succeeded() -> void:
	await get_tree().create_timer(delay_other).timeout
	if _manager.state == MissionManager.State.SUCCEEDED:
		_show_result(true)


func _on_failed(reason: MissionManager.FailReason) -> void:
	var delay := delay_jet_destroyed if reason == MissionManager.FailReason.JET_DESTROYED else delay_other
	await get_tree().create_timer(delay).timeout
	if _manager.state == MissionManager.State.FAILED:
		_show_result(false)


func _show_result(success: bool) -> void:
	_mode = Mode.SUCCESS if success else Mode.FAILURE
	_title.text = "MISSION COMPLETE" if success else "MISSION FAILED"
	_title.add_theme_color_override("font_color", GOOD if success else BAD)
	_body.text = "All objectives destroyed." if success else _reason_text(_manager.fail_reason)

	var lines := PackedStringArray()
	if success:
		# Score is only awarded for a completed mission.
		var mission := _manager.mission
		var score := MissionScore.compute(mission, _manager, _jet, _score_system)
		MissionSession.last_score = score.total
		_fill_score_grid(score)
		lines.append("Mission time:  %s" % _format_time(_manager.elapsed()))

		# Progress: remember what was locked before this win, then save.
		_next_mission = MissionLibrary.next_after(mission)
		var next_was_locked := _next_mission != null and not MissionLibrary.is_unlocked(_next_mission)
		var previous_best := SaveData.best_score(mission.id)
		var is_new_best := SaveData.record_success(mission.id, score.total)
		if is_new_best:
			lines.append("NEW BEST!" if previous_best == 0 else "NEW BEST!  (previous %s)" % MissionScore.format_points(previous_best))
		else:
			lines.append("Best:  %s" % MissionScore.format_points(previous_best))
		if next_was_locked:
			lines.append("Next mission unlocked:  %s" % _next_mission.display_name)
	else:
		lines.append("Objectives destroyed:  %d / %d" % [_manager.objectives_completed(), _manager.objective_total()])
		lines.append("Mission time:  %s" % _format_time(_manager.elapsed()))
		if is_instance_valid(_jet) and _jet.weapons.is_limited():
			lines.append("Missiles left:  %d / %d" % [_jet.weapons.missiles_remaining, _jet.weapons.missiles_max])
	if not success:
		_next_mission = null
	_score_grid.visible = success
	_stats.text = "\n".join(lines)
	_button.text = "PLAY AGAIN" if success else "RETRY"
	_next_button.visible = _next_mission != null
	_menu_button.visible = _menu_available()
	_open()


## Rebuilds the score table: label | detail | points, then a bold total.
func _fill_score_grid(score: MissionScore) -> void:
	for child in _score_grid.get_children():
		_score_grid.remove_child(child)
		child.queue_free()
	for row in score.rows():
		_add_cell(row["label"], 20, TEXT, false)
		_add_cell(row["detail"], 16, TEXT_DIM, false)
		_add_cell(_format_points(row["value"]), 20, TEXT, true)
	_add_cell("TOTAL", 28, ACCENT, false)
	_add_cell("", 16, TEXT_DIM, false)
	_add_cell(_format_points(score.total), 28, GOOD, true)


func _add_cell(text: String, size: int, color: Color, right_aligned: bool) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if right_aligned:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_grid.add_child(label)


## 12345 -> "12,345"
func _format_points(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


func _reason_text(reason: MissionManager.FailReason) -> String:
	match reason:
		MissionManager.FailReason.TIME_EXPIRED:
			return "Time ran out."
		MissionManager.FailReason.JET_DESTROYED:
			return "Your jet was destroyed."
		MissionManager.FailReason.OUT_OF_MISSILES:
			return "You ran out of missiles."
	return "Mission aborted."


# --- Buttons ------------------------------------------------------------------

func _on_button_pressed() -> void:
	match _mode:
		Mode.BRIEFING:
			_close()
			get_tree().paused = false
			_manager.begin_mission()
		Mode.SUCCESS, Mode.FAILURE:
			# Reload the scene: it resets the jet, terrain and targets. The flag makes the new
			# run skip the briefing and begin straight away.
			MissionSession.skip_briefing = true
			get_tree().paused = false
			get_tree().reload_current_scene()


func _on_next_pressed() -> void:
	if _next_mission == null:
		return
	MissionSession.select(_next_mission)
	MissionSession.skip_briefing = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	if not _menu_available():
		return
	get_tree().paused = false
	get_tree().change_scene_to_file(MissionSession.menu_scene_path)


## The menu button only exists when the game was started from the mission-select scene.
func _menu_available() -> bool:
	return MissionSession.menu_scene_path != ""


func _open() -> void:
	_backdrop.visible = true
	get_tree().paused = true
	_button.grab_focus()


func _close() -> void:
	_backdrop.visible = false
	_mode = Mode.NONE


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP # taps never reach anything behind
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(center)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.09, 0.95)
	style.border_color = ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 32)
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	_title = _make_label(34, ACCENT, false)
	box.add_child(_title)
	_body = _make_label(20, TEXT, true)
	box.add_child(_body)
	box.add_child(HSeparator.new())
	_stats = _make_label(20, TEXT_DIM, false)
	box.add_child(_stats)

	_score_grid = GridContainer.new()
	_score_grid.columns = 3
	_score_grid.custom_minimum_size = Vector2(520.0, 0.0)
	_score_grid.add_theme_constant_override("h_separation", 28)
	_score_grid.add_theme_constant_override("v_separation", 6)
	_score_grid.visible = false
	box.add_child(_score_grid)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	box.add_child(button_row)

	_button = _make_button("START", 280.0)
	_button.pressed.connect(_on_button_pressed)
	button_row.add_child(_button)
	_next_button = _make_button("NEXT MISSION", 280.0)
	_next_button.pressed.connect(_on_next_pressed)
	button_row.add_child(_next_button)
	_menu_button = _make_button("MENU", 200.0)
	_menu_button.pressed.connect(_on_menu_pressed)
	button_row.add_child(_menu_button)


func _make_button(text: String, min_width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 68.0)
	button.add_theme_font_size_override("font_size", 26)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.34, 0.40)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.12, 0.45, 0.52)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.05, 0.24, 0.29)))
	button.add_theme_stylebox_override("focus", _button_style(Color(0.12, 0.45, 0.52)))
	return button


func _make_label(size: int, color: Color, wrap: bool) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.custom_minimum_size = Vector2(520.0, 0.0)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style


func _format_time(seconds: float) -> String:
	var whole := int(seconds)
	return "%d:%02d" % [int(whole / 60.0), whole % 60]
