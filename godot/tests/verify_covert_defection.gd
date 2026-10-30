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
	storage.root_override = "res://tests/cache-defection-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER")); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func heard(code: String) -> bool:
	var text: String = game.gameplay_catalogue.tables.radio_messages.records[code].text
	return game.bounty_radio_queue.any(func(entry: Dictionary) -> bool: return entry.text == text)

func fresh(id: String) -> RefCounted:
	runtime._cleanup(); preload("res://mission_survivors.gd").clear(game.submarine_traffic); await physics_frame; await physics_frame
	game.radio_feed.clear(); game.bounty_radio_queue.clear(); runtime.outcome.dismiss()
	game.player_progress = Progress.restore({"campaign_stage":3}); game.player_progress.status.credits = 10000
	game.player_progress.missions.completed["minefield" if id == "defect" else "rovrtn"] = {"success":true,"city":1 if id == "defect" else 3}
	game.pilot.restore_health(); game.pilot.active = true; game.pilot.controls_enabled = true
	game.equipment.set_installed(["deep_sea_lights","escape"])
	game.pilot.global_position = Vector3(10000,120,10000)
	runtime.set_testing_missions(false)
	var city := Rules.offering_city(id)
	game.docking.current = game.submarine_traffic.port_by_id(city); game.docking.stage = game.Docking.Stage.DOCKED
	var result: String = runtime.accept(city,id)
	check(result.is_empty(),"Accept original city variant "+id+": "+result)
	game.docking.stage = game.Docking.Stage.IDLE; game.dock_interface.dismiss(); jobs.set_physics_process(false)
	for agent in jobs.vessels: agent.set_physics_process(false)
	await physics_frame; await physics_frame
	return jobs.defection

func attach(mission: RefCounted) -> void:
	var tools: Node3D = game.equipment.support_tools
	tools.activate("escape",true); tools.pod_deployment = 0.6; tools.set_physics_process(false)
	tools.pod.global_position = mission.ship.get_parent().to_global(Vector3(0,0.9,0.3))
	game.pilot.global_position = tools.pod.global_position+Vector3.UP*0.4
	tools._attach_pod(mission.ship.body)
	check(tools.pod_target == mission.ship.body,"Actual empty pod can attach to prototype surface")

