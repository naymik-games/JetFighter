class_name MissionManager
extends Node
## Runs one mission: the state machine, objective order, per-objective timer and SAM
## network flags. It is the ONLY thing that decides whether a mission is won or lost.
##
## It does not spawn anything and draws nothing. Other systems talk to it:
##   - ObjectiveTarget (Step 4) calls report_objective_destroyed() when its target dies.
##   - The HUD (Step 5) reads current_placement(), time_left() and listens to the signals.
##   - Death and missile rules (Step 6) call fail().
##   - SAMs (Step 7) ask is_network_online().
##
## States:  IDLE -> BRIEFING -> ACTIVE -> OBJECTIVE_COMPLETE -> ACTIVE ... -> SUCCEEDED
##          ACTIVE can also go to FAILED (time expired, jet destroyed, out of missiles).

enum State { IDLE, BRIEFING, ACTIVE, OBJECTIVE_COMPLETE, SUCCEEDED, FAILED }
enum FailReason { NONE, TIME_EXPIRED, JET_DESTROYED, OUT_OF_MISSILES, ABORTED }

signal state_changed(new_state: State, old_state: State)
## The chain is built and the mission is waiting in BRIEFING for begin_mission().
signal mission_started(mission: MissionConfig)
## An objective became the active one. Its timer starts now.
signal objective_revealed(index: int, placement: ObjectivePlacement)
## time_left is the seconds remaining on the objective's timer, or -1.0 when it was untimed.
signal objective_completed(index: int, placement: ObjectivePlacement, time_left: float)
signal network_disabled(network_id: StringName)
signal mission_succeeded
signal mission_failed(reason: FailReason)

## Pause between an objective being destroyed and the next one being revealed.
## The timer is stopped during it. 0 = reveal immediately.
@export var next_objective_delay: float = 2.0

var mission: MissionConfig
var sampler: TerrainSampler
var state: State = State.IDLE
var fail_reason: FailReason = FailReason.NONE

var _placements: Array[ObjectivePlacement] = []
var _index: int = -1
var _time_limit: float = -1.0
var _time_left: float = -1.0
var _pause_left: float = 0.0
var _elapsed: float = 0.0
var _time_left_at_completion: Array[float] = []
var _offline_networks: Dictionary = {}


func _ready() -> void:
	add_to_group(GameConst.GROUP_MISSION)


# --- Control ----------------------------------------------------------------

## Builds the fixed objective chain and waits in BRIEFING. Returns false if it cannot start.
## Validation problems are printed as warnings; only an unusable mission stops here.
func start_mission(p_mission: MissionConfig, p_sampler: TerrainSampler) -> bool:
	_reset()
	if p_mission == null or p_sampler == null:
		push_error("MissionManager.start_mission: mission or sampler is null.")
		return false
	for problem in p_mission.validate():
		push_warning("Mission '%s': %s" % [p_mission.id, problem])
	if p_mission.objectives.is_empty():
		push_error("MissionManager.start_mission: mission has no objectives.")
		return false

	mission = p_mission
	sampler = p_sampler
	_placements = ObjectiveChain.generate(mission, sampler)
	if _placements.size() != mission.objectives.size():
		push_error("MissionManager.start_mission: objective chain could not be built.")
		_placements.clear()
		return false

	_set_state(State.BRIEFING)
	mission_started.emit(mission)
	return true


## Leaves BRIEFING and reveals the first objective. Call it when the player taps Start.
func begin_mission() -> void:
	if state != State.BRIEFING:
		push_warning("MissionManager.begin_mission: not in BRIEFING (state is %s)." % state_name(state))
		return
	_reveal(0)


## Starts the same mission again from the beginning (same seed, same layout).
func restart() -> bool:
	if mission == null or sampler == null:
		return false
	return start_mission(mission, sampler)


