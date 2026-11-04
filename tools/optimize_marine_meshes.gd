extends SceneTree
## Offline worker for optimize_marine_models.py. Never edits the source GLB.

func _initialize() -> void:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=",true,1)
		if pair.size() == 2: options[pair[0]] = pair[1]
	if not options.has("--source") or not options.has("--output"):
		push_error("Expected --source and --output"); quit(1); return
	var output: String = options["--output"]
	DirAccess.make_dir_recursive_absolute(output)
	var document := GLTFDocument.new(); var state := GLTFState.new()
	if document.append_from_file(options["--source"],state) != OK: quit(1); return
	var report := []
	var mesh_index := -1
	for item in state.get_meshes():
		mesh_index += 1
		var mesh: ImporterMesh = item.mesh
		if mesh.get_surface_count() != 1: continue
		var arrays := mesh.get_surface_arrays(0)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.size()/3 < 12000: continue
		var box := mesh.get_mesh().get_aabb()
		mesh.generate_lods(60.0,25.0,[])
		if mesh.get_surface_lod_count(0) == 0: continue
		# Only the first (most detailed) generated level; refuse large transitions.
		var size := mesh.get_surface_lod_size(0,0)
		if size > 0.05: continue
		var reduced := mesh.get_surface_lod_indices(0,0)
		var prefix := output.path_join(str(mesh_index))
		FileAccess.open(prefix+".base.bin",FileAccess.WRITE).store_buffer(indices.to_byte_array())
		FileAccess.open(prefix+".indices.bin",FileAccess.WRITE).store_buffer(reduced.to_byte_array())
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		FileAccess.open(prefix+".positions.bin",FileAccess.WRITE).store_buffer(positions.to_byte_array())
		FileAccess.open(prefix+".uvs.bin",FileAccess.WRITE).store_buffer(uvs.to_byte_array())
		report.append({"mesh":mesh_index,"name":mesh.get_name(),"before":indices.size()/3,"after":reduced.size()/3,"lod_size":size,
			"source_aabb":[box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z]})
	FileAccess.open(output.path_join("plan.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("Conservative reduced meshes: ",report.size())
	quit()
