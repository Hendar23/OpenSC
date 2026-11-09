extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
var game: Node
var runtime: Node
var jobs: Node
var failures := 0
var checks := 0

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-hijacked-filters-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var cfg := ConfigFile.new()
	cfg.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER"))
	cfg.save(storage.preferences_path())
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func start(id: String) -> RefCounted:
	game.player_progress = Progress.restore({"campaign_stage":5})
	game.player_progress.status.credits = 100000
	var city := Rules.offering_city(id)
	check(runtime.board(city).id == id and runtime.board(city).available,"Published stage-five progress can accept " + id)
	game.docking.current = game.submarine_traffic.port_by_id(city)
	game.docking.stage = game.Docking.Stage.DOCKED
	check(runtime.accept(city,id).is_empty(),"Accept " + id)
	check(game.player_progress.missions.unavailable.size() == 3,"Other core offers become unavailable")
	game.docking.stage = game.Docking.Stage.IDLE
	paused = false
	return jobs.controller

func deliver(mission: RefCounted, city: int, physical: bool) -> bool:
	if not physical: return jobs.delivery(mission.filter_body,city)
	var magnet: Node3D = game.equipment.magnet
	var points := get_nodes_in_group("city_drop_off_points")
	var index := points.find_custom(func(point: Node) -> bool: return point.city_id == city)
	if index < 0: return false
	var filter_body: RigidBody3D = mission.filter_body
	var point: Node3D = points[index]
	game.pilot.global_position = point.global_position + Vector3.UP*2.0
	filter_body.global_position = point.global_position
	magnet.set_enabled(true); magnet._attach(filter_body)
	if magnet.target != filter_body or not game._delivery_prompt_active(): return false
	game._answer_delivery(true)
	return filter_body.delivered

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	while not game.startup_complete: await process_frame
	game.front_end.gameplay_menu.fmvs_enabled = false
	await game._begin_new_game()
	game.equipment.set_installed(["deep_sea_lights","magnet"])
	game.set_process(false); game.pilot.freeze = true
	game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	game.wildlife.set_simulating(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs; jobs.set_physics_process(false)
	var movies: Array[String] = []
	game.events.fmv_requested.connect(func(cue: String,_city: int): movies.append(cue))
	for id: String in Rules.CORE_FIVE.values():
		var mission := start(id)
		if mission == null or mission.filter_body == null: quit(1); return
		check(mission.guards.size() == 3 and mission.guards.all(func(pirate: Node3D) -> bool: return pirate.dormant),"Touka starts with three dormant guards")
		game.pilot.global_position = mission.filter_body.global_position + Vector3.RIGHT * 30
		mission.step(8)
		check(mission.guards[0].dormant,"Pirates wait for the original approach radius")
		for pirate in mission.guards:
			check(pirate.global_position.distance_to(mission.poses[5][0].origin)<5,"Touka guards stay near the authored cave position")
			var roof := PhysicsRayQueryParameters3D.create(pirate.global_position,pirate.global_position+Vector3.UP*20,1)
			roof.hit_back_faces = false
			check(not game.get_world_3d().direct_space_state.intersect_ray(roof).is_empty(),"Touka guard has a real cave ceiling")
		game.pilot.global_position = mission.guards[0].global_position + Vector3.RIGHT*15
		mission.step(2)
		check(mission.guards.all(func(pirate: Node3D) -> bool: return pirate.engage_player),"All nearby guards activate")
		for pirate in mission.guards: pirate.dormant = true; pirate.engage_player = false
		mission.guards[0].take_weapon_damage_from(1,game.pilot.global_position,game.pilot)
		check(mission.guards.all(func(pirate: Node3D) -> bool: return not pirate.dormant and pirate.engage_player),"Attacking a guard alerts its group immediately")
		var survivor: Node3D = mission.guards[0]
		var first: Node3D = mission.filter_body
		check(first.get_meta("metal_tow_target") and not first.get_meta("grapple_tow_target") and first.prepare_towing(),"Original purifier supports magnet towing")
		check(jobs.delivery(first,6) and mission.leg == 0,"Refinery cannot consume a filter")
		check(deliver(mission,1,id == "filters") and mission.leg == 1 and jobs.target_body() != first,"Touka delivery reveals the next filter")
		check(mission.walkers.size() == 2 and mission.walkers.all(func(walker: Node3D) -> bool: return walker.health == 20 and walker.get_child(0) != null),"Tryton has the two original walkers")
		check(jobs.delivery(mission.filter_body,1) and mission.leg == 1,"One prototype per city")
		check(deliver(mission,4,id == "filters") and mission.guards.size() == 4,"Abyss encounter follows and has four original pirates")
		check(deliver(mission,3,id == "filters") and mission.guards.size() == 2 and mission.guns.size() == 2,"Aquatraz has two pirates and two battleship guns")
		var boss: Node3D = mission.boss
		var walker: Node3D = mission.walkers[0]
		check(deliver(mission,2,id == "filters"),"Fourth distinct city accepts the last prototype")
		check(runtime.active().is_empty() and game.player_progress.campaign_stage == 6 and game.player_progress.status.credits == 108500,"Success advances and pays 8,500 credits")
		check(movies.is_empty(),"Success does not play a previous mission FMV")
		check(is_instance_valid(survivor) and survivor.mission_owner.is_empty() and runtime.retained_props.has(boss) and runtime.retained_props.has(walker),"Surviving actors persist after success")
		for gun in mission.guns: gun.take_weapon_damage(10000)
		await physics_frame; await physics_frame
		check(is_instance_valid(boss) and boss.get_parent().is_in_group("base_destruction") and not runtime.retained_props.has(boss),"Retained battleship still explodes after both guns are destroyed")
		walker.take_weapon_damage(1000)
		check(walker.dead and not walker.visible,"Retained walker remains destructible")
		runtime.docked(2)
		check(runtime.retained_props.is_empty() and not is_instance_valid(walker),"Docking clears retained mission props")
		preload("res://mission_survivors.gd").clear(game.submarine_traffic)
		await process_frame
	var failed := start("filters")
	var hostile: Node3D = failed.guards[0]
	failed.filter_body.take_weapon_damage(100)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.filters.success and game.player_progress.status.credits == 100000,"Destroying a filter fails without a payout")
	check(is_instance_valid(hostile) and hostile.mission_owner.is_empty(),"A surviving guard remains after failure")
	runtime._session_started(false)
	await process_frame
	var abandoned := start("filters3")
	jobs.delivery(abandoned.filter_body,2)
	jobs.delivery(abandoned.filter_body,1)
	jobs.delivery(abandoned.filter_body,4)
	var remaining_walker: Node3D = abandoned.walkers[0]
	var remaining_boss: Node3D = abandoned.boss
	runtime.finish(false)
	check(runtime.retained_props.has(remaining_walker) and runtime.retained_props.has(remaining_boss),"Failure keeps remaining stationary defenders")
	runtime._session_started(false)
	await process_frame
	check(not is_instance_valid(remaining_walker) and not is_instance_valid(remaining_boss),"Session reset clears retained defenders")
	game.free(); await process_frame
	print("Hijacked filters: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
