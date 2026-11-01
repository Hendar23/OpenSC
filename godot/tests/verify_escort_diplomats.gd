extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
var game: Node
var runtime: Node
var jobs: Node
var checks := 0
var failures := 0
var movies: Array[String] = []
func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-diplomats-fixtures"; storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new(); config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER")); config.save(storage.preferences_path())
	call_deferred("run")
func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(description)
func fresh(id: String) -> RefCounted:
	runtime._cleanup(); preload("res://mission_survivors.gd").clear(game.submarine_traffic)
	await physics_frame; await physics_frame
	game.player_progress = Progress.restore({"campaign_stage":3})
	game.player_progress.missions["stage3_successes"] = 4
	game.player_progress.status.credits = 10000
	game.pilot.restore_health(); game.pilot.active = true; game.pilot.controls_enabled = true
	game.pilot.global_position = Vector3(10000,120,10000)
	var city := Rules.offering_city(id)
	check(Rules.next_offer(game.player_progress,city) == id,"Stage-three threshold offers "+id)
	game.docking.current = game.submarine_traffic.port_by_id(city); game.docking.stage = game.Docking.Stage.DOCKED
	var error: String = runtime.accept(city,id)
	check(error.is_empty(),"Accept original city offer "+id+": "+error)
	game.docking.stage = game.Docking.Stage.IDLE; game.dock_interface.dismiss(); jobs.set_physics_process(false)
	for agent in jobs.vessels: agent.set_physics_process(false)
	await physics_frame; await physics_frame
	return jobs.diplomats
func capture(m: RefCounted) -> void:
	game.pilot.global_position = m.ship.global_position
	m.step(0)
	check(jobs.phase == "escort" and m.ship.waypoints.size() == 3,"Rendezvous begins actual original first route")
	game.pilot.global_position = Vector3(10000,120,10000)
	m.ship.waypoint = 1; m.step(0)
	check(m.disabled and game.pilot.get_meta("diplomat_system_failure",false),"Original waypoint-one event disables controls")
	m.ship.waypoint = 3; m.step(0)
	check(m.captured and not game.pilot.has_meta("diplomat_system_failure"),"Waypoint-three capture restores controls")
	check(m.guns.size() == 2 and m.guns.all(func(g: Node3D) -> bool: return g.health == 20 and g.tuning.turret_sustain == 0.5 and g.head != null),"Original battleship has two real vulnerable gun modules")
