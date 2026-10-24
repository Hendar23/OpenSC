extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
const Minelayer = preload("res://disabled_minelayer.gd")
var game: Node
var runtime: Node
var jobs: Node
var checks := 0
var failures := 0

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-stage-three-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER")); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func fresh(id: String) -> RefCounted:
	runtime._cleanup(); await physics_frame; await physics_frame
	preload("res://mission_survivors.gd").clear(game.submarine_traffic)
	game.radio_feed.clear(); game.bounty_radio_queue.clear()
	game.player_progress = Progress.restore({"campaign_stage":3}); game.player_progress.status.credits = 100000
	game.equipment.set_installed(["deep_sea_lights","rover","escape"])
	game.pilot.restore_health(); game.pilot.active = true; game.pilot.controls_enabled = true
	runtime.set_testing_missions(false); runtime.outcome.dismiss()
	game.docking.stage = game.Docking.Stage.DOCKED
	var city: int = Rules.offering_city(id); game.docking.current = game.submarine_traffic.port_by_id(city)
	check(runtime.accept(city,id).is_empty(),"Accept original city offer: "+id)
	game.docking.stage = game.Docking.Stage.IDLE; game.dock_interface.dismiss()
	game.pilot.show(); game.pilot.visual.show(); game.pilot.collision_layer = 2; game.pilot.collision_mask = 13
	jobs.set_physics_process(false)
	for agent in jobs.vessels: agent.set_physics_process(false)
	await physics_frame; await physics_frame
	return jobs.stage_three

