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
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			if arrays.is_empty(): continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := pose * vertex
				if point.is_finite(): points.append(point)
	for child in node.get_children():
		if child is Node3D: _collect_vertices(child,pose * child.transform,points)
