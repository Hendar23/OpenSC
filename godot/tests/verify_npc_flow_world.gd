extends "res://tests/verify_remaining_stage_two.gd"

func actor(model_id: String, point: Vector3, combat: bool) -> Node3D:
	var model: Node3D = preload("res://map_document.gd").load_model(model_id,game.game_folder)
	game.world_root.add_child(model); model.global_position = point; model.set_meta("editor_model",model_id)
	var agent: Node3D = preload("res://pirate_submarine.gd").install_pirate(model,{"npc_speed":2.5,"npc_health":10000.0,"npc_sustain":0.0}) if combat else preload("res://mission_vessel.gd").install_mission(model,{"npc_speed":2.0,"npc_health":10000.0,"npc_sustain":0.0})
	game.submarine_traffic.register_vessel(agent,game.world_root,game.game_folder)
	agent.set_physics_process(false)
	return agent

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for actual-model NPC flow")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.docking.set_physics_process(false); game.set_process(false); game.weapons.set_physics_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.wildlife.set_simulating(false)
	var traffic: Node = game.submarine_traffic
	while not traffic.navigation_ready: traffic.build_graph(128); await process_frame
	for ship in traffic.traders: ship.running = false; ship.body.collision_layer = 0; ship.set_physics_process(false)
	var center := Vector3.INF
	for point_id in traffic.graph.get_point_ids():
		var point: Vector3 = traffic.graph.get_point_position(point_id)
		var clear := true
		for index in range(8):
			var edge := point+Vector3(cos(index*TAU/8),0,sin(index*TAU/8))*19
			if not traffic.segment_clear(point,edge): clear = false; break
		if clear: center = point; break
	check(center.is_finite(),"Real terrain contains a clear encounter area")
	if not center.is_finite(): game.free(); quit(1); return
	game.pilot.global_position = Vector3(-100,20,-100); game.pilot.pending_reset = false
	var host := actor("PRISON",center,false); host.combat_enabled = false
	var attacker := actor("PIRATE",center+Vector3(0,0,-12),true); attacker.victim = host.body
	var patrol := actor("TRADSHUT",center+Vector3(-12,0,-9),false); patrol.combat_enabled = false; patrol.loop_route = true
	patrol.waypoints = PackedVector3Array([center+Vector3(-12,0,7),center+Vector3(-4,0,7),center+Vector3(-4,0,-9),center+Vector3(-12,0,-9)])
	game.camera.global_position = center+Vector3(15,-0.4,14); game.camera.look_at(center)
	game.camera.make_current()
	var phases := {}; var shots := 0; var moving := 0; var stationary_turns := 0; var previous: Basis = attacker.get_parent().basis
	for tick in range(1800):
		attacker.advance(1.0/60.0); patrol.advance(1.0/60.0)
		phases[attacker.attack_run.phase] = true
		if tick > 120:
			if attacker.speed > 0.3: moving += 1
			if attacker.speed < 0.1 and previous.get_rotation_quaternion().angle_to(attacker.get_parent().basis.get_rotation_quaternion()) > 0.001: stationary_turns += 1
		previous = attacker.get_parent().basis
		shots = maxi(shots,get_nodes_in_group("turret_missiles").size())
		if tick in [180,600,1200,1750] and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tests/npc-world-flow-"+str(tick)+".png")
		await physics_frame
	check(phases.size() == 4 and attacker.attack_run.passes >= 2,"Actual pirate completes repeated runs around the real prison hull")
	check(shots > 0,"Actual pirate fires original missiles during attack runs")
	check(float(moving)/1679 > 0.85 and stationary_turns < 30,"Real model stays in motion rather than turning on the spot")
	check(host.global_position.distance_to(center) < 0.01,"Unarmed stationary host keeps its mission position")
	check(patrol.global_position.distance_to(patrol.home.origin) > 1.0,"Actual civilian model follows its continuous patrol")
	print("World flow: passes ",attacker.attack_run.passes," moving ",float(moving)/1679," stationary turns ",stationary_turns," simultaneous shots ",shots)
	game.free(); await process_frame
	print("World NPC flow: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
