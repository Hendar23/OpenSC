extends SceneTree
const Game = preload("res://game.gd")
var failures := 0
var checks := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/dock-ui-" + name + ".png")
func run() -> void:
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Game loads")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	game.save_games.folder = "res://tests/save-fixture"
	var port: Dictionary = game.docking.ports[0]
	game.docking.current = port; game.docking.saved_collision_mask = game.pilot.collision_mask
	game.pilot.global_position = port.inside; game.pilot.active = false; game.pilot.freeze = true
	game.docking._transition(game.Docking.Stage.DOCKED)
	game.day_night.hour = 18.25; game.equipment.mounted[0].enabled = true
	game.cockpit_hud.map_data.explored.fill(Color.BLACK)
	game.cockpit_hud.map_data.explored.set_pixel(100,101,Color.WHITE)
	var snapshot: Dictionary = game._save_snapshot("Test dock")
	var map_document: Dictionary = preload("res://map_document.gd").load_active()
	var transitional_signature := JSON.stringify(map_document).sha256_text()
	check(not game._exploration_matches_map(transitional_signature),"Legacy placement hashes cannot identify explored terrain")
	map_document.erase("object_types"); map_document.erase("object_groups")
	check(not game._exploration_matches_map(JSON.stringify(map_document).sha256_text()),"Pre-object hashes do not restore uncertain exploration")
	check(snapshot.map_signature == "terrain-v1:" + FileAccess.get_sha256(game.game_folder.path_join("DATA/SCEN1.BSP")),"New saves identify the underlying terrain")
	map_document.object_types = [preload("res://object_definitions.gd").FLOATING_MINE.duplicate(true)]
	map_document.object_groups = [{"id":"test_mines","name":"Mines","type":"floating_mine","position":[1,2,3],"count":10,"radius":5.0}]
	map_document.object_types[0].damage = 45
	# Load an edited map through the real mod path without changing the user's map.
	map_document.entities.player_spawn.transform[9] += 10.0
	var pack_dir := "res://tests/save-map-fixture/edited"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(pack_dir))
	check(preload("res://map_document.gd").save(map_document,pack_dir.path_join("map.json")) == OK,"Edited map fixture validates")
	var manifest := FileAccess.open(pack_dir.path_join("mod.json"),FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema_version":1,"id":"save-map-test","name":"Save map test","assets":{"map.scen1":"map.json"}})); manifest.close()
	game.Mods.initialize(false,"res://tests/save-map-fixture"); game.Mods.apply(["save-map-test"],[],false)
	check(snapshot.map_signature == game._map_signature() and game._exploration_matches_map(snapshot.map_signature),"Object stats, mine placement and spawn moves preserve save compatibility")
	game.Mods.initialize(false)
	for file in ["map.json","mod.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(pack_dir.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pack_dir)); DirAccess.remove_absolute(ProjectSettings.globalize_path(pack_dir.get_base_dir()))
	check(game.save_games.write(0,snapshot) == OK,"Writes named slot")
	snapshot.name = "Replacement"
	check(game.save_games.write(0,snapshot) == OK,"Atomically replaces existing slot")
	check(game.save_games.read(0).name == "Replacement","Replacement is readable")
	check(game.save_games.slots().size() == 7,"Seven slots available")
	check(game.save_games.slots()[0].city == port.name,"Save slots display the current proper city name")
	game._show_main_menu()
	check(game.front_end.is_button_available("load"),"Main menu enables Load Game when a save exists")
	game.front_end._activate_button("load")
	check(game.dock_interface.visible and game.dock_interface.page == "load" and not game.front_end.menu_layer.visible,"Main menu opens the load browser")
	game._dock_ui_action("close",{}); game._resume_game()
	var corrupt := FileAccess.open(game.save_games.path(6),FileAccess.WRITE); corrupt.store_string("broken"); corrupt.close()
	check(not game.save_games.slots()[6].valid,"Corrupt slot cannot be loaded")
	game.dock_interface.open("home"); await capture("home")
	game.dock_interface.button_nodes[1].grab_focus()
	var accept := InputEventJoypadButton.new(); accept.button_index = JOY_BUTTON_A; accept.pressed = true
	game.dock_interface._input(accept)
	check(game.dock_interface.page == "equipment","Controller A activates the focused dock control")
	var override_path := "res://tests/dock-layout-fixture.json"
	var layout_file := FileAccess.open(override_path,FileAccess.WRITE)
	layout_file.store_string(JSON.stringify({"schema_version":1,"text_colour":[1,0,0],"pages":{"home":{"title":[20,20,100,30]}}})); layout_file.close()
	game.Mods.layers["ui.dock"] = [{"path":override_path}]
	game.dock_interface.setup(game.game_folder,game._dock_ui_model); game.dock_interface.open("home")
	check(game.dock_interface.text_colour == Color.RED and game.dock_interface.rect(game.dock_interface.pages.home.title) == Rect2(20,20,100,30),"Mod layout and text colour override survives a screen rebuild")
	game.Mods.layers.erase("ui.dock"); DirAccess.remove_absolute(ProjectSettings.globalize_path(override_path))
	game.dock_interface.setup(game.game_folder,game._dock_ui_model)
	for page in ["equipment","goods","missions","save","load"]:
		game.dock_interface.open(page); await capture(page)
	game.day_night.hour = 7; game.equipment.mounted[0].enabled = false
	game.cockpit_hud.map_data.explored.fill(Color.WHITE)
	var restored: bool = await game._load_saved_game(0)
	check(restored,"Saved game reloads")
	check(game.docking.stage == game.Docking.Stage.DOCKED and game.docking.current.name == port.name,"Returns to saved dock")
	check(is_equal_approx(game.day_night.hour,18.25),"Restores time of day")
	check(game.equipment.mounted[0].enabled,"Restores headlight state")
	check(game.cockpit_hud.map_data.explored.get_pixel(100,101).r > 0.99 and game.cockpit_hud.map_data.explored.get_pixel(99,101).r < 0.01,"Restores explored fog mask")
	check(game.dock_interface.visible and not game.pilot.visual.visible,"Dock UI displayed with docked sub hidden")
	var launch_camera: Vector3 = game.docking.cinematic_camera
	var launch_basis: Basis = game.Docking.upright_basis(game.pilot.global_basis)
	var launch_offset: Vector3 = launch_camera - game.docking.current.entry
	check(is_equal_approx(launch_camera.y,game.docking.current.entry.y),"Restored camera is at launch height above the dock")
	check(launch_offset.dot(launch_basis.z) > 1.99 and launch_offset.dot(launch_basis.x) > 0,"Restored camera is behind and to the right of the sub")
	check(not game._exploration_matches_map("a".repeat(64)),"Unknown legacy terrain resets exploration only")
	check(not game._exploration_matches_map("terrain-v1:" + "a".repeat(64)),"Different terrain resets exploration only")
	var incompatible := snapshot.duplicate(true); incompatible.map_signature = "different"
	game.save_games.write(1,incompatible)
	check(await game._load_saved_game(1),"Loads a save from a different physical map")
	check(game.cockpit_hud.map_data.explored.get_pixel(100,101).r == 0.0,"Changed map starts with fresh exploration")
	check(game.pilot.global_position.is_equal_approx(game.docking.current.inside),"Load uses the current dock location")
	var missing_dock := snapshot.duplicate(true); missing_dock.dock.id = -999
	game.save_games.write(1,missing_dock)
	check(not await game._load_saved_game(1),"Missing saved dock still prevents loading")
	var missing_item := snapshot.duplicate(true); missing_item.weapons.append("unavailable-test-weapon")
	game.save_games.write(1,missing_item)
	check(not await game._load_saved_game(1),"Missing inventory item still prevents loading")
	# Switching from cockpit must not snap the launch camera back into the dock.
	game.first_person = true
	game._dock_ui_action("launch",{})
	check(game.docking.stage != game.Docking.Stage.DOCKED,"Launch starts undocking")
	game.docking.set_physics_process(false)
	game._process(0)
	check(game.camera.global_position.is_equal_approx(launch_camera) and not game.first_person,"Launch preserves outside camera even after cockpit mode")
	check((-game.camera.global_basis.z).y > -0.01,"Launch view frames the exit instead of looking down through the lid")
	await capture("launch-camera")
	for frame in range(2000):
		if game.docking.stage == game.Docking.Stage.IDLE: break
		game.docking._physics_process(0.1)
	check(game.docking.stage == game.Docking.Stage.IDLE and game.pilot.active,"Loaded save can finish undocking")
	# Read real legacy saves, but only write copies into the isolated test folder.
	var actual_saves := preload("res://save_games.gd").new()
	for slot in [0,6]:
		var actual := actual_saves.read(slot)
		if actual.is_empty(): continue
		check(not game._exploration_matches_map(actual.map_signature),"Legacy slot %d starts with fresh exploration" % slot)
		game.save_games.write(2,actual)
		check(await game._load_saved_game(2),"Loads a fixture copy of user's legacy slot %d" % slot)
	for slot in [0,1,2,6]: DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_games.path(slot)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_games.folder))
	paused = false; game.queue_free(); await process_frame
	print("Dock save/load: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
