extends RefCounted
## Rounds SCEN1's tilted, ten-sided coin can in its own cross-section.

const BASE := Vector3(255.26346, 150.14713, 273.8194)
const AXIS := Vector3(0.6744, 0.73837, 0.0)
const SIDE := Vector3(-AXIS.y, AXIS.x, 0.0)
const BOUNDS := AABB(Vector3(253.9, 149.0, 271.9), Vector3(6.7, 7.0, 4.0))
const HALF_PANEL := PI / 10.0
const FIRST_PANEL := 0.0122
const STEPS := 4
const EDGES := [Vector2i(1, 2), Vector2i(2, 0), Vector2i(0, 1)]

static func apply(world: Node3D, pattern: Callable) -> bool:
	var shells: Array[MeshInstance3D] = []
	var neighbors: Array[MeshInstance3D] = []
	var corners := {}
	for node in world.get_children():
		if not node is MeshInstance3D or not node.has_meta("terrain_material"): continue
		if not BOUNDS.intersects(node.mesh.get_aabb()): continue
		if node.get_meta("terrain_texture", "") == "CAN":
			if node.has_meta("terrain_can_rounded") or not BOUNDS.encloses(node.mesh.get_aabb()): continue
			shells.append(node)
			var source: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for point in source: corners[point] = _round_point(point)
		else:
			neighbors.append(node)
	if shells.is_empty(): return false
	var attached := {}
	for node in neighbors:
		# Move the original vertices shared with the lid, floor, or rock. Their
		# edges keep the same segmentation on both sides of the join.
		var arrays := node.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var changed := false
		for i in points.size():
			if not corners.has(points[i]): continue
			attached[points[i]] = true
			points[i] = corners[points[i]]
			changed = true
		if changed:
			arrays[Mesh.ARRAY_VERTEX] = points
			_replace_mesh(node, arrays)
	for node in shells:
		_replace_mesh(node, _shell(node.mesh.surface_get_arrays(0), attached, pattern))
		node.set_meta("terrain_can_rounded", true)
	return true

static func _replace_mesh(node: MeshInstance3D, arrays: Array) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, node.mesh.surface_get_material(0))
	node.mesh = mesh

static func _shell(source: Array, attached: Dictionary, pattern: Callable) -> Array:
	var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
	var positions := PackedVector3Array()
	var directions := PackedVector3Array()
	var coordinates := PackedVector2Array()
	for i in range(0, points.size(), 3):
		var locked := 0
		for j in 3:
			var edge: Vector2i = EDGES[j]
			if attached.has(points[i + edge.x]) and attached.has(points[i + edge.y]): locked |= 1 << j
		var layout: Dictionary = pattern.call(locked, STEPS)
		var samples := PackedVector3Array()
		var sample_normals := PackedVector3Array()
		var sample_uvs := PackedVector2Array()
		for bary: Vector3i in layout.weights:
			var w := Vector3(bary) / float(STEPS)
			var point := points[i] * w.x + points[i+1] * w.y + points[i+2] * w.z
			if maxi(bary.x, maxi(bary.y, bary.z)) < STEPS and (bary.x == 0 or bary.y == 0 or bary.z == 0):
				var side := 0 if bary.x == 0 else 1 if bary.y == 0 else 2
				var edge: Vector2i = EDGES[side]
				var a := points[i + edge.x]
				var b := points[i + edge.y]
				point = a.lerp(b, w[edge.y]) if a < b else b.lerp(a, w[edge.x])
			var normal := (normals[i] * w.x + normals[i+1] * w.y + normals[i+2] * w.z).normalized()
			samples.append(_round_point(point))
			sample_normals.append(_round_normal(point, normal))
			sample_uvs.append(uvs[i] * w.x + uvs[i+1] * w.y + uvs[i+2] * w.z)
		for index: int in layout.indices:
			positions.append(samples[index])
			directions.append(sample_normals[index])
			coordinates.append(sample_uvs[index])
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = positions
	result[Mesh.ARRAY_NORMAL] = directions
	result[Mesh.ARRAY_TEX_UV] = coordinates
	return result

static func _round_point(point: Vector3) -> Vector3:
	var offset := point - BASE
	var across := offset.dot(SIDE)
	var angle := atan2(offset.z, across)
	var panel := fposmod(angle - FIRST_PANEL + HALF_PANEL, HALF_PANEL * 2.0) - HALF_PANEL
	# Undo the chord of each flat panel without changing the can's tilt,
	# axial dimensions, rim dents, or the opening cut out by its peeled lid.
	var radial := SIDE * across + Vector3.BACK * offset.z
	# The original base overlaps the shell along partially split edges.
	var blend := smoothstep(0.02, 0.35, offset.dot(AXIS))
	return point + radial * (cos(panel) / cos(HALF_PANEL) - 1.0) * blend

static func _round_normal(point: Vector3, normal: Vector3) -> Vector3:
	var offset := point - BASE
	var radial := (SIDE * offset.dot(SIDE) + Vector3.BACK * offset.z).normalized()
	return (AXIS * normal.dot(AXIS) + radial * normal.dot(radial)).normalized()
