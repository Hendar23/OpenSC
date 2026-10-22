extends "res://tests/verify_remaining_stage_two.gd"

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for moving convoy boarding")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.docking.set_physics_process(false); game.set_process(false); game.weapons.set_physics_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false); game.wildlife.set_simulating(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	var traffic: Node = game.submarine_traffic
	while not traffic.navigation_ready: traffic.build_graph(128); await process_frame
	for agent in traffic.traders: agent.set_physics_process(false); agent.body.collision_layer = 0
	game.day_night.hour = 12; game._update_daylight()
	for id in ["escort","escort2"]:
		await fresh(id)
		var mission: RefCounted = jobs.remaining
		var host: Node3D = mission.ship
		game.pilot.global_position = host.global_position+Vector3.UP*3; game.pilot.pending_reset = false
		mission._step_escort(0.1)
		var fastest := 0.0; var boarding_started := -1.0; var transfer_start := Vector3.ZERO
		var carriers_checked := false; var damaged := false; var fallback_checked := false
		var original_rescuer: Node3D; var captured := false; var combat_movers := {}
		for tick in range(1800):
			game.pilot.global_position = host.global_position+Vector3(7,-0.5,-3)
			game.pilot.health = 10000
			mission.step(0.1)
			if mission.flags.get("escaped",false) or runtime.active().is_empty(): break
			host.advance(0.1)
			for agent in mission.enemies:
				agent.set_local_simulation(true); agent.set_physics_process(false)
				if not agent.dead: agent.advance(0.1)
				if not agent.get_meta("pod_rescuer",false) and agent.speed > 0.5: combat_movers[agent.get_instance_id()] = true
			if not is_instance_valid(mission.rescuer): await physics_frame; continue
			var boarder: Node3D = mission.rescuer
			fastest = maxf(fastest,boarder.speed)
			if not damaged:
				original_rescuer = boarder
				boarder.take_weapon_damage_from(0.1,game.pilot.global_position,game.pilot)
				check(boarder.boarding and boarder.follow == host and not boarder.engage_player,"Player fire does not cancel the active boarding order: "+id)
				damaged = true
			if not carriers_checked and mission.enemies.size() == 4:
				var carriers: Array = mission.enemies.filter(func(agent: Node3D) -> bool: return agent.get_meta("pod_rescuer",false))
				check(carriers.size() == 2 and carriers.all(func(agent: Node3D) -> bool: return is_instance_valid(agent.boarding_pod) and agent.boarding_pod.visible),"Both original carriers have visible escape pods: "+id)
				check(carriers[0].global_position.distance_to(carriers[1].global_position) > 2,"Carriers have distinct positions rather than stacking: "+id)
				check(carriers.filter(func(agent: Node3D) -> bool: return agent.boarding).size() == 1,"Only one carrier uses the original active boarding slot: "+id)
				carriers_checked = true
			if mission.transfer > 0 and boarding_started < 0:
				boarding_started = tick*0.1; transfer_start = host.global_position
			if mission.transfer > 2 and not captured:
				check(is_instance_valid(mission.rescue_pod) and mission.rescue_pod.get_parent() == host.get_parent() and is_instance_valid(mission.rescue_cable) and mission.rescue_cable.visible,"Boarder visibly deploys its own pod and cable onto the host: "+id)
				if DisplayServer.get_name() != "headless":
					game.camera.global_position = host.global_position+Vector3(3.2,1.8,3.6); game.camera.look_at(host.global_position+Vector3.UP*0.6)
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("res://tests/prison-boarding-"+id+".png")
				captured = true
			if id == "escort2" and mission.transfer > 3 and not original_rescuer.dead:
				original_rescuer.take_weapon_damage_from(1000,game.pilot.global_position,game.pilot)
				mission._step_escort(0)
				check(is_instance_valid(mission.rescuer) and mission.rescuer != original_rescuer and mission.rescuer.boarding and mission.transfer == 0,"Destroying the boarder promotes the backup and resets transfer: "+id)
				fallback_checked = true; boarding_started = -1
			await physics_frame
		check(carriers_checked and damaged and combat_movers.size() == 2,"Both untouched combat-support ships move against the player: "+id)
		check(fastest > 2 and boarding_started >= 0 and boarding_started < 100,"Boarder rapidly intercepts the moving convoy from Velcova: "+id)
		check(mission.flags.get("escaped",false) and host.global_position.distance_to(transfer_start) > 5,"Full transfer completes while the prison transport keeps moving: "+id)
		check(not mission.rescuer.boarding and mission.rescuer.follow == null and is_instance_valid(mission.rescuer.boarding_pod) and mission.rescuer.boarding_pod.get_parent() == mission.rescuer.get_parent(),"Loaded pod returns to its fleeing carrier: "+id)
		if id == "escort2": check(fallback_checked,"Moving convoy exercises actual backup rescue")
		print("Boarding ",id,": started at ",boarding_started,"s, peak ",fastest," units/s, escaped=",mission.flags.get("escaped",false))
		var escaping: Node3D = mission.rescuer
		var loaded_pod: Node3D = escaping.boarding_pod
		var port: Dictionary = traffic.port_by_id(2)
		check(escaping.dock_destination == 2,"Loaded escape ship has a real Velcova docking order: "+id)
		for agent in mission.enemies:
			if agent != escaping: agent.running = false; agent.body.collision_layer = 0
		var phases: Array[String] = []
		var saw_approach := false; var pod_retained := true; var failed_early := false
		for tick in range(1800):
			game.pilot.global_position = Vector3(-100,20,-100)
			if id == "escort2" and escaping.global_position.distance_to(port.entry) > 12:
				escaping.set_local_simulation(false); escaping.advance_abstract(0.1)
			else:
				escaping.set_local_simulation(true); escaping.set_physics_process(false); escaping.advance(0.1)
			if not phases.has(escaping.stage): phases.append(escaping.stage)
			if escaping.stage != "berth":
				# Distant simulation hides the whole ship, including its mounted pod.
				pod_retained = pod_retained and is_instance_valid(loaded_pod) and loaded_pod.get_parent() == escaping.get_parent() and loaded_pod.visible and (not escaping.get_parent().is_visible_in_tree() or loaded_pod.is_visible_in_tree())
				if escaping.global_position.distance_to(port.entry) < 8: saw_approach = true
			mission.step(0.1)
			if runtime.active().is_empty():
				failed_early = escaping.stage != "berth" or escaping.last_city != 2
				break
			await physics_frame
		check(saw_approach and pod_retained and not failed_early,"Approaching the dock retains the visible loaded pod and cannot fail the mission: "+id)
		check(phases.has("open") and phases.has("descend") and phases.has("close") and escaping.stage == "berth" and escaping.last_city == 2,"Escape ship physically opens, enters and closes Velcova dock: "+id)
		check(runtime.active().is_empty() and not game.player_progress.missions.completed.get(id,{}).get("success",true) and game.player_progress.status.credits == 100000,"Only completed docking produces escape failure, without a reward: "+id)
		print("Escape docking ",id,": ",phases," berth=",escaping.last_city," point=",escaping.global_position," goal=",port.entry," path=",escaping.path," waypoint=",escaping.waypoint," speed=",escaping.speed," blocked=",escaping.blocked)
	runtime._cleanup(); game.free(); await process_frame
	print("Moving prison boarding: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
