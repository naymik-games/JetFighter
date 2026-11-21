class_name MissionLibrary
extends RefCounted
## The list of playable missions, in order. Three starter missions are built in code (same style
## as MissionConfig.test_mission). Any MissionConfig .tres saved in res://missions/ is added
## too, so you can make more missions in the editor without touching code.
##
## A mission is unlocked when the one before it (by sort_order) has been completed.

const EXTRA_DIR := "res://missions"

static var _cache: Array[MissionConfig] = []


static func all() -> Array[MissionConfig]:
	if _cache.is_empty():
		_cache = _build()
	return _cache


static func find(mission_id: StringName) -> MissionConfig:
	for mission in all():
		if mission.id == mission_id:
			return mission
	return null


static func index_of(mission: MissionConfig) -> int:
	var list := all()
	for i in list.size():
		if list[i].id == mission.id:
			return i
	return -1


## The mission after this one, or null when it is the last (or not in the library).
static func next_after(mission: MissionConfig) -> MissionConfig:
	var list := all()
	var i := index_of(mission)
	if i < 0 or i + 1 >= list.size():
		return null
	return list[i + 1]


## First mission is always open; the rest need the previous one completed.
## Missions that are not in the library (like the test mission) are always open.
static func is_unlocked(mission: MissionConfig) -> bool:
	var i := index_of(mission)
	if i <= 0:
		return true
	return SaveData.is_completed(all()[i - 1].id)


## 1 to 5, from the average defense level of the objectives.
static func difficulty(mission: MissionConfig) -> int:
	if mission.objectives.is_empty():
		return 1
	var total := 0.0
	for objective in mission.objectives:
		total += float(objective.defense_level)
	return clampi(int(ceil(total / float(mission.objectives.size()))), 1, 5)


static func _build() -> Array[MissionConfig]:
	var list: Array[MissionConfig] = [first_strike(), blind_the_sky(), deep_strike()]

	var dir := DirAccess.open(EXTRA_DIR)
	if dir != null:
		for file in dir.get_files():
			var name := file.trim_suffix(".remap") # exported projects rename resources
			if not name.ends_with(".tres"):
				continue
			var loaded := load("%s/%s" % [EXTRA_DIR, name]) as MissionConfig
			if loaded != null and find_in(list, loaded.id) == null:
				list.append(loaded)

	list.sort_custom(func(a: MissionConfig, b: MissionConfig) -> bool:
		return a.sort_order < b.sort_order if a.sort_order != b.sort_order else String(a.id) < String(b.id))
	return list


static func find_in(list: Array[MissionConfig], mission_id: StringName) -> MissionConfig:
	for mission in list:
		if mission.id == mission_id:
			return mission
	return null


# --- Starter missions ---------------------------------------------------------

## Gentle: three objectives, no SAM network, generous timers.
static func first_strike() -> MissionConfig:
	var m := MissionConfig.new()
	m.id = &"first_strike"
	m.display_name = "First Strike"
	m.briefing = "Warm-up run. Hit the fuel depot, the radio tower and the radar station, one after another. Light defenses."
	m.sort_order = 1
	m.seed_value = 4101
	m.starting_missiles = 24
	m.timer_slack = 1.6
	m.base_combat_seconds = 12.0

	var depot := ObjectiveConfig.make(ObjectiveConfig.Kind.FUEL_DEPOT, 0)
	depot.timed = false
	depot.reveal_text = "Undefended fuel depot ahead. Take it out."
	var tower := ObjectiveConfig.make(ObjectiveConfig.Kind.RADIO_TOWER, 1)
	tower.reveal_text = "Destroy the radio tower."
	var radar := ObjectiveConfig.make(ObjectiveConfig.Kind.RADAR_STATION, 1)
	radar.reveal_text = "Destroy the radar station."

	var list: Array[ObjectiveConfig] = [depot, tower, radar]
	m.objectives = list
	return m


## Teaches the SAM network: kill the radar first and every SAM in the world goes dark.
static func blind_the_sky() -> MissionConfig:
	var m := MissionConfig.new()
	m.id = &"blind_the_sky"
	m.display_name = "Blind the Sky"
	m.briefing = "Enemy SAMs are tied to one radar. Destroy it first and every SAM goes offline, including the ones guarding the targets that follow."
	m.sort_order = 2
	m.seed_value = 8802
	m.starting_missiles = 28
	m.world_networks = {&"sam_turret": &"net_a"}

	var radar := ObjectiveConfig.make(ObjectiveConfig.Kind.RADAR_STATION, 1, &"", PackedStringArray(["net_a"]))
	radar.reveal_text = "Destroy the radar to blind the SAM network."
	var depot := ObjectiveConfig.make(ObjectiveConfig.Kind.FUEL_DEPOT, 2, &"net_a")
	depot.reveal_text = "Fuel depot. Its SAM is offline if the radar is gone."
	var tower := ObjectiveConfig.make(ObjectiveConfig.Kind.RADIO_TOWER, 2, &"net_a")
	tower.reveal_text = "Destroy the radio tower."
	var hq := ObjectiveConfig.make(ObjectiveConfig.Kind.HEADQUARTERS, 3, &"net_a")
	hq.reveal_text = "Destroy enemy headquarters. It takes three hits."
	hq.health_override = 3
	hq.base_points = 2500

	var list: Array[ObjectiveConfig] = [radar, depot, tower, hq]
	m.objectives = list
	return m


## Hard: five objectives, tighter timers, heavy defenses, and the radar sits mid-mission.
static func deep_strike() -> MissionConfig:
	var m := MissionConfig.new()
	m.id = &"deep_strike"
	m.display_name = "Deep Strike"
	m.briefing = "A long push into hostile territory. Tight timers and heavy defenses. Take out the radar halfway through to ease the final targets."
	m.sort_order = 3
	m.seed_value = 31337
	m.starting_missiles = 30
	m.timer_slack = 1.25
	m.base_combat_seconds = 8.0
	m.world_networks = {&"sam_turret": &"net_a"}

	var tower_a := ObjectiveConfig.make(ObjectiveConfig.Kind.RADIO_TOWER, 2)
	tower_a.reveal_text = "Destroy the forward radio tower."
	var radar := ObjectiveConfig.make(ObjectiveConfig.Kind.RADAR_STATION, 3, &"", PackedStringArray(["net_a"]))
	radar.reveal_text = "Destroy the radar. The SAMs ahead depend on it."
	var depot := ObjectiveConfig.make(ObjectiveConfig.Kind.FUEL_DEPOT, 3, &"net_a")
	depot.reveal_text = "Destroy the fuel depot."
	var tower_b := ObjectiveConfig.make(ObjectiveConfig.Kind.RADIO_TOWER, 4, &"net_a")
	tower_b.reveal_text = "Destroy the command relay tower."
	var hq := ObjectiveConfig.make(ObjectiveConfig.Kind.HEADQUARTERS, 5, &"net_a")
	hq.reveal_text = "Destroy enemy headquarters. It takes five hits."
	hq.health_override = 5
	hq.base_points = 4000

	var list: Array[ObjectiveConfig] = [tower_a, radar, depot, tower_b, hq]
	m.objectives = list
	return m
