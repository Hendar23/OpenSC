extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
const Survivors = preload("res://mission_survivors.gd")
var game: Node
var runtime: Node
var jobs: Node
var checks := 0
var failures := 0

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-thwart-terrorists-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	var config := ConfigFile.new(); config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func fresh() -> RefCounted:
	runtime._cleanup(); await physics_frame; await physics_frame
	Survivors.clear(game.submarine_traffic)
	game.radio_feed.clear(); game.bounty_radio_queue.clear()
	game.player_progress = Progress.restore({"campaign_stage":3}); game.player_progress.status.credits = 100000
	game.equipment.set_installed(["deep_sea_lights","magnet","escape"])
	game.pilot.restore_health(); game.pilot.active = true; game.pilot.controls_enabled = true
	game.weapons.set_installed(["zapper"]); runtime.outcome.dismiss(); runtime.set_testing_missions(false)
	game.docking.current = game.submarine_traffic.port_by_id(1); game.docking.stage = game.Docking.Stage.DOCKED
	check(runtime.accept(1,"minefield").is_empty(),"Original Touka stage-three offer accepts")
	game.docking.stage = game.Docking.Stage.IDLE; game.dock_interface.dismiss()
	game.pilot.show(); game.pilot.visual.show(); game.pilot.collision_layer = 2; game.pilot.collision_mask = 13
	jobs.set_physics_process(false)
	for agent in jobs.vessels: agent.set_physics_process(false)
	await physics_frame; await physics_frame
	return jobs.terrorists

func attach(mission: RefCounted) -> void:
	game.equipment.support_tools.pod_target = mission.ship.body
	mission.step(0.001)

func detach(mission: RefCounted) -> void:
	game.equipment.support_tools.pod_target = null; mission.step(0.001)

