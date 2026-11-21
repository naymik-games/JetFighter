class_name DefenseNetworks
extends RefCounted
## Static registry of defense networks (for example &"net_a"). Things that belong to a network
## are NetworkMember nodes. Taking a network offline switches all its members off, now and for
## any that spawn later. Like TargetRegistry it is static, so nothing needs to be in the scene.
##
## Static state survives scene reloads, so reset() is called when a mission's terrain is set up.

static var _members: Dictionary = {} # StringName -> Array of NetworkMember
static var _offline: Dictionary = {} # StringName -> true


static func join(network_id: StringName, member: Node) -> void:
	if network_id == &"":
		return
	var list: Array = _members.get(network_id, [])
	if not list.has(member):
		list.append(member)
	_members[network_id] = list
	if _offline.has(network_id):
		member.call(&"go_offline")


static func leave(network_id: StringName, member: Node) -> void:
	if _members.has(network_id):
		(_members[network_id] as Array).erase(member)


## Takes a whole network offline. Does nothing if it already is.
static func set_offline(network_id: StringName) -> void:
	if network_id == &"" or _offline.has(network_id):
		return
	_offline[network_id] = true
	var list: Array = _members.get(network_id, [])
	for member in list.duplicate():
		if is_instance_valid(member):
			member.call(&"go_offline")


static func is_offline(network_id: StringName) -> bool:
	return _offline.has(network_id)


static func member_count(network_id: StringName) -> int:
	return (_members.get(network_id, []) as Array).size()


static func reset() -> void:
	_members.clear()
	_offline.clear()


static func summary() -> String:
	if _members.is_empty():
		return "no networks"
	var parts := PackedStringArray()
	for id in _members.keys():
		parts.append("%s: %d members, %s" % [id, member_count(id), "OFFLINE" if is_offline(id) else "online"])
	return "; ".join(parts)
