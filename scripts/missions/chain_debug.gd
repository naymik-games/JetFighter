extends Node
## Throwaway Step 2 check. Add this script to any Node in a scene and run it. Read the Output panel.
## It uses the live terrain's sampler when the scene has one (and its seed matches the mission),
## otherwise it builds a default TerrainConfig with the mission's seed.

func _ready() -> void:
	# Give the Terrain node a frame to create its sampler.
	await get_tree().process_frame

	var mission := MissionConfig.test_mission()
	var sampler := _get_sampler(mission)

	print("---- ObjectiveChain test (seed %d, start %s, heading %.0f) ----" % [mission.seed_value, mission.start_position, mission.start_heading_degrees])
	var chain_a := ObjectiveChain.generate(mission, sampler)
	print(ObjectiveChain.describe(chain_a))

	# 1. Determinism: same sampler twice, and a brand new sampler built from the same seed.
	var chain_b := ObjectiveChain.generate(mission, sampler)
	print("Same sampler, run twice identical: ", ObjectiveChain.same_positions(chain_a, chain_b))
	var fresh := _make_sampler(mission.seed_value)
	var chain_c := ObjectiveChain.generate(mission, fresh)
	print("Fresh sampler, same seed identical: ", ObjectiveChain.same_positions(chain_a, chain_c), "  (false is expected if your live terrain uses a customised config)")

	# 2. A different seed must give a different layout.
	var other := MissionConfig.test_mission()
	other.seed_value = 777
	var chain_d := ObjectiveChain.generate(other, _make_sampler(other.seed_value))
	print("Seed 777 layout:")
	print(ObjectiveChain.describe(chain_d))
	print("Seed 777 differs from 12345: ", not ObjectiveChain.same_positions(chain_a, chain_d))

	# 3. Checks on the main chain.
	var all_valid := true
	var max_turn := 0.0
	var prev_bearing := mission.start_heading_degrees
	for p in chain_a:
		all_valid = all_valid and p.valid
		max_turn = maxf(max_turn, absf(wrapf(p.bearing_degrees - prev_bearing, -180.0, 180.0)))
		prev_bearing = p.bearing_degrees
	print("All objectives found a valid site: ", all_valid)
	print("Largest turn between legs: %.1f degrees (limit %.0f unless a site needed widening)" % [max_turn, mission.objectives[0].max_turn_degrees])

	# 4. Robustness: 6-objective missions over 10 seeds. Counts fallback sites, tries needed,
	# how far the local search moved sites, and how far legs ended up from the 20-40 s range.
	var total := 0
	var fallbacks := 0
	var tries_sum := 0
	var worst_tries := 0
	var moved_sum := 0.0
	var worst_moved := 0.0
	var shortest_leg := INF
	var longest_leg := 0.0
	for s in range(1, 11):
		var m := MissionConfig.test_mission()
		m.seed_value = s * 1009
		var objs: Array[ObjectiveConfig] = []
		for i in 6:
			objs.append(ObjectiveConfig.make(ObjectiveConfig.Kind.FUEL_DEPOT, 0))
		m.objectives = objs
		var chain := ObjectiveChain.generate(m, _make_sampler(m.seed_value))
		for p in chain:
			total += 1
			tries_sum += p.attempts_used + 1
			worst_tries = maxi(worst_tries, p.attempts_used + 1)
			moved_sum += p.moved
			worst_moved = maxf(worst_moved, p.moved)
			shortest_leg = minf(shortest_leg, p.leg_distance)
			longest_leg = maxf(longest_leg, p.leg_distance)
			if not p.valid:
				fallbacks += 1
	print("Stress test: %d objectives over 10 seeds, %d fallback sites" % [total, fallbacks])
	print("  tries: average %.1f, worst %d (max %d)" % [float(tries_sum) / float(maxi(total, 1)), worst_tries, ObjectiveChain.MAX_ATTEMPTS])
	print("  local search moved sites: average %.1f, worst %.1f units (limit %.0f)" % [moved_sum / float(maxi(total, 1)), worst_moved, ObjectiveChain.SEARCH_RADIUS])
	print("  leg lengths: %.0f to %.0f units (target 500 to 1000)" % [shortest_leg, longest_leg])
	var t0 := Time.get_ticks_usec()
	ObjectiveChain.generate(mission, sampler)
	print("  time to generate the 3-objective test chain: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))


func _get_sampler(mission: MissionConfig) -> TerrainSampler:
	var terrain := get_tree().get_first_node_in_group(GameConst.GROUP_TERRAIN)
	if terrain != null:
		var live := terrain.get("sampler") as TerrainSampler
		if live != null:
			if live.seed_value == mission.seed_value:
				print("Using the live terrain sampler.")
				return live
			print("Live terrain seed is %d, mission seed is %d. Using a default config with the mission seed instead." % [live.seed_value, mission.seed_value])
	else:
		print("No terrain node in this scene. Using a default config with the mission seed.")
	return _make_sampler(mission.seed_value)


func _make_sampler(seed_value: int) -> TerrainSampler:
	var config := TerrainConfig.new()
	config.world_seed = seed_value
	return TerrainSampler.new(config)
