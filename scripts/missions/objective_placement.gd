class_name ObjectivePlacement
extends RefCounted
## One generated objective position. Produced by ObjectiveChain.generate().
## Pure data: it does not touch the scene tree.

var index: int = 0
var objective: ObjectiveConfig
## World position on the visible terrain surface.
var position: Vector3 = Vector3.ZERO
## Surface normal of the mesh triangle under the position.
var normal: Vector3 = Vector3.UP
## Facing, in radians around the Y axis (seeded, so it is the same every run).
var yaw: float = 0.0
## Direction of the leg that led here, in degrees clockwise from -Z.
var bearing_degrees: float = 0.0
## Straight-line distance from the previous objective (or the start point).
var leg_distance: float = 0.0
## Seconds allowed for this objective, or -1.0 when untimed.
var time_limit: float = -1.0
## How many tries the generator needed (0 = first try worked).
var attempts_used: int = 0
## How far the local search moved the objective from the random spot it first picked.
var moved: float = 0.0
## False when no acceptable site was found and the least-bad one was used instead.
var valid: bool = true
## Steepest slope and height spread measured on the footprint.
var max_slope_degrees: float = 0.0
var relief: float = 0.0
## Tanks and SAMs planned around this objective (see ObjectiveDefenses).
var defenders: Array[DefenderSpawn] = []


func xz() -> Vector2:
	return Vector2(position.x, position.z)


func to_line() -> String:
	var name_text := objective.get_display_name() if objective != null else "?"
	return "%d. %s pos=(%.1f, %.1f, %.1f) leg=%.0f bearing=%.1f timer=%s tries=%d moved=%.0f slope=%.1f relief=%.1f %s" % [
		index + 1, name_text.rpad(14), position.x, position.y, position.z, leg_distance, bearing_degrees,
		("none" if time_limit < 0.0 else "%.0fs" % time_limit),
		attempts_used + 1, moved, max_slope_degrees, relief,
		("" if valid else "<-- NO GOOD SITE FOUND")] + "  defenders=%d" % defenders.size()