func rescue(mission: RefCounted) -> void:
	mission.elapsed = 216
	attach(mission); mission.step(8.01); mission.step(16.01); mission.step(12.01)

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
	var progress := Progress.restore({"campaign_stage":2})
	check(Rules.next_offer(progress,1) != "minefield","Terrorists does not intrude into stage two")
	progress.campaign_stage = 3
	check(Rules.next_offer(progress,1) == "minefield","First original stage-three Touka job")
	for city in [2,3,4,5,6]: check(Rules.next_offer(progress,city) != "minefield","No invented city variant at "+str(city))
	check(runtime.testing_mission_city("minefield") == 1 and "minefield2" not in runtime.testing_missions(),"Dev offers use only released availability")
	progress.missions.completed.minefield = {"success":true}
	check(Rules.next_offer(progress,1).is_empty() and not Rules.core_unlocked(progress),"Resolved stage-three job is not offered again or counted for stage two")
	var mission: RefCounted = await fresh()
	check(game.submarine_traffic.roaming_population.attacks_suppressed(),"Accepting Thwart Terrorists suppresses ambient pirate attacks")
	check(mission.ship.get_parent().get_meta("editor_model") == "FREIGHT","Original FREIGHT model, not a prison or shuttle substitute")
	check(mission.points.size() == 9 and mission.ship.waypoints.size() == 8,"All nine original route markers decoded in numeric order")
	check(mission.ship.get_parent().global_transform.is_equal_approx(mission.points[0]),"Freighter starts at exact source pose")
	check(mission.ship.body.get_child_count() == 12,"Original twelve hull spheres avoid empty-space contacts")
	check(mission.ship.health.capacity == 3.0 and mission.ship.health.sustain == 0.1,"Recovered aggregate damage threshold and per-part sustain")
	check(mission.mines.size() == 80 and mission.mines.any(func(mine: Node3D) -> bool: return mine.stats.model == "HARDMINE"),"Four original twenty-mine clusters include tougher hard mines")
	check(game.equipment.support_tools.passengers,"SWAT starts in the player's pod")
	check(jobs.can_attach_pod(mission.ship.body) and runtime.target_marker.target_body() == mission.ship.body,"Occupied SWAT pod and target guidance recognize the correct freighter")
	var start: Vector3 = mission.ship.global_position
	for index in range(120): mission.ship.advance(1.0/60.0)
	check(mission.ship.global_position.distance_to(start) > 0.5,"Freighter actually moves from its initial pose")
	mission.ship.set_local_simulation(false)
	check(mission.ship.local_simulation,"Objective keeps physical mine interactions outside camera range")
	mission.ship.set_physics_process(false)
	# Direct pod contact uses the real surface and must allow the loaded team.
	var tools: Node3D = game.equipment.support_tools
	tools.activate("escape",true); tools.pod_deployment = 0.6
	tools.set_physics_process(false)
	tools.pod.global_position = mission.ship.get_parent().to_global(Vector3(0,0.9,0.3))
	game.pilot.global_position = tools.pod.global_position+Vector3.UP*0.4
	tools._attach_pod(mission.ship.body)
	check(tools.pod_target == mission.ship.body and tools.pod_attached,"Actual physical pod attachment works with SWAT aboard")
	var host: Node3D = mission.ship.get_parent()
	var contact_pose: Transform3D = host.global_transform
	var relative_basis: Basis = host.global_basis.orthonormalized().inverse()*tools.pod.global_basis
	for turn in [Vector3(0,0.8,0),Vector3(0.2,-0.6,0.3)]:
		host.global_basis = contact_pose.basis*Basis.from_euler(turn)
		game.pilot.global_position = mission.ship.body.to_global(tools.pod_anchor)+Vector3.UP*0.4
		tools._physics_process(0)
		check((host.global_basis.orthonormalized().inverse()*tools.pod.global_basis).is_equal_approx(relative_basis),"Attached pod retains its contact orientation through host yaw/pitch/roll")
		check(tools.pod.global_position.is_equal_approx(mission.ship.body.to_global(tools.pod_anchor)),"Pod stays seated at the rotating hull attachment")
	host.global_transform = contact_pose
	game.pilot.global_position = mission.ship.body.to_global(tools.pod_anchor)+Vector3.UP*0.4
	tools._physics_process(0)
	mission.step(0.01); mission.step(4)
	check(not mission.inside and tools.passengers,"Boarding takes the full eight seconds")
	tools._detach_pod(false); mission.step(0.01)
	check(mission.transfer < 0 and not mission.inside,"Early detachment cancels boarding")
	# Three original failed searches, requiring a detach/reattach each time.
	for attempt in range(3):
		attach(mission); mission.step(8.01)
		check(mission.inside and not tools.passengers,"SWAT enters on attempt "+str(attempt+1))
		mission.step(24.01); mission.step(8.01)
		check(mission.failed_attempts == attempt+1 and not mission.inside and tools.passengers and not mission.won,"Blocked bulkhead returns the team without winning")
		detach(mission)
	attach(mission); mission.step(8.01); mission.step(16.01)
	check(mission.crew_found and not mission.won,"Locating crew alone does not complete the rescue")
	detach(mission); mission.step(20)
	check(mission.inside and not mission.won,"Stranded team must be retrieved")
	attach(mission); mission.step(8.01)
	check(mission.won and tools.passengers and not runtime.active().is_empty(),"Recovered crew stays aboard pod until docking")
	check(not mission.ship.dead and not mission.ship.halted,"Empty freighter continues its runaway course")
	mission.step(8.01)
	check(game.bounty_radio_queue.any(func(entry: Dictionary) -> bool: return entry.text == game.gameplay_catalogue.tables.radio_messages.records.r16.text),"Original Beluga destroy-the-runaway warning follows rescue")
	mission.ship.take_weapon_damage(1000)
	check(mission.ship.dead and not mission.lost,"Destroying empty freighter protects city without failing rescue")
	var credits: int = game.player_progress.status.credits
	jobs.docked(1)
	check(runtime.active().is_empty() and game.player_progress.status.credits == credits+7500,"Docking pays original 7500 credits once")
	check(not game.submarine_traffic.roaming_population.attacks_suppressed(),"Ambient pirate attacks resume after successful docking")
	check(game.player_progress.campaign_stage == 3 and game.player_progress.missions.stage3_successes == 1 and not game.player_progress.missions.has("stage2_successes"),"Stage-three counters remain independent")
	check(preload("res://mailbox.gd").messages(game.gameplay_catalogue,game.player_progress,1).any(func(row: Dictionary) -> bool: return row.id == "381"),"Original success bulletin arrives")
	jobs.docked(1); check(game.player_progress.status.credits == credits+7500,"Repeated docking cannot pay twice")
	mission = await fresh(); rescue(mission)
	mission._city_collision(); check(mission.city_hit and mission.won,"Late rescued freighter can reach the city")
	jobs.docked(3)
	check(game.player_progress.missions.completed.minefield.score == 0.5 and runtime.last_response.contains("Bad call"),"City damage selects original reduced score and response three")
	check(preload("res://mailbox.gd").messages(game.gameplay_catalogue,game.player_progress,3).any(func(row: Dictionary) -> bool: return row.id == "382"),"Original lower-score bulletin arrives")
	check(game.submarine_traffic.traders.any(func(agent: Node3D) -> bool: return agent.has_meta(Survivors.TAG) and agent.get_parent().get_meta("editor_model","") == "FREIGHT"),"Living freighter persists through objective cleanup")
	var saved: Dictionary = game.submarine_traffic.snapshot()
	check(game.submarine_traffic.valid_snapshot(saved),"Surviving freighter snapshot validates")
	game.submarine_traffic.restore(saved)
	check(game.submarine_traffic.traders.any(func(agent: Node3D) -> bool: return agent.has_meta(Survivors.TAG) and agent.retiring and agent.health.capacity == 3.0 and agent.get_parent().get_meta("editor_model","") == "FREIGHT"),"Save restoration retains freighter's natural docking departure and health")
	mission = await fresh(); mission.ship.take_weapon_damage(1000); mission.step(9.21)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.minefield.success and runtime.last_response.contains("mines"),"Loss before rescue fails with source minefield response")
	check(not game.submarine_traffic.roaming_population.attacks_suppressed(),"Failed mission also releases ambient pirate suppression")
	check(game.player_progress.status.credits == 100000,"Failure pays nothing")
	mission = await fresh(); mission._city_collision(); mission.step(5.01); mission.step(9.21)
	check(runtime.active().is_empty() and runtime.last_response.contains("Beluga"),"Unrescued city crash fails with source response two")
	mission = await fresh()
	# A real mine overlapping the nose sphere must detonate and hurt the hull.
	var mine: Node3D = mission.mines[0]
	mine.home = mission.ship.body.to_global(Vector3(0,0,2.6)); mine.global_position = mine.home
	await physics_frame; await physics_frame
	mission._contacts(); await process_frame; await physics_frame
	check(mine.dead and mission.ship.health.remaining < mission.ship.health.capacity,"Real freighter contact detonates mine and applies blast damage")
	mission = await fresh()
	for item in mission.mines: item.collision_layer = 0
	game.pilot.global_position = Vector3(10000,10000,10000)
	var last_waypoint := -1; var stalled := 0.0; var last_position: Vector3 = mission.ship.global_position
	for tick in range(14000):
		mission.ship.advance(0.04)
		if tick%25 == 0:
			await physics_frame
			if mission.ship.waypoint != last_waypoint:
				print("Chopowski route waypoint ",mission.ship.waypoint," at ",mission.ship.global_position)
				last_waypoint = mission.ship.waypoint
			if mission.ship.global_position.distance_to(last_position) < 0.05: stalled += 1.0
			else: stalled = 0
			last_position = mission.ship.global_position
			if stalled > 8 or mission.city_hit: break
	print("Chopowski route end ",mission.ship.global_position," goal ",mission.points[8].origin," obstacle ",mission.ship.last_obstacle)
	check(mission.city_hit,"Cleared original route physically reaches Beluga without getting stuck at terrain or turning points")
	var original_mines: Array = mission.mines.duplicate()
	runtime._cleanup(); await physics_frame; await physics_frame
	check(original_mines.all(func(node: Variant) -> bool: return not is_instance_valid(node)),"Mission mines and signal owners are cleaned between sessions")
	game.player_progress = Progress.restore({}) # New sessions replace campaign state before mission cleanup.
	check(not game.submarine_traffic.roaming_population.attacks_suppressed(),"Session cleanup leaves no global pirate suppression flag")
	var population: Node3D = game.submarine_traffic.roaming_population
	var pirate: Node3D = population.ships[0]
	pirate.reset(); pirate.set_physics_process(false); pirate.running = true
	game.pilot.global_position = Vector3(10000,game.pilot.surface_height-5,10000)
	pirate.get_parent().global_position = game.pilot.global_position-Vector3(0,0,8)
	pirate.get_parent().global_basis = Basis.IDENTITY
	await physics_frame; await physics_frame
	game.player_progress.missions.active = {"id":"minefield","city":1}
	check(not pirate._valid_target(game.pilot),"Roaming pirate cannot acquire the player during the mission")
	pirate.roaming = false
	check(pirate._valid_target(game.pilot),"Authored/scripted pirates retain their normal combat rules")
	pirate.roaming = true; pirate.victim = game.pilot; pirate.path.clear(); pirate.replan = 1
	var shots := get_nodes_in_group("turret_missiles").size()
	var messages: int = game.bounty_radio_queue.size()
	pirate.advance(0)
	check(pirate.victim == null and get_nodes_in_group("turret_missiles").size() == shots,"An existing ambient engagement stops firing and disengages")
	population._taunt(pirate)
	check(game.bounty_radio_queue.size() == messages,"Suppressed random pirates cannot send attack taunts")
	game.player_progress.missions.active = {}; pirate.acquire_clock = 0
	pirate.advance(0)
	check(pirate.victim == game.pilot and get_nodes_in_group("turret_missiles").size() == shots+1,"Same living pirate resumes normal attacks after mission ends")
	game.queue_free(); await process_frame; await physics_frame
	print("Thwart Terrorists: %d checks; %d failures" % [checks,failures]); quit(1 if failures else 0)
