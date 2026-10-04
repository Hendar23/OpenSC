extends SceneTree

const Scenery = preload("res://scenery_loader.gd")
const Assets = preload("res://clump_loader.gd")
const Viewer = preload("res://game.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	var folder := preload("res://asset_paths.gd").find_game_folder()
	var tables := Scenery.read_database(folder.path_join("DATA/SCEN1.DDB"))
	check(tables.get("Objects", []).size() == 434, "All object records decoded")
	check(tables.get("Cities", []).size() == 6, "All city records decoded")
	check(tables.get("Lights", []).size() == 2, "All light records decoded")
	var definitions := Scenery.read_definitions(folder.path_join("DATA/DATA.ENC"))
	check(definitions.size() == 185, "Object definitions decoded")
	check(definitions[75].object == "PULSELIGHT", "One-based database type mapping")
	check(not tables.Objects[7].has("ObjectType"), "Uninitialized masked fields ignored")
	var pose := Scenery.placement(tables.Objects[6], Vector3(250.0, 131.9099884, 204.5083923))
	check(pose.is_finite(), "Matrix padding NaNs ignored")
	check(pose.origin.distance_to(Vector3(209.413391, 160.910751, 208.353317)) < 0.001, "Database origin aligned with terrain")
	for name in ["SUB", "DOCKING", "AQUATRAZ", "PIPEBARS", "CLAM", "TURRET", "THORIUM", "PEARL", "MINE", "COIN", "BOTTLTOP", "REED", "BUSH1", "BUSH2", "BUSH3", "BUSH4"]:
		var model: Node3D = Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF")) if name == "SUB" else Assets.load_clump(folder.path_join("CLUMPS/" + name + ".DFF"))
		check(model != null, name + " model supported")
		if model != null: model.free()
	var viewer := Viewer.new()
	# Verify the original-world fallback independently of the user's authored map.
	viewer.use_map_overrides = false
	viewer.remember_preferences = false
	root.add_child(viewer)
	for frame in range(1200):
		if viewer.startup_complete: break
		await physics_frame
	check(viewer.startup_complete, "Automatic startup completes")
	check(viewer.pilot_mode, "Piloting starts with scenery")
	check(not viewer.canvas.visible, "Game starts with developer UI hidden")
	if viewer.world_root == null:
		quit(1)
		return
	var world: Node3D = viewer.world_root
	print("Scenery: ", world.get_meta("scenery_summary", "missing"))
	check(world.has_node("AmbientFish"), "Ambient fish population added")
	var fish_population := world.get_node("AmbientFish")
	check(fish_population.get_child_count() >= 20 and fish_population.get_child_count() <= 32, "Small ambient population spawns in open water")
	var records: Array = world.get_meta("creature_spawn_records", [])
	check(records.size() == 20, "All authored creature records retained separately")
	check(records.all(func(record: Dictionary) -> bool: return not record.auto_create), "Dormant mission creature records remain inactive")
	var fish_start: Array[Vector3] = []
	for fish in fish_population.get_children():
		fish_start.append(fish.position)
		check(fish.get_meta("spawn_source") == "provisional_ambient" and fish.collision_layer == 0 and fish.collision_mask == 5, "Fish are ambient and collide with terrain/surface without blocking the submarine")
		check(not fish.meshes.is_empty() and is_equal_approx(fish.ANIMATION_SPEED, 0.5), "Fish use original morph poses at half speed")
	for frame in range(90): await physics_frame
	var moved := 0
	for index in range(fish_population.get_child_count()):
		var fish: CharacterBody3D = fish_population.get_child(index)
		if fish.position.distance_to(fish_start[index]) > 0.1: moved += 1
		check(fish.position.is_finite() and fish.position.y + fish.radius < float(world.get_meta("surface_height")), "Wandering fish stay below the surface")
	check(moved >= fish_population.get_child_count() / 2, "Fish swim through the world over time")
	check(world.get_meta("plant_patches", 0) == 10, "All ten plant patches restored")
	check(int(world.get_meta("plant_count", 0)) > 250, "Plant patches populated on terrain")
	check(int(world.get_meta("scenery_props", 0)) >= 35, "Scenery and cities restored")
	check(world.has_node("Scenery/DOCKING_0/SceneryCollision"), "Placed city has collision")
	if world.has_node("Scenery/DOCKING_0/SceneryCollision"):
		var collision := world.get_node("Scenery/DOCKING_0/SceneryCollision").get_child(0) as CollisionShape3D
		check(collision.shape.get_faces().size() > 0, "Scenery collision includes transformed mesh faces")
	var surface := float(world.get_meta("surface_height"))
	check(is_equal_approx(surface, 163.8199463), "Surface follows upper map boundary")
	check(world.has_node("WaterSurfaceCollision"), "Infinite surface collider exists")
	await physics_frame
	await physics_frame
	var motion := PhysicsTestMotionParameters3D.new()
	motion.from = viewer.pilot.global_transform
	motion.motion = Vector3.ZERO
	motion.recovery_as_collision = true
	check(not PhysicsServer3D.body_test_motion(viewer.pilot.get_rid(), motion), "Original scenario spawn is clear of terrain and scenery")
	var query := PhysicsRayQueryParameters3D.create(Vector3(10000, surface - 10, 10000), Vector3(10000, surface + 10, 10000), 4)
	var hit := viewer.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty(), "Surface collider covers positions outside finite terrain")
	viewer.pilot.controls_enabled = false
	viewer.set_physics_process(false)
	viewer.pilot.reset_at(Vector3(10000, surface + 100, 10000))
	check(viewer.pilot.position.y < surface - viewer.pilot.surface_clearance(viewer.pilot.global_basis), "Reset stays fully submerged")
	viewer.pilot.position.y -= 1.0
	viewer.pilot.velocity = Vector3(0, 10000, 0)
	viewer.pilot.movement.settings.vertical_speed = 10000.0
	for frame in range(30): await physics_frame
	check(viewer.pilot.position.y <= surface - viewer.pilot.surface_clearance(viewer.pilot.global_basis), "High-speed ascent cannot breach surface")
	check(viewer.pilot.velocity.y <= 0.001, "Surface removes upward momentum")
	viewer.pilot.rotation.x = PI / 4.0
	viewer.pilot.position.y = surface
	for frame in range(10): await physics_frame
	check(viewer.pilot.position.y + viewer.pilot.surface_clearance(viewer.pilot.global_basis) <= surface + 0.01, "Tilted fitted hull remains below the impenetrable surface")
	var height := viewer.pilot.position.y
	viewer.pilot.velocity = Vector3(0, -3, 0)
	for frame in range(10): await physics_frame
	check(viewer.pilot.position.y < height - 0.1, "Submarine can dive away from surface")
	check(viewer.camera.position.y < surface, "Following camera remains submerged")
	viewer.pilot.movement.settings.vertical_speed = 5.0
	check(viewer.tuning_panel.sliders.size() == 22, "Movement sliders retained with physics, camera, bubbles and spin-down tuning and without braking")
	viewer.tuning_panel.sliders.camera_distance.value = 2.0
	check(is_equal_approx(viewer.pilot.movement.settings.camera_distance, 2.0), "Camera slider updates live settings")
	var zoom := InputEventMouseButton.new()
	zoom.pressed = true
	zoom.button_index = MOUSE_BUTTON_WHEEL_DOWN
	viewer._unhandled_input(zoom)
	check(is_equal_approx(viewer.pilot.movement.settings.camera_distance, 2.2), "Wheel zoom updates stored camera setting")
	check(is_equal_approx(viewer.tuning_panel.sliders.camera_distance.value, 2.2), "Wheel zoom synchronizes camera slider")
	viewer._update_follow_camera(0.0, true)
	var target: Vector3 = viewer.pilot.global_position + Vector3.UP * 0.35
	check(viewer.camera.global_position.distance_to(target) <= 2.2 * Vector3(0, 0.4, 1).length() + 0.01, "Camera uses tuned distance with collision clearance")
	viewer._update_water_environment()
	check(viewer.water_environment.fog_enabled, "Underwater fog enabled while piloting")
	viewer.fog_button.button_pressed = false
	viewer._update_water_environment()
	check(not viewer.water_environment.fog_enabled, "Fog can be disabled for inspection")
	viewer.fog_button.button_pressed = true
	var old_visibility := viewer.water_environment.fog_depth_end
	viewer.fog_slider.value = 150.0
	check(viewer.water_environment.fog_depth_end > old_visibility, "Longer visibility pushes distant fog back immediately")
	viewer.fog_slider.value = 10.0
	check(viewer.water_environment.fog_depth_end < old_visibility, "Shorter visibility brings distant fog closer immediately")
	viewer._toggle_tuning()
	check(viewer.canvas.visible and viewer.tuning_panel.visible, "T reveals developer UI and movement tuning")
	viewer._toggle_developer_ui()
	check(not viewer.canvas.visible and not viewer.tuning_panel.is_visible_in_tree(), "F1 hides all developer panels")
	viewer._toggle_developer_ui()
	check(viewer.canvas.visible and viewer.tuning_panel.is_visible_in_tree(), "F1 restores panel state")
	viewer._toggle_developer_ui()
	viewer.set_physics_process(true)
	viewer._physics_process(0.0)
	check(viewer.pilot.controls_enabled, "Hidden developer controls do not block piloting")
	viewer.fog_slider.value = 70.0
	viewer.remember_preferences = true
	viewer._save_preferences("res://tests/visibility-test.cfg")
	viewer.remember_preferences = false
	viewer.fog_slider.value = 35.0
	viewer._load_preferences("res://tests/visibility-test.cfg")
	check(is_equal_approx(viewer.fog_visibility, 70.0), "Visibility settings save and reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://tests/visibility-test.cfg"))
	if DisplayServer.get_name() != "headless":
		check(viewer.get_window().mode == Window.MODE_FULLSCREEN, "Game starts full screen")
		var key := InputEventKey.new()
		key.keycode = KEY_F11
		key.pressed = true
		viewer._input(key)
		check(viewer.get_window().mode == Window.MODE_FULLSCREEN, "F11 leaves game full screen")
		viewer._input(key)
		check(viewer.get_window().mode == Window.MODE_FULLSCREEN, "F11 restores full screen")
	viewer.queue_free()
	await create_timer(0.25).timeout
	print("World verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
