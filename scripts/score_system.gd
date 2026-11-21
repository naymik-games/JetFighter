class_name ScoreSystem
extends Node
## Owns score and combo. Listens to every Target's `destroyed` signal, so
## nothing calls the HUD by group any more. The HUD only reads these values.
## You don't need to add this to a scene: the HUD creates one if none exists.

signal score_changed(score: int, combo: int)

@export var combo_duration: float = 4.5
@export var max_combo: int = 8

var score: int = 0
var combo: int = 1
var combo_timer: float = 0.0
## Points from everything that is NOT a mission objective (combo included; penalties subtract).
## The mission's final score uses this for its "side targets" line, so objectives are not
## counted twice.
var side_points: int = 0


func _ready() -> void:
	add_to_group(GameConst.GROUP_SCORE)
	# Connect first, then sweep existing targets, so none is missed or doubled.
	TargetRegistry.events.target_registered.connect(_watch)
	for t in TargetRegistry.all().duplicate():
		_watch(t)


func _watch(target: Target) -> void:
	target.destroyed.connect(_on_target_destroyed.bind(target))


func _process(delta: float) -> void:
	if combo > 1:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 1
			score_changed.emit(score, combo)


func _on_target_destroyed(_pos: Vector3, target: Target) -> void:
	var gained := 0
	if target.team == Target.Team.ENEMY and target.points > 0:
		gained = target.points * combo
		score += gained
		combo = mini(combo + 1, max_combo)
		combo_timer = combo_duration
	else:
		# Neutral / friendly: flat value (normally a penalty) and the combo breaks.
		var before := score
		score = maxi(score + target.points, 0)
		gained = score - before
		if target.points < 0:
			combo = 1
	if not (target is ObjectiveTarget):
		side_points += gained
	score_changed.emit(score, combo)
