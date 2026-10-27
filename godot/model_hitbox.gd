extends RefCounted

# Shared by live swimming wildlife and the resource viewer. Transforms include
# the visual root so centring, mod orientation and instance scale agree.
static func fitted_hull(visual: Node3D) -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	_collect_vertices(visual,visual.transform,points)
	if points.size() < 4: return null
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	hull.margin = 0.005
	return hull

static func _collect_vertices(node: Node3D, pose: Transform3D, points: PackedVector3Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for vertex in _vertices(node.mesh):
			var point := pose * vertex
			if point.is_finite(): points.append(point)
	for child in node.get_children():
		if child is Node3D: _collect_vertices(child,pose * child.transform,points)

static func _vertices(mesh: Mesh) -> PackedVector3Array:
	# Shared immutable model geometry: reading renderer-owned vertex buffers
	# for every fish can synchronise with the GPU. Keep one CPU copy per mesh.
	if mesh.has_meta("collision_vertices"): return mesh.get_meta("collision_vertices")
	var points := PackedVector3Array()
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if not arrays.is_empty(): points.append_array(arrays[Mesh.ARRAY_VERTEX])
	mesh.set_meta("collision_vertices",points)
	return points

static func prewarm(node: Node3D) -> void:
	if node is MeshInstance3D and node.mesh != null: _vertices(node.mesh)
	for child in node.get_children():
		if child is Node3D: prewarm(child)
