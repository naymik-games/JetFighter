class_name MissionScore
extends RefCounted
## The final score for a successful mission, built from the weights in the mission's ScoreConfig.
## Only computed on success. Pure data: it reads the finished run and changes nothing.
##
##   Objectives    each objective's base_points (+ ScoreConfig.objective_bonus)
##   Time bonus    whole seconds left on each timed objective x time_bonus_per_second
##   Missiles      missiles left over x missile_bonus_each
##   Jet health    fraction of health left x max_health_bonus
##   Side targets  the per-kill points for everything that was not an objective (combo included)
##                 x side_target_multiplier

var objectives: int = 0
var time_bonus: int = 0
var missile_bonus: int = 0
var health_bonus: int = 0
var side_targets: int = 0
var total: int = 0

# Details shown beside each line on the results screen.
var objectives_done: int = 0
var objectives_total: int = 0
var seconds_banked: int = 0
var missiles_left: int = -1 # -1 = the jet had unlimited missiles
var health_fraction: float = 1.0
var side_multiplier: float = 1.0


static func compute(mission: MissionConfig, manager: MissionManager, jet: Jet, score_system: ScoreSystem) -> MissionScore:
	var result := MissionScore.new()
	var weights := mission.score if mission.score != null else ScoreConfig.new()

	# Objectives: only those actually destroyed (all of them, on a success).
	var placements := manager.placements()
	result.objectives_total = placements.size()
	result.objectives_done = mini(manager.objectives_completed(), placements.size())
	for i in result.objectives_done:
		result.objectives += placements[i].objective.base_points + weights.objective_bonus

	# Time bonus: whole seconds left on each timed objective. Untimed ones are recorded as -1.
	for left in manager.time_left_at_completion():
		if left > 0.0:
			result.seconds_banked += int(floor(left))
	result.time_bonus = result.seconds_banked * weights.time_bonus_per_second

	# Missiles and health come from the jet.
	if is_instance_valid(jet):
		if jet.weapons.is_limited():
			result.missiles_left = jet.weapons.missiles_remaining
			result.missile_bonus = maxi(result.missiles_left, 0) * weights.missile_bonus_each
		result.health_fraction = jet.health.fraction()
		result.health_bonus = int(round(result.health_fraction * float(weights.max_health_bonus)))

	# Side targets: ScoreSystem already keeps the per-kill points (with combo) apart from objectives.
	result.side_multiplier = weights.side_target_multiplier
	if score_system != null:
		result.side_targets = int(round(float(score_system.side_points) * weights.side_target_multiplier))

	result.total = maxi(result.objectives + result.time_bonus + result.missile_bonus + result.health_bonus + result.side_targets, 0)
	return result


## Lines for the results screen: { label, detail, value }.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"label": "Objectives", "detail": "%d / %d" % [objectives_done, objectives_total], "value": objectives})
	out.append({"label": "Time bonus", "detail": "%d s left" % seconds_banked, "value": time_bonus})
	if missiles_left >= 0:
		out.append({"label": "Missiles left", "detail": str(missiles_left), "value": missile_bonus})
	out.append({"label": "Jet health", "detail": "%d%%" % int(round(health_fraction * 100.0)), "value": health_bonus})
	var side_detail := "" if is_equal_approx(side_multiplier, 1.0) else "x%.2f" % side_multiplier
	out.append({"label": "Side targets", "detail": side_detail, "value": side_targets})
	return out


## 12345 -> "12,345"
static func format_points(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
