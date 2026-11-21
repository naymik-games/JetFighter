class_name MissionSelect
extends Control
## The first screen: a scrolling list of missions with best scores. Locked missions need the
## one before them completed. Everything is built in code, so the scene is just a Control with
## this script. Set up: see the notes in the delivery message (assign Game Scene, set as main scene).

## The scene that contains your Terrain, Jet and MissionRunner (the game scene).
@export var game_scene: PackedScene
@export var title_text: String = "MISSIONS"
## Development only: show every mission as unlocked.
@export var debug_unlock_all: bool = false

const ACCENT := Color(0.35, 0.9, 1.0, 1.0)
const GOOD := Color(0.35, 1.0, 0.5, 1.0)
const BAD := Color(1.0, 0.45, 0.35, 1.0)
const TEXT := Color(0.92, 0.95, 0.95, 1.0)
const TEXT_DIM := Color(0.62, 0.70, 0.73, 1.0)

var _list: VBoxContainer
var _message: Label
var _reset_button: Button
var _reset_armed: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh()


# --- UI -----------------------------------------------------------------------

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.07, 0.10)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var title := _label(title_text, 40, ACCENT)
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_list)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)

	_message = _label("", 16, BAD)
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_message)

	_reset_button = _make_button("RESET PROGRESS", 18, Vector2(210.0, 44.0))
	_reset_button.pressed.connect(_on_reset_pressed)
	footer.add_child(_reset_button)


## Rebuilds the cards (used at start and after progress is reset).
func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var missions := MissionLibrary.all()
	for i in missions.size():
		var mission := missions[i]
		var unlocked := debug_unlock_all or MissionLibrary.is_unlocked(mission)
		_list.add_child(_make_card(mission, i, unlocked, missions))


func _make_card(mission: MissionConfig, index: int, unlocked: bool, missions: Array[MissionConfig]) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.11, 0.14)
	style.border_color = ACCENT if unlocked else Color(0.25, 0.30, 0.33)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	if not unlocked:
		panel.modulate = Color(1.0, 1.0, 1.0, 0.6)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)

	# Left: name, briefing, facts.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)

	left.add_child(_label("%d   %s" % [index + 1, mission.display_name.to_upper()], 28, ACCENT if unlocked else TEXT_DIM))
	var briefing := _label(mission.briefing, 16, TEXT_DIM)
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.custom_minimum_size = Vector2(220.0, 0.0)
	left.add_child(briefing)
	var facts := "%d objectives     %d missiles     Difficulty %d / 5" % [mission.objectives.size(), mission.starting_missiles, MissionLibrary.difficulty(mission)]
	left.add_child(_label(facts, 16, TEXT))
	if not unlocked and index > 0:
		left.add_child(_label("Complete \"%s\" to unlock." % missions[index - 1].display_name, 16, BAD))

	# Right: status, best score, play button.
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)

	var best := SaveData.best_score(mission.id)
	if SaveData.is_completed(mission.id):
		right.add_child(_label("COMPLETED", 16, GOOD))
		right.add_child(_label("BEST  %s" % MissionScore.format_points(best), 20, TEXT))
	elif unlocked:
		right.add_child(_label("NEW", 16, ACCENT))
	else:
		right.add_child(_label("LOCKED", 16, BAD))

	var play := _make_button("PLAY" if unlocked else "LOCKED", 26, Vector2(170.0, 62.0))
	play.disabled = not unlocked
	play.pressed.connect(_on_play_pressed.bind(mission))
	right.add_child(play)
	return panel


# --- Actions ------------------------------------------------------------------

func _on_play_pressed(mission: MissionConfig) -> void:
	if game_scene == null:
		_show_message("Assign the game scene: select this node and set 'Game Scene' in the Inspector.", BAD)
		return
	MissionSession.select(mission)
	MissionSession.skip_briefing = false
	# Lets the in-game result screens come back to this menu.
	MissionSession.menu_scene_path = scene_file_path
	get_tree().change_scene_to_packed(game_scene)


func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_button.text = "TAP AGAIN TO CONFIRM"
		await get_tree().create_timer(3.0).timeout
		_reset_armed = false
		_reset_button.text = "RESET PROGRESS"
		return
	_reset_armed = false
	_reset_button.text = "RESET PROGRESS"
	SaveData.reset_all()
	_show_message("Progress reset.", TEXT_DIM)
	_refresh()


func _show_message(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)


# --- Small helpers ------------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String, size: int, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.34, 0.40)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.12, 0.45, 0.52)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.05, 0.24, 0.29)))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.12, 0.15, 0.17)))
	button.add_theme_stylebox_override("focus", _button_style(Color(0.12, 0.45, 0.52)))
	return button


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