func radio_sent(code: String) -> bool:
	var line: String = game.gameplay_catalogue.tables.radio_messages.records[code].text
	return game.bounty_radio_queue.any(func(entry: Dictionary) -> bool: return entry.text == line)

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
	var progress := Progress.restore({"campaign_stage":3})
	check(Rules.next_offer(progress,2) == "disperse" and Rules.next_offer(progress,3) == "rovrtn","Original first stage-three city queues")
	check(Rules.next_offer(progress,4).is_empty(),"No invented Tryton offer")
	check(runtime.testing_mission_city("disperse") == 2 and runtime.testing_mission_city("rovrtn") == 3,"Dev unlock uses source cities")
	var mission: RefCounted = await fresh("disperse")
	check(mission.fish.size() == 10,"Ten original BADJELLY attackers")
	check(mission.fish.all(func(actor: Node3D) -> bool: return actor.health == 10 and actor.damage_sustain == 0.3 and actor.get_child(1).get_meta("asset_source","").contains("BADJELLY")),"Correct models, shield and sustain")
	check(mission.fish.filter(func(actor: Node3D) -> bool: return actor.city_attacker).size() == 4,"Four source attackers assigned directly to city")
	check(mission.fish.all(func(actor: Node3D) -> bool: return not game.cockpit_hud.map_data.actor_markers.has(actor)),"No invented blue wildlife dots")
	var actor: Node3D = mission.fish[0]; actor.set_physics_process(false)
	var point: Vector3 = actor.global_position
	actor.direction = actor.global_position.direction_to(actor.city_target)
	for i in range(20): actor._physics_process(1.0/60.0)
	check(actor.global_position.distance_to(point) > 0.1,"Mission fish actually swim before player arrives")
	var neighbour: Node3D = mission.fish[1]
	var neighbour_pose: Transform3D = neighbour.global_transform
	var city_target: Vector3 = actor.city_target
	actor.global_position = Vector3(10000,game.pilot.surface_height-10,10000)
	var separation_start: Vector3 = actor.global_position
	neighbour.global_position = actor.global_position+Vector3.RIGHT*0.2
	actor.city_target = actor.global_position+Vector3.BACK*10; actor.direction = Vector3.BACK
	actor.shoal.frame = -1; actor.probe_clock = 0; actor.avoidance = Vector3.ZERO
	for tick in range(20): actor._physics_process(1.0/60.0)
	if actor.global_position.x >= separation_start.x-0.02: print("Separation displacement ",actor.global_position-separation_start," radius ",actor.radius," neighbours ",actor.shoal.positions.size()," heading ",actor.direction)
	check(actor.global_position.x < separation_start.x-0.02,"Attack horde separates close neighbours instead of stacking on the city marker")
	actor.global_position = point; actor.city_target = city_target; neighbour.global_transform = neighbour_pose
	actor.repel_from(actor.global_position+Vector3.RIGHT,1.0)
	actor._physics_process(0.1)
	check(actor.fleeing and actor.repulsion_remaining > 0,"Repeller remains effective")
	mission.step(20.01); check(radio_sent("l1"),"Original hurry message at twenty seconds")
	mission.step(12); check(radio_sent("l4"),"Original docking servo damage message")
	mission.step(168); check(radio_sent("l2") and not runtime.active().is_empty(),"Late warning does not invent timed mission failure")
	var credits: int = game.player_progress.status.credits
	for index in range(8): mission.fish[index].take_weapon_damage(1000)
	check(mission.kills == 8 and radio_sent("l5"),"Original kill-count dialogue")
	check(mission.fish[8].pursue_player and mission.fish[9].pursue_player,"Final two survivors pursue player")
	mission.fish[8].take_weapon_damage(1000)
	check(not runtime.active().is_empty(),"Nine kills cannot complete")
	mission.fish[9].take_weapon_damage(1000)
	check(runtime.active().is_empty() and game.player_progress.status.credits == credits+6000,"Tenth kill completes and pays original 6000 credits")
	check(game.player_progress.missions.stage3_successes == 1 and not game.player_progress.missions.has("stage2_successes"),"Independent stage-three counters")
	check(preload("res://mailbox.gd").messages(game.gameplay_catalogue,game.player_progress,2).any(func(row: Dictionary) -> bool: return row.id == "421"),"Original success bulletin")
	mission = await fresh("rovrtn")
	check(mission.ship.get_child(0).get_meta("asset_source","").contains("MINING"),"Original MINING hull")
	check(mission.mines.size() == 25 and mission.mines.filter(func(mine: Node3D) -> bool: return mine.stats.model == "HARDMINE").size() == 10,"All fifteen ordinary and ten authored hard mines")
	check(mission.enemies.is_empty() and mission.pirate_poses.size() == 2,"Pirates spawn after crew rescue, not on the way in")
	check(runtime.target_marker.target_body() == mission.ship and jobs.can_attach_pod(mission.ship),"Guidance and pod recognize physical minelayer")
	check(not mission.ship.movable and mission.ship.mass == 2000,"Initially disabled heavy sub")
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = mission.ship.get_child(1).shape
	shape_query.transform = mission.ship.global_transform*mission.ship.get_child(1).transform
	shape_query.collision_mask = 1; shape_query.exclude = [mission.ship.get_rid()]
	check(game.get_world_3d().direct_space_state.intersect_shape(shape_query,1).is_empty(),"Authored minelayer hull starts clear of cave terrain")
	var rover: Node3D = game.equipment.support_tools.rover
	rover.set_deployed(true); rover.set_physics_process(false)
	rover.global_position = mission.ship.global_position+Vector3.UP
	mission.step(2.01)
	check(mission.rov_seen and mission.ship.movable and is_equal_approx(mission.ship.mass,0.2) and radio_sent("av4"),"ROV proximity activates original pushable mass and radio")
	mission.ship.receive_rov_push(Vector3.RIGHT)
	await physics_frame; await physics_frame
	check(mission.ship.linear_velocity.length() > 0,"ROV pushes apply physical momentum")
	# Exercise the real CharacterBody contact path, not only its impulse API.
	for mine in mission.mines: mine.collision_layer = 0
	var center: Vector3 = mission.ship.to_global(mission.ship.get_meta("mission_target_center"))
	var contact := {}
	for side in [Vector3.UP,Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		var ray := PhysicsRayQueryParameters3D.create(center+side*5,center,8,[game.pilot.get_rid(),rover.get_rid()])
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.get("collider") == mission.ship: contact = hit; break
	check(not contact.is_empty(),"ROV can reach the actual minelayer hull")
	if not contact.is_empty():
		rover.global_position = contact.position+contact.normal*0.16
		mission.ship.linear_velocity = Vector3.ZERO
		var start: Vector3 = mission.ship.global_position
		for tick in range(30):
			rover.velocity = -Vector3(contact.normal)*2; rover._move_remote(); await physics_frame
		check(mission.ship.global_position.distance_to(start) > 0.03,"Actual ROV collision physically nudges minelayer")
	for mine in mission.mines: mine.collision_layer = 8
	var tools: Node3D = game.equipment.support_tools
	tools.pod_target = mission.ship; mission.step(0.01); mission.step(4)
	check(not mission.rescued,"Crew transfer does not finish immediately")
	tools.pod_target = null; mission.step(0.01)
	check(mission.transfer < 0 and radio_sent("av3"),"Detachment interrupts transfer with source dialogue")
	tools.pod_target = mission.ship; mission.step(0.01); mission.step(10.01)
	check(mission.rescued and tools.passengers and not runtime.active().is_empty(),"Crew stays loaded until docking")
	check(mission.enemies.size() == 2 and mission.enemies.all(func(agent: Node3D) -> bool: return agent.engage_player and agent.health.capacity == 60),"Two aggressive pirates with shared doubled attack-sub health")
	credits = game.player_progress.status.credits
	var hull: RigidBody3D = mission.ship
	jobs.docked(3)
	check(runtime.active().is_empty() and game.player_progress.status.credits == credits+8700,"Docking pays original 8700 once")
	check(is_instance_valid(hull) and not hull.has_meta("mission_owner"),"Empty minelayer does not vanish at completion")
	check(game.submarine_traffic.traders.filter(func(agent: Node3D) -> bool: return agent.has_meta("fishing_survivor") and agent.get_parent().get_meta("editor_model","") == "PIRATE").size() == 2,"Living pirates persist")
	var traffic: Dictionary = game.submarine_traffic.snapshot()
	check(game.submarine_traffic.valid_snapshot(traffic),"Surviving pirates validate in beta save format")
	game.submarine_traffic.restore(traffic)
	check(game.submarine_traffic.traders.filter(func(agent: Node3D) -> bool: return agent.has_meta("fishing_survivor") and agent.engage_player and agent.health.capacity == 60 and agent.get_parent().get_meta("editor_model","") == "PIRATE").size() == 2,"Pirate hostility and doubled health survive loading")
	var objects: Array = game.object_population.snapshot()
	check(game.object_population.valid_snapshot(objects) and objects.any(func(entry: Dictionary) -> bool: return entry.stats.id == "rescued_minelayer"),"Empty minelayer saved in existing object snapshot format")
	game.object_population.restore_snapshot(objects)
	check(game.object_population.get_children().any(func(body: Node) -> bool: return body is Minelayer),"Loading preserves disabled minelayer")
	jobs.docked(3); check(game.player_progress.status.credits == credits+8700,"No duplicate rescue payout")
	mission = await fresh("rovrtn")
	mission.mines[0].detonate()
	await process_frame; await physics_frame; await process_frame
	check(mission.mines.all(func(mine: Node3D) -> bool: return mine.dead),"Dense payload chains through all mines")
	check(mission.ship.dead and mission.failed,"Unsafe detonation destroys disabled sub")
	mission.step(2.41)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.rovrtn.success and game.player_progress.status.credits == 100000,"Source failure and no payment")
	check(preload("res://mailbox.gd").messages(game.gameplay_catalogue,game.player_progress,3).any(func(row: Dictionary) -> bool: return row.id == "482"),"Original failure bulletin")
	mission = await fresh("rovrtn")
	# Moving beyond six units is an advisory boundary, not a new rescue gate.
	mission.ship.global_position = mission.ship.global_position+Vector3.UP*10
	mission.ship.reset_physics_interpolation(); await physics_frame
	mission.step(2.01)
	check(mission.safe and radio_sent("av6"),"Original six-unit safe-clearance advisory")
	mission.mines[0].detonate(); await process_frame; await physics_frame
	check(not mission.ship.dead and mission.breach_clock >= 0,"Safe mine clearance starts delayed leak instead of instant loss")
	mission.step(1.21); check(radio_sent("av8"),"Original blast hull-breach warning")
	tools.pod_target = mission.ship; mission.step(0.01); mission.step(10.01)
	check(mission.rescued and tools.passengers,"Crew can be recovered after safe detonation")
	mission.step(18.41); mission.step(18.41); mission.step(9.21)
	check(mission.ship.dead and not mission.failed and not runtime.active().is_empty(),"Empty sub destruction does not kill rescued crew or complete before docking")
	await physics_frame; await physics_frame
	check(mission.ship.collision_layer == 0 and mission.ship.collision_mask == 0 and mission.ship.freeze,"Destroyed minelayer leaves no invisible physical obstruction")
	jobs.docked(3)
	check(game.player_progress.missions.completed.rovrtn.success,"Docking after empty-sub loss still succeeds")
	mission = await fresh("rovrtn")
	mission.ship.global_position += Vector3.UP*10; await physics_frame
	mission.mines[0].detonate(); await process_frame; await physics_frame
	mission.step(1.21); mission.step(18.41); mission.step(18.41)
	check(mission.failed and mission.fail_clock > 0 and radio_sent("av10"),"Ignoring breached crew exhausts source rescue grace period")
	var lost_hull: RigidBody3D = mission.ship
	mission.step(9.21)
	check(lost_hull.dead and runtime.active().is_empty() and not game.player_progress.missions.completed.rovrtn.success,"Unrescued hull visibly explodes before failure cleanup")
	print("Stage-three jobs checks: ",checks," failures: ",failures)
	runtime._cleanup(); mission = null; game.queue_free()
	await process_frame; await process_frame; await physics_frame; await process_frame
	quit(1 if failures else 0)
