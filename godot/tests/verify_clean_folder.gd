extends SceneTree
const Game = preload("res://game.gd")
const Storage = preload("res://player_storage.gd")
const Paths = preload("res://asset_paths.gd")
const Mods = preload("res://mod_registry.gd")
var failures := 0
var checks := 0
func _initialize() -> void:
	Storage.root_override = ProjectSettings.globalize_path("res://..").trim_suffix("/") + "-test-player"
	if not OS.has_feature("editor"): Storage.root_override = OS.get_executable_path().get_base_dir() + "-test-player"
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2: push_error("Expected original asset folder and phase"); quit(1); return
	var assets: String = args[0]; var phase: String = args[1]
	preload("res://input_bindings.gd").reset_defaults()
	Mods.initialize(true)
	check(Mods.packs.size() == 5 and Mods.active_ids().is_empty(), "Five bundled mods are available, disabled by default")
	for pack in Mods.packs:
		check(pack.valid and pack.errors.is_empty(), "Bundled mod manifest and assets validate: " + str(pack.name))
	if phase == "mods":
		var ids: Array[String] = []
		for pack in Mods.packs: ids.append(str(pack.id))
		check(Mods.apply(ids, [], false) == OK, "All bundled mods activate together")
		var document: Dictionary = preload("res://map_document.gd").load_active()
		check(document.species.any(func(s: Dictionary) -> bool: return s.id == "clownfish" and s.random_spawn), "Clownfish joins the spawn pool")
		var fish := preload("res://map_document.gd").load_model("clownfish",assets,true)
		check(fish != null, "Bundled custom fish model loads")
		if fish != null:
			var meshes := fish.find_children("*","MeshInstance3D",true,false)
			check(not meshes.is_empty() and meshes[0].mesh.get_blend_shape_count() > 0, "Clownfish retains swimming animation")
			check(not meshes.is_empty() and meshes[0].mesh.surface_get_material(0).albedo_texture.get_meta("asset_mod", "") == "Clownfish", "Clownfish uses its bundled PNG skin")
			fish.free()
		for pack in Mods.packs:
			for id in pack.assets:
				var entry: Dictionary = pack.assets[id]
				if str(entry.path).get_extension().to_lower() == "glb":
					var model := preload("res://modern_model.gd").load_model(entry.path,entry)
					check(model != null, "Bundled GLB loads: " + str(id))
					if model != null: model.free()
	check(not FileAccess.file_exists("res://asset_editor.tscn") and not FileAccess.file_exists("res://map_editor.gd"), "Standalone editor is absent")
	check(not preload("res://map_document.gd").load_active().is_empty(), "Sibling Maps folder resolves from the clean project")
	var game := Game.new(); game.show_start_menu = true; root.add_child(game)
	if phase == "first":
		for frame in range(60): await process_frame
		check(game.folder_prompt.visible and game.game_folder.is_empty(), "First launch asks for original Sub Culture files")
		check(Paths.find_game_folder().is_empty(), "No development asset path was carried into the package")
		game._choose_game_folder(ProjectSettings.globalize_path("res://"))
		check(game.folder_prompt.visible and game.game_folder.is_empty(), "Invalid original-game folders are rejected")
		game.folder_prompt.hide()
		await game._choose_game_folder(assets)
	else:
		for frame in range(2400):
			if game.startup_complete: break
			await physics_frame
	check(game.startup_complete and game.pilot_mode, "Clean project loads the selected original world")
	if not game.startup_complete: quit(1); return
	check(game.front_end.menu_picture.texture != null and game.front_end.menu_layer.visible and paused, "Title art and live main menu work after a fresh import")
	check(game.status_label.text != "Could not automatically save settings.", "Shared settings load without a persistence error")
	check(Paths.find_game_folder() == assets, "Selected original-game folder persists in isolated preferences")
	if phase == "first":
		game._begin_new_game()
		check(game.has_started_game and not paused and is_equal_approx(game.day_night.hour,10), "New Game starts at 10:00")
		check(game.equipment.mounted.size() == 2 and game.weapons.mounted.size() == 1, "Starting tools and weapon load")
		check(game.world_root.get_meta("searchlight_count",0) == 10 and not game.object_population.snapshot().is_empty(), "Searchlights and world items load in the clean project")
		var port: Dictionary = game.docking.ports[0]
		game.docking.current = port; game.docking.saved_collision_mask = game.pilot.collision_mask
		game.pilot.global_position = port.inside; game.pilot.active = false; game.pilot.freeze = true
		game.docking._transition(game.Docking.Stage.DOCKED)
		game.dock_interface_active = false; game._process(0)
		check(paused and game.dock_interface.visible, "Docking opens working menus and pauses the outside world")
		game.player_progress.status.credits = 100000
		var offers: Dictionary = preload("res://commodity_market.gd").offers(game.gameplay_catalogue, game.player_progress, str(int(port.node.get_meta("city_id"))))
		var traded := false
		for id in offers:
			if offers[id].buy_price > 0 and offers[id].stock > 0:
				var before := int(game.player_progress.cargo.get(id,0))
				game._dock_ui_action("buy_commodity", {"item":id})
				traded = int(game.player_progress.cargo.get(id,0)) == before + 1
				break
		check(traded, "A commodity purchase updates cargo")
		var snapshot: Dictionary = game._save_snapshot("Clean folder test")
		check(game.save_games.write(0,snapshot) == OK, "Saving works in the isolated player folder")
	elif phase == "restart":
		check(not game.folder_prompt.visible, "Second launch remembers the selected asset folder")
		check(game.save_games.slots()[0].valid, "Second launch discovers the saved game")
		check(await game._load_saved_game(0), "Saved game loads after restarting the clean project")
		check(paused and game.dock_interface.visible and not game.player_progress.cargo.is_empty(), "Loaded dock, cargo and paused world survive restart")
		game._dock_ui_action("launch",{})
		check(not paused and game.docking.stage != game.Docking.Stage.DOCKED, "Launching resumes gameplay after load")
	else:
		check(game.pilot.visual.get_meta("modern_model", false), "All-mod game uses the remastered submarine")
		check(game.pilot.visual.get_meta("submarine_parts", {}).size() == 5, "Remastered moving assemblies resolve")
		game._begin_new_game()
		check(game.has_started_game and not paused, "New Game runs with all bundled mods enabled")
		check(Mods.runtime_warnings.is_empty(), "No mod asset fallback warnings")
		for frame in range(60): await physics_frame
	if DisplayServer.get_name() != "headless":
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(Storage.root_override.get_base_dir().path_join("clean-test-" + phase + ".png"))
	game.queue_free(); await process_frame
	print("Clean folder ",phase,": ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
