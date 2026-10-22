extends SceneTree

const Assets = preload("res://clump_loader.gd")
const World = preload("res://world_loader.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	preload("res://asset_cache.gd").enabled = false
	call_deferred("_run")

func check_front_faces(mesh: Mesh, label: String, minimum_agreement: float = 0.99) -> void:
	var aligned := 0
	var reversed := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for index in range(vertices.size()): indices.append(index)
		for index in range(0, indices.size(), 3):
			var a := indices[index]
			var b := indices[index + 1]
			var c := indices[index + 2]
			# Godot uses clockwise front faces. Two-sided materials invert
			# backface normals, so reversed winding lights the wrong side.
			var front := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a]).normalized()
			var normal := (normals[a] + normals[b] + normals[c]).normalized()
			var agreement := front.dot(normal)
			if agreement > 0.1: aligned += 1
			elif agreement < -0.1: reversed += 1
	checks += 1
	# Smoothed terrain normals can disagree at sharp folds. Check the
	# predominant orientation there, and require near-total agreement on
	# the submarine and dock, whose authored normals follow their faces.
	if aligned == 0 or float(aligned) / float(aligned + reversed) < minimum_agreement:
		failures += 1
		push_error("%s: %d faces agree with normals, %d face backwards" % [label, aligned, reversed])

func _run() -> void:
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = preload("res://asset_paths.gd").find_game_folder()
	for file in ["DOCKING", "SUB"]:
		var model := Assets._load_legacy(folder.path_join("CLUMPS/" + file + ".DFF"))
		if model == null:
			failures += 1
			continue
		for node in model.find_children("*", "MeshInstance3D", true, false):
			check_front_faces(node.mesh, file + "/" + str(node.name))
		model.free()
	var world := await World.load_world(folder.path_join("DATA/SCEN1.BSP"), self, func(_message: String) -> void: pass)
	if world == null:
		failures += 1
	else:
		root.add_child(world)
		var lids: Array[MeshInstance3D] = []
		for node in world.get_children():
			if node is MeshInstance3D: check_front_faces(node.mesh, str(node.name), 0.5)
			if node.get_meta("terrain_material",-1) == 89: lids.append(node)
		checks += 1
		if lids.is_empty() or not lids.all(func(lid: MeshInstance3D) -> bool: return lid.get_active_material(0).cull_mode == BaseMaterial3D.CULL_BACK):
			failures += 1; push_error("Can lid opposite-facing coplanar faces must be culled")
		var light := preload("res://natural_light.gd").new(); light.attach(world)
		checks += 1
		if not lids.all(func(lid: MeshInstance3D) -> bool: return lid.get_active_material(0).get_shader_parameter("cull_backfaces") == true):
			failures += 1; push_error("Natural lighting must preserve can-lid backface culling")
		world.free()
	print("Lighting verification: %d meshes, %d failures" % [checks, failures])
	quit(1 if failures else 0)
