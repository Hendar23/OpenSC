extends RefCounted
## The Buried Pipe is a clipped, straight cylinder in SCEN1's PIPE material.

const BURIED := AABB(Vector3(213.0, 150.3, 176.55), Vector3(3.3, 2.9, 10.9))
const AXIS := Vector2(214.631, 151.485)
const STEPS := 4
const SIDES := [Vector2i(1, 2), Vector2i(2, 0), Vector2i(0, 1)]

static func apply(world: Node3D, pattern: Callable) -> bool:
	var changed := false
	for node in world.get_children():
		if not node is MeshInstance3D or node.get_meta("terrain_texture", "") != "PIPE": continue
		if node.has_meta("terrain_pipe_rounded") or not node.mesh.get_aabb().intersects(BURIED): continue
		var geometry := refine(node.mesh.surface_get_arrays(0), pattern)
		if geometry.is_empty(): continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, geometry)
		mesh.surface_set_material(0, node.mesh.surface_get_material(0))
		node.mesh = mesh
		node.set_meta("terrain_pipe_rounded", true)
		changed = true
	return changed

static func refine(source: Array, pattern: Callable) -> Array:
	var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
	var counts := {}
	var faces := {}
	for i in range(0, points.size(), 3):
		if not BURIED.has_point(points[i]) or not BURIED.has_point(points[i+1]) or not BURIED.has_point(points[i+2]): continue
		var edges := []
		for side: Vector2i in SIDES:
			var a := points[i + side.x]
			var b := points[i + side.y]
			var key := [a, b] if a < b else [b, a]
			edges.append(key)
			counts[key] = int(counts.get(key, 0)) + 1
		faces[i] = edges
	if faces.is_empty(): return []
	var vertices := PackedVector3Array()
	var vertex_normals := PackedVector3Array()
	var texture := PackedVector2Array()
	for i in range(0, points.size(), 3):
		if not faces.has(i):
			for j in 3:
				vertices.append(points[i+j])
				vertex_normals.append(normals[i+j])
				texture.append(uvs[i+j])
			continue
		var edges: Array = faces[i]
		var locked := 0
		for edge in 3:
			if counts[edges[edge]] != 2: locked |= 1 << edge
		var layout: Dictionary = pattern.call(locked, STEPS)
		var samples := PackedVector3Array()
		var directions := PackedVector3Array()
		var coordinates := PackedVector2Array()
		var radii := Vector3(_radial(points[i]).length(), _radial(points[i+1]).length(), _radial(points[i+2]).length())
		for bary: Vector3i in layout.weights:
			var w := Vector3(bary) / float(STEPS)
			var point := points[i] * w.x + points[i+1] * w.y + points[i+2] * w.z
			var normal := (normals[i] * w.x + normals[i+1] * w.y + normals[i+2] * w.z).normalized()
			if maxi(bary.x, maxi(bary.y, bary.z)) < STEPS:
				var radius := radii.dot(w)
				if bary.x == 0 or bary.y == 0 or bary.z == 0:
					var edge := 0 if bary.x == 0 else 1 if bary.y == 0 else 2
					var side: Vector2i = SIDES[edge]
					var a: Vector3 = edges[edge][0]
					var b: Vector3 = edges[edge][1]
					var t := w[side.y] if points[i + side.x] == a else w[side.x]
					point = a.lerp(b, t)
					radius = lerpf(_radial(a).length(), _radial(b).length(), t)
				var radial := _radial(point).normalized()
				var curved := AXIS + radial * radius
				point = Vector3(curved.x, curved.y, point.z)
				var surface := Vector3(radial.x, radial.y, 0.0)
				normal = surface if surface.dot(normal) >= 0.0 else -surface
			samples.append(point)
			directions.append(normal)
			coordinates.append(uvs[i] * w.x + uvs[i+1] * w.y + uvs[i+2] * w.z)
		for index: int in layout.indices:
			vertices.append(samples[index])
			vertex_normals.append(directions[index])
			texture.append(coordinates[index])
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = vertices
	result[Mesh.ARRAY_NORMAL] = vertex_normals
	result[Mesh.ARRAY_TEX_UV] = texture
	return result

static func _radial(point: Vector3) -> Vector2:
	return Vector2(point.x, point.y) - AXIS
