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
	storage.root_override = "res://tests/cache-pirate-stockpile-fixtures"; storage.ensure_parent(storage.preferences_path())
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
	check(not game.world_root.has_node("Scenery/PIPEBARS_336") and game.world_root.has_node("Scenery/PIPEBARS_8"),"West Outlet has only its intact startup grille, not the dormant broken mission prop")
	var raw_gate := preload("res://clump_loader.gd").load_clump(game.game_folder.path_join("CLUMPS/PIPEBARS.DFF"))
	for mesh in raw_gate.find_children("*","MeshInstance3D",true,false):
		for index in mesh.mesh.get_surface_count():
			var mat: StandardMaterial3D = mesh.mesh.surface_get_material(index)
			if mat.albedo_texture == null:
				var tint := mat.albedo_color
				check(absf(tint.r-tint.g)<0.03 and absf(tint.g-tint.b)<0.03,"PIPEBARS uses authored neutral metal colours rather than cyan fallback")
	raw_gate.free()
	for id in ["puffa","puffa2"]:
		runtime._cleanup(); await physics_frame; await process_frame
		preload("res://mission_survivors.gd").clear(game.submarine_traffic)
		game.player_progress = Progress.restore({"campaign_stage":4}); game.player_progress.status.credits = 0
		var city := Rules.offering_city(id)
		check(Rules.next_offer(game.player_progress,city) == id,"Original Procha city offers stockpile encounter")
		game.docking.current = game.submarine_traffic.port_by_id(city); game.docking.stage = game.Docking.Stage.DOCKED
		check(runtime.accept(city,id).is_empty(),"Accept stockpile mission")
		game.docking.stage = game.Docking.Stage.IDLE; jobs.set_physics_process(false)
		var m = jobs.controller
		var gate: Node3D = m.pipe_gate
		check(gate != null and not gate.visible,"Stockpile opens original south pipe grille for either city")
		var gate_bodies: Array = gate.find_children("*","CollisionObject3D",true,false)
		check(not gate_bodies.is_empty() and gate_bodies.all(func(body):return body.collision_layer == 0 and body.collision_mask == 0),"Open pipe cannot retain invisible collision")
		check(m.fish.size() == 9 and m.enemies.size() == 6 and m.turrets.size() == 3,"Original nine fishbots, six pirate subs and three turrets")
		check(m.fish.all(func(robot): return robot.get_script() == preload("res://fishbot.gd") and robot.death_frames.is_empty() and robot.death_sound == null and robot.death_flesh_texture == null),"Fishbots use mechanical deaths without blood or organic splats")
		check(not game.wildlife.death_frames.is_empty(),"Mechanical death setup preserves organic wildlife blood assets")
		check(m.blades.size() == 3 and m.outpost.health == 40 and is_equal_approx(m.outpost.sustain,0.2),"Original three fan blades and outpost shield values")
		check(jobs.target_body() == m.outpost and jobs.target_center(m.outpost).is_finite(),"Stockpile targeting works with physical outpost")
		game.pilot.global_position = m.current_pose.origin
		var before: Vector3 = game.pilot.movement.velocity
		m.step(3)
		check(m.fan_speed == 16 and game.pilot.movement.velocity.distance_to(before) > 1,"Fan reaches original full speed and current pushes submarine")
		game.pilot.collision_layer = 2
		game.pilot.global_position = m.button.global_position; m.switch_cooldown = 0
		await physics_frame; await process_frame
		m.step(0)
		check(m.fan_direction == -1 and m.current_direction == -1 and m.switch_health == 10,"Sub contact reverses fan/current without weapon damage")
		check(not m.button.meshes.is_empty() and m.button.meshes[0].get_blend_shape_value(0) == 1,"Contact displays the original pressed switch pose")
		var sweep := KinematicCollision3D.new()
		var start: Transform3D = game.pilot.global_transform
		start.origin = m.button.to_global(Vector3(0,0,2))
		check(game.pilot.test_move(start,-m.button.global_basis.z*3,sweep) and sweep.get_collider() == m.button,"Visible switch physically blocks the submarine")
		var robot: Node3D = m.fish[0]
		robot.take_weapon_damage(100)
		var wreck: Node = game.world_root.get_node_or_null("MachineWreck")
		check(robot.dead and wreck != null and wreck.gore.is_empty() and not wreck.pieces.is_empty() and wreck.explosion_audio == null,"Destroyed fishbot leaves textured metal pieces without organic gore or sound")
		m.step(2.56)
		check(absf(m.fan_speed) < 0.01,"Fan brakes through a slow crossing window before reversing")
		m.step(3)
		check(m.fan_speed == -16,"Fan accelerates to reverse full speed")
		for i in range(5): m.switch_cooldown = 0; m.button.take_weapon_damage(1)
		check(m.switch_health == 0,"Five weapon hits break original switch")
		var direction: float = m.fan_direction
		m.switch_cooldown = 0; m.switch_hit()
		check(m.fan_direction == direction,"Broken switch cannot issue new fan commands")
		var pirate: Node3D = m.enemies[0]
		var kept_fan: Node3D = m.fan
		var kept_switch: Node3D = m.button
		m.outpost.take_weapon_damage(200)
		check(m.resolved and not runtime.active().is_empty(),"Destroying outpost starts success independently of surviving defenders")
		m.step(2.1); await process_frame
		check(runtime.active().is_empty() and game.player_progress.status.credits == 4000,"Two-second success and original 4000-credit reward")
		check(is_instance_valid(pirate) and pirate.mission_owner.is_empty() and pirate.running,"Surviving pirate ships persist after success")
		check(not gate.visible and gate_bodies.all(func(body):return body.collision_layer == 0),"Pipe remains open while the fan is retained")
		check(jobs.controller == null and jobs.actors.is_empty(),"Mission controllers release retained machinery from generic cleanup")
		check(is_instance_valid(kept_fan) and kept_fan.is_visible_in_tree() and is_instance_valid(kept_switch),"Fan and switch survive mission completion")
		var pose: Basis = kept_fan.basis
		for tick in range(6): await physics_frame
		check(not kept_fan.basis.is_equal_approx(pose),"Retained fan keeps rotating after success")
		var sign_before: float = m.current_direction
		m.switch_cooldown = 0; kept_switch.take_weapon_damage(1)
		check(m.current_direction == -sign_before,"Retained switch continues controlling the current")
		runtime.docked(city); await process_frame
		check(not is_instance_valid(kept_fan) and not is_instance_valid(kept_switch),"Next docking removes retained machinery and collision")
		check(gate.visible and gate_bodies.all(func(body):return body.collision_layer != 0),"Next docking restores the original grille")
	runtime._cleanup(); await process_frame
	game.player_progress = Progress.restore({"campaign_stage":4})
	game.docking.current = game.submarine_traffic.port_by_id(2); game.docking.stage = game.Docking.Stage.DOCKED
	runtime.accept(2,"puffa"); jobs.set_physics_process(false)
	var abort_mission = jobs.controller
	var abort_gate: Node3D = abort_mission.pipe_gate
	var old_fan: Node3D = abort_mission.fan
	var old_switch: Node3D = abort_mission.button
	var surviving_pirate: Node3D = abort_mission.enemies[0]
	runtime.finish(false); await process_frame; await physics_frame
	check(abort_gate.visible,"Abort restores the original closed grille")
	check(not is_instance_valid(old_fan) and not is_instance_valid(old_switch),"Abort removes fan/switch and their collision")
	check(is_instance_valid(surviving_pirate) and surviving_pirate.mission_owner.is_empty(),"Abort preserves surviving pirate ships")
	check(game.player_progress.status.credits == 0,"Abort pays no success credits")
	# A new-session reset also cleans up machinery retained after success.
	game.player_progress = Progress.restore({"campaign_stage":4})
	game.docking.current = game.submarine_traffic.port_by_id(2); game.docking.stage = game.Docking.Stage.DOCKED
	runtime.accept(2,"puffa"); jobs.set_physics_process(false)
	var session_mission = jobs.controller
	var session_fan: Node3D = session_mission.fan
	var session_gate: Node3D = session_mission.pipe_gate
	session_mission.outpost.take_weapon_damage(200); session_mission.step(2.1); await process_frame
	check(is_instance_valid(session_fan),"Success retains machinery before session reset")
	# Session cleanup removes released pirate ships; no repeated payout.
	game.events.session_started.emit(false)
	await process_frame
	check(not is_instance_valid(session_fan) and session_gate.visible,"Session reset clears retained machinery and restores the grille")
	check(game.player_progress.status.credits == 4000,"Session reset does not repeat reward")
	game.free(); await process_frame
	print("Pirate stockpile: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
