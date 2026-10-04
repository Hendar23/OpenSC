extends SceneTree
const Fish = preload("res://fish_controller.gd")
const Population = preload("res://wildlife_population.gd")
const Document = preload("res://map_document.gd")
const Paths = preload("res://asset_paths.gd")
const Creatures = preload("res://creature_loader.gd")
const Capture = preload("res://capture_overlay.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func _run() -> void:
	var world := Node3D.new(); root.add_child(world)
	world.set_meta("surface_height",10.0)
	world.set_meta("bounds",AABB(Vector3(-20,-10,-20),Vector3(40,20,40)))
	var floor := StaticBody3D.new(); world.add_child(floor)
	floor.rotation.z = deg_to_rad(15)
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(30,1,30); shape.shape = box; floor.add_child(shape)
	var pop := Population.new(); pop.world = world; world.add_child(pop)
	await physics_frame; await physics_frame
	var model := Document.load_model("CRAB",Paths.find_game_folder(),true)
	var boxes: Array[AABB] = []; Creatures._collect_bounds(model,model.transform,boxes)
	var bounds := boxes[0]
	model.position -= bounds.get_center()
	var crab := Fish.new(); crab.setup(model,Vector3(0,2,0),world.get_meta("bounds"),10,0.7,1)
	crab.mobility = "crawling"; crab.population = pop; crab.configure_crawler(bounds.size)
	world.add_child(crab); crab.set_physics_process(false); crab._ground_on_terrain(1)
	check(crab.meshes.size() == 1 and crab.meshes[0].mesh.get_blend_shape_count() == 7,"Crab retains all eight original walking poses")
	check(crab.get_child(0).shape is BoxShape3D,"Crawlers use a body-shaped box instead of a swimming sphere")
	var contact: Dictionary = pop.floor_contact(crab.global_position)
	check(crab.basis.y.dot(contact.normal) > 0.999,"Crawler tilts to the terrain slope")
	check(absf((crab.global_position - Vector3(contact.position)).dot(contact.normal) - crab.ground_clearance) < 0.01 and crab.ground_clearance < 0.15,"Crab feet sit on the ground using model height")
	crab.animation.apply(0.25); var pose := crab.meshes[0].get_blend_shape_value(0)
	crab.animation.apply(1.25)
	check(not is_equal_approx(pose,crab.meshes[0].get_blend_shape_value(0)) and crab.walking_animation_rate == 2.0,"Original crab poses animate at a two-second walking cycle")
	for frame in range(120): crab._physics_process(1.0 / 60.0)
	contact = pop.floor_contact(crab.global_position)
	check(crab.basis.y.dot(contact.normal) > 0.999 and absf((crab.global_position - Vector3(contact.position)).dot(contact.normal) - crab.ground_clearance) < 0.01,"Moving crab remains grounded and follows the slope")
	crab.global_position = Vector3(0,2,0); crab.direction = Vector3.BACK; crab._ground_on_terrain(1)
	var still := crab.global_position
	for frame in range(60): crab._ground_on_terrain(1.0 / 60.0)
	check(crab.global_position.distance_to(still) < 0.001,"Grounding does not push a resting crawler sideways down a slope")
	var obstacle := StaticBody3D.new(); world.add_child(obstacle); obstacle.position = Vector3(0,1,1.3)
	var obstacle_shape := CollisionShape3D.new(); var obstacle_box := BoxShape3D.new(); obstacle_box.size = Vector3(0.6,1.2,0.6); obstacle_shape.shape = obstacle_box; obstacle.add_child(obstacle_shape)
	pop.terrain_exclusions.append(obstacle.get_rid())
	await physics_frame; await physics_frame
	crab.goal = crab.position + Vector3.BACK * 10; crab.home = crab.position; crab.turn_timer = 100; crab.roam_radius = 20; crab.swim_speed = 1
	var max_vertical_step := 0.0
	for frame in range(600):
		var previous := crab.global_position
		crab._physics_process(1.0 / 60.0)
		max_vertical_step = maxf(max_vertical_step,absf(crab.global_position.y - previous.y))
	check(crab.global_position.distance_to(still) > 4.0,"Crawler walks around an obstacle instead of remaining stuck")
	check(max_vertical_step < 0.1,"Crawler movement keeps ground-height changes smooth")
	var capture := Capture.new(); root.add_child(capture)
	var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_F11
	capture._input(key); check(capture.fps_label.visible,"F11 shows the FPS counter")
	capture._input(key); check(not capture.fps_label.visible,"F11 hides the FPS counter")
	check(capture.screenshot_folder() == ProjectSettings.globalize_path("res://../Screenshots").simplify_path(),"Screenshots go in the main game folder")
	if DisplayServer.get_name() != "headless":
		key.keycode = KEY_F12; capture._input(key)
		for frame in range(120):
			await process_frame
			if not capture.last_screenshot.is_empty(): break
		check(FileAccess.file_exists(capture.last_screenshot) and capture.last_screenshot.get_file().begins_with("OpenSC "),"F12 saves a dated PNG screenshot")
	world.queue_free(); capture.queue_free(); await process_frame
	print("Crawlers and capture: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
