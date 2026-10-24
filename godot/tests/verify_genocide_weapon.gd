extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
const Shop = preload("res://equipment_shop.gd")
const Mine = preload("res://floating_mine.gd")
const CreatureDeath = preload("res://creature_death.gd")
var game: Node
var runtime: Node
var jobs: Node
var checks := 0
var failures := 0

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-genocide-weapon-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	var config := ConfigFile.new(); config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func fresh(id: String) -> void:
	runtime._cleanup(); await physics_frame; await physics_frame
	preload("res://mission_survivors.gd").clear(game.submarine_traffic)
	for shot in get_nodes_in_group("turret_missiles"): shot.free()
	game.radio_feed.clear(); game.bounty_radio_queue.clear()
	game.player_progress = Progress.restore({"campaign_stage":2}); game.player_progress.status.credits = 100000
	game.equipment.set_installed(["deep_sea_lights","magnet","bigears"])
	game.pilot.restore_health(); game.pilot.active = true; game.pilot.controls_enabled = true; game.weapons.set_installed(["zapper"])
	game.pilot.active = true; game.pilot.controls_enabled = true; runtime.outcome.dismiss()
	runtime.set_testing_missions(true)
	var city := Rules.offering_city(id)
	game.docking.current = game.submarine_traffic.port_by_id(city); game.docking.stage = game.Docking.Stage.DOCKED
	check(runtime.accept(city,id).is_empty(),id+" accepts at its original station")
	game.docking.stage = game.Docking.Stage.IDLE; game.dock_interface.dismiss()
	game.pilot.show(); game.pilot.visual.show(); game.pilot.collision_layer = 2; game.pilot.collision_mask = 13
	for agent in jobs.vessels: agent.set_physics_process(false)
	jobs.set_physics_process(false)
	if jobs.genocide != null: jobs.genocide.armament.set_physics_process(false)
	await physics_frame; await physics_frame

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for Genocide Weapon")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game()
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false); game.set_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.wildlife.set_simulating(false); game.photo_mode.replay.set_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	var progress := Progress.restore({"campaign_stage":2})
	check(not Rules.core_unlocked(progress),"Fresh stage two does not unlock its core")
	progress.missions.stage2_successes = 4; progress.missions.stage2_resolved = 7
	check(not Rules.core_unlocked(progress),"Four successes/seven resolved are below retail thresholds")
	progress.missions.stage2_successes = 5
	check(Rules.next_offer(progress,1) == "walktrad2" and Rules.next_offer(progress,3) == "walktrad","Five successes unlock original Bohine city variants, respecting MISSION1 discrepancy")
	progress.missions.stage2_successes = 0; progress.missions.stage2_resolved = 8
	check(Rules.next_offer(progress,2) == "walktech" and Rules.next_offer(progress,4) == "walktech2","Eight resolved jobs unlock Procha city variants")
	progress.missions.erase("stage2_resolved")
	for id in ["stranded","spytrad","bigherd","fishing","breakout"]: progress.missions.completed[id] = {"success":true}
	check(Rules.core_unlocked(progress),"Published beta histories without counters unlock naturally")
	for id in Rules.CORE.values():
		await fresh(id)
		var mission: RefCounted = jobs.genocide
		check(mission != null and is_instance_valid(mission.walker),id+" initializes original walker")
		check(mission.walker.global_position.is_equal_approx(Vector3(286.839813,157.313339,164.02887)),"Walker uses exact database test-ground coordinates")
		var bonus: Array = game.object_population.snapshot().filter(func(entry: Dictionary) -> bool: return entry.get("object_group","") == "campaign/genocide_bonus")
		check(bonus.size() == 8 and game.player_progress.missions.world_events.genocide_bonus,"Original six ore/two coin stage bonuses spawn once as saved world resources")
		check(mission.enemies.size() == 3,"Original three TECH2SUB guards are present before approach")
		check(runtime.target_marker.target_body() == mission.walker,"Green HUD box initially marks walker")
		check(not mission.walker.get_meta("metal_tow_target") and mission.walker.freeze,"Disabled chassis cannot be towed as if it were the detachable head")
		check(runtime.testing_mission_city(id) == Rules.offering_city(id),"Dev offer retains proper station")
		for sibling in Rules.CORE.values():
			if sibling != id: check(sibling in game.player_progress.missions.unavailable,"Accepting core excludes sibling "+sibling)
		check(mission.head_meshes.size() == 2,"Both original head atomics are identified")
		mission.walker.take_typed_weapon_damage(2.5,mission.walker.global_position,game.pilot,"zapper")
		check(is_equal_approx(mission.walker.health,19.75) and mission.zapper_hits == 0 and mission.guards_alert,"Leg zapper damage reduces chassis shields and alerts guards without a false head warning")
		mission.walker.take_typed_weapon_damage(65,mission.walker.global_position-Vector3.UP,game.pilot,"missile")
		check(mission.torpedo_hits == 0,"Torpedo from below does not falsely release the head")
		mission.walker.take_typed_weapon_damage(200,mission.walker.global_position+Vector3.UP*2,game.pilot,"missile")
		await process_frame; await physics_frame
		check(mission.phase == "head" and is_instance_valid(mission.head),"Destroyed legs release original WALKHEAD even when the firing source is above them")
		check(runtime.target_marker.target_body() == mission.head and mission.head.get_meta("metal_tow_target"),"HUD transfers to the live magnet-compatible head")
		check(mission.head.health == 1.0 and mission.head.damage_sustain == 0.1,"Original fragile head shield/sustain values retained")
		check(mission.warning == 6,"Released head switches to second cooling-failure warning sequence")
		mission.head.freeze = true
		check(jobs.delivery(mission.head,2) and mission.phase == "head" and not mission.head.delivered,"Procha city cannot accept the head or prematurely win")
		var before: int = game.player_progress.status.credits
		check(jobs.delivery(mission.head,1),"Bohine drop point accepts the recovered head")
		check(not runtime.active().is_empty() and mission.head.delivered,"Handoff protects delivered head while completion delay runs")
		mission.step(6.1)
		check(runtime.active().is_empty() and game.player_progress.campaign_stage == 3,"Bohine handoff advances campaign to stage three")
		check(game.player_progress.status.credits == before+7000,"Exact original credit reward paid once")
		var sponsor := "1" if Rules.offering_city(id) in [1,3] else "2"
		check(float(game.player_progress.missions.reputation[sponsor]) > 0,"Core reputation follows the original sponsoring faction")
		var mail := preload("res://mailbox.gd").messages(game.gameplay_catalogue,game.player_progress,Rules.offering_city(id))
		check(mail.any(func(message: Dictionary) -> bool: return message.id == ("561" if sponsor == "1" else "562")),"Original post-walker bulletin arrives for both station aliases")
		mission.step(10)
		check(game.player_progress.status.credits == before+7000,"Delayed events cannot pay twice")
		check(game.player_progress.missions.stage2_successes == 0 and game.player_progress.missions.stage2_resolved == 0 and game.player_progress.campaign_jobs == 0,"Core resets side-job counters for the next stage")
		check(game.submarine_traffic.traders.any(func(agent: Node3D) -> bool: return agent.has_meta("fishing_survivor") and agent.get_parent().get_meta("editor_model","") == "TECH2SUB"),"Living guards persist through mission completion")
	await fresh("walktech")
	var mission: RefCounted = jobs.genocide
	mission.walker.take_typed_weapon_damage(2.5*79,mission.walker.global_position,game.pilot,"zapper")
	check(mission.phase == "walker","Seventy-nine original leg zapper ticks do not release head")
	mission.walker.take_typed_weapon_damage(2.5,mission.walker.global_position,game.pilot,"zapper")
	await process_frame; await physics_frame
	check(mission.phase == "head","Eightieth leg zapper tick releases head")
	mission.head.freeze = true
	mission.head.take_weapon_damage_from(1.0,mission.head.global_position,game.pilot)
	mission.step(0)
	check(not game.pilot.dead,"Small hit damages fragile head without triggering false catastrophe")
	mission.head.take_weapon_damage_from(100.0,mission.head.global_position,game.pilot)
	check(game.pilot.dead and runtime.active().is_empty(),"Destroyed head triggers original global catastrophe and mission failure")
	await fresh("walktrad")
	mission = jobs.genocide
	mission.step(117.9)
	check(not game.pilot.dead,"Original warning timer has not expired just before 118 seconds")
	mission.step(0.2)
	check(game.pilot.dead and runtime.active().is_empty(),"Undetached walker catastrophically fails at original deadline")
	await fresh("walktrad2")
	mission = jobs.genocide
	# Exercise the actual swept projectile/damage route, including its singular
	# "missile" ID, rather than testing only the mission's direct callback.
	game.pilot.global_position = Vector3(10000,150,10000)
	var leg_origin := Vector3.ZERO
	var leg_direction := Vector3.ZERO
	for y in [-0.8,-0.4,0.0,0.4]:
		for x in [-1.0,-0.5,0.0,0.5,1.0]:
			var origin: Vector3 = mission.walker.to_global(Vector3(x,y,3))
			var direction: Vector3 = -mission.walker.global_basis.z
			var ray := PhysicsRayQueryParameters3D.create(origin,origin+direction*6,15,[game.pilot.get_rid()])
			var contact: Dictionary = game.world_root.get_world_3d().direct_space_state.intersect_ray(ray)
			if contact.get("collider") != mission.walker: continue
			var shape_node: Object = mission.walker.shape_owner_get_owner(mission.walker.shape_find_owner(contact.shape))
			if shape_node.get_meta("walker_head",false): continue
			leg_origin = origin; leg_direction = direction
	check(not leg_direction.is_zero_approx(),"A real visible leg has a clear torpedo approach")
	if leg_direction.is_zero_approx(): print("Walker pose ",mission.walker.global_transform); quit(1); return
	for index in range(10):
		if mission.phase != "walker": break
		var shot := preload("res://player_projectile.gd").new(); game.world_root.add_child(shot)
		shot.setup(game.weapons.arsenal,"missile",leg_origin,leg_direction)
		shot.set_physics_process(false); shot.velocity = leg_direction*8
		for tick in range(30):
			if shot.spent: break
			shot.advance(0.04)
		check(shot.spent,"Real swept torpedo strikes a visible walker leg")
		await process_frame; await physics_frame
	check(mission.phase == "head","Real swept leg hits release the head through located damage dispatch")
	if mission.phase != "head": print("Remaining chassis health ",mission.walker.health); quit(1); return
	check(mission.torpedo_hits == 0 and mission.zapper_hits == 0,"Real leg impacts never emit head-hit progress or warnings")
	mission.head.freeze = true
	var magnet: Node3D = game.equipment.magnet
	game.pilot.global_position = mission.head.global_position+Vector3.UP*3
	game.pilot.linear_velocity = Vector3.ZERO
	magnet.set_enabled(true)
	for tick in range(100): await physics_frame
	check(is_instance_valid(magnet.head),"Real magnet deploys before heavy-head attachment")
	mission.head.global_position = magnet.head.global_position+Vector3.DOWN*1.0
	mission.head.freeze = false; mission.head.linear_velocity = Vector3.ZERO
	magnet._attach(mission.head)
	check(magnet.target == mission.head and mission.head.mass == 37.5,"Real magnet applies the corrected carried mass immediately when it clamps")
	check(is_equal_approx(game.pilot.movement.cargo_mass,37.5*magnet.cargo_weight),"Actual clamp applies the carried mass, never the temporary 3750kg free-body load")
	for tick in range(100): await physics_frame
	check(not mission.head.dead and mission.head.global_position.is_finite(),"Heavy head remains stable and intact on the physical magnet")
	magnet.release(false)
	check(mission.head.mass == 3750.0 and game.pilot.movement.cargo_mass == 0,"Real release restores heavy free-body mass and clears the engine load")
	magnet.reset()
	mission.head.freeze = true
	game.equipment.magnet.target = mission.head
	game.pilot.global_position = jobs._city(2)+Vector3(10,0,0)
	mission.step(0.01)
	check(mission.chase and is_instance_valid(mission.pursuer) and mission.pursuer.get_parent().get_meta("editor_model") == "TECHNEW","Towing near Velcova dispatches the correct original attack sub")
	check(mission.pursuer.stage == "berth" and not mission.pursuer.get_parent().visible,"Reinforcement begins inside dock and uses normal departure")
	check(mission.head.mass == 37.5,"Clamped head retains a substantial heavy mission-cargo towing mass")
	game.equipment.magnet._update_cargo_mass()
	check(is_equal_approx(game.pilot.movement.cargo_mass,37.5*game.equipment.magnet.cargo_weight) and game.pilot.mass > float(game.pilot.movement.settings.mass)*2.0,"Walker head actually adds heavy towing load to the submarine engine, rather than changing only its free-body weight")
	mission.step(2.4)
	check(mission.chase_announced and mission.helpers.is_empty(),"Interception warning precedes Bohine backup")
	mission.step(8.0)
	check(mission.helpers.size() == 1 and mission.helpers[0].combat_target == mission.pursuer.body,"Touka dispatches actual backup against the pursuing sub")
	game.equipment.magnet.target = null
	mission.step(0.01)
	check(mission.head.mass == 3750.0,"Released head regains original heavy mass")
	check(jobs.delivery(mission.head,6) and mission.phase == "head","Refinery does not consume mission cargo as ordinary metal")
	jobs.delivery(mission.head,3); mission.step(6.1)
	check(game.player_progress.campaign_stage == 3,"Beluga is a valid alternative Bohine delivery")
	check(game.object_population.snapshot().filter(func(entry: Dictionary) -> bool: return entry.get("object_group","") == "campaign/genocide_bonus").size() == 8,"Stage bonus resources persist after mission cleanup")
	await fresh("walktrad")
	mission = jobs.genocide
	game.pilot.global_position = Vector3(10000,150,10000)
	for index in range(3):
		var shot := preload("res://player_projectile.gd").new(); game.world_root.add_child(shot)
		shot.setup(game.weapons.arsenal,"missile",mission.walker.to_global(Vector3(0,4,0)),-mission.walker.global_basis.y)
		shot.set_physics_process(false); shot.velocity = -mission.walker.global_basis.y*8
		for tick in range(30):
			if shot.spent: break
			shot.advance(0.04)
		check(shot.spent,"Actual overhead torpedo contacts the visible head")
		await process_frame; await physics_frame
		if index == 1:
			check(mission.phase == "walker" and mission.head == null and mission.torpedo_hits == 2,"Head hits warn and damage the head; they do not release it")
			check(game.bounty_radio_queue.any(func(message: Dictionary) -> bool: return message.text.contains("Missile impact on walker head")),"Confirmed head collision emits original E18 warning")
	check(game.pilot.dead and runtime.active().is_empty() and mission.head == null,"Third confirmed head torpedo causes catastrophe instead of awarding a salvageable head")

	await fresh("walktrad2")
	mission = jobs.genocide
	var head_ray := PhysicsRayQueryParameters3D.create(mission.walker.to_global(Vector3(0,4,0)),mission.walker.to_global(Vector3(0,-2,0)),15,[game.pilot.get_rid()])
	var head_contact: Dictionary = game.world_root.get_world_3d().direct_space_state.intersect_ray(head_ray)
	check(head_contact.get("collider") == mission.walker,"Zapper contact fixture hits the visible head mesh")
	preload("res://original_damage.gd").weapon(mission.walker,2.5*26,mission.walker.global_position-Vector3.UP,game.pilot,"zapper",head_contact)
	check(mission.phase == "walker" and mission.zapper_hits == 26 and mission.head == null,"Twenty-six confirmed head Zapper contacts are dangerous head damage, not release progress")
	preload("res://original_damage.gd").weapon(mission.walker,2.5,mission.walker.global_position-Vector3.UP,game.pilot,"zapper",head_contact)
	await process_frame; await physics_frame
	check(game.pilot.dead and runtime.active().is_empty(),"Twenty-seventh head Zapper contact causes original catastrophe")

	await fresh("walktech")
	mission = jobs.genocide
	game.pilot.global_position = mission.walker.to_global(Vector3(0,1,8))
	game.pilot.restore_health(100000,100000); game.pilot.linear_velocity = Vector3.ZERO
	await physics_frame; await physics_frame
	var used_ports := {}
	for tick in range(180):
		var before: int = mission.armament.shots
		mission.armament._physics_process(0.04)
		if mission.armament.shots > before: used_ports[mission.armament.port] = true
		await physics_frame
	check(mission.armament.shots >= 3 and used_ports.size() == 2,"Walker rotates and fires actual missiles alternately from both original weapon ports")
	check(game.pilot.health < game.pilot.max_health,"Walker missiles really register damage on the player")
	mission._alert_guards()
	for guard in mission.enemies:
		guard.random.seed = 456+mission.enemies.find(guard); guard.set_local_simulation(true); guard.set_physics_process(false)
	var firing_guards := {}
	for tick in range(180):
		for guard in mission.enemies: guard.advance(1.0/30.0)
		await physics_frame
		for shot in get_nodes_in_group("turret_missiles"):
			if mission.enemies.has(shot.source): firing_guards[shot.source] = true
	if firing_guards.size() != 3:
		for guard in mission.enemies: print("Delayed guard: fired=",firing_guards.has(guard)," position=",guard.global_position," victim=",guard.victim," stage=",guard.stage," cooldown=",guard.cooldown," path=",guard.path.size())
	check(firing_guards.size() == 3,"All three alerted guards acquire and fire on the nearby player within six seconds")
	for guard in mission.enemies:
		check(guard.tuning.npc_speed == 3.5 and guard.pursue_offscreen,"Escort keeps a purposeful combat speed and pursuit order")
	var released_poses := {}
	for mesh in mission.head_meshes: released_poses[str(mesh.name)] = mesh.global_transform
	mission.walker.take_typed_weapon_damage(200,mission.walker.global_position,game.pilot,"zapper")
	await process_frame; await physics_frame
	check(mission.phase == "head","Leg destruction releases the head after the walker has rotated and fired")
	for mesh: MeshInstance3D in mission.head.appearance.find_children("*","MeshInstance3D",true,false):
		var old: Transform3D = released_poses[str(mesh.name)]
		check(mesh.global_basis.is_equal_approx(old.basis) and mesh.global_position.distance_to(old.origin) < 0.04,"Detached "+str(mesh.name)+" preserves actual yaw/pitch and position")
	runtime._cleanup()
	var sandbox := SubViewport.new(); sandbox.own_world_3d = true; root.add_child(sandbox)
	var sea_floor := StaticBody3D.new(); sandbox.add_child(sea_floor); sea_floor.collision_layer = 1
	var floor_shape := CollisionShape3D.new(); floor_shape.shape = BoxShape3D.new(); floor_shape.shape.size = Vector3(20,1,20); sea_floor.add_child(floor_shape)
	var impact_head := preload("res://mission_walker_body.gd").new(); sandbox.add_child(impact_head)
	impact_head.detached = true; impact_head.max_contacts_reported = 8; impact_head.health = 1; impact_head.damage_sustain = 0.1; impact_head.mass = 37.5; impact_head.raw_impact_mass = 0.75; impact_head.surface_height = 100
	var hull := CollisionShape3D.new(); hull.shape = BoxShape3D.new(); hull.shape.size = Vector3.ONE; impact_head.add_child(hull)
	impact_head.position = Vector3(0,3,0); impact_head.linear_velocity = Vector3.DOWN*20
	for frame in range(30): await physics_frame
	check(impact_head.health < 1.0 and not impact_head.dead,"Actual rough terrain impact damages the fragile head using recovered collision arithmetic")
	var resting_health: float = impact_head.health
	for frame in range(30): await physics_frame
	check(is_equal_approx(impact_head.health,resting_health),"Resting on the floor does not repeatedly damage the head")
	sandbox.queue_free(); await process_frame
	print("Genocide Weapon checks: ",checks,"; failures: ",failures)
	game.queue_free(); await process_frame; quit(1 if failures else 0)
