extends SceneTree
const Game = preload("res://game.gd")
const Map = preload("res://hud_map.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func _run() -> void:
	var map := Map.new()
	map.bounds = AABB(Vector3.ZERO,Vector3(200,10,100))
	map.initialize_exploration()
	check(not map.is_explored(Vector3(30,0,50)), "The world starts unexplored")
	map.explore(Vector3(30,0,50))
	check(map.is_explored(Vector3(30,0,50)) and not map.is_explored(Vector3(90,0,50)), "Only the area around the sub is revealed")
	check(map.is_explored(Vector3(38,0,50)) and not map.is_explored(Vector3(42,0,50)), "Exploration uses the reduced ten-unit reveal radius")
	map.explore(Vector3(120,0,50))
	check(map.is_explored(Vector3(30,0,50)) and map.is_explored(Vector3(120,0,50)), "Explored areas remain revealed after travelling")
	var fresh := Map.new(); fresh.bounds = map.bounds; fresh.initialize_exploration()
	check(not fresh.is_explored(Vector3(30,0,50)) and not fresh.is_explored(Vector3(120,0,50)), "A new game does not inherit earlier discoveries")
	map.initialize_exploration()
	map.explore(Vector3(30,0,50))
	check(map.is_explored(Vector3(30,0,50)) and not map.is_explored(Vector3(120,0,50)), "Restarting exploration clears old discoveries and reveals the starting area")
	map.reset_exploration()
	map.reveal_radius = 20.0
	map.height_samples.resize(Map.RESOLUTION * Map.RESOLUTION)
	map.height_samples.fill(0.0)
	for y in range(Map.RESOLUTION):
		for x in [102,103]: map.height_samples[y * Map.RESOLUTION + x] = 3.0
	map.explore(Vector3(30,2,50))
	check(map.is_explored(Vector3(35,0,50)) and not map.is_explored(Vector3(46,0,50)), "A ridge hides terrain behind it while revealing the near side")
	map.explore(Vector3(30,10,50))
	check(map.is_explored(Vector3(46,0,50)), "Rising to see over the ridge reveals the previously occluded area")
	map.reset_exploration()
	check(not map.is_explored(Vector3(35,0,50)), "Reset exploration clears accumulated discoveries")
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Game loads")
	if not game.startup_complete: quit(1); return
	game.map_reveal_slider.value = 5.0
	check(is_equal_approx(game.cockpit_hud.map_data.reveal_radius,5.0), "F1 reveal radius slider updates the map live")
	var config_path := "res://tests/map-radius-export.cfg"
	check(game._export_all_settings(config_path) == OK,"Reveal radius exports with all settings")
	game.map_reveal_slider.value = 15.0
	game._load_preferences(config_path)
	check(is_equal_approx(game.cockpit_hud.map_data.reveal_radius,5.0),"Exported reveal radius reloads correctly")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
	game.pilot.freeze = true; game.pilot.set_physics_process(false)
	var button := InputEventJoypadButton.new(); button.pressed = true; button.button_index = JOY_BUTTON_Y
	game._unhandled_input(button)
	check(game.first_person and game.camera.cull_mask & Game.SUB_RENDER_LAYER == 0,"Controller Y selects cockpit view and excludes the sub")
	var hull: AABB = game.equipment._bounds(game.equipment._meshes(game.pilot.visual,Transform3D.IDENTITY,true))
	check(hull.has_point(game.cockpit_camera_offset),"The camera's eye position is inside the hull")
	game.pilot.global_basis = Basis.from_euler(Vector3(0.3,0.8,0.2)); game.pilot.reset_physics_interpolation()
	game._update_follow_camera(0.0,true)
	check(game.camera.global_position.is_equal_approx(game.pilot.global_transform * game.cockpit_camera_offset) and game.camera.global_basis.is_equal_approx(game.pilot.global_basis),"Cockpit camera follows the sub's pitch, heading and roll")
	game.equipment.toggle_selected()
	check(game.equipment.lamp.visible and game.pilot.visual.visible,"Hiding sub geometry preserves headlight operation")
	var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_V
	game._unhandled_input(key)
	check(not game.first_person and game.camera.cull_mask & Game.SUB_RENDER_LAYER != 0,"Keyboard V restores third person and the visible sub")
	game.pilot.global_basis = Basis.IDENTITY
	game.pilot.global_position = game.docking.ports[0].entry; game.pilot.velocity = Vector3.ZERO
	game.pilot.angular_velocity = Vector3.ZERO; game.pilot.reset_physics_interpolation()
	game._set_camera_mode(true)
	game._request_docking()
	check(game.docking.stage != game.Docking.Stage.IDLE and not game.first_person,"Accepted docking switches to third person automatically")
	check(game.docking.cinematic_camera.is_equal_approx(game.camera.global_position),"Docking freezes the third-person camera position")
	game._unhandled_input(button)
	check(not game.first_person,"Camera toggle cannot interrupt docking")
	game.docking.cancel()
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280,720)
		game.pilot.reset_at(game.pilot.spawn)
		game._set_camera_mode(true)
		for frame in range(60): await process_frame
		root.get_texture().get_image().save_png("res://tests/cockpit-first-person-preview.png")
	game.queue_free(); await process_frame
	print("Cockpit camera and exploration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
