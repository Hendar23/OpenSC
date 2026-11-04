extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
var game: Node
var jobs: Node
var runtime: Node
var checks := 0
var failures := 0
var movies: Array[String] = []

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-nuclear-fixtures"; storage.ensure_parent(storage.preferences_path())
	var cfg := ConfigFile.new(); cfg.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER")); cfg.save(storage.preferences_path())
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func fresh(id: String) -> RefCounted:
	runtime._cleanup(); runtime._clear_retained_props()
	preload("res://mission_survivors.gd").clear(game.submarine_traffic)
	await process_frame
	game.pilot.restore_health(); game.pilot.active = true; game.pilot.controls_enabled = true
	game.pilot.freeze = true
	game.player_progress = Progress.restore({"campaign_stage":4})
	game.player_progress.status.credits = 100
	game.player_progress.missions.completed = {"pwalker":{"success":true},"puffa":{"success":true}}
	var city := Rules.offering_city(id)
	check(Rules.next_offer(game.player_progress,city) == id,"Two original successes unlock the local core offer: "+id)
	game.docking.current = game.submarine_traffic.port_by_id(city); game.docking.stage = game.Docking.Stage.DOCKED
	check(runtime.accept(city,id).is_empty(),"Accept nuclear mission without adding recommended equipment as a gate: "+id)
	game.docking.stage = game.Docking.Stage.IDLE; game.dock_interface.dismiss(); paused = false
	jobs.set_physics_process(false)
	var m = jobs.controller
	for ship in m.allies+m.enemies: ship.set_physics_process(false)
	movies.clear()
	return m

func destroy_all(m: RefCounted) -> void:
	for body in m.canisters: body.take_weapon_damage(100)