## Called when an objective's target is destroyed. Pass the objective's index to guard
## against stray calls; the default (-1) means "whichever one is active".
func report_objective_destroyed(index: int = -1) -> void:
	if state != State.ACTIVE:
		push_warning("MissionManager: objective reported destroyed while %s; ignored." % state_name(state))
		return
	if index >= 0 and index != _index:
		push_warning("MissionManager: objective %d reported destroyed but %d is active; ignored." % [index + 1, _index + 1])
		return

	var placement := _placements[_index]
	var left := maxf(_time_left, 0.0) if is_timed() else -1.0
	_time_left_at_completion.append(left)

	for net in placement.objective.disables_networks:
		_disable_network(StringName(net))

	objective_completed.emit(_index, placement, left)

	if _index >= _placements.size() - 1:
		_set_state(State.SUCCEEDED)
		mission_succeeded.emit()
	elif next_objective_delay <= 0.0:
		_reveal(_index + 1)
	else:
		_pause_left = next_objective_delay
		_set_state(State.OBJECTIVE_COMPLETE)


## Ends the mission as a failure. Safe to call more than once; only the first call counts.
func fail(reason: FailReason) -> void:
	if state != State.ACTIVE and state != State.OBJECTIVE_COMPLETE and state != State.BRIEFING:
		return
	fail_reason = reason
	_set_state(State.FAILED)
	mission_failed.emit(reason)


func abort() -> void:
	fail(FailReason.ABORTED)


# --- Queries ----------------------------------------------------------------

func is_running() -> bool:
	return state == State.ACTIVE or state == State.OBJECTIVE_COMPLETE


func is_finished() -> bool:
	return state == State.SUCCEEDED or state == State.FAILED


func objective_total() -> int:
	return _placements.size()


## Index of the active objective, or -1 when none is active yet.
func current_index() -> int:
	return _index


func objectives_completed() -> int:
	return _time_left_at_completion.size()


## The active objective's placement while ACTIVE, otherwise null.
func current_placement() -> ObjectivePlacement:
	if state == State.ACTIVE and _index >= 0 and _index < _placements.size():
		return _placements[_index]
	return null


func placements() -> Array[ObjectivePlacement]:
	return _placements


func is_timed() -> bool:
	return _time_limit >= 0.0


## Seconds left on the active objective, or -1.0 when it has no limit.
func time_left() -> float:
	return _time_left if is_timed() else -1.0


func time_limit() -> float:
	return _time_limit


## Seconds spent in ACTIVE so far (the pause between objectives is not counted).
func elapsed() -> float:
	return _elapsed


## Seconds left on each completed objective's timer (-1.0 = untimed). Used by scoring.
func time_left_at_completion() -> Array[float]:
	return _time_left_at_completion


## SAMs and other networked defenses ask this. A destroyed radar takes its networks offline.
func is_network_online(network_id: StringName) -> bool:
	return not _offline_networks.has(network_id)


static func state_name(s: State) -> String:
	return State.keys()[s]


static func fail_reason_name(r: FailReason) -> String:
	return FailReason.keys()[r]


## Debug only: jumps the active objective's timer.
func debug_set_time_left(seconds: float) -> void:
	if state == State.ACTIVE and is_timed():
		_time_left = seconds


# --- Internals --------------------------------------------------------------

func _process(delta: float) -> void:
	match state:
		State.ACTIVE:
			_elapsed += delta
			if is_timed():
				_time_left -= delta
				if _time_left <= 0.0:
					_time_left = 0.0
					fail(FailReason.TIME_EXPIRED)
		State.OBJECTIVE_COMPLETE:
			_pause_left -= delta
			if _pause_left <= 0.0:
				_reveal(_index + 1)


func _reveal(index: int) -> void:
	_index = index
	var placement := _placements[index]
	_time_limit = placement.time_limit
	_time_left = _time_limit
	_set_state(State.ACTIVE)
	objective_revealed.emit(index, placement)


func _disable_network(network_id: StringName) -> void:
	if _offline_networks.has(network_id):
		return
	_offline_networks[network_id] = true
	network_disabled.emit(network_id)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_changed.emit(new_state, old)


func _reset() -> void:
	mission = null
	sampler = null
	state = State.IDLE
	fail_reason = FailReason.NONE
	_placements.clear()
	_index = -1
	_time_limit = -1.0
	_time_left = -1.0
	_pause_left = 0.0
	_elapsed = 0.0
	_time_left_at_completion.clear()
	_offline_networks.clear()
