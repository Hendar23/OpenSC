extends SceneTree
const World = preload("res://world_loader.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func add_triangle(world: Node3D, cell: Vector2i, offset: Vector3, cutout: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.mesh = ArrayMesh.new(); node.position = offset
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(0,0,1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2])
	node.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := StandardMaterial3D.new()
	if cutout: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	node.mesh.surface_set_material(0,material); node.set_meta("terrain_cell",cell); world.add_child(node)
	return node
func ray(world: Node3D, x: float, layer: int, below: bool = false) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x,-2 if below else 4,0),Vector3(x,4 if below else -2,0),layer)
	q.hit_back_faces = true
	return world.get_world_3d().direct_space_state.intersect_ray(q)
func run() -> void:
	var world := Node3D.new(); root.add_child(world); world.set_meta("surface_height",10.0)
	var floor_mesh := add_triangle(world,Vector2i.ZERO,Vector3.ZERO,false)
	var leaf := add_triangle(world,Vector2i.ZERO,Vector3(0,2,0),true)
	add_triangle(world,Vector2i(2,0),Vector3(96,1,0),false)
	var geometry := hash(floor_mesh.mesh.surface_get_arrays(0)); var leaf_material := leaf.mesh.surface_get_material(0)
	await World.add_collision(world,self,func(_message: String) -> void: pass)
	await physics_frame; await physics_frame
	var body := world.get_node("WorldCollision"); var shelter := world.get_node("TerrainLightCollision")
	check(body.get_child_count() == 2 and shelter.get_child_count() == 2,"Different terrain materials share one collision shape per spatial cell")
	check(body.get_child(0).shape.get_faces().size() == 6 and shelter.get_child(0).shape.get_faces().size() == 3,"Shelter excludes cutout surfaces while physical collision retains them")
	check(body.get_child(1).shape == shelter.get_child(1).shape,"Entirely solid chunks share their shape resource between collision layers")
	var hit := ray(world,0,1); check(not hit.is_empty() and is_equal_approx(hit.position.y,2.0),"Physical rays hit cutout geometry")
	hit = ray(world,0,16); check(not hit.is_empty() and is_equal_approx(hit.position.y,0.0),"Cave/light rays pass through leaves and hit opaque terrain")
	hit = ray(world,96,1); check(not hit.is_empty() and is_equal_approx(hit.position.y,1.0),"Indexed geometry retains its transformed world position")
	hit = ray(world,0,16,true); check(not hit.is_empty() and is_equal_approx(hit.position.y,0.0),"Legacy reverse-winding terrain remains hittable from below")
	check(hash(floor_mesh.mesh.surface_get_arrays(0)) == geometry and leaf.mesh.surface_get_material(0) == leaf_material,"Collision grouping leaves render geometry and materials untouched")
	await World.add_collision(world,self,func(_message: String) -> void: pass)
	check(body.get_child_count() == 2 and world.get_child_count() == 6,"Repeated collision setup creates no duplicate shapes or water boundary")
	world.free(); print("Terrain collision: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
