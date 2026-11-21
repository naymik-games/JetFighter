class_name GunConfig
extends Resource
## All the tunable numbers for the machine gun. JetGun falls back to these defaults when no
## .tres is assigned, so nothing has to be created in the editor to start testing.
## Heat runs 0..1: reaching 1.0 overheats the gun until it cools to `overheat_resume`.

@export_group("Burst")
## One press fires for this long (seconds), unless heat ends it early.
@export var burst_duration: float = 1.2
## Dead time after a burst ends before the next one can start.
@export var burst_cooldown: float = 0.15
## Pressing fire again mid-burst refills the burst timer (heat is still the limiter).
@export var press_extends_burst: bool = true

@export_group("Fire")
@export var shots_per_second: float = 20.0
@export var max_range: float = 220.0
## Target.take_damage() takes an int. Tanks with max_health 1 die to the first bullet until
## the gun-vulnerability pass (build step 6).
@export var damage: int = 1
## A bullet that lands on terrain also hurts the nearest Target within this radius of the
## impact, because ground targets sit flush with the terrain and strafing mostly hits dirt.
@export var ground_splash_radius: float = 1.5

@export_group("Heat")
@export var heat_per_shot: float = 0.035
## Seconds after the last shot before the gun starts cooling.
@export var cool_delay: float = 0.35
## Heat lost per second while cooling.
@export var cool_rate: float = 0.35
## After an overheat the gun stays locked out until heat falls to this value.
@export_range(0.0, 1.0) var overheat_resume: float = 0.4
