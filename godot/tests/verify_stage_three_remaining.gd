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
	storage.root_override = "res://tests/cache-stage-three-remaining-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER")); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func heard(code: String) -> bool:
	var text: String = game.gameplay_catalogue.tables.radio_messages.records[code].text
	return game.bounty_radio_queue.any(func(entry: Dictionary) -> bool: return entry.text == text)

func fresh(id: String) -> RefCounted:
	runtime._cleanup(); await physics_frame; await physics_frame
	preload("res://mission_survivors.gd").clear(game.submarine_traffic)
	game.radio_feed.clear(); game.bounty_radio_queue.clear(); runtime.outcome.dismiss()
	game.player_progress = Progress.restore({"campaign_stage":3}); game.player_progress.status.credits = 10000
	for previous in Rules.STAGE_THREE[Rules.offering_city(id)]:
		if previous == id: break
		game.player_progress.missions.completed[previous] = {"success":true,"city":Rules.offering_city(id)}
	game.pilot.restore_health(); game.pilot.active = true; game.pilot.controls_enabled = true
	game.equipment.set_installed(["deep_sea_lights","magnet","repulse"])
	game.pilot.global_position = Vector3(10000,120,10000)
	runtime.set_testing_missions(false)
	var city := Rules.offering_city(id)
	game.docking.current = game.submarine_traffic.port_by_id(city); game.docking.stage = game.Docking.Stage.DOCKED
	var result: String = runtime.accept(city,id)
	check(result.is_empty(),"Accept original city variant "+id+": "+result)
	game.docking.stage = game.Docking.Stage.IDLE; game.dock_interface.dismiss(); jobs.set_physics_process(false)
	for actor in jobs.actors:
		if actor is RigidBody3D: actor.freeze = true
		if actor is CharacterBody3D: actor.set_physics_process(false)
	for agent in jobs.vessels: agent.set_physics_process(false)
	await physics_frame; await physics_frame
	return jobs.stage_three_remaining.mission

