extends SceneTree
const Current = preload("res://plant_current.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _run() -> void:
	var current := Current.new()
	var leaf := ArrayMesh.new(); var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.2,0,0),Vector3(0.2,0,0),Vector3(0,1,0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2(0.5,1)])
	leaf.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var flexible := current._flexible_mesh(leaf)
	check(flexible.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 48 and leaf.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 3,"Sparse leaves gain intermediate bending vertices without modifying original assets")
	check(current._flexible_mesh(leaf) == flexible,"Plant instances share the subdivided mesh")
	var modern := Node3D.new(); modern.set_meta("asset_source","res://plants/REED.glb"); modern.set_meta("modern_model",true); root.add_child(modern)
	var model := MeshInstance3D.new(); model.mesh = leaf; modern.add_child(model)
	current.attach(modern)
	check(model.mesh == leaf and leaf.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 3,"Modern plants keep their authored mesh and distance-detail buffers instead of being subdivided again")
	modern.free()
	print("Plant current: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
