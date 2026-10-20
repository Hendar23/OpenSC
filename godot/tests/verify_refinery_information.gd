extends "res://tests/verify_stage_two_missions.gd"

func _initialize() -> void:
	var paths = preload("res://asset_paths.gd")
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	if not paths.valid_game_folder(folder): folder = paths.find_game_folder()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-refinery-information-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")

func capture_information(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/refinery-information-"+name+".png")

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Refinery fixture loads")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.docking.set_physics_process(false); game.set_process(false); game.set_physics_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	port(6); paused = true
	var ui: CanvasLayer = game.dock_interface
	ui.open("missions")
	var info: Array = runtime.board(6).information
	check(info.map(func(entry: Dictionary) -> String: return entry.id) == ["ore","metal","pearl"],"All three original factory entries are present in source order")
	check(not runtime.board(6).available and runtime.board(6).information_only,"Refinery guides never become accepted missions")
	check(ui.layout.get_node_or_null("accept_mission") == null,"Original refinery screen has no Accept control")
	check(ui.layout.find_children("*","Label",true,false).all(func(label: Label) -> bool: return label.text not in ["No missions available","Missions"]),"Refinery has neither the invented empty-list label nor a mission heading")
	var expected := preload("res://legacy_bmp.gd").load_image(game.game_folder.path_join("INTROTEX/RDEFAULT.BMP"))
	check(ui.layout.get_node("MissionPicture").texture.get_image().get_data() == expected.get_data(),"Refinery welcome uses the original RDEFAULT picture")
	check(ui.layout.get_node("MissionBriefingScroll/MissionBriefing").text.contains("list of what we are currently trading"),"Original welcome now has its corresponding selectable list")
	await capture_information("welcome")
	var before: Dictionary = game.player_progress.duplicate(true)
	for entry in info:
		var row: Button = ui.layout.get_node("RefineryInfo_"+entry.id)
		check(row.text == runtime.text(entry.id).get_slice("\n",0),"Original refinery guide title: "+entry.id)
		row.pressed.emit()
		check(ui.layout.get_node("MissionBriefingScroll/MissionBriefing").text == runtime.text(entry.id),"Selecting the guide shows all its original instructions: "+entry.id)
		check(ui.layout.get_node("MissionPicture").texture != null,"Guide picture loads: "+entry.id)
		check(ui.layout.get_node_or_null("accept_mission") == null and runtime.can_save(),"Reading a guide cannot start a mission: "+entry.id)
		await capture_information(entry.id)
	check(game.player_progress == before,"Browsing refinery guides changes no credits, inventory, missions or campaign state")
	var ore: Button = ui.layout.get_node("RefineryInfo_ore")
	check(ore.find_valid_focus_neighbor(SIDE_BOTTOM) == ui.layout.get_node("RefineryInfo_metal"),"Controller moves down through the guide list")
	check(ui.layout.get_node("RefineryInfo_pearl").find_valid_focus_neighbor(SIDE_BOTTOM) == ui.layout.get_node("MissionBriefingScroll"),"Controller reaches the scrollable guide from the final row")
	check(ui.layout.get_node("home").find_valid_focus_neighbor(SIDE_RIGHT) == ui.layout.get_node("home"),"Done cannot navigate into the absent refinery Accept control")
	port(1); check(runtime.accept(1).is_empty(),"Opening mission still accepts normally")
	port(6); ui.open("missions")
	check(ui.layout.get_node("choose_mission").text.begins_with("Current mission:") and ui.layout.get_node_or_null("RefineryInfo_ore") != null,"Current campaign objective coexists with refinery guides")
	ui.layout.get_node("RefineryInfo_metal").pressed.emit()
	check(ui.layout.get_node("MissionBriefingScroll/MissionBriefing").text == runtime.text("metal") and runtime.active().id == "tradetrad","Guide selection overrides the briefing without changing the active mission")
	ui.layout.get_node("choose_mission").pressed.emit()
	check(ui.layout.get_node("MissionBriefingScroll/MissionBriefing").text == runtime.text("tradetrad"),"Current mission can be selected again after reading a guide")
	runtime.finish(false); game.player_progress.campaign_stage = 7; port(1); ui.open("missions")
	check(not runtime.board(1).available and ui.layout.find_children("*","Label",true,false).all(func(label: Label) -> bool: return label.text != "No missions available"),"Empty city mission lists retain the original blank presentation")
	paused = false; game.queue_free(); await process_frame
	print("Refinery information: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
