class_name ScoreConfig
extends Resource
## Score weights for one mission. Placeholder values: the scoring step (Step 8) reads these,
## and the content pass (Step 10) tunes them. Score is only awarded on success.

## Awarded per objective, on top of each objective's own base_points.
@export var objective_bonus: int = 0
## Per second left on an objective's timer when it is destroyed. Untimed objectives give none.
@export var time_bonus_per_second: int = 20
## Per missile left over at the end of a successful mission.
@export var missile_bonus_each: int = 50
## Scaled by the fraction of jet health remaining (1.0 = undamaged).
@export var max_health_bonus: int = 1000
## Multiplies the points of side targets (tanks, SAMs, future types) destroyed on the way.
@export_range(0.0, 5.0, 0.05) var side_target_multiplier: float = 1.0
