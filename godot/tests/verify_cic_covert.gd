extends "res://tests/verify_remaining_stage_two.gd"
const Survivors = preload("res://mission_survivors.gd")
const Identity = preload("res://entity_identity.gd")

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for CIC scenarios")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.docking.set_physics_process(false); game.set_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	while not game.submarine_traffic.navigation_ready: game.submarine_traffic.build_graph(128); await process_frame
	for agent in game.submarine_traffic.traders: agent.set_physics_process(false)
	for id in ["spytech","spytech2"]:
		for tapped in [false,true]:
			Survivors.clear(game.submarine_traffic); await fresh(id)
			var mission: RefCounted = jobs.remaining
			var shuttle: Node3D = mission.ship
			shuttle.health.remaining = 7.5
			var pose: Transform3D = shuttle.get_parent().global_transform
			if tapped: check(jobs.attach_listening_device(shuttle.body),"Big Ears tags shuttle before detection")
			game.pilot.global_position = shuttle.global_position+shuttle.get_parent().global_basis.z
			mission.step(4.1); mission.step(2.5)
			check(mission.flags.get("failed",false),"Two visible approaches detect the player in "+id)
			mission.step(7.1 if tapped else 1.1)
			if id == "spytech2" and not tapped: game.submarine_traffic.navigation_ready = false
			mission.step(6.1); game.submarine_traffic.navigation_ready = true
			check(runtime.active().is_empty() and not game.player_progress.missions.completed[id].success,"Original warning sequence fails detected mission")
			check(is_instance_valid(shuttle) and game.submarine_traffic.traders.has(shuttle) and not shuttle.get_parent().is_queued_for_deletion(),"Detection leaves the same shuttle in the world")
			check(shuttle.get_parent().global_transform.is_equal_approx(pose) and shuttle.health.remaining == 7.5,"Failure preserves shuttle position, orientation and damage")
			check(shuttle.retiring and shuttle.destination in [1,3] and not shuttle.combat_enabled and shuttle.waypoints.is_empty(),"Shuttle leaves its loop for a Bohine dock")
			check(shuttle.get_signal_connection_list("destroyed").all(func(connection: Dictionary) -> bool: return connection.callable.get_object() != mission),"Departing shuttle releases mission callbacks")
			var identity := Identity.of(shuttle)
			# A blocked path or a lost hatch reservation can clear the transient
			# destination; saving must retain the ship's departure order anyway.
			shuttle.destination = 0
			var saved: Dictionary = game.submarine_traffic.snapshot()
			check(saved[identity].destination == shuttle.dock_destination and saved[identity].destination in [1,3],"Saving during route retry preserves the Bohine docking order")
			check(game.submarine_traffic.valid_snapshot(saved),"Optional departure state preserves beta snapshot format")
			game.submarine_traffic.restore(saved)
			shuttle = game.submarine_traffic.traders.filter(func(agent: Node3D) -> bool: return Identity.of(agent) == identity)[0]
			shuttle.set_physics_process(false)
			check(shuttle.retiring and shuttle.dock_destination == shuttle.destination and not shuttle.combat_enabled and shuttle.health.remaining == 7.5 and shuttle.get_parent().global_transform.is_equal_approx(pose),"Reload restores the docking order without healing or hostility")
			if id == "spytech" and not tapped:
				preload("res://campaign_resources.gd").restore_for_progress(game)
				game.docking.stage = game.Docking.Stage.DOCKED
				check(game.save_games.write(4,game._save_snapshot("Departing CIC shuttle")) == OK and await game._load_saved_game(4),"Departure survives a real published-beta-format disk save/load")
				shuttle = game.submarine_traffic.traders.filter(func(agent: Node3D) -> bool: return Identity.of(agent) == identity)[0]
				shuttle.set_physics_process(false)
				game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false); game.set_process(false)
				game.world_root.get_node("ActorActivity").set_physics_process(false)
				check(shuttle.retiring and shuttle.health.remaining == 7.5,"Disk restore retains departure and damage")
			var destination: int = shuttle.destination
			if tapped:
				# Local simulation must physically open, enter and close the hatch.
				shuttle.set_local_simulation(true); shuttle.set_physics_process(false)
				for frame in range(2600):
					shuttle.advance(0.1)
					if not shuttle.running: break
					await physics_frame
				check(shuttle.stage == "berth" and not shuttle.running and shuttle.journey_count == 1,"Visible departing shuttle completes real docking")
			else:
				shuttle.set_local_simulation(false)
				var start: Vector3 = shuttle.global_position
				shuttle.advance_abstract(0.25)
				check(shuttle.global_position.distance_to(start) <= 0.376,"Distant shuttle travels at its normal speed without teleporting")
				for tick in range(2600):
					if not shuttle.running: break
					shuttle.advance_abstract(0.25)
				check(shuttle.stage == "berth" and not shuttle.running,"Distant departing shuttle reaches a dock")
			check(shuttle.last_city == destination,"Shuttle arrives at its chosen Bohine city")
			await process_frame; await process_frame
			check(not is_instance_valid(shuttle) and game.submarine_traffic.traders.all(func(agent: Node3D) -> bool: return Identity.of(agent) != identity),"Docked shuttle is removed from world and traffic")
			check(game.player_progress.status.credits == 100000,"Detection and departure award no money")

	await fresh("spytech")
	var mission: RefCounted = jobs.remaining
	game.pilot.global_position = Vector3(-100,20,-100)
	jobs.attach_listening_device(mission.ship.body)
	mission.step(39.9)
	check(not is_instance_valid(mission.cargo),"All five eight-second intercepted lines precede freighter reveal")
	mission.step(0.1)
	var freighter: Node3D = mission.cargo
	check(is_instance_valid(freighter) and mission.enemies.size() == 4,"Red Orca appears with four original guards")
	check(freighter.freighter_guns and not freighter.combat_enabled and freighter.waypoints.is_empty(),"Freighter has weapons without a chase route")
	check(runtime.target_marker.target_body() == freighter.body,"Green target square switches to Red Orca")
	await capture("freighter")
	var before: Transform3D = freighter.get_parent().global_transform
	var count := get_nodes_in_group("turret_missiles").size()
	game.pilot.global_position = freighter.global_position+freighter.get_parent().global_basis.z*11
	freighter.advance(5.1)
	check(get_nodes_in_group("turret_missiles").size() == count,"Red Orca does not fire outside original ten-unit range")
	for side in [1,-1]:
		game.pilot.global_position = freighter.global_position+freighter.get_parent().global_basis.z*float(side)*7
		freighter.cooldown = 0; freighter.advance(0)
		var shots := get_nodes_in_group("turret_missiles")
		check(shots.size() == count+1,"Red Orca fires from each end of the hull")
		var missile: Node3D = shots.back(); missile.set_physics_process(false)
		check(missile.homing and missile.target == game.pilot and missile.source == freighter,"Original homing missile targets the player")
		var socket := Vector3(0,0,3.2) if side == 1 else Vector3(0,-0.2,-0.6)
		check(missile.global_position.is_equal_approx(freighter.get_parent().to_global(socket)),"Missile uses recovered fore/aft launch socket")
		freighter.advance(4.9)
		check(get_nodes_in_group("turret_missiles").size() == count+1,"Freighter respects its five-second reload")
		missile.free()
	check(freighter.global_position.distance_to(before.origin) < 0.03,"Red Orca remains on station while firing")
	game.pilot.global_position = freighter.global_position+Vector3.UP*7
	mission.step(0.1)
	check(not mission.flags.get("cargo_warning",false),"Freighter's approach scan waits the original eight seconds after reveal")
	mission.step(8.0)
	check(mission.flags.get("cargo_warning",false),"Approach triggers original freighter warning")
	mission.step(20.1)
	check(mission.enemies.all(func(agent: Node3D) -> bool: return agent.engage_player),"Ignoring warning makes all four guards attack")
	var guards: Array[Node3D] = mission.enemies.duplicate()
	freighter.take_weapon_damage_from(1000,freighter.global_position,game.pilot)
	var effects := get_nodes_in_group("base_destruction")
	check(freighter.dead and effects.size() == 1,"Red Orca starts the requested large destruction effect")
	var demolition: Node3D = effects[0]; demolition.set_process(false)
	check(demolition.explosions == 1 and not demolition.buildings[0].model.find_children("*","MeshInstance3D",true,false).is_empty(),"First explosion retains visible freighter geometry")
	if DisplayServer.get_name() != "headless":
		demolition._process(0.7)
		for frame in range(3): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/cic-freighter-destruction.png")
	mission.step(1.9)
	check(not runtime.active().is_empty(),"Original completion waits two seconds after destruction")
	mission.step(0.2); await physics_frame; await physics_frame
	check(runtime.active().is_empty() and game.player_progress.status.credits == 103500,"Destruction pays original 3,500-credit reward once")
	check(is_instance_valid(demolition) and not demolition.is_queued_for_deletion(),"Mission cleanup leaves the ongoing explosion sequence intact")
	check(guards.all(func(agent: Node3D) -> bool: return is_instance_valid(agent) and game.submarine_traffic.traders.has(agent)),"Living guards persist after completion")
	demolition._process(2.11)
	check(demolition.explosions == 7 and demolition.wrecks == 1,"Six distributed explosions lead to a final large burst and debris")
	await process_frame; await process_frame
	check(not is_instance_valid(demolition),"Completed destruction cleans up its visual copy")
	Survivors.clear(game.submarine_traffic)
	await fresh("spytech2")
	mission = jobs.remaining
	jobs.attach_listening_device(mission.ship.body); game.pilot.global_position = Vector3(-100,20,-100)
	mission.step(40)
	mission.enemies[0].take_weapon_damage_from(1,mission.enemies[0].global_position,mission.ship.body)
	check(mission.enemies.all(func(agent: Node3D) -> bool: return agent.engage_player),"Damage from another vessel alerts all freighter guards, as in the source callback")
	game.pilot.global_position = mission.ship.global_position+mission.ship.get_parent().global_basis.z
	mission.step(2.5); mission.step(2.5)
	check(mission.flags.get("reinforced",false) and mission.enemies.size() == 8 and not mission.flags.get("failed",false),"Detection after the exchange adds four reinforcements instead of failing")
	check(mission.enemies.slice(4).all(func(agent: Node3D) -> bool: return agent.get_parent().get_meta("editor_model") == "TRAD2" and agent.engage_player and agent.pursue_offscreen),"Original reinforcement models actively pursue the player")
	mission.step(7.1); mission.step(6.1)
	check(not runtime.active().is_empty(),"Late detection warning leaves the freighter objective playable")
	# Original destruction cancels pending shuttle scans and warning/conversation events.
	mission.later(1,"spy_warning"); mission.later(7,"spy_failed")
	var probe := preload("res://listening_probe.gd").new(); game.world_root.add_child(probe)
	probe.attached = true; probe.designated_target = mission.ship.body; game.equipment.support_tools.projectiles.append(probe)
	mission.ship.take_weapon_damage_from(1000,mission.ship.global_position,game.pilot)
	check(not runtime.active().is_empty(),"Losing the shuttle after reveal does not fail the freighter objective")
	check(probe.is_queued_for_deletion() and not game.equipment.support_tools.projectiles.has(probe),"Destroyed shuttle loses its attached Big Ears probe")
	check(mission.scheduled.all(func(event: Dictionary) -> bool: return event.event not in ["spy_warning","spy_failed"]),"Destroyed shuttle cancels stale warning and failure events")
	await fresh("spytech")
	mission = jobs.remaining
	mission.ship.take_weapon_damage_from(1000,mission.ship.global_position,game.pilot)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.spytech.success and game.player_progress.status.credits == 100000,"Destroying shuttle before reveal fails without a reward")
	await fresh("spytech")
	mission = jobs.remaining; mission._spawn_freighter()
	mission.cargo.take_weapon_damage_from(1000,mission.cargo.global_position,game.pilot)
	check(not get_nodes_in_group("base_destruction").is_empty(),"An unfinished demolition exists before session reset")
	game._begin_new_game()
	check(get_nodes_in_group("base_destruction").is_empty(),"New game removes unfinished demolition without spawning old mission debris")
	check(game.submarine_traffic.traders.all(func(agent: Node3D) -> bool: return not agent.has_meta(Survivors.TAG)),"New game clears mission aftermath")
	runtime._cleanup(); game.free(); await process_frame
	print("CIC covert: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
