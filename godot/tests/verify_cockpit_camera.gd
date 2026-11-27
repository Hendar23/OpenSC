extends "res://tests/test_scene_tree.gd"
const Game = preload("res://game.gd")
const Map = preload("res://hud_map.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func cockpit_follows_pilot(game: Node3D, snap: bool = false) -> bool:
	var pose: Transform3D = game.pilot.global_transform if snap else game.pilot.get_global_transform_interpolated()
	var expected := pose * Transform3D(Basis.IDENTITY,game.cockpit_camera_offset)
	return game.first_person and game.camera.global_transform.is_equal_approx(expected) and (game.camera.cull_mask & Game.SUB_RENDER_LAYER) == 0
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
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	var storage = preload("res://player_storage.gd")
	if folder.is_empty(): folder = preload("res://asset_paths.gd").find_game_folder()
	storage.root_override = test_fixture_path("cockpit-camera")
	storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new()
	config.set_value("game","folder",folder)
	config.save(storage.preferences_path())
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	var native := DisplayServer.get_name() != "headless"
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Game loads")
	if not game.startup_complete: quit(1); return
	game.front_end.gameplay_menu.fmvs_enabled = false
	game.front_end.gameplay_menu.cockpit_3d_enabled = false
	await game._begin_new_game()
	if native:
		root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280,720)
	game.map_reveal_slider.value = 5.0
	check(is_equal_approx(game.cockpit_hud.map_data.reveal_radius,5.0), "F1 reveal radius slider updates the map live")
	var reveal_button: Button = game.graphics_controls.find_child("RevealWholeMap",true,false)
	reveal_button.pressed.emit()
	check(game.cockpit_hud.map_data.is_explored(game.cockpit_hud.map_data.bounds.position) and game.cockpit_hud.map_data.is_explored(game.cockpit_hud.map_data.bounds.end),"Dev button reveals the entire shared map")
	check(game.cockpit_hud.map_data.markers.all(func(marker: Dictionary) -> bool: return game.cockpit_hud.map_data.is_explored(marker.position)),"Reveal whole map also discovers every city dock")
	var reset_button: Button = reveal_button.get_parent().get_child(0)
	reset_button.pressed.emit()
	check(not game.cockpit_hud.map_data.is_explored(game.cockpit_hud.map_data.bounds.position),"Adjacent reset button clears whole-map reveal again")
	var config_path: String = storage.root_override.path_join("map-radius-export.cfg")
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
	game.equipment.set_installed(["deep_sea_lights", "night_vision", "magnet", "escape"])
	game.equipment.cycle(-1)
	game.equipment.toggle_selected()
	check(game.equipment.support_tools.pod_enabled,"Escape Pod is deployed before docking")
	game.equipment.cycle(1)
	game.pilot.global_basis = Basis.IDENTITY
	game.pilot.global_position = game.docking.ports[0].entry; game.pilot.velocity = Vector3.ZERO
	game.pilot.angular_velocity = Vector3.ZERO; game.pilot.reset_physics_interpolation()
	game.docking.set_physics_process(false)
	game._set_camera_mode(true)
	game._request_docking()
	check(game.docking.stage == game.Docking.Stage.ALIGN and cockpit_follows_pilot(game,true),"Docking begins in the selected cockpit view")
	game.equipment.support_tools._physics_process(0.04)
	check(not game.equipment.support_tools.pod_enabled and not game.equipment.mounted[3].enabled,"Docking recalls the Escape Pod and clears its equipment state")
	check(not game.first_person_crosshair._enabled(),"Weapons crosshair is hidden during automatic docking")
	game._unhandled_input(button)
	check(not game.first_person and game.docking.cinematic_camera.is_equal_approx(game.camera.global_position),"Controller Y selects the fixed exterior camera during docking")
	game._unhandled_input(key)
	check(cockpit_follows_pilot(game,true) and game.docking.stage == game.Docking.Stage.ALIGN,"Keyboard V restores cockpit view without interrupting docking")
	var toggle_key := InputEventKey.new(); toggle_key.pressed = true; toggle_key.keycode = KEY_L
	root.push_input(toggle_key)
	check(not game.equipment.lamp.visible,"L turns off the Deep-Sea Lights during docking")
	root.push_input(toggle_key)
	check(game.equipment.lamp.is_visible_in_tree(),"L turns on the Deep-Sea Lights during docking")
	var next_equipment := InputEventJoypadButton.new()
	next_equipment.pressed = true; next_equipment.button_index = JOY_BUTTON_DPAD_RIGHT
	root.push_input(next_equipment)
	var toggle_button := InputEventJoypadButton.new()
	toggle_button.pressed = true; toggle_button.button_index = JOY_BUTTON_B
	root.push_input(toggle_button)
	game._process(0)
	check(game.front_end.player_graphics.night_vision and game.equipment.lamp.is_visible_in_tree(),"Controller B enables Night Vision independently of the lights during docking")
	root.push_input(toggle_button)
	game._process(0)
	check(not game.front_end.player_graphics.night_vision and game.equipment.lamp.is_visible_in_tree(),"Controller B disables Night Vision independently of the lights during docking")
	root.push_input(next_equipment)
	root.push_input(toggle_button)
	check(game.equipment.current().id == "magnet" and not game.equipment.current().enabled,"Automatic docking still blocks activating the magnet")
	var approach_follows := true
	var captured_descent := false
	for frame in range(1000):
		game.docking._physics_process(0.1)
		game._process(0)
		if game.docking.stage == game.Docking.Stage.DOCKED: break
		approach_follows = approach_follows and cockpit_follows_pilot(game)
		if (native and not captured_descent and game.docking.stage == game.Docking.Stage.DESCEND
			and game.docking.elapsed > float(game.docking.travel_profile.duration) * 0.5):
			await RenderingServer.frame_post_draw
			captured_descent = root.get_texture().get_image().save_png(storage.root_override.path_join("cockpit-descent.png")) == OK
	check(approach_follows,"Cockpit camera follows the submarine through the entire approach and descent")
	if native: check(captured_descent,"The cockpit view renders during descent")
	check(game.docking.stage == game.Docking.Stage.DOCKED and game.dock_interface.visible and game.game_dock.view.active,"Docking still opens the city interface with its live exterior view")
	game._dock_ui_action("launch",{})
	check(game.docking.stage == game.Docking.Stage.EXIT_OPEN and cockpit_follows_pilot(game,true),"Undocking begins in the selected cockpit view")
	root.push_input(toggle_button)
	check(game.equipment.current().enabled and game.equipment.magnet.enabled,"First B press deploys the magnet immediately at launch, before another physics tick")
	root.push_input(toggle_button)
	root.push_input(next_equipment)
	root.push_input(toggle_key)
	check(game.equipment.current().enabled and game.equipment.support_tools.pod_enabled,"First L press redeploys the Escape Pod after docking")
	root.push_input(toggle_key)
	root.push_input(next_equipment)
	root.push_input(toggle_button)
	check(not game.equipment.lamp.visible,"Controller B turns off the Deep-Sea Lights during launch")
	root.push_input(next_equipment)
	root.push_input(toggle_key)
	game._process(0)
	check(game.front_end.player_graphics.night_vision,"L enables Night Vision during launch")
	root.push_input(toggle_key)
	game._process(0)
	check(not game.front_end.player_graphics.night_vision,"L disables Night Vision during launch")
	game._unhandled_input(key)
	check(not game.first_person and game.camera.global_position.is_equal_approx(game.docking.cinematic_camera),"Exterior camera remains available during launch")
	game._unhandled_input(button)
	check(cockpit_follows_pilot(game,true),"Switching back during launch restores cockpit view")
	var launch_follows := true
	for frame in range(1000):
		game.docking._physics_process(0.1)
		game._process(0)
		launch_follows = launch_follows and cockpit_follows_pilot(game)
		if game.docking.stage == game.Docking.Stage.IDLE: break
	check(launch_follows and game.docking.stage == game.Docking.Stage.IDLE,"Cockpit view follows launch and remains selected when piloting resumes")
	root.push_input(toggle_button)
	game._process(0)
	check(game.front_end.player_graphics.night_vision,"First B press after undocking switches on Night Vision at the departing port")
	var departure_position: Vector3 = game.pilot.global_position
	game.pilot.global_position += Vector3.UP * (game.docking.approach_radius + 1.0)
	game.docking.update_approach()
	game.pilot.global_position = departure_position
	game.docking.update_approach()
	check(not game.docking.nearby.is_empty(),"Returning to the port offers docking again")
	root.push_input(toggle_button)
	check(game.equipment.night_vision_enabled() and game.docking.nearby.is_empty(),"B still declines a new docking offer without changing equipment")
	game.queue_free(); await process_frame
	print("Cockpit camera and exploration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
