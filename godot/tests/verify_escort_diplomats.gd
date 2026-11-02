extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
var game: Node
var runtime: Node
var jobs: Node
var checks := 0
var failures := 0
var movies: Array[String] = []
var films: Array[String] = []
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
	m.ship.set_local_simulation(false)
	check(not m.ship.get_parent().visible,"Distant shuttle enters hidden traffic simulation before capture")
	m.ship.waypoint = 3; m.step(0)
	check(m.ship.presentation_locked and m.ship.get_parent().visible and m.ship.local_simulation,"Scripted capture reveals a previously hidden shuttle")
	var activity: Node = game.world_root.get_node("ActorActivity")
	var old_views: Array = activity.views.duplicate()
	activity.views.clear(); activity.views.append({"origin":Vector3(10000,10000,10000),"range":1.0,"planes":[]})
	activity.update_actors(0); activity.views.assign(old_views)
	check(m.ship.get_parent().visible and m.ship.body.collision_layer == 0,"Distance activity cannot hide captured shuttle or restore its collision")
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
	game.events.fmv_requested.connect(func(cue: String, city: int) -> void:
		movies.append(cue); films.append(preload("res://fmv_library.gd").movie(cue,city)))
	var moving: RefCounted = await fresh("diptrad")
	game.pilot.global_position = moving.ship.global_position+Vector3.UP*2
	moving.step(0)
	var starting_position: Vector3 = moving.ship.global_position
	for point in moving.ship.waypoints:
		check(game.submarine_traffic.segment_clear(point,point),"Outbound diplomat waypoint clears the navigation ceiling and scenery")
	for tick in range(12000):
		moving.ship.advance(1.0/60.0)
		moving.step(1.0/60.0)
		if tick%30 == 0: await physics_frame
		if moving.captured: break
	check(moving.ship.global_position.distance_to(starting_position) > 50 and moving.ship.waypoint >= 2,"Rendezvoused diplomat physically follows the first two route legs")
	check(moving.captured and not game.pilot.has_meta("diplomat_system_failure"),"Full physical route reaches capture and restores player controls")
	moving._route(4,6)
	for point in moving.ship.waypoints:
		check(game.submarine_traffic.segment_clear(point,point),"Return diplomat waypoint clears terrain and uses the dock entrance")
	var failed_system: RefCounted = await fresh("diptrad")
	failed_system._disable()
	game.game_input._physics_process(0)
	check(game.pilot.controls_enabled and not preload("res://submarine_controller.gd").tools_allowed(game.pilot),"System failure locks equipment without invoking UI damage protection")
	var hp: float = game.pilot.health
	game.pilot.take_damage(1)
	check(game.pilot.health < hp,"Disabled submarine still takes ordinary damage")
	hp = game.pilot.health
	game.pilot.receive_projectile_hit(0.1,game.pilot.global_position,Vector3.ZERO)
	check(game.pilot.health < hp,"Disabled submarine still takes torpedo damage")
	hp = game.pilot.health
	game.pilot.receive_explosion(game.pilot.global_position,1,0)
	check(game.pilot.health < hp,"Disabled submarine still takes explosion damage")
	failed_system._restore_controls(); game.game_input._physics_process(0)
	check(preload("res://submarine_controller.gd").tools_allowed(game.pilot),"Repair releases the mission-only equipment lock")
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
		for mesh in m.boss.find_children("*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():
				var material: Material = mesh.get_active_material(surface)
				if not material is ShaderMaterial or not material.has_meta("natural_original"): continue
				var original: StandardMaterial3D = material.get_meta("natural_original")
				if original.get_meta("exterior_canopy",false):
					check(material.shader == preload("res://exterior_glass.gdshader") and original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and original.albedo_color.a < 1,"Both BOSS windows retain transparency and canopy reflections after lighting")
		var upper: MeshInstance3D = m.guns[0].head.find_child("Mesh_0",true,false)
		var gun_material: StandardMaterial3D = upper.get_active_material(0).get_meta("natural_original")
		check(gun_material.albedo_color.is_equal_approx(Color(55.0/255,67.0/255,55.0/255)),"Upper turret uses its authored green material instead of cyan placeholder")
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
		check(animation.hatch.is_visible_in_tree() and m.ship.get_parent().is_visible_in_tree() and m.ship.get_parent().global_position.is_equal_approx(animation.inside.origin),"Hatch closes at captured dialogue with shuttle in recovered original pose")
		for gun in m.guns:
			var old_basis: Basis = gun.head.global_basis
			game.pilot.global_position = gun.head.global_position-gun.head.global_basis.z*gun.barrel_sign*6
			var old_shots: int = gun.shots
			gun.cooldown = 0; gun._physics_process(0.01)
			check(gun.shots == old_shots,"Gun cannot fire while barrel faces away from player")
			gun.head.global_basis = old_basis
			game.pilot.global_position = gun.head.global_position+Vector3(0,6 if gun == m.guns[0] else -6,0)
			gun._physics_process(5)
			check(gun.shots > 0,"Original battleship gun launches visible straight torpedoes")
			var missiles: Array = get_nodes_in_group("turret_missiles").filter(func(shot: Node) -> bool: return shot.source == gun)
			check(not missiles.is_empty() and missiles.back().direction.dot(gun.head.global_basis.z.normalized()*gun.barrel_sign) > 0.99,"Torpedo leaves along the rendered barrel direction")
			if not missiles.is_empty():
				var shot: Node3D = missiles.back()
				var hit: Dictionary = shot._impact(shot.global_position+shot.direction*0.3)
				check(hit.is_empty() or not m.boss.is_ancestor_of(hit.collider),"Gun muzzle and initial torpedo travel clear its own mothership")
			game.pilot.global_position = m.boss.global_position
			old_shots = gun.shots; gun.cooldown = 0; gun._physics_process(5)
			check(gun.shots == old_shots,"Gun does not fire at player through the mothership hull")
		var previous_effects: Array = game.world_root.find_children("MineExplosion*","Node3D",false,false)
		var gun_point: Vector3 = m.guns[0].head.global_position
		m.guns[0].hitbox.take_weapon_damage(40)
		var blasts: Array = game.world_root.find_children("MineExplosion*","Node3D",false,false).filter(func(effect: Node) -> bool: return effect not in previous_effects)
		check(blasts.size() == 1 and blasts[0].global_position.distance_to(gun_point) < 0.01 and not blasts[0].frames.is_empty() and blasts[0].audio != null,"Destroyed upper gun produces a visible, audible fireball at the turret rather than inside the hull")
		var impact_point: Vector3 = m.boss.global_position+Vector3(4,4,4)
		previous_effects = game.world_root.find_children("MineExplosion*","Node3D",false,false)
		m.guns[0].burst(impact_point,0.5)
		blasts = game.world_root.find_children("MineExplosion*","Node3D",false,false).filter(func(effect: Node) -> bool: return effect not in previous_effects)
		check(blasts.size() == 1 and blasts[0].global_position.is_equal_approx(impact_point),"Torpedo impact after gun destruction is shown at impact rather than its source")
		m.step(0)
		check(not m.freed and not runtime.active().is_empty(),"One defeated gun cannot free diplomats")
		m.guns[1].hitbox.take_weapon_damage(40); m.step(0)
		check(m.freed and m.ship.dock_destination == 4 and jobs.phase == "release" and not animation.hatch.visible,"Both guns open hatch and free shuttle")
		m.step(animation.release_duration*0.5)
		check(m.ship.dormant and m.ship.body.collision_layer == 0 and not animation.released,"Shuttle visibly exits before navigation/collision resumes")
		m.step(animation.release_duration*0.5+0.01)
		check(animation.released and not m.ship.presentation_locked and not m.ship.dormant and m.ship.body.collision_layer == animation.layer and m.ship.waypoints.size() == 3,"Clear shuttle resumes original onward route and collision")
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
		check(game.player_progress.status.credits == 18000 and movies.back() == "diplomats_rescued","Original reward paid once and diplomat news cue sent")
		check(films.back() == ("btvflat" if Rules.offering_city(id) in [1,3] else "pnnflat"),"Actual mission completion selects diplomat film rather than earlier walker film")
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