func clear_terrain(body: RigidBody3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = body.get_child(1).shape
	query.transform = body.global_transform*body.get_child(1).transform; query.collision_mask = 1; query.exclude = [body.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func tow(body: RigidBody3D) -> void:
	game.equipment.magnet.set_enabled(true); game.equipment.magnet.set_physics_process(false)
	body.freeze = false; game.equipment.magnet._attach(body)
	check(game.equipment.magnet.target == body,"Actual magnet attaches to "+str(body.stats.name))

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
	for frame in range(2000):
		if game.submarine_traffic.navigation_ready: break
		game.submarine_traffic.build_graph(128); await process_frame
	var mission: RefCounted
	for id in ["miners","miners2"]:
		mission = await fresh(id)
		check(mission.ship != null and mission.rock != null,"Rescue uses MINING and BIGROCK original callbacks")
		check(mission.target_body() == mission.rock,"Original boulder guidance before excavation")
		check(mission.pirate_poses.size() == 10 and mission.enemies.is_empty(),"Pirate ambush waits for discovery")
		check(clear_terrain(mission.ship),"Disabled student hull fits actual cave")
		check(mission.ship.get_meta("metal_tow_target",false) and mission.ship.health == 500,"Protected until found, remains towable")
		game.pilot.global_position = mission.ship.global_position+Vector3.UP*3
		mission.step(2)
		for agent in mission.enemies: agent.set_physics_process(false)
		check(mission.found and heard("m1") and mission.ship.health == 5,"Approach starts original distress call and vulnerable hull")
		check(mission.enemies.size() == 10 and mission.enemies.all(func(a: Node3D) -> bool: return a.engage_player and a.pursue_offscreen),"All ten original pirates actively pursue")
		mission.rock.take_weapon_damage(100); check(mission.rock.dead and not mission.rock.visible,"Boulder destroys with debris instead of blocking rescue forever")
		tow(mission.ship); mission.step(0)
		check(heard("m3"),"Magnet contact original confirmation")
		check(mission.delivery(mission.ship,1) and not mission.delivered and not runtime.active().is_empty(),"Bohine delivery refused without generic cargo collection")
		game.equipment.magnet.release(false); mission.step(0)
		check(heard("m4"),"Original loose tow warning")
		mission.ship.take_weapon_damage(11); mission.step(2)
		check(heard("m7") and not mission.ship.dead,"Low hull warning")
		var rescued_ship: RigidBody3D = mission.ship
		check(mission.delivery(rescued_ship,4) and runtime.active().is_empty(),"Procha city accepts the rescued students")
		check(game.player_progress.status.credits == 14500 and game.player_progress.campaign_stage == 3,"Both student variants pay 4500 without premature stage advance")
		check(game.player_progress.missions.get("stage3_successes",0) == 1,"Stage three accounting")
		var other := "miners2" if id == "miners" else "miners"
		check(Rules.next_offer(Progress.restore(JSON.parse_string(JSON.stringify(game.player_progress))),Rules.offering_city(other)) != other,"Published save history excludes alternate rescue")
	mission = await fresh("miners"); mission.ship.take_weapon_damage(10000)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.miners.success and heard("m2"),"Lost students fail with original radio, no reward")
	mission = await fresh("bomb")
	check(mission.ship != null and mission.bombs.size() == 3,"Original FREIGHT and three PIXIE bombs")
	check(mission.bombs.all(func(i: Dictionary) -> bool: return i.body.freeze and i.body.release_on_tow),"Original PIXIE anchoring until first grab")
	game.equipment.magnet.set_enabled(true); game.equipment.magnet._attach(mission.ship)
	check(game.equipment.magnet.target == null and heard("an11"),"Freighter refuses towing with original heavy-hull radio")
	check(clear_terrain(mission.ship) and mission.bombs.all(func(i: Dictionary) -> bool: return clear_terrain(i.body)),"Freighter and all bombs fit real terrain")
	mission.step(10); check(not mission.started,"Bomb clocks wait until reaching freighter")
	game.pilot.global_position = mission.ship.global_position+Vector3.UP*3
	mission.step(0); mission.step(0.4)
	check(mission.started and mission.bombs[0].remaining == 149 and heard("an1") and heard("an7"),"Approach starts exact original bomb clock and radio")
	for index in range(3):
		var item: Dictionary = mission.bombs[index]
		tow(item.body); mission.step(0)
		check(mission.delivery(item.body,1) and not item.body.has_meta("delivery_city"),"Cities refuse armed bomb delivery")
		game.equipment.magnet.release(false); mission.step(0)
		if index < 2: check(item.remaining == 30,"Releasing a bomb shortens its fuse")
	check(mission.bombs.all(func(i: Dictionary) -> bool: return i.remaining == 5),"Handling third bomb synchronises surviving fuses")
	game.bounty_radio_queue.clear(); mission.step(1.2)
	check(not heard("an19") and heard("an17"),"Final bomb misses five-count warning as in FAQ")
	# Move every live bomb well away from the ship/player, as when dropped into the abyss.
	for index in range(3): mission.bombs[index].body.global_position = mission.ship.global_position+Vector3(40+index*12,-10,0)
	game.pilot.global_position = mission.ship.global_position+Vector3.UP*10
	mission.step(6)
	check(mission.rescued and not runtime.active().is_empty() and not mission.ship.dead,"Safe disposal waits original confirmation interval")
	mission.step(8)
	check(runtime.active().is_empty() and game.player_progress.status.credits == 14500 and heard("an14"),"Bomb rescue original reward and radio")
	mission = await fresh("bomb")
	var bomb: Dictionary = mission.bombs[0]; bomb.body.global_position = mission.ship.global_position
	game.pilot.global_position = mission.ship.global_position+Vector3.UP*20
	bomb.body.take_weapon_damage(1000)
	check(not runtime.active().is_empty() and mission.failed,"Freighter loss keeps original four-second outcome delay")
	mission.step(4)
	check(runtime.active().is_empty() and heard("an10") and game.player_progress.status.credits == 10000,"Explosion beside freighter fails without payout")
	mission = await fresh("bomb"); mission.started = true
	bomb = mission.bombs[0]; var next_bomb: Dictionary = mission.bombs[1]
	bomb.body.global_position = Vector3(500,50,500); next_bomb.body.global_position = Vector3(501,50,500)
	var victim := preload("res://mission_prop.gd").new(); var visual := Node3D.new()
	victim.setup(preload("res://object_definitions.gd").SALVAGE,visual,0,100,true)
	game.world_root.add_child(victim); victim.global_position = Vector3(502,50,500); victim.freeze = true
	await physics_frame; await physics_frame
	bomb.body.take_weapon_damage(1000)
	check(victim.dead and next_bomb.remaining == 1,"Original lethal sphere and nearby PIXIE chain reaction")
	victim.free()
	for id in ["aliens","aliens2"]:
		mission = await fresh(id)
		check(mission.queen != null and mission.fish.size() == 9 and mission.eggs.size() == 23,"Exact queen, five children, three adults and 23 original eggs")
		check(mission.tethers.size() == 3 and mission.guard != null,"Three chained ships plus Bohine entrance guard")
		var ceiling := PhysicsRayQueryParameters3D.create(mission.queen.global_position,mission.queen.global_position+Vector3.UP*20,1)
		ceiling.hit_back_faces = true
		check(not game.get_world_3d().direct_space_state.intersect_ray(ceiling).is_empty(),"Queen remains beneath the cave roof")
		check(mission.tethers.all(func(p: Dictionary) -> bool: return clear_terrain(p.ship)),"Chained ships fit actual cave")
		mission.step(0)
		var health: float = mission.queen.health
		mission.queen.take_weapon_damage(100)
		check(mission.queen.health == health and mission.queen.queen_held,"Queen protected while restrained by live ships")
		game.pilot.global_position = mission.guard.global_position+Vector3.UP*4
		mission.step(0.2)
		check(heard("q1") and mission.guard.engage_player,"Original guard warning and hostility")
		game.pilot.global_position = mission.queen.global_position+Vector3.UP*4; mission.step(0.2)
		check(heard("q2") and mission.queen.provoked,"Queen enrages when approached")
		for pair in mission.tethers: pair.ship.take_weapon_damage(1000)
		mission.step(0.2)
		check(not mission.queen.queen_held and mission.queen.damage_sustain == 0.05,"Queen becomes vulnerable after chains lose their ships")
		var passive: Node3D = mission.fish.filter(func(a: Node3D) -> bool: return not a.queen)[0]
		game.pilot.global_position = passive.global_position+Vector3.RIGHT*20
		passive.provoked = false; passive.repel_from(game.pilot.global_position,2); passive._physics_process(0.04)
		check(passive.fleeing,"Repellertron also moves passive nursery fish")
		mission.queen.set_physics_process(true); mission.queen.repel_from(game.pilot.global_position,2)
		mission.queen._physics_process(0.04)
		check(mission.queen.fleeing,"Existing Repellertron remains effective")
		var egg: Node3D = mission.eggs[0]; egg.take_weapon_damage(100)
		check(egg.dead and not egg.visible,"Eggs break with original model; hatching remains chance-driven")
		mission.queen.take_weapon_damage(10000)
		check(runtime.active().is_empty() and game.player_progress.status.credits == 17000 and heard("miss1"),"Both queen variants award original 7000 only on queen death")
		check(jobs.stage_three_remaining == null and jobs.actors.is_empty(),"Completion removes mission callbacks and chains")
	await physics_frame; await process_frame
	game.free(); await process_frame; await process_frame
	print("Remaining stage three: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