func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(5000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Original world loads")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game()
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false); game.set_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.wildlife.set_simulating(false); game.photo_mode.replay.set_process(false)
	for frame in range(2000):
		if game.submarine_traffic.navigation_ready: break
		game.submarine_traffic.build_graph(128); await process_frame
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	game.events.fmv_requested.connect(func(cue: String, _city: int) -> void: movies.append(cue))
	var progress := Progress.restore({"campaign_stage":3})
	progress.missions["stage3_successes"] = 3; progress.missions["stage3_resolved"] = 7
	check(not Rules.core_three_unlocked(progress),"Core locked below both original thresholds")
	progress.missions["stage3_resolved"] = 8
	check(Rules.core_three_unlocked(progress),"Eight resolved jobs unlock core")
	for id in ["diptrad","diptrad2","diptech","diptech2"]:
		var m: RefCounted = await fresh(id)
		check(m.points.size() == 7 and is_instance_valid(m.ship),"All seven original markers and shuttle exist")
		for other in Rules.CORE_THREE.values():
			if other != id: check(other in game.player_progress.missions.unavailable,"Sibling core offer excluded")
		capture(m)
		var animation: RefCounted = m.capture_visual
		var first_pose: Transform3D = m.ship.get_parent().global_transform
		check(animation.inside.origin.is_equal_approx(m.boss.global_position+m.boss.global_basis.z*1.3-Vector3.UP*0.3),"Captured pose uses original executable transform at correct end of battleship")
		check(not animation.hatch.visible and m.ship.body.collision_layer == 0,"Capture opens original tag-five hatch and disables captive collision")
		m.step(3)
		check(not m.ship.get_parent().global_transform.is_equal_approx(first_pose),"Shuttle moves continuously into alignment without teleporting")
		m.step(3)
		check(m.ship.get_parent().global_position.is_equal_approx(animation.outside.origin),"Shuttle reaches mouth as original SOS begins")
		m.step(12)
		check(m.ship.get_parent().global_position.distance_to(animation.inside.origin) > 0.01 and m.ship.get_parent().global_position.distance_to(animation.outside.origin) > 0.01,"Half-swallowed shuttle lies between mouth and original captive position")
		m.step(12)
		check(animation.hatch.visible and m.ship.get_parent().global_position.is_equal_approx(animation.inside.origin),"Hatch closes at captured dialogue with shuttle in recovered original pose")
		for gun in m.guns:
			game.pilot.global_position = gun.head.global_position+Vector3(0,6 if gun == m.guns[0] else -6,0)
			gun._physics_process(5)
			check(gun.shots > 0,"Original battleship gun launches visible straight torpedoes")
		m.guns[0].hitbox.take_weapon_damage(40)
		m.step(0)
		check(not m.freed and not runtime.active().is_empty(),"One defeated gun cannot free diplomats")
		m.guns[1].hitbox.take_weapon_damage(40); m.step(0)
		check(m.freed and m.ship.dock_destination == 4 and jobs.phase == "release" and not animation.hatch.visible,"Both guns open hatch and free shuttle")
		m.step(animation.release_duration*0.5)
		check(m.ship.dormant and m.ship.body.collision_layer == 0 and not animation.released,"Shuttle visibly exits before navigation/collision resumes")
		m.step(animation.release_duration*0.5+0.01)
		check(animation.released and not m.ship.dormant and m.ship.body.collision_layer == animation.layer and m.ship.waypoints.size() == 3,"Clear shuttle resumes original onward route and collision")
		m.step(200)
		check(not runtime.active().is_empty() and game.player_progress.status.credits == 10000,"Time alone cannot complete the escort")
		var port: Dictionary = game.submarine_traffic.port_by_id(4)
		m.ship.get_parent().global_position = port.entry+Vector3.UP
		m.ship.waypoint = m.ship.waypoints.size(); m.ship.path.clear(); m.ship.wait = 0
		var ship: Node3D = m.ship
		for tick in range(2400):
			if runtime.active().is_empty(): break
			ship.advance(1.0/60.0); m.step(1.0/60.0)
			if tick%30 == 0: await physics_frame
		check(runtime.active().is_empty() and game.player_progress.campaign_stage == 4,"Actual Tryton docking advances campaign to stage four")
		check(game.player_progress.status.credits == 18000 and movies.back() == "peace","Original reward paid once and correct news cue sent")
		check(preload("res://mission_state.gd").valid(game.player_progress.missions),"Stage-four history preserves beta save schema")
	var m: RefCounted = await fresh("diptrad")
	capture(m); m.step(168)
	check(m.lost,"Unrescued diplomats self-destruct at original deadline")
	m.step(8)
	check(runtime.active().is_empty() and game.pilot.dead,"Retail failure initiates player auto-destruct")
	m = await fresh("diptrad2"); capture(m); runtime._cleanup()
	check(not game.pilot.has_meta("diplomat_system_failure") and jobs.diplomats == null,"Cancellation cleans actors and always restores controls")
	m = await fresh("diptech"); capture(m)
	var early_pose: Transform3D = m.ship.get_parent().global_transform
	m.guns[0].hitbox.take_weapon_damage(40); m.guns[1].hitbox.take_weapon_damage(40); m.step(0); m.step(0.1)
	check(jobs.phase == "return" and m.ship.get_parent().global_transform.is_equal_approx(early_pose) and not m.ship.dormant,"Early rescue releases outside shuttle in place without pulling it into defeated ship")
	m = await fresh("diptech2"); capture(m); m.step(18)
	var body: CollisionObject3D = m.ship.body
	var layer: int = m.capture_visual.layer; var mask: int = m.capture_visual.mask
	runtime._cleanup()
	check(body.collision_layer == layer and body.collision_mask == mask,"Cancelling mid-swallow restores transient collision state")
	var fragment_source := MeshInstance3D.new(); fragment_source.mesh = ArrayMesh.new()
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	fragment_source.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	game.world_root.add_child(fragment_source)
	var fragment_test := preload("res://submarine_death.gd").new(); game.world_root.add_child(fragment_test)
	fragment_test.setup_machine(fragment_source,fragment_source,game.submarine_traffic.bubble_texture)
	check(not fragment_test.pieces.is_empty(),"Unindexed mechanical debris surfaces fragment without null-index errors")
	fragment_test.free(); fragment_source.free()
	await physics_frame; game.free(); await process_frame
	print("Escort diplomats: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
