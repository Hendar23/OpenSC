extends RefCounted

# Each shoal shares one snapshot per physics tick, regardless of member count.
var frame := -1
var center := Vector3.ZERO
var alignment := Vector3.ZERO
var goal := Vector3.ZERO
var positions: Array[Vector3] = []
var cells := {}
const CELL_SIZE := 2.0

func refresh(members: Array[Node3D]) -> void:
	var tick := Engine.get_physics_frames()
	if tick == frame: return
	frame = tick
	center = Vector3.ZERO; alignment = Vector3.ZERO; positions.clear(); cells.clear()
	for member in members:
		if not is_instance_valid(member) or member.dead or not member.get_meta("wildlife_awake",true): continue
		if positions.is_empty(): goal = member.goal
		positions.append(member.position)
		var cell := Vector3i((member.position / CELL_SIZE).floor())
		if not cells.has(cell): cells[cell] = []
		cells[cell].append(member.position)
		center += member.position; alignment += member.direction
	center /= maxi(1,positions.size())
	alignment = alignment.normalized()

func separation(point: Vector3, radius: float) -> Vector3:
	var result := Vector3.ZERO
	var reach_squared := radius * radius * 9.0
	var neighbours: Array = []
	if positions.size() <= 16:
		neighbours.assign(positions)
	else:
		var low := Vector3i(((point - Vector3.ONE * radius * 3) / CELL_SIZE).floor())
		var high := Vector3i(((point + Vector3.ONE * radius * 3) / CELL_SIZE).floor())
		var search: Array = []
		if (high.x-low.x+1) * (high.y-low.y+1) * (high.z-low.z+1) < cells.size():
			for x in range(low.x,high.x+1):
				for y in range(low.y,high.y+1):
					for z in range(low.z,high.z+1): search.append(Vector3i(x,y,z))
		else: search = cells.keys()
		for cell in search:
			if cell.x >= low.x and cell.x <= high.x and cell.y >= low.y and cell.y <= high.y and cell.z >= low.z and cell.z <= high.z: neighbours.append_array(cells.get(cell,[]))
	for other: Vector3 in neighbours:
		var away := point - other
		var distance_squared := away.length_squared()
		if distance_squared > 0.001 and distance_squared < reach_squared:
			result += away / sqrt(distance_squared)
	return result
