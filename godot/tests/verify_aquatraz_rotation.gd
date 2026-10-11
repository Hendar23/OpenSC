extends SceneTree
const Scenery = preload("res://scenery_loader.gd")
const Document = preload("res://map_document.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	preload("res://mod_registry.gd").initialize(false)
	var folder := preload("res://asset_paths.gd").find_game_folder()
	var world := Node3D.new(); root.add_child(world)
	var tables := Scenery.read_database(folder.path_join("DATA/SCEN1.DDB"))
	var cache := {}
	var city: Node3D
	for row in tables.Cities:
		if str(row.get("clump","")).to_upper() != "AQUATRAZ": continue
		check(Scenery._place_prop(world,row,"AQUATRAZ",Vector3.ZERO,folder,cache,true),"Original Aquatraz placement loads")
		city = world.get_child(-1)
	check(city != null,"Original database contains Aquatraz")
	if city == null: quit(1); return
	var motion := city.get_node("SceneryRotation")
	motion.set_physics_process(false)
	var placement := city.transform
	var frame: Node3D = city.get_node("Frame_0")
	var rest := frame.transform
	var collision: Node3D = city.get_node("SceneryCollision")
	check(city.get_meta("city_id") == 5 and collision is StaticBody3D,"Dock identity and collision lookup remain intact")
	motion._physics_process(1.0)
	var spin := Transform3D(Basis(Vector3.UP,deg_to_rad(25.0)),Vector3.ZERO)
	check(frame.transform.is_equal_approx(spin * rest),"Original clump turns 25 degrees about vertical in one second")
	check(collision.transform.is_equal_approx(spin),"Collision follows rotating top")
	check(city.transform.is_equal_approx(placement),"Authored map placement stays fixed")
	for tick in range(59): motion._physics_process(1.0)
	check(frame.basis.is_equal_approx(Basis(Vector3.UP,deg_to_rad(60.0)) * rest.basis),"Rotation wraps without drift after a minute")
	var modern := Node3D.new(); var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); mesh.position = Vector3(2,1,0); modern.add_child(mesh); world.add_child(modern)
	Scenery.add_model_motion(modern,"AQUATRAZ"); Scenery.add_model_motion(modern,"AQUATRAZ")
	var modern_motion := modern.get_node("SceneryRotation"); modern_motion.set_physics_process(false)
	Scenery._add_prop_collision(modern)
	var modern_rest := mesh.transform
	modern_motion._physics_process(1.0)
	check(mesh.transform.is_equal_approx(spin * modern_rest),"Modern replacement meshes rotate around original pivot")
	check(modern.get_node("SceneryCollision").transform.is_equal_approx(spin),"Collision added after loading is included")
	check(modern.get_child_count() == 3,"Motion attachment is idempotent")
	var added := Document.load_model("AQUATRAZ",folder,true); world.add_child(added)
	check(added.has_node("SceneryRotation"),"Editor-added Aquatraz models get the same motion")
	var added_motion := added.get_node("SceneryRotation")
	paused = true
	var before: float = added_motion.angle
	for tick in range(3): await physics_frame
	check(added_motion.angle == before,"Dock/world pause also pauses rotation")
	paused = false
	for tick in range(3): await physics_frame
	check(added_motion.angle > before,"Rotation resumes with world")
	var plain := Node3D.new(); Scenery.add_model_motion(plain,"DOCKING")
	check(plain.get_child_count() == 0,"Other buildings remain unchanged"); plain.free()
	if DisplayServer.get_name() != "headless":
		var faces := PackedVector3Array(); Scenery._collect_faces(city,city.transform,faces)
		var bounds := AABB(faces[0],Vector3.ZERO)
		for vertex in faces: bounds = bounds.expand(vertex)
		var camera := Camera3D.new(); world.add_child(camera)
		var width := maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
		camera.position = bounds.get_center() + Vector3(1,0.6,1).normalized() * width * 2
		camera.look_at(bounds.get_center()); camera.current = true
		var light := DirectionalLight3D.new(); world.add_child(light); light.rotation_degrees = Vector3(-40,-30,0)
		for degrees in [0,20]:
			motion.angle = deg_to_rad(degrees); motion._physics_process(0.0)
			await process_frame; await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../dist/aquatraz-%d.png" % degrees)
	for template in cache.values(): template.free()
	world.free()
	print("Aquatraz rotation: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
