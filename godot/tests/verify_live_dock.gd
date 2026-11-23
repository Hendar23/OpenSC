extends "res://tests/test_scene_tree.gd"
const Trader = preload("res://trader_submarine.gd")
const Vessel = preload("res://mission_vessel.gd")
const Access = preload("res://dock_access.gd")
var checks := 0
var failures := 0
var destroyed := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func _initialize() -> void: call_deferred("run")

func vessel(game: Node, port: Dictionary, mission: bool) -> Node3D:
	var model := Node3D.new(); game.world_root.add_child(model)
	model.global_position = port.entry
	var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); model.add_child(mesh)
	var values := {"npc_health":10.0,"npc_sustain":0.3,"npc_faction":1}
	var agent: Node3D = Vessel.install_mission(model,values) if mission else Trader.install(model,values)
	game.submarine_traffic.register_vessel(agent,game.world_root,game.game_folder)
	agent.set_physics_process(false)
	agent.destroyed.connect(func(_id: String,_attacker: String) -> void: destroyed += 1)
	return agent

func run() -> void:
	var storage = preload("res://player_storage.gd")
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = preload("res://asset_paths.gd").find_game_folder()
	storage.root_override = test_fixture_path("live-dock"); storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",folder); config.save(storage.preferences_path())
	var game := preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Live dock game loads")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game()
	game.pilot.freeze = true; game.docking.set_physics_process(false)
	game.save_games.folder = storage.saves_path()
	game.day_night.hour = 10
	var graphics: Node = game.front_end.player_graphics
	graphics.set_value("fog_distance",30.0)
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280,960)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../.local/live-dock"))
	for port in game.docking.ports:
		game.docking.current = port; game.pilot.global_position = port.inside
		game.pilot.active = false; game.pilot.controls_enabled = false
		game.docking._transition(game.Docking.Stage.DOCKED)
		game.dock_interface_active = false; game._process(0)
		check(not paused and game.dock_interface.live_window,"City %s has a live picture window" % port.name)
		check(is_equal_approx(game.water_environment.fog_depth_begin,game.fog_start_slider.value * 0.8) and is_equal_approx(game.water_environment.fog_depth_end,game.fog_visibility * 0.8),"City %s uses the fixed 80%% fog distance" % port.name)
		var title: TextureRect = game.dock_interface.layout.get_node("CityTitle")
		check(title.texture.get_image().get_pixel(0,0).a == 0,"City %s title corners are transparent" % port.name)
		check(not game.cockpit_hud.visible and not game.radio_feed.visible and not game.docked_screen.visible,"City %s window contains no piloting HUD or opaque dock backdrop" % port.name)
		var fixed := game.camera.global_transform
		var health: float = game.pilot.health; game.pilot.take_weapon_damage(100)
		check(game.pilot.health == health,"Docked player remains protected")
		game._process(1)
		check(game.camera.global_transform.is_equal_approx(fixed),"City camera remains fixed")
		if DisplayServer.get_name() != "headless":
			for frame in range(6): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../.local/live-dock/city-%s.png" % port.node.get_meta("city_id"))
		for page in ["equipment","goods","missions","save"]:
			game.dock_interface.open(page)
			check(not game.dock_interface.live_window and game.dock_interface.backdrop.material == null,"%s retains its original solid %s screen" % [port.name,page])
		game.dock_interface.open("home")
	graphics.set_value("fog_distance",60.0)
	check(is_equal_approx(game.water_environment.fog_depth_end,game.fog_visibility * 0.8),"Changing the gameplay fog distance leaves the dock view at 80%")
	# Timers and radio pause independently of outside-world processing.
	var jobs: Node = game.mission_runtime.side_jobs
	game.player_progress.missions.active = {"id":"fixture"}; jobs.id = "fixture"; jobs.phase = "fixture"
	jobs.age = 20; jobs.clock = 30; jobs._physics_process(10)
	check(jobs.age == 20 and jobs.clock == 30,"Mission clocks do not advance while docked")
	game.radio_feed.clear(); game.game_radio.set_docked(false)
	game.radio_feed.push_message({"speaker":"fixture","text":"Existing radio"})
	game.game_radio.set_docked(true); game.radio_feed._process(20)
	check(game.radio_feed.entries[0].age == 0,"Existing radio lifetime pauses")
	game.radio_feed.push_message({"speaker":"later","text":"Queued radio"})
	check(game.radio_feed.entries.size() == 1 and game.radio_feed.pending.size() == 1,"Outside transmissions wait while docked")
	game.game_radio._pirate_bounty(game.docking.current.entry)
	var ttl: float = game.bounty_radio_queue.back().ttl
	game._update_radio_messages(20)
	check(game.bounty_radio_queue.back().ttl == ttl and game.bounty_radio_queue.back().get("deferred",false),"Combat bounty is retained for radio after launch")
	game.mission_runtime._radio("ag1","PIR")
	check(game.bounty_radio_queue.back().get("deferred",false) and not game.mission_runtime.speech.playing,"Mission transmissions queue without speaking over dock controls")
	game.mission_runtime.speech.stream = game.radio_message_audio.stream
	game.mission_runtime.speech.volume_db = -80; game.mission_runtime.speech.play()
	game.game_radio.set_docked(true)
	check(game.mission_runtime.speech.stream_paused,"An existing playing radio stream pauses while docked")
	game.game_radio.set_docked(false)
	check(not game.mission_runtime.speech.stream_paused,"Mission speech resumes after leaving dock")
	game.mission_runtime.speech.stop()
	check(game.radio_feed.pending.is_empty() and game.radio_feed.entries.size() == 2,"Queued feed resumes on leaving dock")
	game.player_progress.missions.active = {}; jobs.id = ""; jobs.phase = "finished"
	# Exit obstruction cleanup uses actual ships, collision, locks and navigation.
	var port: Dictionary = game.docking.current
	var ordinary := vessel(game,port,false)
	ordinary.port = port; Access.acquire(port,ordinary)
	game.submarine_traffic.clear_player_exit(port)
	check(ordinary.dead and not ordinary.get_parent().visible and ordinary.body.collision_layer == 0 and Access.owner(port) == null,"Blocking trader silently removed and hatch lock released")
	check(destroyed == 0,"Silent trader removal has no destruction callback")
	var protected := vessel(game,port,true); protected.mission_owner = "fixture"
	protected.waypoints = PackedVector3Array([port.entry + Vector3.RIGHT * 20]); protected.port = port; Access.acquire(port,protected)
	var before := protected.global_position; var health_before: float = protected.health.remaining
	game.submarine_traffic.clear_player_exit(port)
	check(not protected.dead and protected.global_position.distance_to(before) > 2 and protected.health.remaining == health_before and protected.mission_owner == "fixture" and protected.waypoints.size() == 1,"Blocking mission ship moves safely aside with health, route and mission preserved")
	check(Access.owner(port) == null and destroyed == 0,"Moving a mission ship releases the hatch without destruction")
	protected.take_weapon_damage(0.5)
	check(protected.health.remaining < health_before,"NPC damage continues while the player is docked")
	game.docking.saved_collision_mask = 13; game._dock_ui_action("launch",{})
	check(game.docking.stage == game.Docking.Stage.EXIT_OPEN and not paused,"Launch acquires the cleared hatch immediately")
	game._process(0)
	check(game.cockpit_hud.visible and not game.game_radio.docked,"Piloting HUD and radio resume for launch")
	check(is_equal_approx(game.water_environment.fog_depth_begin,game.fog_start_slider.value * 0.6) and is_equal_approx(game.water_environment.fog_depth_end,game.fog_visibility * 0.6),"Launching restores both selected gameplay fog distances")
	# A new session from a dock must not retain the hidden piloting HUD or view.
	game.docking._transition(game.Docking.Stage.DOCKED); game._process(0)
	check(not game.cockpit_hud.visible,"Re-entering a dock hides the HUD")
	game._reset_loaded_world()
	check(game.cockpit_hud.visible and not game.game_dock.view.active,"Session reset restores the HUD and clears the fixed dock camera")
	check(is_equal_approx(game.water_environment.fog_depth_end,game.fog_visibility * 0.6),"Session reset clears the fixed dock fog")
	game.queue_free(); await process_frame
	print("Live dock: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
