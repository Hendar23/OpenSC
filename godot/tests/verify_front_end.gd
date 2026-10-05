extends SceneTree
const Game = preload("res://game.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
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
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280,720)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/startup-loading-preview.png")
	for frame in range(1200):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete and game.front_end.menu_layer.visible and paused,"Startup finishes at the classic menu with the world paused")
	check(game.gameplay_catalogue.tables.equipment.records.size() == 30 and game.gameplay_catalogue.warnings.is_empty(),"Startup imports original gameplay data before opening the menu")
	check(game.front_end.menu_picture.texture == game.front_end.MENU_BACKGROUND and game.front_end.progress_bar.value == 100.0,"Project menu artwork loads and startup progress completes")
	check(not game.front_end.is_button_available("continue") and not game.front_end.is_button_available("load") and not game.front_end.is_button_available("controls") and not game.front_end.is_button_available("audio") and not game.front_end.is_button_available("graphics"),"Unimplemented entries and Continue before a new game are inactive")
	check(game.front_end.is_button_available("website") and game.front_end.WEBSITE_URL == "https://github.com/Hendar23/OpenSC","Website is enabled and targets the project repository")
	check(game._desired_mouse_mode() == Input.MOUSE_MODE_VISIBLE or Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"Main menu shows the pointer")
	if DisplayServer.get_name() != "headless":
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/classic-main-menu-preview.png")
	var accept := InputEventJoypadButton.new(); accept.pressed = true; accept.button_index = JOY_BUTTON_A
	game.day_night.hour = 0.0
	Input.parse_input_event(accept)
	await process_frame
	check(not paused and not game.front_end.menu_layer.visible and game.has_started_game,"Controller A starts the focused New Game without another GUI activation")
	check(absf(game.day_night.hour - 12.0) < 0.1,"First New Game starts at midday even with night selected")
	var pilot_position: Vector3 = game.pilot.global_position
	var event := InputEventJoypadButton.new(); event.pressed = true; event.button_index = JOY_BUTTON_START
	game.front_end._input(event)
	check(paused and game.front_end.menu_layer.visible and game.front_end.is_button_available("continue") and not game.developer_ui_visible,"Start opens the main menu, not the developer menu")
	var hour: float = game.day_night.hour
	for frame in range(10): await process_frame
	check(game.pilot.global_position.is_equal_approx(pilot_position) and is_equal_approx(game.day_night.hour,hour),"Menu freezes submarine physics and world time")
	game.front_end._input(event)
	check(not paused and not game.front_end.menu_layer.visible,"Start resumes the current game")
	game.front_end._input(event)
	Input.parse_input_event(accept)
	await process_frame
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
	check(game.cockpit_hud.map_data != map and not game.cockpit_hud.map_data.is_explored(distant),"New Game clears exploration instead of continuing the old map")
	check(absf(game.day_night.hour - 12.0) < 0.1 and game.day_night.daylight() > 0.99,"Restarting New Game resets the clock and lighting to daytime")
	print("Front end: %d checks, %d failures" % [checks,failures])
	if failures:
		paused = false; game.queue_free(); await process_frame; quit(1)
	else:
		game.front_end._input(event)
		game.front_end.buttons.exit.grab_focus()
		game.front_end._input(accept)
