extends "res://tests/test_scene_tree.gd"
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-map-status-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",ProjectSettings.globalize_path("res://../Original Sub Culture")); config.save(storage.preferences_path())
	call_deferred("run")
func run() -> void:
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280,720)
	var game := preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	while not game.startup_complete: await process_frame
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.docking.set_physics_process(false)
	var screen: Control = game.map_screen
	var progress: Dictionary = game.player_progress
	progress.status.credits = 123456; progress.status.hull_strength = 160
	progress.cargo = {"thorium":3}; progress.hold = {"depth":12,"shield":2,"bigears":1}
	progress.ammunition.bigears = 3
	game.equipment.vacuum.storage.assign(["thorium","thorium","@none"])
	progress.suckomat = []
	var before := progress.duplicate(true)
	var key := InputEventKey.new(); key.keycode = KEY_M; key.pressed = true
	game._input(key)
	check(progress == before,"Opening the map does not mutate player progress or sync stale save-only intake")
	for frame in range(4): await process_frame
	check(game.map_open and not paused,"Map opens with its existing unpaused behaviour")
	check(game.expanded_map.full_world and game.expanded_map.map_data == game.cockpit_hud.map_data,"Whole-world map retains shared exploration")
	check(screen.credits.text == "Credits: 123456","Credits shown on opening")
	check(screen.fields.keys() == ["hold"],"Only hold contents accompany credits")
	check(screen.fields.hold.text.contains("3") and not screen.fields.hold.text.contains("Empty"),"Cargo quantities shown")
	check(screen.fields.hold.text.contains("Depth Charges") and screen.fields.hold.text.contains("12"),"Hold uses source equipment names and individual ammo count")
	check(screen.fields.hold.get_theme_color("font_color") == preload("res://map_screen.gd").GOLD,"Panel inherits game gold text")
	check(screen.fields.hold.get_theme_font("font") == ThemeDB.fallback_font,"Panel uses existing game font")
	progress.status.credits += 3500; progress.status.shields = 57; progress.cargo.thorium = 4
	screen._process(0.21)
	check(screen.credits.text == "Credits: 126956" and screen.fields.hold.text.contains("4"),"Credits and hold contents refresh while map stays open")
	progress.cargo = {}; progress.hold = {}; game.equipment.vacuum.storage.clear(); screen.refresh()
	check(screen.fields.hold.text == "Empty","Empty hold clears stale entries")
	for index in range(45): progress.hold["test_item_%02d" % index] = index+1
	progress.status.credits = 126956; progress.cargo = {"thorium":4,"copper":2}
	screen.refresh()
	for frame in range(5): await process_frame
	check(screen.scroll.get_v_scroll_bar().max_value > screen.scroll.size.y,"Long inventory scrolls within the panel")
	var down := InputEventKey.new(); down.keycode = KEY_DOWN; down.pressed = true
	screen._input(down)
	check(screen.scroll.scroll_vertical > 0,"Keyboard scroll works")
	var prior_scroll: int = screen.scroll.scroll_vertical
	var pad := InputEventJoypadButton.new(); pad.button_index = JOY_BUTTON_DPAD_DOWN; pad.pressed = true
	screen._input(pad)
	check(screen.scroll.scroll_vertical > prior_scroll,"Controller D-pad scroll works")
	prior_scroll = screen.scroll.scroll_vertical; progress.status.credits += 1; screen.refresh()
	await process_frame
	check(screen.scroll.scroll_vertical == prior_scroll,"Live updates preserve inventory scroll position")
	for resolution in [Vector2i(640,480),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		for frame in range(8): await process_frame
		var map_rect: Rect2 = game.expanded_map.get_global_rect()
		var panel_rect: Rect2 = screen.panel.get_global_rect()
		check(map_rect.end.x <= panel_rect.position.x and map_rect.size.x > 200,"Map and status have separate usable space at %s" % resolution)
		check(panel_rect.end.x <= root.get_visible_rect().size.x and panel_rect.end.y <= root.get_visible_rect().size.y,"Status stays inside viewport at %s" % resolution)
	root.size = Vector2i(1280,720)
	progress.hold = {"shield":2,"magnet":1,"bigears":1,"depth":12}; progress.ammunition.bigears = 3
	game.equipment.vacuum.storage.assign(["thorium","thorium"])
	progress.mission = "Rescue Bacau Shuttle"; progress.missions.active = {"id":"stranded","city":1}
	game.mission_runtime.side_jobs.id = "stranded"
	game.cockpit_hud.map_data.reveal_all()
	screen.refresh(); screen.scroll.scroll_vertical = 0
	if DisplayServer.get_name() != "headless":
		for frame in range(15): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/map-status.png")
	progress.missions.active = {}; progress.mission = "None"; game.mission_runtime.side_jobs.id = ""
	game._input(key); check(not game.map_open,"Existing map key closes panel and map together")
	var hidden_text: String = screen.credits.text
	progress.status.credits += 123; screen._process(1)
	check(screen.credits.text == hidden_text,"Hidden map does not poll inventory")
	game._input(key); check(screen.credits.text != hidden_text,"Reopening refreshes immediately")
	var cancel := InputEventKey.new(); cancel.keycode = KEY_ESCAPE; cancel.pressed = true
	game._input(cancel); check(not game.map_open and not paused,"Escape closes without changing pause state")
	game._physics_process(0)
	check(game.pilot.controls_enabled,"Closing map restores flight controls")
	print("Map status checks: ",checks," failures: ",failures)
	game.queue_free(); await process_frame; quit(1 if failures else 0)
