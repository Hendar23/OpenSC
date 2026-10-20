extends "res://tests/verify_remaining_stage_two.gd"

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for live mission simulation")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.docking.set_physics_process(false); game.set_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	var activity: Node = game.world_root.get_node("ActorActivity")
	while not game.submarine_traffic.navigation_ready: game.submarine_traffic.build_graph(128); await process_frame
	for id in ["spytech","spytech2"]:
		await fresh(id)
		var ship: Node3D = jobs.remaining.ship
		game.pilot.global_position = Vector3(-100,20,-100); game.pilot.pending_reset = false
		game.dock_interface_active = false
		game.camera.global_position = ship.global_position+Vector3(0,4,8); game.camera.look_at(ship.global_position)
		ship.set_physics_process(true); jobs.set_physics_process(true)
		var start: Vector3 = ship.global_position
		for frame in range(150): await physics_frame
		check(ship.global_position.distance_to(start) > 1.0,"Actual physics moves CIC scout after launch: "+id)
		check(not ship.retiring and not ship.freighter_guns and not runtime.active().is_empty(),"Scout retains its patrol rather than freighter or departure orders")
		# A stale local flag used to bypass activation entirely, leaving the
		# model/controller disabled even though the nearby player could see it.
		ship.set_physics_process(false); ship.get_parent().process_mode = Node.PROCESS_MODE_DISABLED
		start = ship.global_position
		for frame in range(100): await physics_frame
		check(ship.is_physics_processing() and ship.get_parent().process_mode != Node.PROCESS_MODE_DISABLED and ship.global_position.distance_to(start) > 0.5,"Activity manager repairs disabled processing on an already-local scout")
		# Force distant travel through ActorActivity, then return close enough
		# for the real activation/hull-clearance path rather than calling advance.
		var far: float = game.camera.far; game.camera.far = 2
		game.camera.global_position = Vector3(-100,20,-100)
		for frame in range(20): await physics_frame
		check(not ship.local_simulation,"Distant scout switches to abstract simulation")
		start = ship.global_position
		for frame in range(100): await physics_frame
		check(ship.global_position.distance_to(start) > 1.0,"Distant scout keeps moving")
		game.camera.far = far
		game.camera.global_position = ship.global_position+Vector3(0,4,8); game.camera.look_at(ship.global_position)
		for frame in range(20): await physics_frame
		check(ship.local_simulation and ship.get_parent().visible,"Returning to scout reactivates visible physics")
		check(runtime.target_marker.process_mode == Node.PROCESS_MODE_ALWAYS,"Mission overlay can erase its draw commands while gameplay is paused")
		start = ship.global_position
		game._show_main_menu()
		for frame in range(8): await process_frame
		check(not runtime.target_marker.target_point().is_finite() and runtime.target_marker.can_process(),"Paused main menu clears mission target boxes")
		check(ship.global_position.is_equal_approx(start),"Main menu pauses the scout")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tests/mission-menu-no-target.png")
		game._resume_game()
		for frame in range(150): await physics_frame
		check(ship.global_position.distance_to(start) > 1.0 and not runtime.active().is_empty(),"Scout continues moving after menu resume")
		game.pilot.global_position = ship.global_position+Vector3(0,12,0)
		check(jobs.attach_listening_device(ship.body),"Scout accepts Big Ears during live simulation")
		start = ship.global_position
		for frame in range(100): await physics_frame
		check(ship.global_position.distance_to(start) > 0.5,"Tagging does not stop the scout")
		jobs.set_physics_process(false)
	for id in ["escort","escort2"]:
		await fresh(id)
		var ship: Node3D = jobs.remaining.ship
		game.pilot.global_position = Vector3(-100,20,-100); game.pilot.pending_reset = false
		game.camera.global_position = ship.global_position+Vector3(0,4,8); game.camera.look_at(ship.global_position)
		ship.set_physics_process(true); jobs.set_physics_process(true)
		for frame in range(120): await physics_frame
		check(not runtime.active().is_empty() and not jobs.remaining.flags.get("started",false),"Idle escort waits for the player instead of completing on launch: "+id)
		check(not ship.arrival_reported,"Unassigned route cannot report arrival")
		game.pilot.global_position = ship.global_position+Vector3.UP*3
		for frame in range(30): await physics_frame
		check(not runtime.active().is_empty() and jobs.remaining.flags.get("started",false) and ship.dock_destination == 5,"Joining starts the prison journey without an instant reward")
		ship.arrived.emit()
		check(not runtime.active().is_empty() and game.player_progress.status.credits == 100000,"An arrival signal away from Aquatraz cannot complete escort")
		jobs.set_physics_process(false)
	runtime._cleanup(); game.free(); await process_frame
	print("Live mission simulation: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