func ready(mission: RefCounted) -> void:
	attach(mission); mission.step(16); mission.step(8)
	game.equipment.support_tools._detach_pod(); mission.step(0)
	mission.encounter_clock = -1
	game.pilot.global_position = mission.ship.global_position+Vector3.UP*10

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Original world loads")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game()
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false); game.set_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.wildlife.set_simulating(false); game.photo_mode.replay.set_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	for frame in range(2000):
		if game.submarine_traffic.navigation_ready: break
		game.submarine_traffic.build_graph(128); await process_frame
	check(game.submarine_traffic.navigation_ready,"Shared navigation ready for interceptors and final docking")
	var progress := Progress.restore({"campaign_stage":3})
	check(Rules.next_offer(progress,1) == "minefield" and Rules.next_offer(progress,3) == "rovrtn","Both original prerequisite queues retained")
	progress.missions.completed["minefield"] = {"success":true,"city":1}
	progress.missions.completed["rovrtn"] = {"success":true,"city":3}
	check(Rules.next_offer(progress,1) == "defect" and Rules.next_offer(progress,3) == "defect2","Both original Defection offers follow local predecessors")
	progress.missions.completed["defect2"] = {"success":true,"city":3}
	check(Rules.next_offer(Progress.restore(JSON.parse_string(JSON.stringify(progress))),1) == "bomb","Published save history excludes paired duplicate and advances to Bomb Disposal")
	check(runtime.testing_mission_city("defect") == 1 and runtime.testing_mission_city("defect2") == 3,"Dev tools expose original mission cities")
	game.player_progress = Progress.restore({"campaign_stage":3}); game.equipment.set_installed([])
	check(Rules.requirement_cost(game,"defect",1) == 4800 and Rules.requirement_cost(game,"defect2",3) == 4860,"Original Escape Pod affordability gates")
	var mission: RefCounted = await fresh("defect")
	check(mission.ship.get_parent().get_meta("asset_source","").contains("CARAVAN"),"Uses the blind CARAVAN prototype, not a placeholder freighter")
	check(mission.ship.health.capacity == 15 and mission.ship.health.sustain == 0.1 and not mission.ship.combat_enabled,"Original prototype armour, shields and noncombatant behaviour")
	check(game.submarine_traffic.can_activate(mission.ship),"Prototype starts clear of real scenery")
	var waiting_pose: Vector3 = mission.ship.global_position
	for tick in range(30): mission.ship._advance_motion(1.0/60.0)
	check(mission.ship.global_position.distance_to(waiting_pose) < 0.001,"Unfuelled prototype waits at the rendezvous")
	check(mission.mines.size() > 0 and mission.mines.size() <= 50,"Original five fields attempt ten mines each without buried extras")
	check(game.player_progress.missions.unavailable.has("defect2") and runtime.target_marker.target_body() == mission.ship.body,"Paired exclusion and original target guidance")
	mission.step(12)
	check(heard("bb23") and not heard("bb1"),"Original refinery request after twelve seconds; recognition waits for approach")
	game.pilot.global_position = mission.ship.global_position+Vector3.UP*4; mission.step(2)
	check(heard("bb1"),"Recognition inside eight-unit approach radius")
	attach(mission); mission.step(8)
	check(heard("bb5") and not mission.received and not mission.ship.tracking,"Supplies transfer does not finish early")
	game.equipment.support_tools._detach_pod(); mission.step(0)
	check(heard("bb7") and mission.transfer == 0,"Early detachment cancels incomplete transfer")
	attach(mission); mission.step(16)
	check(mission.received and heard("bb6") and not mission.operational,"Sixteen seconds delivers the tracker but does not immediately fit it")
	game.equipment.support_tools._detach_pod(); mission.step(7.99)
	check(not mission.operational,"Bridge installation waits full eight seconds after receipt")
	mission.step(0.01)
	check(mission.operational and heard("bb8") and mission.ship.tracking and mission.encounter_clock == 8,"Tracker activates and schedules first interception eight seconds later")
	check(not game.equipment.support_tools.passengers,"Fuel delivery never invents rescued passengers in the pod")
	mission.encounter_clock = -1
	mission.ship.get_parent().global_transform = Transform3D(Basis.IDENTITY,Vector3(10000,120,10000)); mission.ship.motion.velocity = Vector3.ZERO
	game.pilot.global_position = mission.ship.global_position+Vector3.BACK*10
	var start: Vector3 = mission.ship.global_position
	for tick in range(60): mission.ship._advance_motion(1.0/60.0)
	check(mission.ship.global_position.z > start.z+0.2,"Physical prototype follows player vector with smooth inertial movement")
	mission.ship.set_local_simulation(false)
	check(mission.ship.local_simulation and mission.ship.body.collision_layer != 0,"Blind prototype retains real collision outside camera instead of teleporting along abstract routes")
	game.pilot.global_position = mission.ship.global_position+Vector3.FORWARD*20
	mission.step(0); mission.step(6)
	check(heard("bb13") and heard("bb14"),"Weak-signal warning and source compass bearing")
	# Sweep the actual moving hull into a solid wall; no route planner may
	# secretly guide the blinded prototype around the player's bad heading.
	var wall := StaticBody3D.new(); game.world_root.add_child(wall)
	var collider := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(10,10,0.2); collider.shape = box; wall.add_child(collider)
	start = mission.ship.global_position; wall.global_position = start+Vector3.BACK*3
	game.pilot.global_position = start+Vector3.BACK*10
	await physics_frame; await physics_frame
	for tick in range(180): mission.ship._advance_motion(1.0/60.0)
	check(mission.ship.global_position.z < wall.global_position.z and mission.ship.last_obstacle.is_empty(),"Blind hull physically stops at rock faces without auto-routing through them")
	wall.queue_free(); await physics_frame
	mission.ship.get_parent().global_position = start; mission.ship.motion.velocity = Vector3.ZERO
	var mine: Node3D = mission.mines[0]
	mine.home = start+Vector3.BACK*3; mine.global_position = mine.home
	game.pilot.global_position = start+Vector3.BACK*10
	await physics_frame; await physics_frame
	var before_health: float = mission.ship.health.remaining
	for tick in range(180): mission.ship._advance_motion(1.0/60.0)
	await process_frame; await physics_frame; await process_frame
	check(mine.dead and mission.ship.health.remaining < before_health,"Blind prototype detonates a real mine on contact and receives its blast damage")
	mission.ship.get_parent().global_position = start; mission.ship.motion.velocity = Vector3.ZERO
	mission._wave()
	check(mission.enemies.size() in [1,2] and is_instance_valid(mission.boarder),"Original one-or-two guards plus a dedicated boarding ship")
	check(mission.enemies.all(func(agent: Node3D) -> bool: return agent.engage_player and agent.pursue_offscreen and agent.health.capacity == 15),"Attack guards pursue the player using original attack-sub health")
	check(mission.boarder.health.capacity == 15 and mission.boarder.health.sustain == 0.6 and mission.boarder.boarding and is_instance_valid(mission.pod),"Boarder has source vulnerability, aggressive boarding orders and visible pod")
	check(jobs.vessels.all(func(agent: Node3D) -> bool: return game.submarine_traffic.can_activate(agent)),"No interception ship begins embedded in scenery")
	for agent in jobs.vessels: agent.set_physics_process(false)
	mission.boarder.get_parent().global_position = mission.boarder.boarding_goal()
	mission.step(4)
	check(mission.boarding_clock >= 4 and heard("bb11") and mission.ship.held_by_boarders,"Docked boarding pod stops prototype and warns after four seconds")
	check(mission.pod.get_parent() == mission.ship.get_parent() and is_instance_valid(mission.cable),"Boarding pod visibly attaches to prototype with a cable")
	mission.boarder.take_weapon_damage_from(1000,game.pilot.global_position,game.pilot)
	check(mission.boarding_clock < 0 and not mission.ship.held_by_boarders and heard("bb12") and mission.encounter_clock == 108,"Destroying boarder stops recapture and schedules original108-second replacement")
	mission._wave(); mission.boarder.set_physics_process(false); mission.boarder.get_parent().global_position = mission.boarder.boarding_goal()
	mission.step(39.99)
	check(not mission.captured and not runtime.active().is_empty(),"Recapture requires forty seconds, not proximity alone")
	mission.step(0.01)
	check(mission.captured and heard("bb4") and not runtime.active().is_empty(),"Full boarding retakes prototype before delayed failure message")
	var captured_ship: Node3D = mission.ship; var captor: Node3D = mission.boarder; var captor_pod: Node3D = mission.pod
	var guards: Array[Node3D] = mission.enemies.duplicate()
	mission.step(8)
	check(runtime.active().is_empty() and heard("bb24") and runtime.last_response == runtime.text("defect",3) and game.player_progress.status.credits == 10000,"Recapture fails with original response3 and no reward")

	var returning: Array[Node3D] = [captured_ship,captor]; returning.append_array(guards)
	check(returning.all(func(agent: Node3D) -> bool: return is_instance_valid(agent) and agent.retiring and not agent.combat_enabled and agent.dock_destination in [2,4] and agent.mission_owner.is_empty() and game.submarine_traffic.traders.has(agent)),"Recaptured prototype, boarding sub and surviving guards remain to return to a Procha dock")
	check(is_instance_valid(captor_pod) and captor_pod.get_parent() == captor.get_parent() and captor.boarding_pod == captor_pod,"Returning boarding sub keeps its recovered pod")
	check(not captured_ship.held_by_boarders and not captured_ship.tracking and not captor.boarding and not captor.body.get_collision_exceptions().has(captured_ship.body),"Failure releases tracking, boarding and temporary hull collision exceptions")
	var snapshot: Dictionary = game.submarine_traffic.snapshot()
	var ship_id: String = preload("res://entity_identity.gd").of(captured_ship)
	var captor_id: String = preload("res://entity_identity.gd").of(captor)
	check(game.submarine_traffic.valid_snapshot(snapshot),"Returning Defection ships produce a valid published save snapshot")
	game.submarine_traffic.restore(snapshot)
	returning = game.submarine_traffic.traders.filter(func(agent: Node3D) -> bool: return agent.has_meta("fishing_survivor"))
	var restored_ship: Node3D
	var restored_captor: Node3D
	for agent in returning:
		agent.set_physics_process(false)
		if preload("res://entity_identity.gd").of(agent) == ship_id: restored_ship = agent
		if preload("res://entity_identity.gd").of(agent) == captor_id: restored_captor = agent
	check(is_instance_valid(restored_ship) and restored_ship.retiring and is_equal_approx(restored_ship.health.sustain,0.1) and restored_ship.dock_destination == snapshot[ship_id].destination,"Reload preserves the prototype model, armour and return destination")
	check(is_instance_valid(restored_captor) and is_instance_valid(restored_captor.boarding_pod) and is_equal_approx(restored_captor.health.sustain,0.6) and restored_captor.tuning.npc_speed == 3.5,"Reload preserves the boarding ship's pod, vulnerability and speed")
	# Exercise the real hatch sequence for both unique hulls, after restoring.
	for agent in [restored_ship,restored_captor]:
		var home_port: Dictionary = game.submarine_traffic.port_by_id(agent.dock_destination)
		agent.get_parent().global_position = home_port.entry+Vector3.UP*0.8
		agent.body.transform = Transform3D.IDENTITY; agent.motion.velocity = Vector3.ZERO; agent.path.clear(); agent.wait = 0
		var docked := false
		for tick in range(1800):
			agent.advance(1.0/60.0)
			if agent.stage == "berth": docked = true; break
			if tick%30 == 0: await physics_frame
		check(docked,"Returned hull completes the real Procha hatch sequence: "+str(agent.get_parent().get_meta("editor_model")))
		await process_frame
	check(not is_instance_valid(restored_ship) and not is_instance_valid(restored_captor),"Returning mission ships retire only after docking")

	mission = await fresh("defect2"); ready(mission)
	var port: Dictionary = game.submarine_traffic.port_by_id(3)
	mission.ship.get_parent().global_transform = Transform3D(Basis.IDENTITY,port.entry+Vector3.UP*1)
	game.pilot.global_position = port.entry+Vector3.UP*10
	mission.step(2)
	check(mission.safe and heard("bb9") and mission.ship.dock_destination == 3 and runtime.target_marker.target_body() == null,"Beluga safety orders actual docking, clears guidance and announces arrival")
	mission.step(10)
	check(not runtime.active().is_empty() and game.player_progress.status.credits == 10000,"Proximity and elapsed timer cannot pay before prototype physically docks")
	var ship: Node3D = mission.ship
	for tick in range(2400):
		if runtime.active().is_empty(): break
		ship.advance(1.0/60.0); mission.step(1.0/60.0)
		if tick%30 == 0: await physics_frame
	check(runtime.active().is_empty() and ship.stage == "berth" and ship.last_city == 3,"Prototype completes the real Beluga hatch sequence")
	check(heard("bb25") and game.player_progress.status.credits == 15500 and game.player_progress.missions.completed.get("defect2",{}).get("success",false),"Successful escort pays original5500 and records completion")
	check(game.player_progress.missions.get("stage3_successes",0) == 1,"Original stage-three progress advances once")
	mission = await fresh("defect")
	mission.ship.take_weapon_damage_from(1000,game.pilot.global_position,game.pilot)
	check(mission.ship.dead and heard("bb3") and not runtime.active().is_empty(),"Prototype has real damage and death before failure confirmation")
	mission.step(6)
	check(runtime.active().is_empty() and heard("bb22") and runtime.last_response == runtime.text("defect",2),"Destroyed prototype selects original response2")
	await physics_frame; await physics_frame
	check(jobs.defection == null and jobs.actors.is_empty() and jobs.vessels.is_empty(),"Failure clears mission vessels, pod, cables and mines")
	mission = await fresh("defect2")
	mission.step(12); runtime._cleanup()
	await physics_frame; await process_frame
	check(jobs.defection == null and game.submarine_traffic.traders.all(func(agent: Node3D) -> bool: return agent.mission_owner not in ["defect","defect2"]),"Cancellation removes mission actors from ambient traffic")
	game.free(); await process_frame; await process_frame
	print("Covert Defection: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
