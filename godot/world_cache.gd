extends RefCounted
## Signatures of the actual inputs to derived world data, independent of textures,
## decorative batches, scene names, instance IDs and player save state.
const Cache = preload("res://asset_cache.gd")

static func digest(value: Variant) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

static func terrain_signature(world: Node3D) -> String:
	var records: Array = [world.get_meta("bounds", AABB()), world.get_meta("surface_height", 0.0)]
	for node in world.get_children():
		if node is MeshInstance3D and node.mesh != null and node.name != "WaterSurface":
			records.append([node.transform, digest(node.mesh.get_faces())])
	return digest(records)

static func collision_signature(world: Node3D, mask: int) -> String:
	var records: Array = [world.get_meta("bounds", AABB()), world.get_meta("surface_height", 0.0)]
	var shapes := {}
	for body in [world] + world.find_children("*", "PhysicsBody3D", true, false):
		if not body is PhysicsBody3D or (body.collision_layer & mask) == 0: continue
		var pose: Transform3D = body.global_transform if body.is_inside_tree() else body.transform
		for owner_id in body.get_shape_owners():
			if body.is_shape_owner_disabled(owner_id): continue
			for index in body.shape_owner_get_shape_count(owner_id):
				var shape: Shape3D = body.shape_owner_get_shape(owner_id, index)
				if not shapes.has(shape):
					var values: Array = [shape.get_class()]
					for property in shape.get_property_list():
						if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0 or str(property.name).begins_with("resource_") or property.name == "script": continue
						var value: Variant = shape.get(property.name)
						# Unknown custom resource-backed shapes cannot safely be cached.
						if value is Object: return ""
						values.append([property.name, value])
					shapes[shape] = digest(values)
				records.append([body.collision_layer & mask, pose * body.shape_owner_get_transform(owner_id), shapes[shape]])
	return digest(records)
