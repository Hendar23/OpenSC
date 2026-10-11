extends SceneTree

func _initialize() -> void: call_deferred("run")
func run() -> void:
	var source := preload("res://modern_model.gd").load_model("res://../Other resources/bubbles/free_bubble_kit.glb")
	var node := source.find_child("Object_11", true, false) as MeshInstance3D
	if node == null: push_error("Bubble variant not found"); quit(1); return
	var arrays := node.mesh.surface_get_arrays(0)
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(60, 60, [])
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for lod in importer.get_surface_lod_count(0):
		var candidate := importer.get_surface_lod_indices(0, lod)
		print("Bubble LOD: ", candidate.size() / 3, " triangles")
		if candidate.size() >= 2100: indices = candidate
	var compact := []; compact.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var uv := PackedVector2Array(); var remap := {}; var triangles := PackedInt32Array()
	for index in indices:
		if not remap.has(index):
			remap[index] = vertices.size()
			vertices.append(arrays[Mesh.ARRAY_VERTEX][index] / 2.000004)
			normals.append(arrays[Mesh.ARRAY_NORMAL][index])
			uv.append(arrays[Mesh.ARRAY_TEX_UV][index])
		triangles.append(remap[index])
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices: bounds = bounds.expand(vertex)
	for index in vertices.size(): vertices[index] = (vertices[index] - bounds.get_center()) / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	compact[Mesh.ARRAY_VERTEX] = vertices; compact[Mesh.ARRAY_NORMAL] = normals; compact[Mesh.ARRAY_TEX_UV] = uv; compact[Mesh.ARRAY_INDEX] = triangles
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, compact)
	var material := node.get_active_material(0).duplicate() as StandardMaterial3D
	material.metallic = 0; material.vertex_color_use_as_albedo = true; material.albedo_color.a = 0.22
	mesh.surface_set_material(0, material)
	var bubble := MeshInstance3D.new(); bubble.name = "Bubble"; bubble.mesh = mesh
	var state := GLTFState.new(); var document := GLTFDocument.new()
	var result := document.append_from_scene(bubble, state)
	if result == OK: result = document.write_to_filesystem(state, "res://../Mods/3d-bubbles/bubble.glb")
	print("Isolated bubble: ", vertices.size(), " vertices, ", triangles.size() / 3, " triangles; export ", result)
	bubble.free(); source.free(); quit(0 if result == OK else 1)
