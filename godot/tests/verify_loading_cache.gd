extends "res://tests/test_scene_tree.gd"
const Cache = preload("res://asset_cache.gd")
const Keys = preload("res://world_cache.gd")
const Light = preload("res://natural_light.gd")
const Map = preload("res://hud_map.gd")
const Traffic = preload("res://submarine_traffic.gd")
var checks := 0
var failures := 0
func _init() -> void: Cache.enabled = true
func _initialize() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-loading-fixtures"
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func graph_data(traffic: Node) -> Array:
	var rows: Array = []
	for id in traffic.graph.get_point_ids(): rows.append([id, traffic.graph.get_point_position(id), traffic.graph.get_point_connections(id)])
	return rows
func navigation(world: Node3D, map: RefCounted) -> Node:
	var traffic := Traffic.new(); world.add_child(traffic); traffic.set_physics_process(false)
	traffic.map = map; traffic.space = world.get_world_3d().direct_space_state; traffic.probe.radius = 0.9
	traffic.width = 4; traffic.depth = 4; traffic.cruise = 8.0
	traffic._prepare_navigation_cache(world)
	while not traffic.navigation_ready: traffic.build_graph(128)
	return traffic
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	world.set_meta("bounds", AABB(Vector3(-64,-1,-64),Vector3(128,11,128))); world.set_meta("surface_height",10.0)
	var floor := MeshInstance3D.new(); floor.mesh = BoxMesh.new(); floor.mesh.size = Vector3(128,1,128); floor.position.y = -0.5; world.add_child(floor)
	var body := StaticBody3D.new(); body.collision_layer = 17; world.add_child(body)
	var shape := CollisionShape3D.new(); shape.shape = BoxShape3D.new(); shape.shape.size = Vector3(128,1,128); shape.position.y = -0.5; body.add_child(shape)
	await physics_frame; await physics_frame
	var rotating := Node3D.new(); world.add_child(rotating)
	var part := Node3D.new(); rotating.add_child(part)
	var motion := preload("res://scenery_rotation.gd").new(); rotating.add_child(motion); motion.set_physics_process(false)
	world.set_meta("world_loading",true); motion._physics_process(1.0)
	check(motion.angle == 0.0 and part.transform == Transform3D.IDENTITY,"Loading keeps rotating scenery at authored pose")
	world.remove_meta("world_loading"); motion._physics_process(1.0)
	check(motion.angle > 0.0 and part.transform != Transform3D.IDENTITY,"Scenery motion resumes after loading")
	rotating.free()
	var original_key := Keys.collision_signature(world,17)
	body.name = "Renamed"; check(original_key == Keys.collision_signature(world,17),"Names do not invalidate geometry")
	shape.position.y += 1
	check(original_key != Keys.collision_signature(world,17),"Moved collision invalidates derived data")
	shape.position.y -= 1; shape.shape.size.x = 7
	check(original_key != Keys.collision_signature(world,17),"Changed shape geometry invalidates derived data")
	shape.shape.size.x = 128; shape.disabled = true
	check(original_key != Keys.collision_signature(world,17),"Disabled collision invalidates derived data")
	shape.disabled = false; body.collision_layer = 1
	check(original_key != Keys.collision_signature(world,17),"Changed cave collision mask invalidates derived data")
	body.collision_layer = 17
	var terrain_key := Keys.terrain_signature(world)
	floor.mesh.material = StandardMaterial3D.new()
	check(terrain_key == Keys.terrain_signature(world),"Texture/material changes do not invalidate height data")
	floor.position.y += 1; check(terrain_key != Keys.terrain_signature(world),"Moved terrain invalidates height data"); floor.position.y -= 1
	await physics_frame; await physics_frame
	var lighting := Light.new(); await lighting.build(world,Callable(),16)
	var overhead := lighting.image.get_data(); var slices: Array = []
	for slice in lighting.light_slices: slices.append(slice.get_data())
	var hits := Cache.hits; var again := Light.new(); await again.build(world,Callable(),16)
	check(Cache.hits == hits + 1,"Lighting reuses persisted data")
	check(again.image.get_data() == overhead,"Cached sunlight is byte-identical")
	var identical := true
	for index in slices.size():
		if again.light_slices[index].get_data() != slices[index]: identical = false
	check(identical,"Cached cave light is byte-identical")
	var map := Map.new(); await map.setup_async(world,1.1,self)
	var second := Map.new(); hits = Cache.hits; second.setup(world,1.1)
	check(Cache.hits == hits + 1,"Synchronous/editor map setup consumes async-built cache")
	check(map.height_samples == second.height_samples and map.blocked_samples == second.blocked_samples and map.texture.get_image().get_data() == second.texture.get_image().get_data(),"Cached map preserves heights, passage blocking and pixels")
	hits = Cache.hits; var other_clearance := Map.new(); other_clearance.setup(world,2.0)
	check(Cache.hits == hits,"Passage-clearance change invalidates map data")
	var traffic := navigation(world,map); var expected := graph_data(traffic)
	check(not expected.is_empty(),"Navigation fixture has routes")
	hits = Cache.hits; var restored := navigation(world,map)
	check(Cache.hits == hits + 1 and graph_data(restored) == expected,"Navigation restores point, neighbour and cell ordering")
	var same_routes := true
	for a in traffic.graph.get_point_ids():
		for b in traffic.graph.get_point_ids():
			if traffic.graph.get_id_path(a,b) != restored.graph.get_id_path(a,b): same_routes = false
	check(same_routes,"Every cached fixture route matches fresh routing")
	# A damaged derived entry must regenerate through the ordinary algorithm.
	var key := Cache.key("world-map",[],[Keys.terrain_signature(world),1.1,Map.RESOLUTION,Map.PASSAGE_MARGIN])
	var file := FileAccess.open(Cache.path_for(key,"bin"),FileAccess.WRITE); file.store_string("damaged"); file.close()
	var recovered := Map.new(); recovered.setup(world,1.1)
	check(recovered.height_samples == map.height_samples and recovered.blocked_samples == map.blocked_samples,"Corrupt map cache rebuilds without altering results")
	world.free()
	var plants := preload("res://plant_current.gd").new()
	var bounded := true
	for index in 3:
		var holder := Node3D.new(); root.add_child(holder)
		var plant := MeshInstance3D.new(); plant.mesh = BoxMesh.new(); plant.mesh.material = StandardMaterial3D.new(); plant.set_meta("editor_model","REED"); holder.add_child(plant)
		plants.attach(holder); holder.free()
		if plants.flexible_meshes.size() != 1: bounded = false
	check(bounded,"Full world replacement releases old flexible meshes")
	var doc := preload("res://map_document.gd")
	var path := "res://tests/cache-loading-fixtures/map.json"
	check(doc.save(doc.empty(),path) == OK,"Valid authored map saves")
	var before := FileAccess.get_file_as_bytes(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	check(doc.save(doc.empty(),path) != OK and FileAccess.get_file_as_bytes(path) == before,"Failed temporary-file open preserves existing map")
	DirAccess.remove_absolute(path + ".tmp")
	print("Loading cache: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
