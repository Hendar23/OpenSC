extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
const Shop = preload("res://equipment_shop.gd")
const Mine = preload("res://floating_mine.gd")
var game: Node
var runtime: Node
var jobs: Node
var checks := 0
var failures := 0

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-remaining-stage-two-fixtures"; storage.ensure_parent(storage.preferences_path())
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
	game.radio_feed.clear(); game.bounty_radio_queue.clear()
	game.player_progress = Progress.restore({"campaign_stage":2}); game.player_progress.status.credits = 100000
	game.equipment.set_installed(["deep_sea_lights","magnet","bigears"]); game.weapons.set_installed(["zapper"])
	game.pilot.active = true; game.pilot.controls_enabled = true; runtime.outcome.dismiss()
	runtime.set_testing_missions(true)
	var city := Rules.offering_city(id)
	game.docking.current = game.submarine_traffic.port_by_id(city); game.docking.stage = game.Docking.Stage.DOCKED
	check(runtime.accept(city,id).is_empty(),id+" accepts at its original station")
	game.docking.stage = game.Docking.Stage.IDLE; game.dock_interface.dismiss()
	for agent in jobs.vessels: agent.set_physics_process(false)
	jobs.set_physics_process(false)
	await physics_frame; await physics_frame

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for remaining side jobs")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false); game.set_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	for id in ["spytech","spytech2","escort","escort2","tagtech","eel","recontech","recontech2"]:
		await fresh(id)
		check(jobs.remaining != null and jobs.remaining.family != "","Mission has its own initialized flow")
		check(runtime.target_marker.target_body() != null,"HUD has an initial target for "+id)
		check(Vector3(runtime.target_marker.target_body().get_meta("mission_target_center",Vector3.ZERO)).length() < 15,"HUD centre is a local hull point rather than the world bounds")
		await capture(id)
		check(not runtime.can_save(),"Mission preserves the pre-mission save")
		check(runtime.testing_mission_city(id) == Rules.offering_city(id),"Dev override preserves correct station")
		var other := 1 if Rules.offering_city(id) != 1 else 2
		check(runtime.accept(other,id) != "","Cannot accept mission at the wrong station")
		for agent in jobs.vessels:
			check(not agent.get_parent().find_children("*","MeshInstance3D",true,false).is_empty(),"Vessel loads its visible original model")
		if id == "spytech":
			var mission: RefCounted = jobs.remaining
			check(jobs.attach_listening_device(mission.ship.body),"Big Ears attaches to designated Bohine shuttle")
			game.pilot.global_position = Vector3(-100,20,-100)
			mission.step(40)
			check(is_instance_valid(mission.cargo) and mission.cargo.get_parent().get_meta("editor_model") == "FREIGHT","Complete intercepted exchange reveals the freighter")
			check(mission.enemies.size() == 4,"Freighter has four guards")
			check(runtime.target_marker.target_body() == mission.cargo.body,"Target moves from shuttle to freighter")
			await capture("freighter")
			mission.cargo.take_weapon_damage_from(1000,mission.cargo.global_position,game.pilot)
			mission.step(2.1)
			check(runtime.active().is_empty() and game.player_progress.missions.completed.spytech.success,"Freighter destruction completes without docking")
			check(game.player_progress.status.credits == 103500,"Covert reward paid exactly once")
			check(game.submarine_traffic.traders.any(func(agent: Node3D) -> bool: return agent.has_meta("fishing_survivor")),"Surviving guards persist after success")
			for survivor in game.submarine_traffic.traders.filter(func(agent: Node3D) -> bool: return agent.has_meta("fishing_survivor")):
				check(survivor.get_signal_connection_list("destroyed").all(func(connection: Dictionary) -> bool: return connection.callable.get_object() != mission),"Surviving ships release old mission callbacks")
		elif id == "escort":
			var mission: RefCounted = jobs.remaining
			game.pilot.global_position = mission.ship.global_position+Vector3.UP*2
			mission.step(0.1)
			check(not mission.ship.waypoints.is_empty() and mission.ship.dock_destination == 5,"Prison transport departs toward Aquatraz when joined")
			for index in range(4): mission._escort_wave()
			check(mission.enemies.size() == 4,"Four original Procha attackers arrive")
			mission.step(0.1)
			check(is_instance_valid(mission.rescuer),"A live rescue ship approaches the prison")
			mission.rescuer.local_simulation = false
			var departure: Vector3 = mission.rescuer.global_position
			mission.rescuer.advance_abstract(0.25)
			check(mission.rescuer.global_position.distance_to(departure) <= 0.51,"Distant rescue ship travels instead of teleporting to its host")
			for tick in range(1200):
				if mission.flags.get("escaped",false): break
				mission.rescuer.advance_abstract(0.25); mission._step_escort(0.25)
			check(mission.flags.get("escaped",false),"Sixteen-second transfer starts escape pursuit")
			check(runtime.target_marker.target_body() == mission.rescuer.body,"HUD tracks the escaping prisoners")
			mission.rescuer.set_local_simulation(true)
			mission.rescuer.take_weapon_damage_from(1000,mission.rescuer.global_position,game.pilot)
			check(runtime.active().is_empty() and game.player_progress.missions.completed.escort.score == 0.5,"Stopping escaped prisoners gives original partial-success outcome")
		elif id == "tagtech":
			var mission: RefCounted = jobs.remaining
			check(mission.creature.route.size() == 17,"Tagged fish follows all 17 original markers")
			game.pilot.global_position = mission.cargo.global_position+Vector3.UP*2; mission.step(0.1)
			check(runtime.target_marker.target_body() == mission.cargo,"Finding the canister switches guidance")
			await capture("canister")
			check(jobs.delivery(mission.cargo,1) and not runtime.active().is_empty(),"Bohine delivery is rejected without losing the canister")
			check(jobs.delivery(mission.cargo,4) and runtime.active().is_empty(),"Procha canister delivery resolves at the drop point")
			check(game.player_progress.status.credits == 103000,"Canister reward paid")
		elif id == "eel":
			var mission: RefCounted = jobs.remaining
			check(mission.creature.get_child(1).get_meta("asset_source","").to_upper().contains("MEEL"),"First eel uses MEEL rather than a draft marker")
			check(not jobs.can_attach_pod(mission.structure),"Miners refuse rescue while the monster is alive")
			mission.creature.take_weapon_damage(1000,mission.creature.global_position)
			mission.step(6.1)
			check(is_instance_valid(mission.creature) and not mission.creature.dead,"Larger second eel appears after six seconds")
			await capture("huge-eel")
			mission.creature.take_weapon_damage(1000,mission.creature.global_position)
			check(jobs.can_attach_pod(mission.structure),"Escape Pod accepts mine after the second eel dies")
			game.equipment.set_installed(["escape"])
			var tools: Node3D = game.equipment.support_tools
			game.pilot.global_position = mission.structure.global_position+Vector3.UP
			tools.activate("escape",true); tools.pod_deployment = 0.6
			tools.pod.global_position = mission.structure.global_position+Vector3.UP*0.5
			tools._attach_pod(mission.structure)
			check(tools.pod_target == mission.structure and tools.pod_attached,"Physical Escape Pod seats on the mine hull through the real equipment contact handler")
			mission.step(12)
			check(runtime.active().is_empty() and game.player_progress.status.credits == 105000,"Miners boarding completes and rewards the rescue")
		elif id == "recontech":
			var mission: RefCounted = jobs.remaining
			check(mission.turrets.size() == 3,"Cave outpost has three destructible turrets")
			var mines: Array = jobs.actors.filter(func(actor: Node) -> bool: return actor is Mine)
			check(mines.size() == 3 and mines.all(func(mine: Node3D) -> bool: return mine.position.distance_to(mine.home) < 0.07 and mine.home.length() > 1 and not mine.get_signal_connection_list("exploded").is_empty()),"Three original mines stay at their source positions and use the shared blast damage handler")
			check(Shop.offer(game.gameplay_catalogue,"2",2,"rover").price == 10000,"ROV uses original Velcova price")
			game.player_progress.hold["rover"] = 1
			check(Shop.swap(game.player_progress,game.equipment,game.weapons,7,"rover").is_empty(),"ROV mounts in original slot seven")
			check(game.equipment.mounted.any(func(item: Dictionary) -> bool: return item.id == "rover"),"ROV is selectable as equipment")
			game.equipment.selected = game.equipment.mounted.size()-1; game.equipment.toggle_selected()
			var rov: CharacterBody3D = game.equipment.support_tools.rover
			check(rov.deployed,"Equipment activation deploys the remote vehicle")
			game._physics_process(0); game._update_follow_camera(0,true)
			check(game.pilot.remote_controlled and game.pilot.controls_enabled and game.camera.cull_mask & rov.RENDER_LAYER == 0,"Remote control redirects player input without disabling AI hostility, and excludes its own camera housing")
			mission.rov_recorded(0.0)
			check(not mission.flags.get("recorded",false),"Unusable recording cannot complete recon")
			var center: Vector3 = mission.structure.to_global(mission.structure.get_meta("mission_target_center",Vector3.ZERO))
			var clear_view := false
			for index in range(16):
				var angle := index*TAU/16.0
				var point := center+Vector3(cos(angle)*3,0.5,sin(angle)*3)
				rov.global_position = point; rov.look_at(center)
				rov.recording = 4; rov.exposure = 0; rov.advance_recording(4)
				if mission.flags.get("recorded",false): clear_view = true; break
			check(clear_view,"Actual four-second ROV exposure recognizes a clear view of the outpost")
			if DisplayServer.get_name() != "headless":
				rov.yaw = rov.global_rotation.y; rov.pitch = rov.global_rotation.x
				game._update_follow_camera(0,true)
				for frame in range(5): await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://tests/remaining-rov-view.png")
			mission.step(10.1)
			check(mission.flags.get("recorded",false) and mission.enemies.size() == 4,"Confirmed footage triggers original three reinforcements")
			jobs.docked(2)
			check(runtime.active().is_empty() and game.player_progress.status.credits == 105000,"Recorded footage succeeds on returning to city")
			check(rov.deployed and rov.launched,"Resolving a mission does not teleport or reclaim the player's ROV")
			rov.reset()
			check(game.save_games.write(0,game._save_snapshot("ROV loadout")) == OK,"Installed ROV and new mission history use the existing beta save format")
			game.player_progress.hold["depthl"] = 1
			Shop.swap(game.player_progress,game.equipment,game.weapons,7,"depthl")
			check(game.player_progress.hold.get("rover",0) == 1 and Shop.installed(game.equipment,game.weapons).get(7) == "depthl","Charge Launcher replaces ROV in the shared slot and returns ROV to hold")
			Shop.swap(game.player_progress,game.equipment,game.weapons,7,"rover")
			check(game.player_progress.hold.get("depthl",0) == 1 and Shop.installed(game.equipment,game.weapons).get(7) == "rover","ROV replaces Charge Launcher without losing either item")
		await physics_frame; await physics_frame
	await fresh("spytech2")
	var spy: RefCounted = jobs.remaining
	game.pilot.global_position = spy.ship.global_position+spy.ship.get_parent().global_basis.z
	spy.step(4.1); spy.step(2.5); spy.step(1.1); spy.step(6.1)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.spytech2.success,"Repeated visible approach gives the warning and original detection failure")
	check(game.player_progress.status.credits == 100000,"Detected covert mission pays no reward")
	await fresh("escort2")
	var convoy: RefCounted = jobs.remaining
	game.pilot.global_position = convoy.ship.global_position+Vector3.UP
	convoy.step(0.1)
	convoy.ship.local_simulation = false
	for tick in range(1600):
		if runtime.active().is_empty(): break
		convoy.ship.advance_abstract(0.25); convoy._step_escort(0.25)
	check(runtime.active().is_empty() and game.player_progress.missions.completed.get("escort2",{}).get("score",0) == 1,"Prison transport can traverse the actual map route and finish at Aquatraz without player docking")
	await fresh("escort")
	jobs.remaining.ship.take_weapon_damage_from(1000,jobs.remaining.ship.global_position,game.pilot)
	jobs.remaining.step(6.1)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.escort.success,"Destroying the occupied prison transport fails the escort")
	await fresh("tagtech")
	jobs.remaining.creature.take_weapon_damage(1000,jobs.remaining.creature.global_position)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.tagtech.success,"Losing the tagged fish before finding the canister fails")
	await fresh("eel")
	jobs.remaining.structure.take_weapon_damage(1000)
	jobs.remaining.step(6.1)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.eel.success,"Destroying the occupied mine fails with the original delayed report")
	await fresh("recontech2")
	jobs.remaining.structure.take_weapon_damage(1000)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.recontech2.success,"Destroying the outpost before confirmation fails recon")
	check(runtime.last_response == runtime.text("recontech2",2),"Unconfirmed destruction selects the original hospital response")
	# Every source radio code used by these missions has both text and a portrait.
	for prefix in ["ae","aa","ii","c","o"]:
		var count: int = {"ae":14,"aa":11,"ii":8,"c":11,"o":7}[prefix]
		for index in range(1,count+1):
			var record: Dictionary = game.gameplay_catalogue.tables.radio_messages.records.get(prefix+str(index),{})
			check(not record.is_empty() and not str(record.get("portrait","")).is_empty(),"Source dialogue and portrait loaded: "+prefix+str(index))
			check(preload("res://docking_radio.gd").speaker_portrait(game.game_folder,str(record.get("portrait",""))) != null,"Actual original portrait resolves: "+prefix+str(index))
			check(preload("res://legacy_audio.gd").load_file(game.game_folder.path_join("WAVES/ENGLISH/"+prefix.to_upper()+str(index)+".RAW")) != null,"Original speech asset resolves: "+prefix+str(index))
	runtime._cleanup(); game.free(); await process_frame
	print("Remaining stage two: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)

func capture(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var body: Node3D = runtime.target_marker.target_body()
	if body == null: return
	var center: Vector3 = body.to_global(body.get_meta("mission_target_center",Vector3.ZERO))
	game.pilot.global_position = center+Vector3(0,4,6)
	var size := 6.0 if id != "freighter" else 13.0
	for index in range(16):
		var angle := index*TAU/16
		var point := center+Vector3(cos(angle)*size,2,sin(angle)*size)
		var query := PhysicsRayQueryParameters3D.create(center,point,1,[body.get_rid()]); query.hit_back_faces = true
		if game.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): game.camera.global_position = point; break
	game.camera.look_at(center); game.camera.make_current()
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/remaining-"+id+".png")
