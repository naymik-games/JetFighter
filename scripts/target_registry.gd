class_name TargetRegistry
extends RefCounted
## Static list of live Targets. Replaces get_nodes_in_group("targets") scans.
## Targets add themselves in _ready and remove themselves in _exit_tree
## (which also fires when their chunk unloads), so the list is always live-only.

## 1 << Target.Team.* (kept as literals to avoid a load-order cycle with Target).
const MASK_ENEMY := 1
const MASK_NEUTRAL := 2
const MASK_FRIENDLY := 4
const MASK_ALL := 7


## Signals can't be static, so they live on a tiny object.
class Events extends RefCounted:
	signal target_registered(target: Target)


static var events := Events.new()
static var _targets: Array[Target] = []


static func register(target: Target) -> void:
	if _targets.has(target):
		return
	_targets.append(target)
	events.target_registered.emit(target)


static func unregister(target: Target) -> void:
	_targets.erase(target)


## The live list. Treat as read-only; duplicate() it if you might free targets while looping.
static func all() -> Array[Target]:
	return _targets


static func count() -> int:
	return _targets.size()


## Every live target within radius of origin whose team bit is in team_mask.
static func query(origin: Vector3, radius: float, team_mask: int = MASK_ALL) -> Array[Target]:
	var out: Array[Target] = []
	var r_sq := radius * radius
	for t in _targets:
		if (Target.team_bit(t.team) & team_mask) == 0:
			continue
		if origin.distance_squared_to(t.global_position) <= r_sq:
			out.append(t)
	return out


## Target closest to the forward axis inside the cone and range (lock-on selection).
## `filter` (optional) is called as filter.call(target) -> bool, and only for targets that
## would otherwise win, so an expensive check (a line-of-sight ray) stays cheap.
static func best_in_cone(origin: Vector3, forward: Vector3, max_range: float,
		max_angle: float, team_mask: int = MASK_ENEMY, filter: Callable = Callable()) -> Target:
	var best: Target = null
	var best_angle := max_angle
	var r_sq := max_range * max_range
	for t in _targets:
		if (Target.team_bit(t.team) & team_mask) == 0:
			continue
		var to_t := t.global_position - origin
		if to_t.length_squared() > r_sq:
			continue
		var angle := forward.angle_to(to_t.normalized())
		if angle < best_angle:
			if filter.is_valid() and not filter.call(t):
				continue
			best_angle = angle
			best = t
	return best
