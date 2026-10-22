extends "res://tests/verify_remaining_stage_two.gd"

func start_game() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for developer mission persistence")
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	game.remember_preferences = true

func unlock_button() -> Button:
	return game.developer_tabs.get_node("System/UnlockTestingMissions")

func offers_remain_local() -> void:
	for city in [1,2,3,4,5,6]:
		var expected: Array = runtime.testing_missions().filter(func(id: String) -> bool: return runtime.testing_mission_city(id) == city)
		var offered: Array = runtime.board(city).offers.map(func(entry: Dictionary) -> String: return entry.id)
		expected.sort(); offered.sort()
		check(offered == expected,"Restored testing offers remain at their correct station: " + str(city))

func run() -> void:
	var path := preload("res://current_settings.gd").path("view_defaults.cfg")
	var config := ConfigFile.new(); config.set_value("developer","enabled",true); config.save(path)
	await start_game()
	if not game.startup_complete: quit(1); return
	check(not runtime.testing_all_missions and not unlock_button().button_pressed,"Existing settings without an unlock preference default to Off")
	await game._begin_new_game()
	game.docking.current = game.submarine_traffic.port_by_id(1); game.docking.stage = game.Docking.Stage.DOCKED
	game.player_progress.status.credits = 12345
	var snapshot: Dictionary = game._save_snapshot("Developer preference fixture")
	check(game.save_games.write(0,snapshot) == OK,"Write a normal beta-compatible campaign save")
	unlock_button().button_pressed = true
	await process_frame; await process_frame
	config.load(path)
	check(config.get_value("developer","testing_all_missions",false) == true,"Developer toggle automatically persists its enabled state")
	check(unlock_button().text.ends_with("On"),"Enabled developer button matches runtime")
	check(await game._load_saved_game(0),"Load campaign in the same session")
	check(runtime.testing_all_missions and unlock_button().button_pressed,"Loading a save retains the enabled testing preference")
	offers_remain_local()
	check(game.player_progress.campaign_stage == snapshot.progress.campaign_stage and game.player_progress.status.credits == 12345,"Testing override does not advance the campaign or alter credits")
	check(not snapshot.has("testing_all_missions") and not snapshot.progress.has("testing_all_missions"),"Developer override is independent of published campaign save data")
	game.remember_preferences = false; game.free(); paused = false
	await process_frame
	await start_game()
	if not game.startup_complete: quit(1); return
	check(runtime.testing_all_missions and unlock_button().button_pressed and unlock_button().text.ends_with("On"),"A fresh game instance restores the preference and button")
	check(await game._load_saved_game(0),"A fresh instance loads the existing save")
	check(runtime.testing_all_missions,"Fresh-start save loading retains the testing override")
	offers_remain_local()
	game.dock_interface.open("missions")
	check(game.dock_interface.layout.get_node_or_null("MissionOffer_escort") != null,"Loaded dock mission screen includes later testing jobs")
	unlock_button().button_pressed = false
	await process_frame; await process_frame
	config.load(path)
	check(config.get_value("developer","testing_all_missions",true) == false,"Turning testing Off also persists")
	check(game.dock_interface.layout.get_node_or_null("MissionOffer_escort") == null,"Turning Off immediately rebuilds the open mission board")
	check(await game._load_saved_game(0),"Reload after disabling the override")
	check(not runtime.testing_all_missions and not unlock_button().button_pressed and runtime.board(1).offers.size() == 1,"Loading restores normal progression while testing is Off")
	config.set_value("developer","testing_all_missions",true); config.save(path); game._load_preferences()
	check(runtime.testing_all_missions and unlock_button().button_pressed,"Settings reload synchronizes runtime and developer button")
	var equipment_button: Button = game.developer_tabs.get_node("System/UnlockTestingEquipment")
	equipment_button.button_pressed = true
	game.player_progress.status.credits = 100000
	await game._begin_new_game()
	await process_frame; await process_frame
	check(not runtime.testing_all_missions and not unlock_button().button_pressed and unlock_button().text.ends_with("Off"),"New Game resets the mission override and its button")
	check(not game.testing_all_equipment and not equipment_button.button_pressed and equipment_button.text.ends_with("Off"),"New Game resets the equipment override and its button")
	check(game.player_progress.status.credits == Progress.restore().status.credits and runtime.board(1).offers.size() == 1,"New Game restores starting credits and normal mission progression")
	config.load(path)
	check(config.get_value("developer","testing_all_missions",true) == false,"New Game persists the reset so restarting cannot restore the old override")
	check(await game._load_saved_game(0) and not runtime.testing_all_missions,"Loading after New Game keeps testing Off until explicitly enabled again")
	unlock_button().button_pressed = true
	check(await game._load_saved_game(0) and runtime.testing_all_missions,"Explicitly re-enabling testing still survives loading a save")
	config.set_value("developer","testing_all_missions",true)
	config.set_value("developer","enabled",false); config.save(path); game._load_preferences()
	check(not runtime.testing_all_missions and not unlock_button().button_pressed,"Release-disabled developer tools cannot activate saved mission overrides")
	config.set_value("developer","enabled",true); config.set_value("developer","testing_all_missions","true"); config.save(path); game._load_preferences()
	check(not runtime.testing_all_missions,"Malformed non-boolean unlock preferences remain disabled")
	game.remember_preferences = false; game.free(); paused = false
	await process_frame
	print("Testing mission persistence verification: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
