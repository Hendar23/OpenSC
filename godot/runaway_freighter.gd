extends "res://mission_vessel.gd"
## Chopowski's retail waypoint chain is a runaway course, not safe traffic routing.
var halted := false

func set_local_simulation(on: bool) -> void:
	# This single objective must hit mines even outside the camera's range.
	super.set_local_simulation(true if not mission_owner.is_empty() else on)

func _react_to_damage(_source: Vector3) -> void:
	pass # The hijacked crew cannot flee or retaliate against the escort.

func _advance_motion(delta: float) -> void:
	if mission_owner.is_empty(): super._advance_motion(delta); return
	if dead or halted: _coast(delta); return
	# The final retail marker is inside the city/terrain. FREIGHT's original
	# outer collision radius is four, plus the waypoint's half-unit radius;
	# requiring its origin to enter the marker
	# wedges the visible hull against our solid scenery before arrival fires.
	while waypoint < waypoints.size() and global_position.distance_to(waypoints[waypoint]) < (4.5 if waypoint == waypoints.size()-1 else 1.0):
		waypoint += 1
	if waypoint >= waypoints.size():
		halted = true
		if not arrival_reported: arrival_reported = true; arrived.emit()
		return
	var hit := _flow_move(delta,global_position.direction_to(waypoints[waypoint]),float(tuning.npc_speed))
	if hit != null: last_obstacle = str(hit.get_collider().get_path())

func _continuous_route() -> bool:
	return not halted if not mission_owner.is_empty() else super._continuous_route()
