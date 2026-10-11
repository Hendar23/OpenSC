extends RefCounted

const Mods = preload("res://mod_registry.gd")
static var cached_path := ""
static var cached_mesh: Mesh

# Shared by the instanced propeller wake and CPU death particles. Model
# replacements remain optional; texture.BUBBLE mods retain their old behavior.
static func replacement() -> Mesh:
	Mods.ensure()
	for descriptor in Mods.candidates("model.bubble"):
		var key := str(descriptor.path) + ":" + str(descriptor.scale)
		if key == cached_path and cached_mesh != null: return cached_mesh
		var scene := preload("res://modern_model.gd").load_model(descriptor.path, descriptor)
		if scene == null: continue
		var meshes: Array[Dictionary] = []
		_collect(scene, Transform3D.IDENTITY, meshes)
		if meshes.size() != 1:
			Mods.note(descriptor.name + ": bubble model must contain one mesh.")
			scene.free(); continue
		var entry: Dictionary = meshes[0]
		var result := ArrayMesh.new()
		for surface in entry.mesh.get_surface_count():
			var arrays: Array = entry.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for index in vertices.size(): vertices[index] = entry.pose * vertices[index]
			for index in normals.size(): normals[index] = (entry.pose.basis.inverse().transposed() * normals[index]).normalized()
			arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var original: Material = entry.mesh.surface_get_material(surface)
			var material := ShaderMaterial.new()
			material.shader = preload("res://bubble_surface.gdshader")
			if original is BaseMaterial3D and original.albedo_texture != null:
				material.set_shader_parameter("surface_texture", original.albedo_texture)
				material.set_shader_parameter("has_texture", true)
			result.surface_set_material(surface, material)
		scene.free()
		cached_path = key; cached_mesh = result
		return result
	return null

static func _collect(node: Node3D, parent_pose: Transform3D, meshes: Array[Dictionary]) -> void:
	var pose := parent_pose * node.transform
	if node is MeshInstance3D and node.mesh != null: meshes.append({"mesh": node.mesh, "pose": pose})
	for child in node.get_children():
		if child is Node3D: _collect(child, pose, meshes)

static func death_mesh(texture: Texture2D) -> Mesh:
	var model := replacement()
	if model != null: return model
	var quad := QuadMesh.new(); quad.size = Vector2.ONE
	quad.material = preload("res://natural_light.gd").billboard_material(texture)
	return quad
