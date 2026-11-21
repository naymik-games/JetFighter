class_name MissionSession
extends RefCounted
## Which mission is being played. The mission-select menu (Step 9) will call select() and then
## load the game scene; the Terrain node and the MissionRunner both read it from here.
##
## While no menu exists, get_current() falls back to the hand-written test mission so the game
## scene still runs on its own. Set use_test_mission_when_empty to false to turn that off.

static var current: MissionConfig = null
static var use_test_mission_when_empty: bool = true
## Set by the Retry button so the reloaded scene skips the briefing and starts straight away.
static var skip_briefing: bool = false
## Total score of the last successful mission (read by the mission-select menu in Step 9).
static var last_score: int = 0
## Path of the mission-select scene, set when it starts a mission. The in-game result screens use
## it for their MENU button. Empty when the game scene was started directly (no menu button then).
static var menu_scene_path: String = ""

static var _fallback: MissionConfig = null
static var _chain_cache: Dictionary = {}


static func select(mission: MissionConfig) -> void:
	current = mission


static func clear() -> void:
	current = null


## The mission to play, or null when none is selected and the fallback is disabled.
static func get_current() -> MissionConfig:
	if current != null:
		return current
	if use_test_mission_when_empty:
		if _fallback == null:
			_fallback = MissionConfig.test_mission()
		return _fallback
	return null


## True once after Retry was pressed; clears itself so the next fresh start shows the briefing.
static func consume_skip_briefing() -> bool:
	var value := skip_briefing
	skip_briefing = false
	return value


## The objective chain for a mission, built once and shared. Both the Terrain node (to keep random
## spawns off the objective sites) and the MissionManager need it, and it is deterministic, so
## the second caller just gets the first one's result.
static func chain_for(mission: MissionConfig, sampler: TerrainSampler) -> Array[ObjectivePlacement]:
	var key := "%d_%d" % [mission.get_instance_id(), sampler.seed_value]
	if not _chain_cache.has(key):
		_chain_cache[key] = ObjectiveChain.generate(mission, sampler)
	return _chain_cache[key]
