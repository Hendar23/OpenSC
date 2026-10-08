extends SceneTree
const Game = preload("res://game.gd")
const Mods = preload("res://mod_registry.gd")
const Bindings = preload("res://input_bindings.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Mods.initialize(false)
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1800):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"World loads with bottom camera available")
	if not game.startup_complete: quit(1); return
	game.pilot.freeze = true; game.set_physics_process(false); game.set_process(false)
	var hud: CanvasLayer = game.cockpit_hud
	hud.show(); hud.set_enabled(2,true,false)
	check(not hud.bottom_camera_enabled and hud.bottom_view.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Unused bottom camera costs no extra world rendering")
	hud.set_bottom_camera_enabled(true)
	check(hud.bottom_view.world_3d == game.world_root.get_world_3d(),"Bottom camera reuses the loaded world")
	check(hud.displays[2].camera_feed == hud.bottom_view.get_texture() and hud.displays[2].material == null and not hud.displays[2].player_marker.visible and not hud.displays[2].city_markers.visible,"Feed replaces map content without map fog or markers")
	check(hud.bottom_camera.cull_mask & game.SUB_RENDER_LAYER == 0,"Hull and equipment cannot obscure the intake camera")
	var intake: Node3D = game.equipment.vacuum
	check(hud.bottom_camera.global_position.is_equal_approx(intake.get_global_transform_interpolated().origin),"Camera starts at the Suck-O-Matic intake")
	check((-hud.bottom_camera.global_basis.z).dot(-intake.global_basis.orthonormalized().y) > 0.999,"Camera looks down from the intake")
	var old_pose: Transform3D = game.pilot.global_transform
	game.pilot.global_transform = Transform3D(Basis.from_euler(Vector3(0.2,0.8,-0.3)),old_pose.origin + Vector3(1,2,3))
	game.pilot.reset_physics_interpolation(); intake.reset_physics_interpolation(); hud._update_bottom_camera()
	check(hud.bottom_camera.global_position.is_equal_approx(intake.get_global_transform_interpolated().origin) and (-hud.bottom_camera.global_basis.z).dot(-intake.get_global_transform_interpolated().basis.orthonormalized().y) > 0.999,"Camera follows movement, pitch and roll")
	game.pilot.global_transform = old_pose; game.pilot.reset_physics_interpolation(); intake.reset_physics_interpolation()
	game.pilot.active = true; game.pilot.controls_enabled = true; game.pilot.visual.show()
	game.equipment.set_installed(["deep_sea_lights","magnet"])
	var magnet: Node3D = game.equipment.magnet; magnet.set_enabled(true)
	for frame in range(90): await physics_frame
	var meshes: Array[Node] = magnet.head.find_children("*","MeshInstance3D",true,false)
	for link in magnet.links: meshes.append_array(link.find_children("*","MeshInstance3D",true,false))
	check(not meshes.is_empty() and meshes.all(func(mesh: MeshInstance3D) -> bool: return (mesh.layers & hud.bottom_camera.cull_mask) != 0),"Deployed magnet and chain render in the bottom camera while the submarine stays hidden")
	magnet.reset()
	hud.hide()
	check(hud.bottom_view.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Hiding the HUD immediately suspends the camera")
	hud.show(); hud.set_enabled(2,false,false)
	check(hud.bottom_view.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Hiding the map instrument suspends its feed")
	hud.set_enabled(2,true,false)
	check(hud.bottom_view.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"Revealing the instrument resumes the selected feed")
	hud.set_bottom_camera_enabled(false)
	check(hud.displays[2].camera_feed == null and hud.displays[2].material == hud.displays[2].fog_material and hud.displays[2].player_marker.visible,"Toggling off restores the existing minimap and exploration")
	Bindings.bindings = Bindings.defaults(); Bindings.apply_all()
	var shoulder := InputEventJoypadButton.new(); shoulder.device = 77; shoulder.button_index = JOY_BUTTON_RIGHT_SHOULDER; shoulder.pressed = true; Bindings.track_event(shoulder)
	var y := InputEventJoypadButton.new(); y.device = 77; y.button_index = JOY_BUTTON_Y; y.pressed = true
	var was_first_person: bool = game.first_person
	game._unhandled_input(y)
	check(hud.bottom_camera_enabled and game.first_person == was_first_person and not game.map_open,"Controller chord toggles the feed without altering the main view")
	game._unhandled_input(y)
	check(not hud.bottom_camera_enabled,"Repeating the chord returns to the minimap")
	shoulder.pressed = false; Bindings.track_event(shoulder)
	hud.set_bottom_camera_enabled(true)
	await game._begin_new_game()
	check(not hud.bottom_camera_enabled and hud.displays[2].camera_feed == null and hud.bottom_view.render_target_update_mode == SubViewport.UPDATE_DISABLED,"New Game restores the minimap and disables bottom-camera rendering")
	if DisplayServer.get_name() != "headless":
		hud.set_bottom_camera_enabled(true)
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = hud.bottom_view.get_texture().get_image()
		image.save_png("res://tests/bottom-camera-feed.png")
		root.get_texture().get_image().save_png("res://tests/bottom-camera-hud.png")
		var minimum := 1.0; var maximum := 0.0
		for x in range(0,image.get_width(),8):
			for z in range(0,image.get_height(),8):
				var brightness := image.get_pixel(x,z).get_luminance(); minimum = minf(minimum,brightness); maximum = maxf(maximum,brightness)
		check(maximum - minimum > 0.01,"Feed renders visible world detail")
	game.queue_free(); await process_frame
	print("Bottom camera: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
