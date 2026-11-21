extends Node
## Throwaway Step 1 check. Add this script to any Node in a scene, run, and read the Output panel.
## Delete it (or just remove the node) once Step 1 looks right.

func _ready() -> void:
	var mission := MissionConfig.test_mission()
	print("---- MissionConfig test ----")
	print(mission.describe())

	var problems := mission.validate()
	if problems.is_empty():
		print("validate(): OK")
	else:
		for p in problems:
			print("validate() problem: ", p)

	# Timer formula check on the radar (timed, defense 1) at a 750-unit leg.
	var radar := mission.objectives[0]
	print("Radar timer for a 750-unit leg: %.1fs (expect 750/25*1.4 + 10 + 5 = 57.0)" % radar.time_limit_for_leg(750.0, mission))

	# The untimed depot should report no limit.
	print("Depot timer: ", mission.objectives[1].time_limit_for_leg(750.0, mission), " (expect -1.0)")

	# Break the mission on purpose to prove validate() catches it.
	var broken := MissionConfig.test_mission()
	broken.seed_value = 0
	broken.objectives[2].defender_network = &""
	print("Broken copy problems:")
	for p in broken.validate():
		print("  - ", p)
