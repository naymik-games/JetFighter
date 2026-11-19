class_name MissileConfig
extends Resource
## Tuning data for a Missile. One .tres per variant (player, SAM, ...).

enum Team { PLAYER, ENEMY }

@export var team: Team = Team.PLAYER

@export_group("Flight")
@export var speed: float = 85.0
@export var turn_rate: float = 4.5
## Hard cap on flight time. Missile deletes itself when it runs out.
@export var lifetime: float = 5.0

@export_group("Damage")
## Applied to Target.take_damage (player missiles) or the jet's take_damage (enemy missiles).
@export var damage: int = 100

@export_group("Seeker")
## If true the missile gives up when it misses: it stops homing, flies straight
## for fly_off_time, then deletes itself. It never turns back for a second pass.
@export var loses_lock_on_miss: bool = false
## Lock is lost when the target is further than this off the nose.
@export_range(10.0, 180.0) var seeker_cone_degrees: float = 75.0
## Lock is also lost beyond this distance. 0 = unlimited.
@export var lose_lock_range: float = 0.0
@export var fly_off_time: float = 1.5

@export_group("Smoke Trail")
@export var smoke_amount: int = 36
@export var smoke_lifetime: float = 0.85
@export var smoke_puff_radius: float = 0.35
@export var smoke_spread: float = 12.0
@export var smoke_velocity_min: float = 2.0
@export var smoke_velocity_max: float = 5.0
@export var smoke_gravity: Vector3 = Vector3(0.0, 1.2, 0.0)
@export var smoke_color_start: Color = Color(1.0, 0.85, 0.45)
@export var smoke_color_mid: Color = Color(0.92, 0.92, 0.94)
@export var smoke_color_end: Color = Color(0.55, 0.58, 0.62)
@export_range(0.0, 1.0) var smoke_mid_offset: float = 0.15
@export var smoke_scale_start: float = 0.4
@export var smoke_scale_peak: float = 1.1
@export_range(0.0, 1.0) var smoke_scale_peak_time: float = 0.3
