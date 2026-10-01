extends RefCounted

# Stored-pose preview: two pose transitions per second at 1x, in file order.
# Original animation scheduling remains unresolved.
static func collect(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh.get_blend_shape_count() > 0:
		meshes.append(node)
	for child in node.get_children(): collect(child, meshes)

static func apply(meshes: Array[MeshInstance3D], time: float) -> void:
	for instance in meshes:
		var count: int = instance.mesh.get_blend_shape_count() + 1
		var phase := fposmod(time * 2.0, float(count))
		var current := int(floor(phase))
		var next: int = (current + 1) % count
		var weight := phase - current
		for pose in range(1, count):
			var value := (1.0 - weight if pose == current else 0.0) + (weight if pose == next else 0.0)
			instance.set_blend_shape_value(pose - 1, value)
