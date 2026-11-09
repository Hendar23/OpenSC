extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
var game: Node
var runtime: Node
var jobs: Node
var failures := 0
var checks := 0
var movies: Array[String] = []

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-final-missions-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var cfg := ConfigFile.new()
	cfg.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER"))
	cfg.save(storage.preferences_path())
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func capture(point: Vector3, offset: Vector3, caption: String) -> void:
	if DisplayServer.get_name()=="headless": return
	game.front_end.menu_layer.hide()
	game.camera.global_position=point+offset; game.camera.look_at(point)
	var lamp:=OmniLight3D.new(); game.world_root.add_child(lamp)
	lamp.global_position=point+offset*0.4; lamp.omni_range=30; lamp.light_energy=2
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../.local/final-"+caption+".png")
	lamp.free()

func start(id: String, stage: int) -> RefCounted:
	runtime._session_started(false)
	preload("res://mission_survivors.gd").clear(game.submarine_traffic)
	game.player_progress = Progress.restore({"campaign_stage":stage})
	preload("res://campaign_resources.gd").restore_for_progress(game)
	game.player_progress.status.credits = 100000
	var city := Rules.offering_city(id)
	check(runtime.board(city).id == id and runtime.board(city).available,"Offer available: "+id)
	game.docking.current = game.submarine_traffic.port_by_id(city)
	game.docking.stage = game.Docking.Stage.DOCKED
	var error: String = runtime.accept(city,id)
	check(error.is_empty(),"Accept: "+id+" "+error)
	check(game.player_progress.missions.get("unavailable",[]).size() == 3,"Other city variants excluded")
	game.docking.stage = game.Docking.Stage.IDLE
	paused = false
	return jobs.controller

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	while not game.startup_complete: await process_frame
	if "--ending-playback" in OS.get_cmdline_user_args():
		# FMV validation requires the cache; keep ordinary asset conversions
		# disabled while preparing the real films inside this isolated fixture.
		preload("res://asset_cache.gd").enabled = true
		game.fmv.prepared_folder = ""
		await game.fmv.prepare(game.game_folder)
		preload("res://asset_cache.gd").enabled = false
	game.front_end.gameplay_menu.fmvs_enabled = false
	await game._begin_new_game()
	game.equipment.set_installed(["deep_sea_lights","magnet","rover","woosh"])
	game.set_process(false); game.pilot.freeze = true
	game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	game.wildlife.set_simulating(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs; jobs.set_physics_process(false)
	game.events.fmv_requested.connect(func(cue: String,_city: int): movies.append(cue))
	var city: Node3D = game.submarine_traffic.port_by_id(5).node
	for id: String in Rules.CORE_SIX.values():
		var mission := start(id,6)
		if mission == null: quit(1); return
		check(mission.guns.size()==8 and mission.allies.size()==3 and mission.modulators.size()==2,"Original Aquatraz actor counts")
		check(not city.visible and mission.shield.visible and mission.shield.collision_layer == 1,"Factory replaces city behind solid shield")
		check(mission.guns.all(func(gun): return gun.health == 75 and gun.get_meta("damage_sustain") == 0.5),"Original gun shields and sustain")
		check(mission.ground_guns.size()==3 and mission.ground_guns.all(func(gun): return gun.armed()),"Three original ground turrets activate")
		if id=="aquatraz": await capture(mission.factory.global_position,Vector3(11,6,12),"aquatraz")
		if id=="aquatraz":
			game.pilot.active=true; game.pilot.controls_enabled=true
			var before_health: float = game.pilot.health
			for gun in mission.guns:
				game.pilot.global_position = gun.barrel.to_global(Vector3(0,0,7))
				game.pilot.reset_physics_interpolation()
				await physics_frame; await physics_frame
				mission._step_guns(0.04)
				if not get_nodes_in_group("aquatraz_plasma").is_empty(): break
			check(not get_nodes_in_group("aquatraz_plasma").is_empty(),"Aligned factory gun launches actual plasma")
			for frame in 150: await physics_frame
			check(game.pilot.health<before_health,"Swept plasma hits and damages real player hull")
		mission.step(8)
		game.pilot.global_position = mission.modulators[0].global_position
		mission.step(4); check(jobs.phase == "modulating","Rendezvous starts field countdown")
		mission.step(18); mission.step(18)
		check(jobs.phase == "shield_open" and not mission.shield.visible and mission.shield.get_collision_exceptions().has(game.pilot),"Shield lets the specially modified player cross")
		game.pilot.global_position.z = mission.shield_left.z+1
		mission.step(12); check(jobs.phase == "shield_open","Opening waits for the player to cross")
		game.pilot.global_position.z = mission.shield_left.z-1
		mission.step(18); check(jobs.phase == "attack" and mission.shield.visible,"Shield closes behind player")
		mission.step(2); check(mission.enemies.size()==1,"Factory launches pirate reinforcement")
		mission.step(12); check(mission.enemies.size()==2,"Second reinforcement launches")
		mission.enemies[0].take_weapon_damage(10000)
		mission.step(12); check(mission.enemies.size()==3,"Destroyed reinforcements are replaced")
		for index in 5: mission.guns[index].take_weapon_damage(1000)
		mission.step(1); check(mission.spinup and mission.rotation_speed>mission.NORMAL_SPIN,"Last three guns spin faster")
		for index in range(5,8): mission.guns[index].take_weapon_damage(1000)
		mission.step(5)
		check(runtime.active().is_empty() and game.player_progress.campaign_stage==7,"Aquatraz advances campaign")
		check(game.player_progress.status.credits==110000,"Aquatraz pays 10,000 credits once")
		check(not city.visible and city.get_meta("mission_dock_disabled",false),"Aquatraz remains destroyed")
		check(is_instance_valid(mission.enemies[-1]) and mission.enemies[-1].mission_owner.is_empty(),"Pirate survivor remains independent")
		check(movies.is_empty(),"Aquatraz does not play an unrelated ending")
		var saved := Progress.restore(game.player_progress.duplicate(true))
		game.player_progress = saved
		preload("res://campaign_resources.gd").restore_for_progress(game)
		check(not city.visible and runtime.board(1).id=="endgame","Stage-seven save preserves destroyed city and final offer")
		await physics_frame; await process_frame
	var failed := start("aquatraz",6)
	var retained_site: Node3D = failed.site
	var old_rotation: Basis = failed.factory.basis
	runtime.finish(false)
	check(runtime.retained_props.has(retained_site) and not city.visible,"Failure keeps surviving installation until docking")
	failed._retained_step(0.1)
	check(failed.factory.basis!=old_rotation,"Retained factory keeps turning")
	failed.guns[0].take_weapon_damage(1000)
	check(failed.guns[0].dead and failed.guns[0].collision_layer==0,"Retained gun remains destructible without invisible collisions")
	runtime.docked(1); await process_frame
	check(not is_instance_valid(retained_site) and city.visible,"Docking restores failed installation scenery")
	for id: String in Rules.CORE_SEVEN.values():
		var mission := start(id,7)
		if mission == null: quit(1); return
		check(mission.guards.size()==11 and mission.bomb_guards.size()==3 and mission.allies.size()==4 and mission.fish.size()==8,"Original Armageddon actor counts")
		check(mission.arcs.size()==6 and mission.bomb.get_meta("metal_tow_target"),"Six electrode hazards and magnet bomb")
		check(mission.robot.power.health==10 and mission.robot.power.sustain==0.5,"Original rear power-pack vulnerability")
		check(mission.site.masked.size()>0,"Northwest inlet grating opens")
		await physics_frame; await physics_frame
		for enemy in mission.enemies:
			check(game.submarine_traffic.can_activate(enemy),"Pirate hull starts in clear water: "+str(enemy.global_position))
		var guard: Node3D = mission.guards[0]
		var guard_pose: Transform3D = guard.get_parent().global_transform
		var local: bool = guard.local_simulation
		guard.local_simulation=false; guard.advance_abstract(60); guard.local_simulation=local
		check(guard.get_parent().global_transform==guard_pose,"Offscreen traffic graph cannot teleport guards out of the pipe network")
		var center: Vector3 = mission.iris.global_position
		var ray:=PhysicsRayQueryParameters3D.create(center+Vector3.UP*7,center+Vector3.DOWN*5,1)
		var closed: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not closed.is_empty() and closed.collider==mission.iris,"Closed iris physically blocks its centre")
		check(mission.bomb.freeze and mission.bomb.prepare_towing(),"Bomb releases into physical magnet towing")
		check(not mission.bomb.freeze,"Bomb can sink after detaching")
		mission.bomb.freeze = true
		mission.button.activate(); mission.iris._physics_process(0.4)
		check(mission.iris.openness>0.99 and mission.iris.collision_open,"Switch opens iris and its collision")
		await physics_frame; await physics_frame
		var opened: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
		check(opened.is_empty() or opened.collider!=mission.iris,"Open iris physically clears its centre")
		if id=="endgame": await capture(center,Vector3(0,10,4),"iris-open")
		if id=="endgame":
			var remote: Node3D = game.equipment.support_tools.rover
			remote.launched=true; remote.collision_layer=8
			remote.global_position=mission.button.shape.global_transform*mission.button.shape.shape.get_debug_mesh().get_aabb().get_center()
			await physics_frame; await physics_frame
			mission.button._physics_process(0.1)
			check(mission.button.pressed_for>0 and mission.iris.latch>19,"Parked ROV's physical contact holds the hatch switch")
			remote.reset()
			# Let the real rigid body fall through the animated hatch, rather
			# than relying solely on an artificial delivery callback.
			mission.bomb.global_position = center+Vector3.UP
			mission.bomb.freeze = false; mission.bomb.reset_physics_interpolation()
			for frame in 360: await physics_frame
			check(mission.bomb.global_position.y<center.y-0.5,"Released bomb physically sinks through open hatch")
			mission.bomb.freeze = true
		mission.iris._physics_process(21)
		check(mission.iris.openness<0.01 and not mission.iris.collision_open,"Iris closes when switch is released")
		if id=="endgame":
			await capture(center,Vector3(0,10,4),"iris-closed")
			await capture(mission.robot.global_position,Vector3(-2,1,-4),"robot-rear")
		mission.robot.fan_speed=deg_to_rad(100)
		mission.robot.snout.take_weapon_damage(1); mission.robot._physics_process(0.1)
		check(not mission.robot.dead and mission.robot.fan_speed<deg_to_rad(10),"Front snout briefly stalls fan without killing robot")
		mission.robot.power.take_weapon_damage(20)
		check(mission.robot.dead and mission.robot.dying==8,"Rear pack stops and destroys robot")
		var rover: Node3D = game.equipment.support_tools.rover
		rover.set_deployed(true)
		mission.bomb.global_position = mission.destination
		mission.step(0.1)
		check(jobs.phase == "escape" and mission.bomb.dead and mission.target_body()==null,"Bomb delivery triggers escape")
		check(not rover.launched and rover.collision_layer==0 and not game.pilot.remote_controlled,"Explosion sacrifices ROV and returns control")
		var fire: Node3D = mission.fire
		game.pilot.global_position.x = mission.escape_point.x+5
		var playback := "--ending-playback" in OS.get_cmdline_user_args() and id=="endgame"
		game.front_end.gameplay_menu.fmvs_enabled = playback
		mission.step(8)
		check(runtime.active().is_empty() and game.player_progress.status.credits==100666,"Escape completes and pays original 666 credits")
		check(movies[-1]=="campaign_escape" and fire.finished,"Successful escape requests OUTRO and stops fire wall")
		check(mission.enemies.all(func(enemy):return enemy.dead or enemy.mission_owner.is_empty()),"Surviving pirates persist")
		check(runtime.retained_props.has(mission.site) and runtime.retained_props.has(mission.fish[0]),"Mission scenery and robot fish persist until dock")
		check(runtime.board(1).is_empty() or str(runtime.board(1).get("id","")).is_empty(),"Campaign does not reoffer final mission")
		if playback:
			check(game.fmv.active and game.fmv.current=="outro" and paused,"Escape plays prepared original OUTRO immediately")
			if game.fmv.active: game.fmv._finish_current()
			game.front_end.gameplay_menu.fmvs_enabled = false
		await process_frame
	# The other original ending is selected by contact with the fire wall.
	var caught := start("endgame",7)
	caught.bomb.global_position = caught.destination; caught.step(0.1)
	game.front_end.gameplay_menu.fmvs_enabled = "--ending-playback" in OS.get_cmdline_user_args()
	caught._caught()
	check(not game.player_progress.missions.completed.endgame.success and movies[-1]=="antagonist_destroyed","Fire-wall capture selects ALTOUT")
	if game.front_end.gameplay_menu.fmvs_enabled:
		check(game.fmv.active and game.fmv.current=="altout" and paused,"Capture plays prepared original ALTOUT immediately")
		if game.fmv.active: game.fmv._finish_current()
		game.front_end.gameplay_menu.fmvs_enabled = false
	await process_frame
	var lost := start("endgame2",7)
	var movie_count := movies.size()
	# Retail zero sustain is invulnerable, but explicit combat overrides retain
	# the scripted lost-bomb branch rather than conflating it with an ending.
	lost.bomb.health=1; lost.bomb.sustain=1
	lost.bomb.take_weapon_damage(10)
	check(not game.player_progress.missions.completed.endgame2.success and game.player_progress.status.credits==100000,"Lost bomb fails without payout")
	check(movies.size()==movie_count,"Lost bomb does not play a terminal FMV")
	var old_site: Node3D = lost.site
	runtime._session_started(false); await process_frame
	check(not is_instance_valid(old_site) and runtime.retained_props.is_empty(),"Session reset removes retained final actors")
	game.free(); await process_frame
	print("Final missions: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
