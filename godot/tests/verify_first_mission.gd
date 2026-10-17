extends "res://tests/test_scene_tree.gd"
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-mission-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",ProjectSettings.globalize_path("res://../Original Sub Culture")); config.save(storage.preferences_path())
	call_deferred("run")
func run() -> void:
	var game := preload("res://game.gd").new(); game.remember_preferences = false; game.show_start_menu = true; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game loads mission runtime")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.set_physics_process(false); game.pilot.freeze = true
	game.docking.set_physics_process(false)
	var runtime: Node = game.mission_runtime
	var initial_npcs: int = game.submarine_traffic.traders.size()
	var backdrop: Node3D = game.menu_backdrop
	check(backdrop.pass_visuals.size() == backdrop.PASS_MODELS.size() + 1,"Menu fly-by pool includes player and all faction/pirate variants")
	var selected := {}; var heights := {}
	backdrop.random.seed = 20261015; backdrop.active = true
	for attempt in range(80):
		backdrop.pass_time = -1; backdrop.next_pass = 0; backdrop._process(0)
		heights[str(backdrop.pass_height)] = true
		for index in range(backdrop.pass_visuals.size()):
			if backdrop.pass_visuals[index].visible: selected[index] = true
	check(selected.size() == backdrop.pass_visuals.size() and heights.size() > 1,"Menu fly-bys vary ship and height between passes")
	backdrop.active = false; backdrop.hide()
	check(not runtime.board(5).available and not runtime.board(6).available,"Special docks do not offer prospecting")
	for city in [1,2,3,4]:
		game.player_progress = preload("res://player_progress.gd").restore()
		for port in game.docking.ports:
			if int(port.node.get_meta("city_id")) == city: game.docking.current = port
		game.docking.stage = game.Docking.Stage.DOCKED
		check(runtime.board(city).available,"First job offered at city %d" % city)
		var credits: int = game.player_progress.status.credits
		check(runtime.accept(city).is_empty(),"Accept first mission %d" % city)
		check(runtime.spawned.size() == 13,"Five inert crystals, four bonus ore, three caps and one pirate")
		check(runtime.pirate.patrol.size() == 5 and is_equal_approx(runtime.pirate.health.remaining,9.0),"Original patrol and weakened pirate")
		check(game.save_games.read(-1).progress.missions.active.is_empty(),"Autosave records state before acceptance")
		var before_mission := FileAccess.get_file_as_string(game.save_games.path(-1))
		game._autosave_docked()
		check(FileAccess.get_file_as_string(game.save_games.path(-1)) == before_mission,"Mission docking preserves pre-mission autosave byte for byte")
		check(game.save_games.write(0,game._save_snapshot("Blocked")) == ERR_UNAVAILABLE,"Backend refuses mission saves")
		check(not game._dock_ui_model().can_save,"UI exposes save restriction")
		runtime.docked(city); check(not runtime.can_save(),"Home docking before refinery does not complete")
		runtime.docked(6); check(runtime.active().refinery,"Refinery visit is recorded")
		# Original resolves without refined cargo; alternate text explicitly acknowledges that.
		runtime.docked(city); check(runtime.can_save(),"Docking after refinery completes")
		check(game.player_progress.campaign_stage == 2,"Core advances campaign exactly once")
		check(runtime.last_response.contains("No refined thorium"),"Original empty cargo response")
		check(game.player_progress.status.credits == credits,"No invented flat reward")
		check(game.submarine_traffic.traders.size() == initial_npcs,"Mission pirate cleaned up")
		runtime.docked(city); check(game.player_progress.campaign_jobs == 1,"Duplicate docking cannot award again")
		var saved_result: Error = game.save_games.write(0,game._save_snapshot("After mission"))
		check(saved_result == OK,"Saving restored after completion: " + game.save_games.error)
	game.player_progress = preload("res://player_progress.gd").restore()
	runtime.accept(4); runtime.finish(false)
	check(runtime.can_save() and game.player_progress.campaign_stage == 1,"Failure leaves opening job retryable")
	check(runtime.board(4).available,"Failed job available again")
	runtime.accept(4); runtime.docked(6); game.player_progress.cargo.thorium = 1; runtime.docked(4)
	check(runtime.last_response.contains("Excellent! You have refined thorium"),"Refined cargo selects positive response")
	game.dock_interface_active = true; paused = true
	game.dock_interface.open("missions")
	await process_frame
	check(game.dock_interface.layout.find_children("*","RichTextLabel",true,false).size() >= 1,"Mission response has scrollable briefing")
	# Save failure must leave mission/world untouched.
	game.player_progress = preload("res://player_progress.gd").restore()
	var valid_folder: String = game.save_games.folder
	var blocker := FileAccess.open("res://tests/cache-mission-fixtures/blocker",FileAccess.WRITE); blocker.store_string("file"); blocker.close()
	game.save_games.folder = "res://tests/cache-mission-fixtures/blocker/invalid"
	check(not runtime.accept(4).is_empty() and runtime.can_save(),"Autosave failure prevents acceptance")
	check(game.submarine_traffic.traders.size() == initial_npcs,"Autosave failure adds no actors")
	game.save_games.folder = valid_folder
	check(runtime.accept(4).is_empty(),"Retry after autosave failure")
	check(await game._load_saved_game(-1),"Before-mission save is loadable while a job is active")
	check(runtime.can_save() and game.player_progress.campaign_stage == 1,"Loading restores pre-mission progression")
	check(game.submarine_traffic.traders.size() == initial_npcs,"Loading clears temporary encounter")
	game._begin_new_game()
	for port in game.docking.ports:
		if int(port.node.get_meta("city_id")) == 1: game.docking.current = port
	game.docking.stage = game.Docking.Stage.DOCKED; game.dock_interface_active = true; paused = true
	game.dock_interface.open("missions")
	var done := game.dock_interface.layout.get_node("home") as Button
	var accept := game.dock_interface.layout.get_node("accept_mission") as Button
	var row := game.dock_interface.layout.get_node("choose_mission") as Button
	check(accept.disabled,"Accept stays disabled until a mission is selected")
	check(done.find_valid_focus_neighbor(SIDE_RIGHT) == done,"Right stays on Done while Accept is disabled")
	check(done.find_valid_focus_neighbor(SIDE_TOP) is ScrollContainer,"Up reaches briefing from Done")
	row.pressed.emit()
	accept = game.dock_interface.layout.get_node("accept_mission") as Button
	row = game.dock_interface.layout.get_node("choose_mission") as Button
	done = game.dock_interface.layout.get_node("home") as Button
	check(not accept.disabled and row.find_valid_focus_neighbor(SIDE_BOTTOM) is ScrollContainer,"Selected mission leads down to briefing")
	check(done.find_valid_focus_neighbor(SIDE_RIGHT) == accept and accept.find_valid_focus_neighbor(SIDE_LEFT) == done,"Done and Accept navigate horizontally")
	check(row.find_valid_focus_neighbor(SIDE_RIGHT) == row,"Right cannot jump vertically from mission row")
	check(accept.held_art[0].rect.position + accept.position == Vector2(547,415),"Pressed Accept artwork aligns with the original panel")
	var mission_picture := game.dock_interface.layout.get_node("MissionPicture") as TextureRect
	check(mission_picture.texture != null,"Selected mission displays its own picture")
	check(runtime.board(1).welcome.contains("Bohine Recruitment Agency"),"Original recruitment welcome is available")
	var briefing := game.dock_interface.layout.find_children("*","RichTextLabel",true,false)[0] as RichTextLabel
	check(briefing.get_theme_font_size("normal_font_size") == 10,"Mission text uses smaller original-style sizing")
	check(done.find_valid_focus_neighbor(SIDE_TOP) is ScrollContainer,"Controller can reach briefing")
	var scroll := done.find_valid_focus_neighbor(SIDE_TOP) as ScrollContainer
	scroll.grab_focus(); await process_frame
	var down := InputEventJoypadButton.new(); down.button_index = JOY_BUTTON_DPAD_DOWN; down.pressed = true
	root.push_input(down,true); await process_frame
	check(scroll.scroll_vertical > 0,"Controller scrolls the full original briefing")
	game._dock_ui_action("accept_mission",{})
	check(not runtime.can_save() and game.dock_interface.page == "home","Accepting returns directly to dock home")
	game.dock_interface.open("home")
	check(game.dock_interface.layout.get_node_or_null("save") == null,"Dock Save button is removed during mission")
	check(game.dock_interface.layout.get_node_or_null("NoSavePanel") != null,"Original wood panel replaces the removed Save artwork")
	runtime._radio("ag2","PIR")
	check(not game.radio_feed.entries.is_empty(),"Mission transmission appears in history immediately")
	var message: Dictionary = game.bounty_radio_queue.back()
	var expected := preload("res://docking_radio.gd").speaker_portrait(game.game_folder,"pir")
	check(message.portrait.get_image().get_data() == expected.get_image().get_data(),"Pirate message uses radio portrait rather than fish texture")
	runtime._collected("ore"); message = game.bounty_radio_queue.back()
	expected = preload("res://docking_radio.gd").speaker_portrait(game.game_folder,"ship")
	check(message.portrait.get_image().get_data() == expected.get_image().get_data(),"Computer tutorial uses ship computer portrait")
	game.dock_interface.open("load")
	var automatic := game.dock_interface.layout.get_node("choose_slot_-1") as Button
	check(not automatic.disabled and automatic.text == "Auto Save","Load screen includes reserved automatic slot")
	check(automatic.position.y > game.dock_interface.layout.get_node("choose_slot_6").position.y,"Automatic slot sits below all seven manual slots")
	game.dock_interface.open("save")
	check(game.dock_interface.layout.get_node_or_null("choose_slot_-1") == null,"Automatic slot is reserved for loading rather than manual saving")
	var original_distance: float = game.pilot.movement.settings.camera_distance
	var cargo := RigidBody3D.new(); cargo.freeze = true; cargo.set_meta("test_cargo",true); game.world_root.add_child(cargo)
	cargo.global_position = game.pilot.global_position + Vector3.DOWN * 1.0
	game._set_camera_mode(false); game._update_follow_camera(0,true)
	var normal_camera: Vector3 = game.camera.global_position
	for tool in [game.equipment.magnet,game.equipment.grapple]:
		tool.target = cargo; game._update_follow_camera(0,true)
		check(game.camera.global_position.distance_to(game.pilot.global_position) > normal_camera.distance_to(game.pilot.global_position),"Attached %s cargo pulls third person camera back" % tool.tool_id)
		tool.target = null; game._update_follow_camera(0,true)
		check(game.camera.global_position.is_equal_approx(normal_camera),"Releasing %s restores normal view" % tool.tool_id)
	check(game.pilot.movement.settings.camera_distance == original_distance,"Towing leaves saved camera preference unchanged")
	cargo.free()
	var traffic: Node = game.submarine_traffic
	while not traffic.navigation_ready: traffic.build_graph(10000); await process_frame
	var trader: Node3D
	for agent in traffic.traders:
		if agent.get_parent().name == "Trader_1": trader = agent
	check(trader != null and traffic.water_clear(trader.home.origin),"Relocated Touka trader starts in clear water")
	check(trader.home.origin.distance_to(traffic.port_by_id(1).entry) > 20 and not traffic.route(trader.home.origin,traffic.port_by_id(1).entry).is_empty(),"Touka trader has a longer valid approach")
	game.pilot.global_position = traffic.port_by_id(6).entry + Vector3(0,1.5,-1)
	var attack_path: PackedVector3Array = runtime.pirate._attack_route(game.pilot.global_position)
	check(not attack_path.is_empty() and runtime.pirate._clear_shot(attack_path[-1],game.pilot.global_position),"Pirate finds a reachable firing position around the refinery dock")
	var crystal: RigidBody3D = runtime.spawned[0]
	game.object_population._shatter(crystal)
	var shards := 0
	for body in game.object_population.get_children():
		if body.has_meta("mission_owner") and body.get("shard") != null and body.shard > 0: shards += 1
	check(shards == 3,"Shattered mission crystals retain ownership for cleanup")
	game._submarine_destroyed()
	check(runtime.can_save() and runtime.outcome.visible,"Death triggers failed outcome and releases mission")
	game._begin_new_game()
	check(runtime.can_save() and runtime.last_response.is_empty(),"New Game clears mission and response")
	game.free(); print("First mission: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
