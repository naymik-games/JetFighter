class_name JetHealth
extends Node
## Hit points for the jet. Jet.take_damage() forwards here.

signal changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
signal died

@export var max_health: float = 100.0
## Used when a caller invokes take_damage() without an amount.
@export var default_damage: float = 25.0
## Camera shake trauma added on every hit (0..1).
@export_range(0.0, 1.0) var hit_shake: float = 0.45
## Debug: take hits (shake, signals) but never lose health.
@export var invulnerable: bool = false

var health: float = 0.0

var is_dead: bool:
	get:
		return health <= 0.0


func _ready() -> void:
	health = max_health


func fraction() -> float:
	return clampf(health / maxf(max_health, 0.001), 0.0, 1.0)


func take_damage(amount: float = -1.0, source: Node = null) -> void:
	if is_dead:
		return
	var dmg := amount if amount >= 0.0 else default_damage
	if not invulnerable:
		health = maxf(health - dmg, 0.0)
	damaged.emit(dmg, source)
	changed.emit(health, max_health)
	if health <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(health + amount, max_health)
	changed.emit(health, max_health)


func reset() -> void:
	health = max_health
	changed.emit(health, max_health)
