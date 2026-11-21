class_name MissionConfig
extends Resource
## One mission: a seed (which fixes terrain AND objective layout), a start point,
## a missile budget and an ordered list of objectives.
## Pure data. Save as .tres files later, or build in code with test_mission().

@export_group("Identity")
## Stable id used for saved progress (best score, completed). Never change it once shipped.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var briefing: String = ""
## Position in the mission-select list. Completing a mission unlocks the next higher one.
@export var sort_order: int = 0

@export_group("World")
## Becomes TerrainConfig.world_seed. Must not be 0 (0 means a random world).
@export var seed_value: int = 12345
## Start position on the ground plane (x, z). The jet's height is set elsewhere.
@export var start_position: Vector2 = Vector2.ZERO
## Degrees clockwise from the -Z axis (the jet's default forward). Leg 1's bearing is
## measured from this heading.
@export_range(-180.0, 180.0, 1.0) var start_heading_degrees: float = 0.0

@export_group("Resources")
## The whole missile budget for the mission. No resupply.
@export var starting_missiles: int = 30

@export_group("Timers")
## Mirror of JetFlight.cruise_speed. Timers and leg distances are built from it.
@export var cruise_speed: float = 25.0
## Multiplier on cruise-speed travel time. Above 1 leaves room for turns and detours.
@export_range(1.0, 3.0, 0.05) var timer_slack: float = 1.4
## Combat allowance added to every timed objective, in seconds.
@export var base_combat_seconds: float = 10.0
## Extra seconds added per defense level.
@export var combat_seconds_per_defense_level: float = 5.0

@export_group("Defense networks")
## Spawn rule name -> network id for the random world spawns, e.g. { &"sam_turret": &"net_a" }
## puts every open-world SAM on net_a, so destroying a radar that disables net_a switches them
## all off. Leave empty for no networks. Applied by the Terrain node when the mission starts.
@export var world_networks: Dictionary = {}

@export_group("Objectives & Score")
## Completed strictly in this order.
@export var objectives: Array[ObjectiveConfig] = []
@export var score: ScoreConfig = ScoreConfig.new()


func objective_count() -> int:
	return objectives.size()


## Sanity checks for hand-written missions. Returns human-readable problems (empty = fine).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("Mission id is empty.")
	if seed_value == 0:
		problems.append("seed_value is 0, which gives a random world every run.")
	if objectives.is_empty():
		problems.append("Mission has no objectives.")
	if starting_missiles <= 0:
		problems.append("starting_missiles must be above 0.")
	if cruise_speed <= 0.0:
		problems.append("cruise_speed must be above 0.")

	for i in objectives.size():
		var o := objectives[i]
		var label := "Objective %d" % (i + 1)
		if o == null:
			problems.append("%s is empty." % label)
			continue
		label += " (%s)" % o.get_display_name()
		if o.leg_seconds_min <= 0.0 or o.leg_seconds_max <= 0.0:
			problems.append("%s: leg seconds must be above 0." % label)
		if o.leg_seconds_min > o.leg_seconds_max:
			problems.append("%s: leg_seconds_min is larger than leg_seconds_max." % label)
		if o.timed and o.timer_override < 0.0:
			problems.append("%s: timer_override is negative." % label)

		# Network checks: a disabled network should have members: a LATER objective's defenders,
		# or the world spawns listed in world_networks.
		for net in o.disables_networks:
			var world_uses := _world_uses_network(net)
			var users := _objectives_using_network(net)
			if users.is_empty() and not world_uses:
				problems.append("%s disables network '%s', but nothing belongs to it." % [label, net])
				continue
			var any_later := false
			for j in users:
				if j > i:
					any_later = true
			if not any_later and not world_uses:
				problems.append("%s disables network '%s', but only earlier objectives use it." % [label, net])
	return problems


func _world_uses_network(net: String) -> bool:
	for value in world_networks.values():
		if String(value) == net:
			return true
	return false


func _objectives_using_network(net: String) -> Array[int]:
	var found: Array[int] = []
	for j in objectives.size():
		var o := objectives[j]
		if o != null and String(o.defender_network) == net:
			found.append(j)
	return found


## Readable multi-line summary for debugging.
func describe() -> String:
	var lines := PackedStringArray()
	lines.append("Mission '%s' (%s)  seed=%d  missiles=%d  objectives=%d" % [display_name, id, seed_value, starting_missiles, objectives.size()])
	for i in objectives.size():
		var o := objectives[i]
		if o == null:
			lines.append("  %d. <null>" % (i + 1))
			continue
		var range_units := o.leg_distance_range(cruise_speed)
		var mid_leg := (range_units.x + range_units.y) * 0.5
		var limit := o.time_limit_for_leg(mid_leg, self)
		var limit_text := "no limit" if limit < 0.0 else "%.0fs" % limit
		lines.append("  %d. %s | defense %d | leg %.0f-%.0f units | timer %s (mid-leg) | net '%s' | disables %s" % [
			i + 1, o.get_display_name(), o.defense_level, range_units.x, range_units.y,
			limit_text, o.defender_network, str(o.disables_networks)])
	return "\n".join(lines)


## Hand-written mission for testing. Shows the full set of features:
## radar (disables net_a) -> undefended fuel depot -> headquarters defended by net_a SAMs.
static func test_mission() -> MissionConfig:
	var m := MissionConfig.new()
	m.id = &"test_mission"
	m.display_name = "Test Mission"
	m.briefing = "Knock out the radar, hit the fuel depot, then destroy headquarters."
	m.sort_order = 0
	m.seed_value = 12345
	m.starting_missiles = 20
	m.world_networks = {&"sam_turret": &"net_a"}

	var radar := ObjectiveConfig.make(ObjectiveConfig.Kind.RADAR_STATION, 1, &"", PackedStringArray(["net_a"]))
	radar.reveal_text = "Destroy the radar station to blind the SAM network."

	var depot := ObjectiveConfig.make(ObjectiveConfig.Kind.FUEL_DEPOT, 0)
	depot.reveal_text = "Undefended fuel depot ahead."
	depot.timed = false

	var hq := ObjectiveConfig.make(ObjectiveConfig.Kind.HEADQUARTERS, 3, &"net_a")
	hq.reveal_text = "Destroy enemy headquarters."
	hq.health_override = 3
	hq.base_points = 2500

	var list: Array[ObjectiveConfig] = [radar, depot, hq]
	m.objectives = list
	return m
