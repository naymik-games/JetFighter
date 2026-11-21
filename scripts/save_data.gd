class_name SaveData
extends RefCounted
## Saved mission progress: whether each mission is completed and its best score.
## Stored in a small ConfigFile in the user data folder (user://progress.cfg), one section per
## mission id. Loaded the first time it is needed.

const PATH := "user://progress.cfg"

static var _config: ConfigFile = null


static func is_completed(mission_id: StringName) -> bool:
	return bool(_cfg().get_value(String(mission_id), "completed", false))


## 0 when the mission has never been completed.
static func best_score(mission_id: StringName) -> int:
	return int(_cfg().get_value(String(mission_id), "best", 0))


## Marks the mission completed and keeps the score if it beats the old best.
## Returns true when this score is a new best (including the first time).
static func record_success(mission_id: StringName, score: int) -> bool:
	var cfg := _cfg()
	var section := String(mission_id)
	var is_new_best := score > best_score(mission_id)
	cfg.set_value(section, "completed", true)
	if is_new_best:
		cfg.set_value(section, "best", score)
	cfg.save(PATH)
	return is_new_best


static func reset_all() -> void:
	_config = ConfigFile.new()
	_config.save(PATH)


static func _cfg() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		_config.load(PATH) # A missing file is fine: everything just reads as "not completed".
	return _config
