extends "res://tests/verify_remaining_stage_two.gd"

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for prison docking")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.docking.set_physics_process(false); game.set_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	while not game.submarine_traffic.navigation_ready: game.submarine_traffic.build_graph(128); await process_frame
	for agent in game.submarine_traffic.traders: agent.set_physics_process(false)
	for id in ["escort","escort2"]:
		await fresh(id)
		var mission: RefCounted = jobs.remaining
		var ship: Node3D = mission.ship
		game.pilot.global_position = ship.global_position+Vector3.UP*3
		mission._step_escort(0.1)
		game.pilot.global_position = Vector3(-100,20,-100); game.pilot.pending_reset = false
		var port: Dictionary = game.submarine_traffic.port_by_id(5)
		var approach: Vector3 = ship.waypoints[0]-port.entry
		var incoming: Vector3 = ship.global_position-port.entry
		check(approach.dot(incoming) > 0,"Aquatraz approach stays on the incoming side instead of circling behind it")
		check(is_instance_valid(ship.dock_audio) and ship.dock_audio.sources.values().all(func(sound: AudioStream) -> bool: return sound != null),"Mission prison sub loads docking, door and closing sounds")
		ship.set_local_simulation(false)
		for tick in range(6000):
			if ship.global_position.distance_to(port.entry) < 6: break
			ship.advance_abstract(0.25); mission._step_escort(0.25)
		check(not runtime.active().is_empty() and ship.global_position.distance_to(port.entry) < 6,"Transport reaches Aquatraz approach without ending mission: "+id)
		ship.arrived.emit()
		check(not runtime.active().is_empty() and game.player_progress.status.credits == 100000,"Approach arrival signal cannot award success before docking")
		if id == "escort":
			ship.set_local_simulation(true); ship.set_physics_process(false)
			game.camera.global_position = port.entry+Vector3(8,-0.7,9); game.camera.look_at(port.entry-Vector3.UP*2)
			var phases: Array[String] = []
			for frame in range(3600):
				ship.advance(0.1)
				if not phases.has(ship.stage):
					phases.append(ship.stage)
					if ship.stage in ["open","descend","close"]:
						check(not runtime.active().is_empty() and ship.get_parent().visible,"Transport remains present during hatch phase "+ship.stage)
						check(ship.dock_audio.sequence_active and ship.dock_audio.players.sequence.playing,"Docking sequence audio runs during "+ship.stage)
						check(ship.dock_audio.doors_active == (ship.stage in ["open","close"]),"Door audio follows the hatch phase")
						if DisplayServer.get_name() != "headless":
							for settling in range(3): await process_frame
							await RenderingServer.frame_post_draw
							root.get_texture().get_image().save_png("res://tests/prison-dock-"+ship.stage+".png")
				if runtime.active().is_empty(): break
				await physics_frame
			if not runtime.active().is_empty(): print("Docking diagnostic: ",ship.stage," position ",ship.global_position," entry ",port.entry," waypoint ",ship.waypoint," path ",ship.path," obstacle ",ship.last_obstacle," destination ",ship.destination)
			check(phases.has("open") and phases.has("descend") and phases.has("close") and ship.stage == "berth","Visible transport opens hatch, enters and closes it before completion")
		else:
			for tick in range(3600):
				ship.advance_abstract(0.25)
				if runtime.active().is_empty(): break
			check(ship.stage == "berth" and ship.last_city == 5,"Distant transport reaches actual Aquatraz berth")
		check(runtime.active().is_empty() and game.player_progress.missions.completed.get(id,{}).get("score",0) == 1,"Docking completes full escort success: "+id)
		check(game.player_progress.status.credits == 103500,"Docking pays original reward once")
		check(not ship.get_parent().visible,"Transport is removed only after becoming hidden inside Aquatraz")
		await process_frame; await process_frame
		check(not is_instance_valid(ship),"Docked transport leaves traffic cleanly")

	# Source 0040cc80: the two TECHNEW ships carry rescue pods. The selected
	# one approaches the host, transfers for 400 ticks and retreats to Velcova.
	await fresh("escort")
	var mission: RefCounted = jobs.remaining
	for index in range(4): mission._escort_wave()
	check(mission.enemies.size() == 4 and mission.enemies.filter(func(agent: Node3D) -> bool: return agent.get_meta("pod_rescuer",false)).size() == 2,"Two of four Procha attackers carry rescue pods")
	mission._step_escort(0)
	var rescuer: Node3D = mission.rescuer
	check(rescuer.follow == mission.ship and not rescuer.engage_player and not is_instance_valid(rescuer.combat_target),"Rescuer targets prison ship rather than attacking player")
	check(rescuer.body.get_collision_exceptions().has(mission.ship.body) and mission.ship.body.get_collision_exceptions().has(rescuer.body),"Boarding ships ignore their own host in collision avoidance")
	rescuer.get_parent().global_position = mission.ship.global_position+Vector3(0,3.5,0)
	rescuer.path.clear(); rescuer.set_local_simulation(true); rescuer.set_physics_process(false)
	for frame in range(150):
		rescuer.advance(0.1); mission._step_escort(0.1)
		if mission.transfer > 0: break
		await physics_frame
	check(mission.transfer > 0 and is_instance_valid(mission.rescue_pod),"Actual local rescuer approaches and begins pod transfer")
	mission._step_escort(15.0)
	check(not mission.flags.get("escaped",false),"Prisoner transfer does not complete before sixteen seconds")
	mission._step_escort(1.1)
	check(mission.flags.get("escaped",false) and rescuer.follow == null and not rescuer.waypoints.is_empty(),"Completed transfer sends prisoners toward Velcova")
	check(runtime.target_marker.target_body() == rescuer.body,"HUD follows escaping prisoners")
	mission.flags["started"] = true
	mission.ship.stage = "berth"; mission.ship.last_city = 5; mission.ship.dock_destination = 5; mission.ship.wait = 0
	mission.ship._advance_motion(60)
	check(mission.ship.stage == "berth","Empty prison transport remains docked while player pursues the prisoners")
	rescuer.get_parent().global_position = jobs._city(2)
	mission._step_escort(0.1); mission._step_escort(0.1)
	check(mission.flags.get("escaped",false) and mission.flags.get("escape_reported",false) and not runtime.active().is_empty(),"Rescuer reaching Velcova cannot turn the empty prison ship into a full success")
	mission.step(6.1)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.escort.success and game.player_progress.status.credits == 100000,"Escaped prisoners produce original delayed failure without a reward")
	runtime._cleanup(); game.free(); await process_frame
	print("Prison docking and boarding: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