func run() -> void:
	var saved := Progress.restore({"campaign_stage":4,"missions":{"version":1,"active":{},"completed":{"pwalker":{"success":true},"puffa":{"success":false},"backstab":{"success":false}}}})
	check(Rules.core_four_unlocked(saved),"Three resolved jobs unlock the core from published save history")
	saved.missions.completed.erase("backstab")
	check(not Rules.core_four_unlocked(saved),"One success and two resolved jobs do not unlock early")
	saved.missions.stage4_successes = 2
	check(Rules.core_four_unlocked(saved),"Published stage counters also unlock the core")
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	while not game.startup_complete: await process_frame
	game.front_end.gameplay_menu.fmvs_enabled = false
	await game._begin_new_game()
	game.set_process(false); game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	game.wildlife.set_simulating(false); game.world_root.get_node("ActorActivity").set_physics_process(false)
	for agent in game.submarine_traffic.traders: agent.set_physics_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	game.events.fmv_requested.connect(func(cue: String,_city: int) -> void: movies.append(cue))
	for id in Rules.CORE_FOUR.values():
		var m = await fresh(id)
		check(m.canisters.size() == 6 and m.enemies.size() == 3 and m.allies.size() == 3,"Original group41 has six canisters, three pirates and three Bohine allies")
		check(m.canisters.all(func(body: Node3D) -> bool: return body.health == 10 and body.sustain == 0.5 and body.mass == 10000 and body.freeze and not body.prepare_towing()),"Canisters use the callback's fixed health, sustain and immovable mass")
		check(m.allies[1].get_parent().get_meta("editor_model") == "TRAD2" and m.allies.all(func(ship: Node3D) -> bool: return ship.health.sustain == 0),"Original carrier variant and protection during charge preparation")
		for row in jobs._rows(41):
			if int(row.ObjectID) == 2: check(m.canisters[int(row.param2)].global_position.is_equal_approx(jobs._pose(row).origin),"Canister retains authored world position")
		game.pilot.global_position = m.waypoints[0]; m.step(8.1); m.step(0.3); m.step(12.1)
		check(m.announced and m.warned and m.setting_charges and not m.cave.radioactive and m.first_destroyed_at < 0,"Approaching triggers original briefing without starting the escape clock")
		m.canisters[0].take_weapon_damage(19)
		check(m.remaining == 6 and m.first_destroyed_at < 0,"Nonfatal damage cannot start the deadline")
		m.canisters[0].take_weapon_damage(1)
		check(m.remaining == 5 and m.first_destroyed_at == m.elapsed and not m.canisters[0].visible,"First actual destruction starts the countdown and hides the destroyed canister")
		check(m.allies[1].global_position.distance_to(m.guard_pose.origin) < 3 and m.allies[0].global_position.is_equal_approx(m.allies[0].home.origin),"Only the charge carrier moves to the original guard marker, with hull clearance for our physics")
		check(m.cave.get_children().any(func(node: Node) -> bool: return node.get("puffs") != null and node.puffs.size() == 9),"Canister destruction produces the original nine cloud puffs")
		m.step(1.9); check(not m.cave.radioactive,"Original two-second exposure delay")
		m.step(0.1)
		game.pilot.global_position = m.cave.global_position+Vector3.RIGHT*10
		game.pilot.radiation_rating = 0; game.pilot.restore_health()
		game.object_population._update_radiation(1)
		check(is_equal_approx(game.pilot.health,100-1.1375) and game.pilot.radiation_exposed,"Cave damage is original flat .013 per tick through the combined radiation HUD")
		game.pilot.global_position = m.cave.global_position+Vector3.RIGHT*20; game.pilot.restore_health(); game.pilot.radiation_rating = 100
		game.object_population._update_radiation(1)
		check(is_equal_approx(game.pilot.health,100-1.1375*0.2),"RADOFF protects the player; area damage does not vary inside the cave")
		game.pilot.global_position = m.cave.global_position+Vector3.UP*100; game.pilot.restore_health()
		game.object_population._update_radiation(1)
		check(game.pilot.health == 100 and not game.pilot.radiation_exposed,"Outside original 31-unit area there is no radiation")
		destroy_all(m); m.step(57.19)
		check(not m.sealed and not runtime.active().is_empty() and m.remaining == 0,"All six targets alone do not end the escape phase")
		m.step(0.02)
		check(m.sealed and m.escaped and is_instance_valid(m.plug) and m.plug.sustain == 0 and m.warning == 6 and m.urgency,"Original 59.2-second deadline seals the cave with all radio warnings")
		await physics_frame; await physics_frame
		var direction: Vector3 = m.seal_pose.basis.z.normalized()
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(m.seal_pose.origin+direction*4,m.seal_pose.origin-direction*4,8))
		check(not hit.is_empty() and hit.collider == m.plug,"Sealed rock physically blocks the passage")
		m.step(13.9); check(not runtime.active().is_empty(),"Original fourteen-second post-collapse radio delay")
		var cave: Node3D = m.cave; var ships: Array = m.allies.duplicate(); var enemy: Node3D = m.enemies[0]
		m.step(0.2); await process_frame
		check(runtime.active().is_empty() and game.player_progress.status.credits == 6100 and game.player_progress.campaign_stage == 5,"Exact 6000-credit reward and stage-five progression: "+id)
		check(game.player_progress.mail.outcomes.get(id,0) == 1,"Nuclear completion records its accepted mission outcome without publishing unused placeholder bulletins")
		check(movies.is_empty(),"Nuclear completion cannot replay a prior core mission's news FMV")
		check(runtime.retained_props.has(cave) and cave.radioactive and is_instance_valid(m.plug),"Sealed entrance and radiation survive resolution until docking")
		check(ships.all(func(ship: Node3D) -> bool: return is_instance_valid(ship) and ship.retiring and ship.dock_destination in [1,3]) and is_instance_valid(enemy),"Surviving team retires to a Bohine dock while surviving pirates stay present")
		enemy.body.take_weapon_damage(10000)
		check(enemy.dead and enemy.body.collision_layer == 0 and enemy.body.collision_mask == 0,"Released pirate can be destroyed after completion without an invisible collider")
		ships[0].body.take_weapon_damage(10000)
		check(ships[0].dead,"Surviving military ships lose scripted protection after completion")
		runtime.finish(true); check(game.player_progress.status.credits == 6100,"Repeated outcome cannot pay again")
		runtime.docked(city_for(id)); await process_frame
		check(not is_instance_valid(cave),"Next docking removes the retained cave actors")
	var m = await fresh("canister")
	game.pilot.global_position = m.cave.global_position
	destroy_all(m); var cave: Node3D = m.cave
	m.step(m.SEAL_DELAY); await process_frame
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.canister.success and game.player_progress.status.credits == 100,"Being sealed inside fails even after destroying all six canisters")
	check(is_instance_valid(cave) and cave.radioactive,"Trapped player's radiation continues after mission failure")
	game.pilot.radiation_rating = 0; game.pilot.restore_health(); game.object_population._update_radiation(100)
	check(game.pilot.dead,"The trapped player dies from the actual continuing radiation, without an invented instant-kill timer")
	m = await fresh("canister3"); m.canisters[0].take_weapon_damage(100)
	game.pilot.global_position = m.cave.global_position+Vector3.UP*100
	m.step(m.SEAL_DELAY+14.1); await process_frame
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.canister3.success and game.player_progress.status.credits == 100,"Escaping with undestroyed stockpile fails without reward")
	var body: Node3D = m.canisters[1]
	body.take_weapon_damage(100); check(body.dead and not body.visible,"Undestroyed retained canisters still react to weapons after failure")
	m = await fresh("canister4"); cave = m.cave
	var survivor: Node3D = m.allies[0]
	runtime.finish(false); await process_frame
	check(not is_instance_valid(cave) and is_instance_valid(survivor) and survivor.retiring,"Aborting before collapse cleans cargo and sends living guards home")
	m = await fresh("canister2"); cave = m.cave
	game.events.session_started.emit(false); await process_frame
	check(not is_instance_valid(cave) and jobs.actors.is_empty() and runtime.retained_props.is_empty(),"Session reset cleans active nuclear mission scenery")
	m = await fresh("canister2"); cave = m.cave
	game.pilot.global_position = cave.global_position+Vector3.UP*100
	destroy_all(m); m.step(m.SEAL_DELAY+14.1); await process_frame
	game.events.session_started.emit(false); await process_frame
	check(not is_instance_valid(cave) and runtime.retained_props.is_empty(),"Session reset also clears retained sealed scenery and radiation after completion")
	game.free(); await process_frame
	print("Nuclear stockpile: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func city_for(id: String) -> int:
	return Rules.offering_city(id)
