extends "res://tests/test_scene_tree.gd"
var game: Node
var checks := 0
var failures := 0

func _init() -> void:
	super._init()
	if "--with-cache" in OS.get_cmdline_user_args(): preload("res://asset_cache.gd").enabled = true
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-continue-fixtures"; storage.ensure_parent(storage.preferences_path())
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	var config := ConfigFile.new(); config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func clear_saves(saves: RefCounted) -> void:
	assert(saves.folder.begins_with("res://tests/cache-continue-fixtures/"))
	for slot in range(-1,saves.SLOT_COUNT): DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.path(slot)))

func cold_menu() -> void:
	game.has_started_game = false; game.front_end.can_resume = false
	game.dock_interface.dismiss(); game._show_main_menu()

func run() -> void:
	var saves := preload("res://save_games.gd").new(); clear_saves(saves)
	check(saves.latest_slot() == -2,"No saves has no Continue target")
	game = preload("res://game.gd").new(); game.remember_preferences = false; game.show_start_menu = true; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game starts at menu")
	if not game.startup_complete: quit(1); return
	check(game.pilot != null and game.docking != null and game.equipment != null and game.weapons != null and game.pilot_mode,"Startup prepares player and gameplay controllers before opening the menu")
	var preloaded_world: int = game.world_root.get_instance_id()
	var prepared_player: int = game.pilot.get_instance_id()
	var preloaded_backdrop: int = game.menu_backdrop.get_instance_id()
	check(not game.has_started_game and not game.front_end.is_button_available("continue"),"Continue unavailable on first launch without saves")
	check(not game.front_end.is_button_available("load"),"Load unavailable without saves")
	await game._begin_new_game()
	check(game.pilot.get_instance_id() == prepared_player and game.pilot.active and game.world_root.get_instance_id() == preloaded_world,"New Game reuses the prepared player and world")
	check(game.menu_backdrop.get_instance_id() == preloaded_backdrop,"First session reuses the prepared menu backdrop instead of rebuilding its display models")
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false); game.set_process(false)
	game.docking.current = game.submarine_traffic.port_by_id(1); game.docking.stage = game.Docking.Stage.DOCKED
	game.pilot.global_position = game.docking.current.inside
	game.player_progress.status.credits = 100
	var older: Dictionary = game._save_snapshot("Older manual"); older.saved_at = "2026-10-18T12:00:00"
	check(game.save_games.write(6,older) == OK,"Older save written in high-numbered slot")
	var newer := older.duplicate(true); newer.saved_at = "2026-10-19T12:00:00"; newer.progress.status.credits = 200
	check(game.save_games.write(0,newer) == OK and game.save_games.latest_slot() == 0,"Continue selects newest save by date rather than slot number")
	var automatic := newer.duplicate(true); automatic.saved_at = "2026-10-19T13:00:00"; automatic.progress.status.credits = 300
	check(game.save_games.write(-1,automatic) == OK and game.save_games.latest_slot() == -1,"Most recent autosave is eligible for Continue")
	var broken := FileAccess.open(game.save_games.path(3),FileAccess.WRITE); broken.store_string("broken save"); broken.close()
	check(game.save_games.latest_slot() == -1,"Corrupt saves do not hide the newest valid save")
	game.free(); await process_frame; paused = false
	game = preload("res://game.gd").new(); game.remember_preferences = false; game.show_start_menu = true; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete and not game.has_started_game and game.front_end.menu_layer.visible,"Actual fresh game instance opens at startup menu with existing saves")
	check(game.pilot != null and game.docking != null,"Cold Continue begins with gameplay systems already prepared")
	game.set_process(false)
	check(game.front_end.is_button_available("continue") and not game.front_end.can_resume,"Startup Continue is available without pretending there is a live game")
	check(game.front_end.active_button == game.front_end.buttons["continue"],"Continue is focused for controller use when a save exists")
	game.front_end._activate_button("load")
	check(game.dock_interface.visible and game.dock_interface.page == "load" and game.pilot != null,"Cold Load menu lists saves using the prepared player")
	game.dock_interface.dismiss(); game._show_main_menu()

	game.player_progress.status.credits = 999
	var accept := InputEventJoypadButton.new(); accept.button_index = JOY_BUTTON_A; accept.pressed = true
	game.front_end._input(accept)

	check(game.loading_save and game.loading_canvas.visible and not game.front_end.menu_layer.visible and not game.dock_interface.visible,"Selecting a save immediately replaces the interactive menu with loading artwork")
	var menu_event := InputEventAction.new(); menu_event.action = "main_menu"; menu_event.pressed = true
	game.front_end._input(menu_event)
	check(not game.front_end.menu_layer.visible and game.loading_canvas.visible,"Menu navigation cannot reopen the UI during restoration")
	for frame in range(1200):
		if game.has_started_game and not game.loading_save: break
		await process_frame
	check(game.has_started_game and game.player_progress.status.credits == 300,"Controller Continue loads latest autosave through real loader")
	check(not game.loading_canvas.visible and paused and game.dock_interface.visible and game.dock_interface.page == "home" and not game.front_end.menu_layer.visible,"Continue restores saved dock interface")
	game.player_progress.status.credits = 777
	game._show_main_menu(); await game._continue_game()
	check(game.player_progress.status.credits == 777 and not game.front_end.menu_layer.visible,"Continue resumes live session without reloading or losing progress")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_games.path(-1)))
	cold_menu(); await game._continue_game()
	check(game.has_started_game and game.player_progress.status.credits == 200,"Continue loads latest manual save when no autosave exists")
	# A well-formed save can reference unavailable equipment. Use the existing
	# load screen/error rather than silently loading a different, older game.
	var unavailable := newer.duplicate(true); unavailable.saved_at = "2026-10-19T14:00:00"
	unavailable.weapons = ["unavailable_test_weapon"]
	check(game.save_games.write(2,unavailable) == OK,"Compatibility-error fixture uses ordinary valid save format")
	cold_menu(); await game._continue_game()
	check(not game.has_started_game and game.dock_interface.visible and game.dock_interface.page == "load" and not game.front_end.menu_layer.visible,"Failed Continue leaves visible save selection")
	check(not game.loading_canvas.visible and not game.loading_save and game.dock_interface.status.contains("unavailable_test_weapon"),"Existing load error remains visible")
	game._dock_ui_action("close",{})
	check(game.front_end.is_button_available("continue") and game.front_end.menu_layer.visible,"Returning from load selection refreshes startup Continue")
	clear_saves(game.save_games)
	check(game.save_games.write(-1,automatic) == OK,"Only-autosave fixture created")
	cold_menu()
	check(game.front_end.is_button_available("load") and game.front_end.is_button_available("continue"),"Both Load and Continue work with an autosave alone")
	clear_saves(game.save_games); cold_menu()
	check(not game.front_end.is_button_available("continue") and not game.front_end.is_button_available("load"),"Removing all saves updates both menu buttons")
	check(game.save_games.VERSION == 1,"Published beta save format is unchanged")
	game.free(); await process_frame
	print("Continue game: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
