extends SceneTree
const Searchlight = preload("res://searchlight.gd")
const Game = preload("res://game.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func key_event(code: int) -> InputEventKey:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true; return event
func _initialize() -> void:
	preload("res://asset_cache.gd").enabled = false
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-front-end-fixtures"; storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new(); config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER")); config.save(storage.preferences_path())
	call_deferred("_run")
func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func _run() -> void:
	Mods.initialize(false)
	var game := Game.new(); game.remember_preferences = false; game.show_start_menu = true
	root.add_child(game)
	for frame in range(1200):
		if game.front_end.loading_picture.texture != null: break
		await process_frame
	check(game.loading_canvas.visible and game.front_end.loading_picture.texture != null,"Startup shows the original loading artwork")
	game.front_end.update_progress("Loading environment: 1 / 2 sectors")
	var progress: float = game.front_end.progress_bar.value
	game.front_end.update_progress("Loading environment: 1 / 4 sectors")
	check(game.front_end.progress_bar.value >= progress,"Loading progress never moves backwards")
	game.front_end.update_progress("Converting assets: environment textures: 1 / 2")
	check(game.front_end.loading_status.text == "Converting assets" and game.front_end.progress_bar.value >= 48.0,"Cold asset conversion updates both the caption and stage progress")
	game.front_end.update_progress("Loading cached environment")
	check(game.front_end.loading_status.text == "Loading","Cached loading does not claim to convert assets")
	game.front_end.update_progress("Checking cave light: 50%")
	check(game.front_end.loading_status.text == "Loading","Internal loading details stay out of the caption")
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280,720)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/startup-loading-preview.png")
	for frame in range(1200):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete and game.front_end.menu_layer.visible and paused,"Startup finishes at the live menu with gameplay paused")
	check(game.gameplay_catalogue.tables.equipment.records.size() == 30 and game.gameplay_catalogue.warnings.is_empty(),"Startup imports original gameplay data before opening the menu")
	check(game.front_end.menu_picture.texture != null and game.front_end.buttons.new_game.text == "New Game" and game.front_end.progress_bar.value == 100.0,"Title artwork and labelled buttons load and startup progress completes")
	check(game.menu_backdrop.view.current and game.pilot != null and game.cockpit_hud != null,"Menu camera works with player and HUD already prepared")
	var menu_pose: Transform3D = game.menu_backdrop.view.transform
	var saved_spawn: Vector3 = game.world_root.get_meta("player_spawn")
	game.world_root.set_meta("player_spawn",saved_spawn + Vector3(20,5,20))
	game.menu_backdrop._position_camera()
	check(game.menu_backdrop.view.transform.is_equal_approx(menu_pose),"Editing the New Game spawn leaves menu framing unchanged")
	game.world_root.set_meta("player_spawn",saved_spawn)
	var camera_fixture := "res://tests/menu-camera-fixture/view"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(camera_fixture))
	var camera_document := preload("res://map_document.gd").load_active()
	var captured_pose := menu_pose; captured_pose.origin += Vector3(0.5,0,0)
	camera_document.menu_camera = {"transform":preload("res://map_document.gd").encode(captured_pose),"fov":57.0}
	check(preload("res://map_document.gd").save(camera_document,camera_fixture.path_join("map.json")) == OK,"Captured menu camera is valid map data")
	var camera_manifest := FileAccess.open(camera_fixture.path_join("mod.json"),FileAccess.WRITE)
	camera_manifest.store_string(JSON.stringify({"schema_version":1,"id":"camera-view-test","name":"Camera view test","assets":{"map.scen1":"map.json"}})); camera_manifest.close()
	Mods.initialize(false,"res://tests/menu-camera-fixture"); Mods.apply(["camera-view-test"],[],false)
	game.menu_backdrop._position_camera()
	check(game.menu_backdrop.view.transform.is_equal_approx(captured_pose) and is_equal_approx(game.menu_backdrop.view.fov,57.0),"Live menu uses captured map camera position, angle and field of view")
	Mods.initialize(false); game.menu_backdrop._position_camera()
	for filename in ["map.json","mod.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(camera_fixture.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(camera_fixture)); DirAccess.remove_absolute(ProjectSettings.globalize_path(camera_fixture.get_base_dir()))
	check(game.menu_backdrop.group_count >= 2 and game.menu_backdrop.group_count <= 3 and not game.menu_backdrop.actors.is_empty(),"Menu chooses two or three wildlife groups")
	check(game.folder_dialog.use_native_dialog and game.front_end.loading_picture.texture != null,"Startup provides loading artwork and the native folder picker")
	if game.wildlife != null:
		for actor in game.menu_backdrop.actors:
			var species: Dictionary = game.wildlife.definitions[actor.node.get_meta("species")]
			check(actor.node.mobility == species.mobility and is_equal_approx(actor.node.roam_radius,float(species.roam_radius)),"Menu respects creature mobility and roaming settings")
	check(game.menu_backdrop.actors.all(func(actor: Dictionary) -> bool: return actor.node.collision_layer == 0 and actor.node.collision_mask == 5),"Menu actors cannot change gameplay collisions")
	check(not game.front_end.is_button_available("continue") and game.front_end.is_button_available("load") == game.save_games.slots().any(func(slot: Dictionary) -> bool: return slot.valid) and game.front_end.is_button_available("controls") and game.front_end.is_button_available("audio") and game.front_end.is_button_available("graphics"),"Controls, Audio and Graphics are available and Load reflects existing saves")
	check(not game.front_end.buttons.has("website") and game.front_end.menu_config.title_rect[2] == 294,"Main menu removes Website and preserves title layout")
	check(game.front_end.buttons.options.visible and game.front_end.buttons.mods.visible and not game.front_end.buttons.controls.visible and not game.front_end.buttons.graphics.visible and not game.front_end.buttons.audio.visible,"Main menu exposes Mods directly and groups settings behind Options")
	check(game.front_end.menu_picture.material is ShaderMaterial and game.front_end.menu_picture.material.get_shader_parameter("corner_radius") == 12.0,"Title card has rounded corners without changing the source artwork")
	check(game._desired_mouse_mode() == Input.MOUSE_MODE_VISIBLE or Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"Main menu shows the pointer")
	if DisplayServer.get_name() != "headless":
		game.day_night.hour = 12.0; game._update_daylight()
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/live-main-menu-preview.png")
		check(root.get_texture().get_image().get_pixel(10,10).b > 0.1,"Rendered live background is visible behind the menu")
		game.front_end._activate_button("options"); game.front_end._activate_button("audio")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/live-audio-menu-preview.png")
		check(game.menu_backdrop.active and game.menu_backdrop.view.current and root.get_texture().get_image().get_pixel(10,10).b > 0.1,"Audio page preserves the live sea camera and visible background")
		game.front_end.audio_menu.close_menu(); game.front_end._activate_button("back")
		game.front_end._activate_button("options"); game.front_end._activate_button("gameplay")
		check(not game.weapons.auto_aim_enabled,"Zapper auto aim is off for a fresh player")
		game.front_end.gameplay_menu._toggle()
		check(game.weapons.auto_aim_enabled,"Gameplay toggle immediately enables weapon auto aim")
		game.front_end.gameplay_menu._toggle()
		check(not game.weapons.auto_aim_enabled,"Gameplay toggle immediately disables weapon auto aim")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/live-gameplay-menu-preview.png")
		game.front_end.gameplay_menu.close_menu(); game.front_end._activate_button("back")
		game.front_end._activate_button("options"); game.front_end._activate_button("graphics")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/live-graphics-menu-preview.png")
		check(game.front_end.graphics_menu.visible and game.menu_backdrop.active and game.menu_backdrop.view.current,"Graphics keeps the live sea backdrop")
		var graphics: Node = game.front_end.player_graphics
		check(not graphics.settings.has("hud_scale") and not game.front_end.graphics_menu.controls.has("hud_scale"),"HUD sizing is automatic rather than a graphics setting")
		graphics.set_value("shadows",0); game._update_daylight()
		check(not game.sun.shadow_enabled,"Day/night updates preserve the chosen shadow setting")
		graphics.set_value("shadows",2)
		game.front_end.graphics_menu.close_menu(); game.front_end._activate_button("back")
		game.menu_backdrop.next_pass = 0.0
		for frame in range(120): game.menu_backdrop._process(0.05)
		check(game.menu_backdrop.submarine.visible and game.menu_backdrop.wake.particles.size() > 0,"Menu sub cruises past with a live bubble wake")
		check(game.menu_backdrop.propeller_audio.playing and game.menu_backdrop.propeller_audio.stream != null,"Passing sub plays the loaded propeller loop while gameplay is paused")
		check(game.menu_backdrop.propeller_audio.get_parent() == game.menu_backdrop.submarine and game.menu_backdrop.propeller_audio.volume_db > -60.0,"Propeller sound moves with the sub at an audible level")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/live-menu-submarine-preview.png")
	var accept := InputEventJoypadButton.new(); accept.pressed = true; accept.button_index = JOY_BUTTON_A
	game.front_end.buttons.options.grab_focus(); game.front_end._input(accept)
	check(game.front_end.menu_page == "options" and game.front_end._visible_button_order() == ["controls","graphics","audio","gameplay","player_folder","back"] and not game.front_end.buttons.new_game.visible,"Controller opens settings, player folder and Back")
	var down := InputEventJoypadButton.new(); down.pressed = true; down.button_index = JOY_BUTTON_DPAD_DOWN
	game.front_end._input(down)
	check(root.gui_get_focus_owner() == game.front_end.buttons.graphics,"Options navigation reaches Graphics after Controls")
	if DisplayServer.get_name() != "headless":
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/options-menu-preview.png")
	game.front_end._activate_button("back")
	check(game.front_end.is_button_available("mods") and game.front_end.buttons.mods.visible,"Mods is available from the main menu")
	game.front_end.buttons.mods.grab_focus(); game.front_end._input(accept)
	check(game.mod_panel.visible and not game.mod_panel.embedded,"Main-menu Mods opens the mod-management window")
	check(paused and game.mod_panel.can_process() and game.mod_panel.content.can_process(),"Mods controls stay interactive while the main menu pauses gameplay")
	if DisplayServer.get_name() != "headless":
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/main-menu-mods-preview.png")
	var mods_cancel := InputEventJoypadButton.new(); mods_cancel.pressed = true; mods_cancel.button_index = JOY_BUTTON_B
	game.mod_panel._input(mods_cancel)
	check(not game.mod_panel.visible,"Controller Back closes the Mods window")
	check(game.front_end.menu_page == "main" and root.gui_get_focus_owner() == game.front_end.buttons.mods,"Closing Mods returns focus to its main menu entry")
	game.front_end._activate_button("options")
	game.front_end.buttons.controls.pressed.emit()
	check(game.front_end.controls_menu.visible and paused,"Controls opens over the paused main menu")
	var cancel := InputEventJoypadButton.new(); cancel.pressed = true; cancel.button_index = JOY_BUTTON_B
	Input.parse_input_event(cancel); await process_frame
	check(not game.front_end.controls_menu.visible and root.gui_get_focus_owner() == game.front_end.buttons.controls,"Controller Back closes Controls and restores menu focus")
	game.front_end._input(cancel)
	check(game.front_end.menu_page == "main" and root.gui_get_focus_owner() == game.front_end.buttons.options and game.front_end.menu_layer.visible,"Back returns from Options to the main menu")
	game.front_end.buttons.new_game.grab_focus()
	game.day_night.hour = 0.0
	Input.parse_input_event(accept)
	for frame in range(4000):
		if game.has_started_game: break
		await process_frame
	check(not paused and not game.front_end.menu_layer.visible and game.has_started_game,"Controller A starts the focused New Game without another GUI activation")
	check(not game.menu_backdrop.propeller_audio.playing,"Closing the menu stops its propeller audio")
	check(not game.menu_backdrop.active and game.camera.current and game.pilot.visible and game.cockpit_hud.visible,"Starting play restores the player camera, submarine and HUD")
	var shoulder := InputEventJoypadButton.new(); shoulder.pressed = true; shoulder.button_index = JOY_BUTTON_LEFT_SHOULDER; shoulder.device = 77
	Input.parse_input_event(shoulder); await process_frame
	var combo := InputEventJoypadButton.new(); combo.pressed = true; combo.button_index = JOY_BUTTON_Y; combo.device = 77
	var first_person: bool = game.first_person
	Input.parse_input_event(combo); await process_frame
	check(game.map_open and game.first_person == first_person,"Actual left shoulder + Y opens map without switching camera")
	combo.pressed = false; Input.parse_input_event(combo); await process_frame
	combo.pressed = true; Input.parse_input_event(combo); await process_frame
	check(not game.map_open,"Controller combo also closes map")
	shoulder.pressed = false; Input.parse_input_event(shoulder); await process_frame
	game._set_map_open(true)
	Input.parse_input_event(key_event(KEY_ESCAPE)); await process_frame
	check(not game.map_open and not paused,"Escape closes map without opening main menu")
	check(absf(game.day_night.hour - 10.0) < 0.1,"First New Game starts at 10:00 even with night selected")
	var pilot_position: Vector3 = game.pilot.global_position
	var original_world: Node3D = game.world_root
	var camera_pose: Transform3D = game.camera.global_transform
	var event := InputEventJoypadButton.new(); event.pressed = true; event.button_index = JOY_BUTTON_START
	game.front_end._input(event)
	check(paused and game.front_end.menu_layer.visible and game.front_end.is_button_available("continue") and not game.developer_ui_visible,"Start opens the main menu, not the developer menu")
	var generation: int = game.menu_backdrop.generation
	var hour: float = game.day_night.hour
	var actor_position: Vector3 = game.menu_backdrop.actors[0].node.global_position
	var light_states := []
	for entry in game.menu_backdrop.animated_lights:
		var light: Node3D = entry.node
		light_states.append({"node":light,"value":light.angle if light is Searchlight else light.elapsed,"mode":entry.mode})
	check(not light_states.is_empty(),"Menu includes map light animations")
	for frame in range(10): await physics_frame
	for entry in light_states:
		var light: Node3D = entry.node
		check(not is_equal_approx(entry.value,light.angle if light is Searchlight else light.elapsed),"Map light animates while gameplay is paused")
	check(game.pilot.global_position.is_equal_approx(pilot_position) and is_equal_approx(game.day_night.hour,hour),"Menu freezes submarine physics and the gameplay clock")
	check(not game.menu_backdrop.actors[0].node.global_position.is_equal_approx(actor_position),"Decorative fish keep swimming while gameplay is paused")
	game.day_night.enabled = false
	hour = game.day_night.hour
	for frame in range(3): await physics_frame
	check(is_equal_approx(game.day_night.hour,hour),"Menu respects the disabled day/night cycle")
	game.day_night.hour = 0.0; game._update_daylight()
	check(game.sun.light_energy > 1.0 and game.day_night.hour == 0.0,"Menu stays in daylight without changing the gameplay time")
	game.day_night.enabled = true
	game.front_end._input(event)
	check(game.menu_backdrop.actors.all(func(actor: Dictionary) -> bool: return not actor.node.is_physics_processing()),"Menu fish stop simulating when gameplay resumes")
	check(light_states.all(func(entry: Dictionary) -> bool: return entry.node.process_mode == entry.mode),"Closing menu restores map light processing modes")
	check(not paused and not game.front_end.menu_layer.visible,"Start resumes the current game")
	check(game.world_root == original_world and game.camera.global_transform.is_equal_approx(camera_pose),"Menu reuses the loaded world and restores the gameplay view")
	game.front_end._input(event)
	check(game.menu_backdrop.generation == generation + 1,"Returning to the menu refreshes the wildlife")
	var release := InputEventJoypadButton.new(); release.button_index = JOY_BUTTON_A; release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	Input.parse_input_event(accept)
	for frame in range(2): await process_frame
	check(not paused and not game.front_end.menu_layer.visible,"Controller A activates the focused Continue while paused")
	var map: RefCounted = game.cockpit_hud.map_data
	var distant: Vector3 = map.bounds.position + map.bounds.size * 0.9
	map.explored.fill(Color.WHITE); map.exploration_texture.update(map.explored)
	game.pilot.global_position += Vector3(10,0,0)
	game.day_night.hour = 0.0
	game.front_end._input(event)
	game.front_end.buttons.new_game.pressed.emit()
	for frame in range(1200):
		if not game.world_loading and not game.loading_canvas.visible: break
		await process_frame
	check(not game.world_loading and not paused and game.pilot.global_position.distance_to(game.pilot.spawn) < 0.1,"New Game from the menu resets the submarine to its spawn")
	check(game.world_root == original_world and game.cockpit_hud.map_data == map and not game.cockpit_hud.map_data.is_explored(distant),"New Game reuses the world and map renderer while clearing exploration")
	check(absf(game.day_night.hour - 10.0) < 0.1 and game.day_night.daylight() > 0.99,"Restarting New Game resets the clock and lighting to 10:00")
	game._show_main_menu()
	game.front_end.buttons.mods.pressed.emit()
	game.mod_panel._apply()
	check(game.mod_panel.apply_confirmation.visible and game.has_started_game and paused,"Applying mods requests confirmation without ending the current game")
	game.mod_panel.apply_confirmation.hide()
	game.mod_panel.apply_confirmation.confirmed.emit()
	await process_frame
	for frame in range(1800):
		if not game.world_loading and game.front_end.menu_layer.visible: break
		await process_frame
	check(not game.world_loading and paused and game.front_end.menu_layer.visible and game.pilot != null and game.pilot_mode,"Confirmed mods reload finishes at the main menu without freezing")
	check(not is_instance_valid(original_world),"Applying mods still rebuilds the world rather than retaining old assets")
	check(not game.has_started_game and not game.front_end.can_resume ,"Applying mods ends the previous live game")
	game.front_end.buttons.new_game.pressed.emit()
	for frame in range(4000):
		if game.has_started_game: break
		await process_frame
	check(game.has_started_game and not paused and not game.front_end.menu_layer.visible,"New Game is playable after applying mods")
	print("Front end: %d checks, %d failures" % [checks,failures])
	if failures:
		paused = false; game.queue_free(); await process_frame; quit(1)
	else:
		game.front_end._input(event)
		game.front_end.buttons.exit.grab_focus()
		game.front_end._input(accept)
