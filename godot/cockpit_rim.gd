extends RefCounted
## Fit the original console and adjacent hull faces to the same continuous rim
## as the remastered dome. Operate on the first-person copy of the hull only.

const CORNERS := 8
const EDGE_STEPS := 16


static func find_edges(mesh: Mesh, glazing: int, console: int = -1) -> Dictionary:
	for surface in range(mesh.get_surface_count()):
		if surface == glazing or (console != -1 and surface != console): continue
		var arrays := mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_INDEX] == null: continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.size() != CORNERS * 3: continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uses := {}
		for index in indices:
			var point := vertices[index]
			uses[point] = uses.get(point, 0) + 1
		if uses.size() != CORNERS + 1: continue
		var neighbours := {}
		for i in range(0, indices.size(), 3):
			var edge: Array[Vector3] = []
			for j in range(3):
				var point := vertices[indices[i + j]]
				if uses[point] == 2: edge.append(point)
			if edge.size() != 2: break
			for j in range(2):
				if not neighbours.has(edge[j]): neighbours[edge[j]] = []
				neighbours[edge[j]].append(edge[1 - j])
		if neighbours.size() == CORNERS and neighbours.values().all(
			func(points: Array) -> bool: return points.size() == 2 and points[0] != points[1]
		):
			return neighbours
	return {}


static func round_edges(arrays: Array, neighbours: Dictionary) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var original: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var triangles := PackedInt32Array()
	for offset in range(0, original.size(), 3):
		var rim_side := -1
		for side in range(3):
			var a := vertices[original[offset + side]]
			var b := vertices[original[offset + (side + 1) % 3]]
			if neighbours.has(a) and b in neighbours[a]:
				rim_side = side
				break
		if rim_side == -1:
			triangles.append_array(original.slice(offset, offset + 3))
			continue

		var start := original[offset + rim_side]
		var end := original[offset + (rim_side + 1) % 3]
		var apex := original[offset + (rim_side + 2) % 3]
		var a := vertices[start]
		var b := vertices[end]
		var before: Vector3 = neighbours[a][1] if neighbours[a][0] == b else neighbours[a][0]
		var after: Vector3 = neighbours[b][1] if neighbours[b][0] == a else neighbours[b][0]
		var last := start
		for step in range(1, EDGE_STEPS):
			var t := float(step) / EDGE_STEPS
			var next := vertices.size()
			vertices.append(a.cubic_interpolate(b, before, after, t))
			var normal := normals[start].lerp(normals[end], t).normalized()
			normals.append(normal)
			if not tangents.is_empty():
				var from := Vector3(tangents[start * 4], tangents[start * 4 + 1], tangents[start * 4 + 2])
				var to := Vector3(tangents[end * 4], tangents[end * 4 + 1], tangents[end * 4 + 2])
				var tangent := from.lerp(to, t).slide(normal).normalized()
				tangents.append_array([tangent.x, tangent.y, tangent.z, tangents[(start if t < 0.5 else end) * 4 + 3]])
			uvs.append(uvs[start].lerp(uvs[end], t))
			triangles.append_array([last, next, apex])
			last = next
		triangles.append_array([last, end, apex])

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = triangles
	return arrays
