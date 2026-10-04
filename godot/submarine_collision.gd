extends RefCounted

const Geometry = preload("res://submarine_equipment.gd")

# Convex sections retain the rendered hull's taper without filling the empty
# space between its bow/stern and the side pods.
static func fit(visual: Node3D, player: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var faces := PackedVector3Array()
	for entry in Geometry._meshes(visual,Transform3D.IDENTITY,true):
		for vertex in entry.mesh.get_faces(): faces.append(entry.pose * vertex)
	if faces.is_empty(): return result
	var bounds := AABB(faces[0],Vector3.ZERO)
	for point in faces: bounds = bounds.expand(point)
	for section in range(3):
		var low := bounds.position.z + bounds.size.z * section / 3.0
		var high := bounds.position.z + bounds.size.z * (section + 1) / 3.0
		var points := _unique(_slice(faces,low,high))
		if points.size() >= 4: result.append({"name": "HullCollision" if section == 0 else "HullCollision%d" % section,"points": points})
	var roles: Dictionary = visual.get_meta("submarine_parts", {"left_pod": "Hull/LeftPod", "right_pod": "Hull/RightPod", "main_propeller": "Hull/RearPropeller"})
	for role in ["left_pod","right_pod","main_propeller"]:
		var source := visual.get_node_or_null(NodePath(str(roles.get(role,"")))) as Node3D
		if source == null or source == visual: continue
		var parent_pose: Transform3D = player.global_transform.affine_inverse() * source.get_parent().global_transform
		var points := PackedVector3Array()
		for entry in Geometry._meshes(source,parent_pose):
			for vertex in entry.mesh.get_faces(): points.append(entry.pose * vertex)
		points = _unique(points)
		if points.size() < 4: continue
		var part := {"name": str(role).to_pascal_case() + "Collision", "points": points}
		# Follow the pods, including their propellers, as they tilt. The rear
		# propeller's swept outline stays fixed rather than spinning the collider.
		if role != "main_propeller":
			part["source"] = source
			part["rest_pose"] = player.global_transform.affine_inverse() * source.global_transform
		result.append(part)
	return result

static func _unique(points: PackedVector3Array) -> PackedVector3Array:
	var seen := {}
	var result := PackedVector3Array()
	for point in points:
		if seen.has(point): continue
		seen[point] = true
		result.append(point)
	return result

static func _slice(faces: PackedVector3Array, low: float, high: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in range(0,faces.size(),3):
		for edge in range(3):
			var a := faces[index + edge]
			var b := faces[index + (edge + 1) % 3]
			if a.z >= low and a.z <= high: points.append(a)
			if is_equal_approx(a.z,b.z): continue
			for plane in [low,high]:
				var fraction: float = (plane - a.z) / (b.z - a.z)
				if fraction >= 0.0 and fraction <= 1.0: points.append(a.lerp(b,fraction))
	return points

static func fallback() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in [
		["HullCollision",Vector3(0,-0.02,-0.23),Vector3(0.28,0.32,0.26)],
		["HullCollision1",Vector3(0,0,0.05),Vector3(0.34,0.40,0.30)],
		["HullCollision2",Vector3(0,0.04,0.30),Vector3(0.25,0.30,0.26)],
		["LeftPodCollision",Vector3(0.223,-0.0094,-0.104),Vector3(0.16,0.166,0.183)],
		["RightPodCollision",Vector3(-0.223,-0.0094,-0.104),Vector3(0.16,0.166,0.183)]
	]:
		var points := PackedVector3Array()
		for x in [-0.5,0.5]:
			for y in [-0.5,0.5]:
				for z in [-0.5,0.5]: points.append(entry[1] + entry[2] * Vector3(x,y,z))
		result.append({"name": entry[0],"points": points})
	return result
