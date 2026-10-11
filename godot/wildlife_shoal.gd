extends RefCounted

# Each shoal shares one snapshot per physics tick, regardless of member count.
var frame := -1
var center := Vector3.ZERO
var alignment := Vector3.ZERO
var goal := Vector3.ZERO
var positions: Array[Vector3] = []

func refresh(members: Array[Node3D]) -> void:
	var tick := Engine.get_physics_frames()
	if tick == frame: return
	frame = tick
	center = Vector3.ZERO; alignment = Vector3.ZERO; positions.clear()
	for member in members:
		if not is_instance_valid(member) or member.dead or not member.get_meta("wildlife_awake",true): continue
		if positions.is_empty(): goal = member.goal
		positions.append(member.position)
		center += member.position; alignment += member.direction
	center /= maxi(1,positions.size())
	alignment = alignment.normalized()

func separation(point: Vector3, radius: float) -> Vector3:
	var result := Vector3.ZERO
	var reach_squared := radius * radius * 9.0
	for other in positions:
		var away := point - other
		var distance_squared := away.length_squared()
		if distance_squared > 0.001 and distance_squared < reach_squared:
			result += away / sqrt(distance_squared)
	return result
