extends RefCounted
## Curved shells and annular rims of the original west, south and sandy outlets.

const PROFILES := [
	{"bounds": AABB(Vector3(181.3,156.2,207.4), Vector3(5.25,5.25,5.35)), "center": Vector3(0,158.807,210.081), "axis": 0, "mouth": 186.423, "buried": 181.418},
	{"bounds": AABB(Vector3(252.7,156.2,289.2), Vector3(5.3,5.3,7.45)), "center": Vector3(255.323,158.807,0), "axis": 2, "mouth": 289.309, "buried": 296.502},
	{"bounds": AABB(Vector3(241.7,158.25,109.8), Vector3(5.3,5.3,14.7)), "center": Vector3(244.356,160.903,0), "axis": 2, "mouth": 124.319, "buried": 109.934},
]
const STEPS := 4
const SIDES := [Vector2i(1, 2), Vector2i(2, 0), Vector2i(0, 1)]

static func apply(world: Node3D, pattern: Callable) -> bool:
	var changed := false
	for node in world.get_children():
		if not node is MeshInstance3D or not node.has_meta("terrain_material") or node.get_meta("terrain_texture", "") not in ["PIPE", "METALLY", ""]: continue
		for profile: Dictionary in PROFILES:
			if not node.mesh.get_aabb().intersects(profile.bounds): continue
			var geometry := refine(node.mesh.surface_get_arrays(0), pattern, profile)
			if geometry.is_empty(): continue
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, geometry)
			mesh.surface_set_material(0, node.mesh.surface_get_material(0))
			node.mesh = mesh
			changed = true
	return changed

static func refine(source: Array, pattern: Callable, profile: Dictionary) -> Array:
	var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
	var counts := {}
	var faces := {}
	for i in range(0, points.size(), 3):
		if not profile.bounds.has_point(points[i]) or not profile.bounds.has_point(points[i+1]) or not profile.bounds.has_point(points[i+2]): continue
		var radial_sizes := Vector3(_radial(points[i], profile).length(), _radial(points[i+1], profile).length(), _radial(points[i+2], profile).length())
		if minf(radial_sizes.x, minf(radial_sizes.y, radial_sizes.z)) < 1.85: continue
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
			var a: Vector3 = edges[edge][0]
			var b: Vector3 = edges[edge][1]
			var mouth_edge := absf(a[profile.axis] - profile.mouth) < 0.03 and absf(b[profile.axis] - profile.mouth) < 0.03
			if counts[edges[edge]] < 2 and not mouth_edge: locked |= 1 << edge
		var layout: Dictionary = pattern.call(locked, STEPS)
		var samples := PackedVector3Array()
		var directions := PackedVector3Array()
		var coordinates := PackedVector2Array()
		for bary: Vector3i in layout.weights:
			var w := Vector3(bary) / float(STEPS)
			var point := points[i] * w.x + points[i+1] * w.y + points[i+2] * w.z
			var normal := (normals[i] * w.x + normals[i+1] * w.y + normals[i+2] * w.z).normalized()
			if maxi(bary.x, maxi(bary.y, bary.z)) < STEPS:
				if bary.x == 0 or bary.y == 0 or bary.z == 0:
					var edge := 0 if bary.x == 0 else 1 if bary.y == 0 else 2
					var side: Vector2i = SIDES[edge]
					var a: Vector3 = edges[edge][0]
					var b: Vector3 = edges[edge][1]
					var t := w[side.y] if points[i + side.x] == a else w[side.x]
					point = a.lerp(b, t)
			# BSP cuts introduce vertices partway across a flat panel. Recover
			# its circular radius at every sample, including those cut vertices.
			var radial := _radial(point, profile)
			var angle := atan2(radial.z, radial.y) if profile.axis == 0 else atan2(radial.x, radial.y)
			var half_panel := PI / 12.0
			var panel := fposmod(angle, half_panel * 2.0) - half_panel
			var blend := smoothstep(0.0, 0.5, absf(point[profile.axis] - profile.buried))
			point += radial * (cos(panel) / cos(half_panel) - 1.0) * blend
			var axial := Vector3.ZERO
			axial[profile.axis] = normal[profile.axis]
			var direction := radial.normalized()
			normal = (axial + direction * normal.dot(direction)).normalized()
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

static func _radial(point: Vector3, profile: Dictionary) -> Vector3:
	var offset: Vector3 = point - profile.center
	offset[profile.axis] = 0.0
	return offset
