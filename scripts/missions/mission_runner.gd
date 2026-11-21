class_name MissionRunner
extends Node
## Drop this node into the game scene. It creates the MissionManager, ObjectiveSpawner,
## MissionHud and MissionScreens, starts the selected mission (MissionSession) and applies the
## rules that need the jet: death and the missile limit.
##
## Start-up: the world builds around the jet while the game is paused, then the briefing
## shows. Tapping Start un-pauses and begins the mission. Retry reloads the scene and skips the
## briefing. The mission-select menu (Step 9) will sit in front of all this.
##
## Debug keys (turn off with debug_keys = false; they work while the game is running):
##   K  destroy the active objective      G  fly the jet to 250 units short of it
##   T  set the objective timer to 3 s    N  print status

## Assign the same explosion scene your tanks and SAMs use (ExplosionBurst.tscn).
@export var explosion_scene: PackedScene
## Show the briefing screen and wait for Start. Off = begin on its own after auto_begin_delay.
@export var show_briefing: bool = true
## Seconds before the mission begins when the briefing is turned off.
@export var auto_begin_delay: float = 2.0
## With no missiles left and none in flight, the mission fails after this many seconds
## (long enough for the last hit to register).
@export var out_of_missiles_grace: float = 1.0
@export var debug_keys: bool = true

var manager: MissionManager
var spawner: ObjectiveSpawner
var hud: MissionHud
var screens: MissionScreens

var _terrain: Node
var _jet: Jet
var _dry_time: float = 0.0


func _ready() -> void:
	# One frame so the Terrain node has built its sampler and the jet exists.
	await get_tree().process_frame

	_terrain = get_tree().get_first_node_in_group(GameConst.GROUP_TERRAIN)
	_jet = get_tree().get_first_node_in_group(GameConst.GROUP_PLAYER) as Jet
	var mission := MissionSession.get_current()
	if _terrain == null or mission == null:
		push_error("MissionRunner: needs a Terrain node (group 'terrain') and a mission. Nothing started.")
		return
	var sampler := _terrain.get("sampler") as TerrainSampler
	if sampler == null:
		push_error("MissionRunner: the Terrain node has no sampler yet.")
		return
	if sampler.seed_value != mission.seed_value:
		push_warning("MissionRunner: terrain seed %d does not match mission seed %d. Is 'use_mission_seed' off on the Terrain node?" % [sampler.seed_value, mission.seed_value])

	manager = MissionManager.new()
	manager.name = "MissionManager"
	add_child(manager)
	spawner = ObjectiveSpawner.new()
	spawner.name = "ObjectiveSpawner"
	spawner.explosion_scene = explosion_scene
	add_child(spawner)
	spawner.setup(manager, _terrain)
	hud = MissionHud.new()
	hud.name = "MissionHud"
	add_child(hud)
	hud.setup(manager, spawner)
	screens = MissionScreens.new()
	screens.name = "MissionScreens"
	add_child(screens)
	screens.setup(manager, _jet)

	if is_instance_valid(_jet):
		# The mission decides what happens on death, so the jet must not reload the scene itself.
		_jet.respawn_delay = 0.0
		_jet.died.connect(_on_jet_died)

	manager.mission_started.connect(_on_mission_started)
	manager.network_disabled.connect(_on_network_disabled)
	manager.objective_revealed.connect(_on_revealed)
	manager.objective_completed.connect(func(i: int, p: ObjectivePlacement, left: float) -> void:
		print("[Mission] objective #%d %s destroyed, time left %.1f" % [i + 1, p.objective.get_display_name(), left]))
	manager.mission_succeeded.connect(func() -> void:
		print("[Mission] SUCCESS in %.1f s" % manager.elapsed()))
	manager.mission_failed.connect(func(r: int) -> void:
		print("[Mission] FAILED: ", MissionManager.fail_reason_name(r)))

	if not manager.start_mission(mission, sampler):
		return
	_warn_if_jet_off_start(mission)

	var skip_briefing := MissionSession.consume_skip_briefing()
	if show_briefing and not skip_briefing:
		await _freeze_and_show_briefing()
	elif skip_briefing or auto_begin_delay >= 0.0:
		await get_tree().create_timer(0.5 if skip_briefing else auto_begin_delay).timeout
		manager.begin_mission()


