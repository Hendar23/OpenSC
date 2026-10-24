extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
var game: Node
var runtime: Node
var jobs: Node
var checks := 0
var failures := 0

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-recon-ambush-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	var config := ConfigFile.new(); config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func fresh(id: String) -> void:
	runtime._cleanup(); await physics_frame; await physics_frame
	game.radio_feed.clear(); game.bounty_radio_queue.clear()
	game.player_progress = Progress.restore({"campaign_stage":2}); game.player_progress.status.credits = 100000
	game.equipment.set_installed(["deep_sea_lights","magnet","bigears"]); game.weapons.set_installed(["zapper"])
	game.pilot.active = true; game.pilot.controls_enabled = true; runtime.outcome.dismiss()
	runtime.set_testing_missions(true)
	var city := Rules.offering_city(id)
	game.docking.current = game.submarine_traffic.port_by_id(city); game.docking.stage = game.Docking.Stage.DOCKED
	check(runtime.accept(city,id).is_empty(),id+" accepts at its original station")
	game.docking.stage = game.Docking.Stage.IDLE; game.dock_interface.dismiss()
	for agent in jobs.vessels: agent.set_physics_process(false)
	jobs.set_physics_process(false)
	await physics_frame; await physics_frame

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for Recon ambush test")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game()
	game.set_process(false); game.set_physics_process(false); game.docking.set_physics_process(false)
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.pilot.pending_reset = false
	game.photo_mode.replay.set_process(false); game.weapons.set_physics_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false); game.wildlife.set_simulating(false)
	for creature in game.wildlife.get_children():
		if creature is CollisionObject3D: creature.collision_layer = 0
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	while not game.submarine_traffic.navigation_ready:
		game.submarine_traffic.build_graph(128); await process_frame
	for agent in game.submarine_traffic.traders:
		agent.running = false; agent.body.collision_layer = 0; agent.set_physics_process(false)
	await fresh("recontech")
	var mission: RefCounted = jobs.remaining
	mission._recon_alarm()
	var attackers: Array = mission.recon_reinforcements
	var starts := {}
	for agent: Node3D in attackers:
		starts[agent] = agent.global_position
		check(agent.wait == 0 and agent.flee == 0,"Alarm attacker has no civilian delay or flee order")
		var hull: AABB = agent.get_parent().global_transform*agent.bounds.grow(0.25)
		for other: Node3D in attackers:
			if other != agent:
				var occupied: AABB = other.get_parent().global_transform*other.bounds.grow(0.25)
				check(not hull.intersects(occupied),"Alarm wave starts without overlapping hulls")
	for agent: Node3D in attackers:
		agent.random.seed = 1234+attackers.find(agent)
		agent.set_local_simulation(true); agent.set_physics_process(false)
	for phase in ["inside","exit","open"]:
		game.pilot.global_position = mission.structure.global_position+Vector3.UP*2 if phase == "inside" else Vector3(310,154,266) if phase == "open" else Vector3(326,154,266)
		game.pilot.reset_physics_interpolation()
		var fired := {}; var hit_player := false
		for frame in range(60 if phase == "inside" else 480):
			game.pilot.active = true; game.pilot.controls_enabled = true; game.pilot.restore_health(100000)
			for agent: Node3D in attackers: agent.advance(1.0/30.0)
			await physics_frame
			hit_player = hit_player or game.pilot.health < game.pilot.max_health
			for shot in get_nodes_in_group("turret_missiles"):
				if attackers.has(shot.source): fired[shot.source] = true
		if phase == "inside":
			check(fired.is_empty(),"Ambush remains outside without firing through cave terrain")
		else:
			check(fired.size() == 3,"All three attackers fire unprovoked during %s" % phase)
			check(hit_player,"Ambush projectiles can damage the player during %s" % phase)
		if phase == "open":
			for agent: Node3D in attackers:
				check(agent.global_position.distance_to(starts[agent]) > 4,"Every attacker pursues beyond its spawn instead of parking at the cave")
				check(game.submarine_traffic.water_clear(agent.global_position),"Pursuing attacker remains in navigable water")
		print("Recon ambush ",phase,": ",fired.size()," firing attackers")
	game.free(); await process_frame
	print("Recon ambush: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
