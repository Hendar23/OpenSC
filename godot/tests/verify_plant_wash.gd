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
	var sources: Array[Dictionary] = [{"position":Vector3.ZERO,"direction":Vector3.BACK,"power":1.0}]
	var near := current.wash_at(Vector3(0,0,0.5),sources)
	check(near.z > 0.1 and near.x == 0,"Nearby plants bend with the outgoing propeller stream")
	check(current.wash_at(Vector3(0,0,-0.5),sources) == Vector3.ZERO and current.wash_at(Vector3(2,0,0.5),sources) == Vector3.ZERO and current.wash_at(Vector3(0,0,10),sources) == Vector3.ZERO,"Plants ahead, outside the cone and beyond range are unaffected")
	check(current.wash_at(Vector3(0,0,3),sources).length() < near.length(),"Propeller wash weakens with distance")
	sources[0].power = 0.5
	check(is_equal_approx(current.wash_at(Vector3(0,0,0.5),sources).length(),near.length() * 0.5),"Wash scales with analogue propeller power")
	sources[0].power = 1.0; sources[0].direction = Vector3.FORWARD
	check(current.wash_at(Vector3(0,0,-0.5),sources).z < 0,"Reverse thrust blows plants in the opposite direction")
	sources[0].direction = Vector3.DOWN
	check(current.wash_at(Vector3(0,-0.5,0),sources).y < 0,"Tilted pods produce vertical wash")
	sources[0].direction = Vector3.BACK
	var material := ShaderMaterial.new(); material.shader = preload("res://plant_current.gdshader")
	current.patches = [{"point":Vector3(0,0,0.5),"materials":[material],"bend":Vector3.ZERO}]
	current.update_sources(sources,0.1)
	var bent: Vector3 = current.patches[0].bend
	check(bent.length() > 0 and bent.length() < near.length(),"Plant response bends smoothly instead of snapping")
	current.update_sources([],0.1)
	check(current.patches[0].bend.length() > 0 and current.patches[0].bend.length() < bent.length(),"Plants relax gradually after leaving the wash")
	for step in range(60): current.update_sources([],0.1)
	check(current.patches[0].bend == Vector3.ZERO and material.get_shader_parameter("propeller_bend") == Vector3.ZERO,"Plant wash eventually settles completely")
	current.settings.wash_strength = 0
	check(current.wash_at(Vector3(0,0,0.5),sources) == Vector3.ZERO,"Zero wash strength disables the effect")
	current.settings.wash_strength = 0.65
	var world := Node3D.new(); root.add_child(world); current.world = world
	var obstacle := StaticBody3D.new(); world.add_child(obstacle); obstacle.position.z = 0.25
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(1,1,0.1); shape.shape = box; obstacle.add_child(shape)
	await physics_frame; await physics_frame
	check(current.wash_at(Vector3(0,0,0.5),sources) == Vector3.ZERO,"Solid scenery shields plants from propeller wash")
	world.queue_free(); await process_frame
	print("Plant wash: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
