extends "res://tests/test_scene_tree.gd"
const Modern = preload("res://modern_model.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func fixture() -> GLTFState:
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-0.4,0.1,-0.3),Vector3(0.4,0.1,0.3),Vector3(0,0.8,0)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	var importer := ImporterMesh.new(); importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var gltf := GLTFMesh.new(); gltf.mesh=importer
	var meshes: Array[GLTFMesh] = [gltf]
	var state := GLTFState.new(); state.set_meshes(meshes); return state
func _initialize() -> void:
	preload("res://player_storage.gd").root_override="res://tests/cache-modern-bounds-fixtures"
	var state := fixture(); var mesh: ArrayMesh = state.get_meshes()[0].mesh.get_mesh()
	var original := mesh.get_aabb()
	check(Modern.source_bounds(mesh)==original,"Ordinary models retain their exact bounds")
	var expected := AABB(Vector3(-1,0,-1),Vector3(2,1,2))
	Modern._apply_source_bounds(state,{"meshes":[{"extras":{"osc_original_aabb":[-1,0,-1,2,1,2]}}]})
	check(Modern.source_bounds(mesh)==expected,"Optimized models retain source placement and animation bounds")
	check(mesh.custom_aabb==expected and mesh.get_aabb()==original,"Rendering culling expands while remaining geometry stays intact")
	check(Modern.source_bounds(mesh.duplicate())==expected,"Cached/shared mesh duplication retains the source bounds")
	var cache := "res://tests/cache-modern-bounds-fixtures/cache/assets/bounds.res"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache.get_base_dir()))
	check(ResourceSaver.save(mesh,cache)==OK,"Optimized mesh bounds can be written into an isolated asset cache")
	var stored := ResourceLoader.load(cache,"ArrayMesh",ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	check(stored!=null and Modern.source_bounds(stored)==expected and stored.custom_aabb==expected,"Disk-cached geometry retains exact source placement and culling bounds")
	mesh.set_meta("scenery_source_bounds","invalid")
	check(Modern.source_bounds(mesh)==original,"Malformed resource metadata falls back to actual bounds")
	for values in [null,[],[0,0,0,0,0,0],[0,0,0,1,-1,1],[-1,0,-1,2,INF,2],[-1,0,-1,2,"1",2],[-0.1,0,-0.1,0.2,1,0.2]]:
		state=fixture(); mesh=state.get_meshes()[0].mesh.get_mesh(); original=mesh.get_aabb()
		Modern._apply_source_bounds(state,{"meshes":[{"extras":{"osc_original_aabb":values}}]})
		check(Modern.source_bounds(mesh)==original and not mesh.has_meta("scenery_source_bounds"),"Invalid or clipping bounds cannot change placement/culling")
	state=fixture(); mesh=state.get_meshes()[0].mesh.get_mesh(); original=mesh.get_aabb()
	Modern._apply_source_bounds(state,{"meshes":[{"extras":"invalid"}]})
	check(Modern.source_bounds(mesh)==original,"Non-dictionary extras preserve the ordinary loader")
	print("Modern source bounds: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
