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
	storage.root_override = "res://tests/cache-rampaging-walker-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER")); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func heard(code: String) -> bool:
	var text: String = game.gameplay_catalogue.tables.radio_messages.records[code].text
	return game.bounty_radio_queue.any(func(entry: Dictionary) -> bool: return entry.text == text)

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	while not game.startup_complete: await process_frame
	await game._begin_new_game()
	game.set_process(false); game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	game.wildlife.set_simulating(false); game.photo_mode.replay.set_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	for id in ["pwalker","pwalker2"]:
		runtime._cleanup(); await physics_frame; await process_frame
		preload("res://mission_survivors.gd").clear(game.submarine_traffic)
		game.player_progress = Progress.restore({"campaign_stage":4}); game.player_progress.status.credits = 0
		check(Rules.next_offer(game.player_progress,Rules.offering_city(id)) == id,"Stage-four city offer "+id)
		game.docking.current = game.submarine_traffic.port_by_id(Rules.offering_city(id)); game.docking.stage = game.Docking.Stage.DOCKED
		check(runtime.accept(Rules.offering_city(id),id).is_empty(),"Accept "+id)
		game.docking.stage = game.Docking.Stage.IDLE; jobs.set_physics_process(false)
		var mission=jobs.rampaging
		check(mission.walker != null and mission.route.size()==11,"Original walker and eleven path markers")
		check(mission.minelayers.size()==2 and mission.allies.size()==4,"Two minelayers and four allied attackers")
		check(mission.minelayers.all(func(a):return is_equal_approx(a.health.remaining,6)),"Original minelayer shield modifier")
		check(mission.animation.has_animation(),"Walker loads original walking morph animation")
		check(mission.walker.health==300,"Original walker shields")
		check(mission.armament.yaw!=null and mission.armament.pitch!=null,"Separate original gun head tracks targets")
		var saved_pose: Transform3D = mission.walker.global_transform
		mission.walker.global_position = Vector3(10000,120,10000)
		var socket: Vector3 = mission.armament.pitch.to_global(mission.armament.PORTS[0])
		game.pilot.global_position = socket+mission.armament.pitch.global_basis.z*3
		game.pilot.active = true; game.pilot.controls_enabled = true
		mission.armament.cooldown = 0; mission.armament._physics_process(0.04)
		check(mission.armament.shots>0,"Walker fires original rotating weapon ports")
		mission.walker.global_transform = saved_pose
		game.pilot.active = true; game.pilot.global_position = mission.walker.global_position+Vector3.UP*3
		mission.step(4.1)
		check(mission.begun and heard("d1"),"Rendezvous plays original greeting")
		check(mission.allies.all(func(a):return a.combat_target==mission.walker),"Allied subs attack walker")
		check(mission.mines.size()==2,"Both minelayers lay mines")
		mission.walker.take_weapon_damage(1500); mission.step(4)
		check(mission.walker.health>=198,"Minelayers retain retail two-thirds shield floor")
		for ship in mission.minelayers: ship.take_weapon_damage(10000)
		mission.walker.take_weapon_damage(1100); mission.step(8)
		check(mission.walker.health<198,"Walker can be worn down after minelayer loss")
		mission.waypoint=mission.route.size()-1;mission.walker.global_position=mission.route[mission.waypoint];mission.step(0.1)
		check(mission.city_attacked and heard("d12") and not runtime.active().is_empty(),"Reaching city warns without invented instant failure")
		var survivors=mission.allies.duplicate()
		mission.walker.take_weapon_damage(10000)
		check(not runtime.retained_props.is_empty(),"Destroyed walker releases its intact recoverable head")
		check(mission.resolved and heard("d10") and game.player_progress.status.credits==0,"Walker destroyed; original delayed settlement")
		mission.step(8.1)
		check(runtime.active().is_empty() and game.player_progress.status.credits==8000,"Original 8000-credit reward")
		check(game.player_progress.campaign_stage==4,"Side job preserves campaign stage")
		check(Rules.next_offer(game.player_progress,3 if id=="pwalker" else 1)=="","Alternate city offer excluded")
		check(survivors.all(func(a):return is_instance_valid(a) and a.retiring),"Surviving allied subs depart after success")
		check(jobs.rampaging==null,"Mission callbacks cleaned up")
		check(game.submarine_traffic.valid_snapshot(game.submarine_traffic.snapshot()),"Departing allies remain valid in published save format")
	runtime._cleanup(); await physics_frame
	game.player_progress = Progress.restore({"campaign_stage":4})
	game.docking.current = game.submarine_traffic.port_by_id(1); game.docking.stage = game.Docking.Stage.DOCKED
	var accepted: String = runtime.accept(1,"pwalker")
	check(accepted.is_empty(),"Mission can start in a fresh session: "+accepted)
	if not accepted.is_empty(): game.free();quit(1);return
	var abandoned = jobs.rampaging
	var surviving = abandoned.minelayers+abandoned.allies
	runtime.finish(false)
	check(jobs.rampaging==null and game.player_progress.status.credits==0,"Abort cleans callbacks without a success reward")
	check(surviving.all(func(a):return is_instance_valid(a) and a.retiring),"Abort preserves surviving allies and sends them home")
	game.free();await process_frame
	print("Rampaging walker: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