## Lets the jet and camera settle for two physics frames, freezes the world, waits for the
## terrain around the jet to finish building, then shows the briefing.
func _freeze_and_show_briefing() -> void:
	# The terrain keeps streaming chunks while everything else is paused.
	_terrain.process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().physics_frame
	await get_tree().physics_frame
	get_tree().paused = true

	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 4000:
		var built: bool = not _terrain.active_chunks.is_empty() and _terrain.pending_chunks.is_empty()
		if built:
			break
		await get_tree().process_frame
	screens.show_briefing()


func _physics_process(delta: float) -> void:
	# Out-of-missiles rule: nothing left to fire, nothing still flying, objective still alive.
	if manager == null or manager.state != MissionManager.State.ACTIVE or not is_instance_valid(_jet):
		_dry_time = 0.0
		return
	var weapons := _jet.weapons
	if weapons.is_limited() and weapons.missiles_remaining == 0 and weapons.missiles_in_flight() == 0:
		_dry_time += delta
		if _dry_time >= out_of_missiles_grace:
			manager.fail(MissionManager.FailReason.OUT_OF_MISSILES)
	else:
		_dry_time = 0.0


## A destroyed radar (or anything with disables_networks) switches its networks off.
func _on_network_disabled(network_id: StringName) -> void:
	DefenseNetworks.set_offline(network_id)
	print("[Mission] network '%s' offline: %s" % [network_id, DefenseNetworks.summary()])


func _on_jet_died() -> void:
	manager.fail(MissionManager.FailReason.JET_DESTROYED)


## Every (re)start gives the jet the mission's whole missile budget.
func _on_mission_started(mission: MissionConfig) -> void:
	_dry_time = 0.0
	if is_instance_valid(_jet):
		_jet.weapons.set_missiles(mission.starting_missiles)


func _on_revealed(index: int, placement: ObjectivePlacement) -> void:
	var line := "[Mission] objective #%d/%d revealed: %s at (%.0f, %.0f)" % [index + 1, manager.objective_total(), placement.objective.get_display_name(), placement.position.x, placement.position.z]
	if is_instance_valid(_jet):
		line += ", %.0f units from the jet" % _jet.global_position.distance_to(placement.position)
	print(line)


## The chain is laid out from mission.start_position, so the jet should start near it.
func _warn_if_jet_off_start(mission: MissionConfig) -> void:
	if not is_instance_valid(_jet):
		return
	var jet_xz := Vector2(_jet.global_position.x, _jet.global_position.z)
	var off := jet_xz.distance_to(mission.start_position)
	if off > 50.0:
		push_warning("MissionRunner: the jet starts %.0f units from the mission start %s. Objective legs are measured from the mission start, so set start_position to the jet's start." % [off, mission.start_position])


func _unhandled_input(event: InputEvent) -> void:
	if not debug_keys or manager == null:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_K:
			manager.report_objective_destroyed()
		KEY_T:
			manager.debug_set_time_left(3.0)
		KEY_G:
			_teleport_near_objective()
		KEY_N:
			_print_status()


func _teleport_near_objective() -> void:
	var placement := manager.current_placement()
	if placement == null or not is_instance_valid(_jet):
		print("[Mission] nothing to fly to right now.")
		return
	# Back along the leg that leads to the objective, 250 units short, well above the ground.
	var back := -ObjectiveChain.bearing_to_dir(placement.bearing_degrees) * 250.0
	_jet.global_position = Vector3(placement.position.x + back.x, placement.position.y + 45.0, placement.position.z + back.y)
	print("[Mission] jet moved to %s" % _jet.global_position)


func _print_status() -> void:
	var line := "[Mission] state=%s  objective %d/%d  completed=%d  time_left=%.1f" % [MissionManager.state_name(manager.state), manager.current_index() + 1, manager.objective_total(), manager.objectives_completed(), manager.time_left()]
	var placement := manager.current_placement()
	if placement != null and is_instance_valid(_jet):
		line += "  distance to objective %.0f" % _jet.global_position.distance_to(placement.position)
	var alive := spawner.current_instance()
	line += "  objective in world: %s" % ("yes" if alive != null else "no")
	if is_instance_valid(_jet):
		line += "  missiles %d (in flight %d)" % [_jet.weapons.missiles_remaining, _jet.weapons.missiles_in_flight()]
	line += "  networks: " + DefenseNetworks.summary()
	print(line)
