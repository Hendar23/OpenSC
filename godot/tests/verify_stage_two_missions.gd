extends "res://tests/test_scene_tree.gd"
const Shop = preload("res://equipment_shop.gd")
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
var checks := 0
var failures := 0
var game: Node
var runtime: Node
var jobs: Node
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-stage-two-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",ProjectSettings.globalize_path("res://../Original Sub Culture")); config.save(storage.preferences_path())
	call_deferred("run")
func port(city: int) -> void:
	game.docking.current = game.submarine_traffic.port_by_id(city); game.docking.stage = game.Docking.Stage.DOCKED
func fresh() -> void:
	runtime._cleanup(); game.player_progress = Progress.restore({"campaign_stage":2})
	runtime.outcome.dismiss(); game.radio_feed.clear(); game.bounty_radio_queue.clear()
	game.player_progress.status.credits = 100000
	game.equipment.set_installed(["deep_sea_lights","suckomat"]); game.weapons.set_installed(["zapper"])
	game.pilot.active = true; game.pilot.controls_enabled = true
func capture(name: String, focus: Node3D = null) -> void:
	if DisplayServer.get_name() == "headless" or not is_instance_valid(jobs.target): return
	if focus == null: focus = jobs.target
	var previous: Transform3D = game.camera.global_transform
	var target_position: Vector3 = focus.global_position + Vector3.UP * 0.2
	for offset in [Vector3(5,2,5),Vector3(-5,2,-5),Vector3(-5,2,5),Vector3(5,2,-5),Vector3(0,3,5),Vector3(0,3,-5)]:
		var candidate: Vector3 = target_position + offset
		var query := PhysicsRayQueryParameters3D.create(target_position,candidate,1); query.hit_back_faces = true
		if game.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): game.camera.global_position = candidate; break
	game.camera.look_at(focus.global_position); game.camera.make_current()
	if name == "bacau":
		var activity: Node = game.world_root.get_node("ActorActivity")
		activity.refresh_views(); activity.update_actors(0.1)
		check(jobs.escorts.all(func(agent: Node3D) -> bool: return agent.local_simulation and agent.get_parent().visible),"Approaching the shuttle activates both visible guards through normal activity management")
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	if name in ["bacau","prison","covert"]:
		check(runtime.target_marker.target_point().is_finite(),"Green target brackets track the visible shuttle")
		game.map_open = true
		check(not runtime.target_marker.target_point().is_finite(),"Fullscreen map hides the shuttle's world brackets")
		game.map_open = false
	root.get_texture().get_image().save_png("res://tests/stage-two-" + name + ".png")
	game.dock_interface.open("missions"); game.dock_interface.mission_selection = str(runtime.active().id); game.dock_interface.rebuild()
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/stage-two-" + name + "-board.png")
	game.dock_interface.dismiss(); game.camera.global_transform = previous
func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game loads stage-two runtime")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	game.set_process(false); game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.dock_interface.open("load"); game._update_mouse_pointer()
	check(game._desired_mouse_mode() == Input.MOUSE_MODE_VISIBLE,"Load slots keep the pointer visible when the main menu is hidden and player is undocked")
	if DisplayServer.get_name() != "headless": check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"Native cursor is visible over load slots")
	game.dock_interface.dismiss(); game._update_mouse_pointer()
	check(game._desired_mouse_mode() == Input.MOUSE_MODE_HIDDEN,"Returning from load slots restores the piloting pointer state")
	runtime = game.mission_runtime; jobs = runtime.side_jobs; jobs.set_physics_process(false)
	var original_npcs: int = game.submarine_traffic.traders.size()
	var original_markers: int = game.cockpit_hud.map_data.actor_markers.size()
	for frame in range(2400):
		if game.submarine_traffic.navigation_ready: break
		game.submarine_traffic.build_graph(128); await process_frame
	check(game.submarine_traffic.navigation_ready,"Shared water navigation is ready for mission routes")
	var camera_pose: Transform3D = game.pilot.global_transform
	var camera_distance: float = game.pilot.movement.settings.camera_distance
	var camera_velocity: Vector3 = game.pilot.velocity
	var interpolation: int = game.pilot.physics_interpolation_mode
	game.pilot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	game.pilot.velocity = Vector3.ZERO
	game.pilot.pending_reset = false
	game.pilot.global_transform = Transform3D(Basis.IDENTITY,Vector3(10000,-10,10000)); game.pilot.reset_physics_interpolation()
	game.pilot.movement.settings.camera_distance = 3.0
	var wall := StaticBody3D.new(); game.world_root.add_child(wall)
	var wall_shape := CollisionShape3D.new(); wall_shape.shape = BoxShape3D.new(); wall_shape.shape.size = Vector3(3,3,0.2); wall.add_child(wall_shape)
	wall.global_position = game.pilot.global_position + Vector3(0,0.35,0.35)
	await physics_frame; await physics_frame
	await process_frame; await process_frame
	game._set_camera_mode(false)
	var stationary: Vector3 = game.camera.global_position; var jitter := 0.0
	for frame in range(120):
		game._update_follow_camera(1.0/120.0)
		jitter = maxf(jitter,stationary.distance_to(game.camera.global_position))
	print("Close-wall camera: ",stationary," -> ",game.camera.global_position," jitter ",jitter)
	check(jitter < 0.002 and game.camera.global_position.z > game.pilot.global_position.z,"A wall very close behind the hull neither flips nor judders the third-person camera")
	wall.free(); await physics_frame
	var last: Vector3 = game.camera.global_position; var largest_step := 0.0
	for frame in range(120):
		game._update_follow_camera(1.0/60.0)
		largest_step = maxf(largest_step,last.distance_to(game.camera.global_position)); last = game.camera.global_position
	print("Cleared-wall camera: ",game.camera.global_position," largest step ",largest_step)
	check(largest_step < 0.2 and game.camera.global_position.distance_to(stationary) > 1.0,"Camera smoothly returns to its full boom after the real obstacle clears")
	game.pilot.global_transform = camera_pose; game.pilot.velocity = camera_velocity; game.pilot.physics_interpolation_mode = interpolation; game.pilot.reset_physics_interpolation(); game.pilot.movement.settings.camera_distance = camera_distance; game._set_camera_mode(false)
	fresh(); port(1)
	var unlock: Button = game.developer_tabs.get_node("System/UnlockTestingMissions")
	var picker: OptionButton = game.developer_tabs.get_node("System/TestingMission")
	game.player_progress.campaign_stage = 1; game.player_progress.status.credits = 0
	game.player_progress.missions.completed["stranded"] = {"success":true}
	game.player_progress.missions["unavailable"] = ["breakout","breakout2"]
	unlock.button_pressed = true
	check(runtime.testing_all_missions and not picker.disabled and picker.item_count == 8,"Dev button unlocks the eight implemented opening variants and side missions")
	check(picker.get_item_text(picker.selected).begins_with("Rescue Bacau Shuttle"),"Mission selector has readable names even though the dev UI builds before catalogue loading")
	for index in range(picker.item_count):
		picker.select(index); picker.item_selected.emit(index)
		var chosen: String = picker.get_item_metadata(index)
		var origins := {"tradetrad":1,"tradetrad2":3,"tradetech":2,"tradetech2":4,"stranded":1,"spytrad2":3,"breakout":2,"breakout2":4}
		for city in [1,2,3,4,5,6]:
			check(runtime.board(city).available == (city == origins[chosen]) and runtime.board(city).id == (chosen if city == origins[chosen] else ""),"Testing unlock preserves the original station for " + chosen)
	check(game.player_progress.campaign_stage == 1 and game.player_progress.missions.completed.has("stranded") and game.player_progress.missions.unavailable.size() == 2,"Unlocking leaves campaign history and stage intact")
	port(1)
	check(not runtime.accept(1).is_empty() and runtime.can_save(),"Testing cannot accept Tryton's selected mission at Touka")
	port(4)
	var testing_error: String = runtime.accept(4)
	check(testing_error.is_empty(),"Accept testing mission: " + testing_error)
	check(not runtime.can_save() and not runtime.board(1).available,"Testing acceptance still enforces one mission and blocks saving")
	fresh(); unlock.button_pressed = false
	check(not runtime.testing_all_missions and picker.disabled and not runtime.board(5).available,"Turning testing off restores normal mission availability")
	for row in [[1,"stranded","magnet",2500],[3,"spytrad2","bigears",5000],[2,"breakout","escape",5060],[4,"breakout2","escape",5060]]:
		fresh(); port(row[0]); game.player_progress.status.credits = row[3] - 1
		check(not runtime.board(row[0]).available,"Missing required tool hides unaffordable offer " + row[1])
		game.player_progress.status.credits += 1
		check(runtime.board(row[0]).available and runtime.board(row[0]).id == row[1],"Exact original affordability threshold reveals " + row[1])
		check(Rules.requirement_cost(game,row[1],row[0]) == row[3],"Required cost uses local price or highest four-city fallback")
		game.player_progress.status.credits = 0; game.player_progress.hold[row[2]] = 1
		check(runtime.board(row[0]).available,"Required tool in hold is sufficient for acceptance")
		Shop.swap(game.player_progress,game.equipment,game.weapons,Shop.SLOTS[row[2]],row[2])
		check(runtime.board(row[0]).available and Rules.requirement_cost(game,row[1],row[0]) == 0,"Installed required tool removes affordability requirement")
		check(runtime.board(5).available == false and runtime.board(6).available == false,"Special docks do not offer these jobs")
		game.player_progress.campaign_stage = 1
		check(runtime.board(row[0]).id != row[1],"Stage-two job requires the opening mission stage")
	fresh(); port(1)
	check(runtime.accept(1).is_empty(),"Accept Bacau rescue")
	check(jobs.target != null and jobs.escorts.size() == 2 and jobs.vessels.size() == 2,"Retail Bacau encounter contains the shuttle and two guards, without the unused surveillance craft")
	check(jobs.target.get_meta("metal_tow_target",false) and jobs.target.mass == 10,"Bacau uses a substantial ten-unit physical towing mass")
	check(jobs.target.damage_smoke.damaged and jobs.target.damage_smoke.enabled,"The disabled shuttle engine emits smoke before hull damage")
	jobs.target.damage_smoke._process(0.2)
	check(not jobs.target.damage_smoke.puffs.is_empty(),"Smoke particles are actually emitted from the shuttle")
	check(jobs.escorts.all(func(agent: Node3D) -> bool: return agent.get_parent().get_meta("editor_model") == "TECHNEW" and not agent.engage_player),"Both original Procha attack subs initially escort rather than attack")
	for agent in jobs.escorts:
		agent.set_local_simulation(false); agent.advance_abstract(0.25)
	check(jobs.escorts.all(func(agent: Node3D) -> bool: return game.submarine_traffic.can_activate(agent)),"Guards remain clear of the volcano after hidden formation travel")
	for agent in jobs.escorts: agent.set_local_simulation(true)
	var guard: Node3D = jobs.escorts[0]
	guard.body.take_weapon_damage_from(0.1,game.pilot.global_position,game.pilot)
	check(guard.engage_player,"An attacked guard retaliates against the player")
	guard.engage_player = false; guard.victim = null
	var cargo_query := PhysicsShapeQueryParameters3D.new(); var cargo_shape: CollisionShape3D = jobs.target.find_children("*","CollisionShape3D",true,false)[0]
	cargo_query.shape = cargo_shape.shape; cargo_query.transform = cargo_shape.global_transform; cargo_query.collision_mask = 1
	cargo_query.exclude = [jobs.target.get_rid()]
	check(game.get_world_3d().direct_space_state.intersect_shape(cargo_query,1).is_empty(),"Bacau spawns clear of terrain and scenery")
	var previous_pilot: Transform3D = game.pilot.global_transform
	game.pilot.global_position = jobs.target.global_position + Vector3.UP * 2
	game.equipment.set_installed(["magnet"])
	var magnet: Node3D = game.equipment.magnet
	magnet.set_enabled(true); magnet.set_physics_process(false)
	magnet.head.global_position = cargo_shape.global_position
	magnet.head.reset_physics_interpolation()
	for tick in range(12): await physics_frame
	check(magnet.target == jobs.target and is_instance_valid(magnet.clamp_joint),"Actual magnet contact automatically clamps the mission shuttle")
	check(is_equal_approx(game.pilot.movement.cargo_mass,jobs.target.mass * magnet.cargo_weight),"Heavier shuttle load reaches the actual engine using the existing player multiplier")
	var unloaded := preload("res://movement_model.gd").new(); var loaded := preload("res://movement_model.gd").new(); loaded.cargo_mass = game.pilot.movement.cargo_mass
	unloaded.step(0.1,Basis.IDENTITY,1.0,0.0,0.0,0.0); loaded.step(0.1,Basis.IDENTITY,1.0,0.0,0.0,0.0)
	check(loaded.velocity.length() < unloaded.velocity.length() * 0.8,"Shuttle load noticeably reduces acceleration under identical thrust")
	var previous_cargo: Vector3 = jobs.target.global_position
	jobs.target.global_position = game.submarine_traffic.port_by_id(3).entry
	jobs._step_stranded()
	check(jobs.warned and jobs.escorts.all(func(agent: Node3D) -> bool: return agent.engage_player),"Towing Bacau toward Beluga also provokes the Procha guards")
	jobs.target.global_position = previous_cargo; jobs.target.reset_physics_interpolation(); jobs.warned = false
	for agent in jobs.escorts: agent.engage_player = false; agent.victim = null
	magnet.reset(); magnet.set_physics_process(true); game.pilot.global_transform = previous_pilot
	await capture("bacau")
	check(jobs.vessels.all(func(agent: Node3D) -> bool: return game.submarine_traffic.can_activate(agent)),"Procha rescue team spawns clear of scenery")
	check(not runtime.can_save() and game.save_games.read(-1).progress.missions.active.is_empty(),"Pre-mission save precedes actors and active state")
	var backup := FileAccess.get_file_as_string(game.save_games.path(-1)); game._autosave_docked()
	check(FileAccess.get_file_as_string(game.save_games.path(-1)) == backup,"Docking mid-mission preserves pre-mission save")
	check(not jobs.delivery(jobs.target,6),"Factory cannot accept the rescue shuttle")
	for agent in jobs.escorts: agent.take_weapon_damage(10000)
	check(jobs.delivery(jobs.target,1),"Touka accepts Bacau at drop point")
	check(not runtime.target_marker.target_point().is_finite(),"Delivered shuttle no longer has target brackets")
	check(runtime.active().is_empty() and runtime.outcome.visible,"Drop-off immediately completes the mission and starts the outcome animation")
	jobs._step_stranded(); runtime.docked(1)
	check(runtime.can_save() and game.player_progress.missions.completed.stranded.success,"Subsequent docking preserves the already completed rescue")
	check(game.player_progress.status.credits == 102000,"Bacau success pays original fixed 2000 credits")
	check(game.player_progress.missions.stage2_successes == 1 and game.player_progress.missions.stage2_resolved == 1,"Side-job counts exclude opening mission")
	check(not runtime.board(1).available,"Resolved rescue is not repeatable")
	check(not runtime.board(1).report and runtime.board(1).id.is_empty() and runtime.board(1).response.is_empty(),"Completed rescue and its debrief no longer occupy the mission board")
	runtime.outcome.dismiss(); game.dock_interface.open("missions"); game.dock_interface.mission_selection = "stranded"; game.dock_interface.rebuild()
	var picture: TextureRect = game.dock_interface.layout.find_child("MissionPicture",true,false)
	var welcome_picture: Texture2D = game.dock_interface.texture("texture.mission_picture_bdefault","INTROTEX/BDEFAULT.BMP")
	check(picture.texture.get_image().get_data() == welcome_picture.get_image().get_data(),"Completed mission screen restores the faction welcome image even with a stale selection")
	check(game.dock_interface.layout.find_children("*","RichTextLabel",true,false).all(func(body: RichTextLabel) -> bool: return not body.text.contains("Rescue attempt")),"Completed rescue debrief is absent from the rendered mission screen")
	if DisplayServer.get_name() != "headless":
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/stage-two-bacau-completed-board.png")
	game.dock_interface.dismiss()
	check(runtime.board(3).response.is_empty(),"Another city's offer does not inherit the previous mission debrief")
	await process_frame
	check(game.submarine_traffic.traders.size() == original_npcs and game.cockpit_hud.map_data.actor_markers.size() == original_markers,"Rescue actors and minimap markers clean up")
	for city in [1,2]:
		fresh(); port(1); runtime.accept(1)
		check(jobs.delivery(jobs.target,city) and runtime.active().is_empty() and runtime.outcome.visible,"Drop-off with live guards resolves immediately at city %d" % city)
		var expected_voice := "X1.RAW" if city == 1 else "X12.RAW"
		check(runtime.speech.playing and str(runtime.speech.stream.get_meta("asset_source","")).ends_with(expected_voice),"Completion plays original %s immediately and survives mission cleanup" % expected_voice)
		var paid: int = game.player_progress.status.credits
		runtime.docked(city)
		check(paid == 102000 and game.player_progress.status.credits == paid,"Later docking does not pay the rescue reward twice")
		await process_frame
	fresh(); port(1); runtime.accept(1)
	for agent in jobs.escorts: agent.take_weapon_damage(10000)
	jobs.delivery(jobs.target,2)
	check(runtime.speech.playing and str(runtime.speech.stream.get_meta("asset_source","")).ends_with("X21.RAW"),"Alternate Procha return with destroyed guards plays original X21 speech through cleanup")
	await process_frame
	fresh(); port(1); runtime.accept(1); jobs.age = 360; jobs._step_stranded()
	check(runtime.can_save() and not game.player_progress.missions.completed.stranded.success,"Bacau oxygen depletion fails the rescue")
	check(game.player_progress.status.credits == 100000 and game.player_progress.missions.stage2_resolved == 1,"Failed rescue pays nothing but counts resolved")
	await process_frame
	for city in [2,4]:
		fresh(); port(city); runtime.accept(city)
		if city == 2: await capture("prison")
		check(jobs.target != null and jobs.escorts.size() == 4,"Prison transport and four guards spawn for both city variants")
		check(not jobs.target.combat_enabled and jobs.escorts.all(func(agent: Node3D) -> bool: return agent.get_parent().get_meta("editor_model") == "TRAD2" and not agent.engage_player),"Unarmed PRISON transport and four original TRAD2 guards start peacefully")
		check(not runtime.board(4 if city == 2 else 2).available,"Accepted prison job excludes the other city variant")
		check(game.submarine_traffic.traders.size() == original_npcs + 5,"Mission convoy is separate from ambient transport")
		game.equipment.set_installed(["deep_sea_lights","escape"])
		var ship: Node3D = jobs.target
		for agent in jobs.vessels: agent.set_physics_process(false)
		ship.body.take_weapon_damage_from(0.1,game.pilot.global_position,game.pilot)
		check(runtime.speech.playing and str(runtime.speech.stream.get_meta("asset_source","")).ends_with("Y1.RAW") and game.bounty_radio_queue.any(func(message: Dictionary) -> bool: return message.text.contains("You want a fight?") and message.speaker.ends_with("/jude") and message.portrait != null),"First attack plays original Y1 taunt with Jude's portrait")
		check(not ship.engage_player and jobs.escorts.filter(func(agent: Node3D) -> bool: return agent.engage_player).size() == 2,"Hitting the transport sends half its escorts, while the unarmed transport stays on its route")
		for agent in jobs.escorts: agent.engage_player = false
		game.pilot.global_position = ship.global_position + Vector3.UP * 2; jobs._step_breakout(0)
		check(not ship.waypoints.is_empty() and ship.waypoints[0].distance_to(jobs._city(5)) < 8 and not game.submarine_traffic.route(ship.global_position,ship.waypoints[0]).is_empty(),"Prison destination connects to local navigation in water beside Aquatraz")
		var local_start: Vector3 = ship.global_position
		var prison_goal: Vector3 = ship.waypoints[0]
		for tick in range(180):
			await physics_frame
			for agent in jobs.vessels: agent.advance(1.0/60.0)
		check(ship.global_position.distance_to(local_start) > 0.5 and ship.global_position.distance_to(prison_goal) < local_start.distance_to(prison_goal),"Actual collision-enabled convoy moves toward Aquatraz while in view")
		var start: Vector3 = ship.global_position; ship.set_local_simulation(false); ship.advance_abstract(1.0)
		check(ship.global_position.distance_to(start) > 0.1,"Prison convoy follows a reachable water route toward Aquatraz")
		check(not runtime.active().is_empty() and not ship.arrival_reported,"Switching to distant simulation cannot falsely report prison arrival when its local path is cleared")
		ship.set_local_simulation(true); ship.set_physics_process(false)
		game.pilot.global_position = ship.body.global_position + Vector3.UP * (ship.bounds.end.y + 0.65)
		game.equipment.selected = game.equipment.mounted.find(game.equipment.mounted.filter(func(item: Dictionary) -> bool: return item.id == "escape")[0])
		game.equipment.toggle_selected()
		for frame in range(120): await physics_frame
		check(game.equipment.support_tools.pod_target == ship.body,"Deployed Escape Pod physically finds prison hull")
		check(game.equipment.support_tools.pod is RigidBody3D and game.equipment.current().icon_state == 2,"Escape Pod has physical collision and attached HUD state through ordinary equipment input")
		var attached_pod: RigidBody3D = game.equipment.support_tools.pod
		check(attached_pod.collision_layer == 0 and ship.body.get_collision_exceptions().has(attached_pod) and attached_pod.get_collision_exceptions().has(ship.body) and game.pilot.get_collision_exceptions().has(ship.body),"Attached pod and tethered player cannot collide with or push the prison hull")
		var observer: Node3D = game.submarine_traffic.player
		game.submarine_traffic.player = null
		var unobserved: Dictionary = game.submarine_traffic.avoidance(ship,Vector3.FORWARD)
		game.submarine_traffic.player = observer
		var tethered: Dictionary = game.submarine_traffic.avoidance(ship,Vector3.FORWARD)
		check(unobserved.direction.is_equal_approx(tethered.direction) and is_equal_approx(unobserved.speed,tethered.speed),"Prison steering ignores its attached pod's tethered player")
		var attached_start: Vector3 = ship.global_position
		var stable_heading := true
		for tick in range(90):
			game.pilot.global_position = ship.body.to_global(game.equipment.support_tools.pod_anchor) + Vector3.UP * 0.9
			var facing: Vector3 = ship.get_parent().global_basis.z.normalized()
			ship.advance(1.0/60.0)
			stable_heading = stable_heading and facing.angle_to(ship.get_parent().global_basis.z.normalized()) < 0.06
			await physics_frame
		check(ship.global_position.distance_to(attached_start) > 0.4 and stable_heading and game.equipment.support_tools.pod_target == ship.body,"Prison hull continues smoothly along its route with a live attached pod and tethered player")
		if city == 2 and DisplayServer.get_name() != "headless":
			game.camera.global_position = ship.global_position + Vector3(2,2,2)
			game.camera.look_at(ship.body.to_global(ship.bounds.get_center()))
			for frame in range(6): await process_frame
			await RenderingServer.frame_post_draw
			check(runtime.target_marker.target_point().is_finite(),"Prison marker remains visible while the physical pod is attached")
			root.get_texture().get_image().save_png("res://tests/stage-two-prison-pod.png")
		jobs._step_breakout(8)
		check(not jobs.passengers,"Transfer does not complete early")
		check(jobs.escorts.all(func(agent: Node3D) -> bool: return agent.engage_player),"Pod transfer sends all surviving escorts against the player")
		var before_break: Vector3 = game.pilot.global_position
		game.pilot.global_position = ship.body.to_global(game.equipment.support_tools.pod_anchor) + Vector3.UP * 3.5
		game.equipment.support_tools._physics_process(1.0/60.0)
		game.pilot.global_position = before_break
		check(not game.equipment.support_tools.pod_enabled and not game.equipment.current().enabled,"Broken Escape Pod tether automatically recalls equipment and clears enabled state")
		for frame in range(300): await physics_frame
		check(game.equipment.support_tools.pod_stowed,"Automatically recalled Escape Pod fully stows")
		jobs._step_breakout(0.1)
		check(not ship.body.has_meta("rescue_pod_pilot") and not game.pilot.get_collision_exceptions().has(ship.body),"Pod retrieval restores ordinary prison hull collision and avoidance")
		check(jobs.transfer == 0,"Detaching interrupts incomplete transfer")
		game.equipment.support_tools._attach_pod(game.pilot)
		check(game.equipment.support_tools.pod_target == null,"Escape Pod rejects the player's hull and non-mission targets")
		game.equipment.toggle_selected()
		for frame in range(100): await physics_frame
		check(game.equipment.support_tools.pod_target == ship.body,"Retrieved pod can deploy and physically reattach after interruption")
		jobs._step_breakout(16)
		check(jobs.passengers and game.equipment.support_tools.passengers,"Sixteen-second transfer rescues prisoners")
		check(runtime.outcome.visible and runtime.active().get("outcome_shown",false) and game.player_progress.status.credits == 100000,"Original success banner appears immediately on transfer, with city payment still pending")
		check(not runtime.target_marker.target_point().is_finite(),"Prison transport target brackets clear once passengers are rescued")
		game.equipment.toggle_selected()
		for frame in range(100): await physics_frame
		check(game.equipment.support_tools.pod_target == null and game.equipment.support_tools.passengers and game.equipment.current().icon_state == 3,"Retrieving the loaded pod preserves passengers and filled HUD state")
		var tools: Node = game.equipment.support_tools
		check(tools.pod_stowed and not tools.pod.visible and tools.pod.freeze,"Retracted loaded pod latches to the mount instead of remaining spring-followed")
		var before_motion: Transform3D = game.pilot.global_transform
		var stayed_latched := true
		for tick in range(120):
			game.pilot.global_position += Vector3(0.03,0.002,0.02)
			game.pilot.global_basis = Basis(Vector3.UP,float(tick)*0.02)
			tools._physics_process(1.0/60.0)
			stayed_latched = stayed_latched and tools.pod_stowed and not tools.pod.visible and not tools.pod_enabled and tools.passengers
		check(stayed_latched,"Loaded pod stays latched throughout sustained movement and turning")
		# Deploy/retrieve the full pod while the hull is already moving, rather
		# than only testing a stationary retrieval followed by movement.
		tools.activate("escape",true); tools.pod.global_position = tools.pod_socket() + Vector3.DOWN * 1.5
		tools.activate("escape",false)
		for tick in range(120):
			game.pilot.global_position += Vector3(0.08,0,0)
			game.pilot.global_basis = Basis(Vector3.UP,float(tick)*0.02)
			tools._physics_process(1.0/60.0)
		check(tools.pod_stowed and not tools.pod.visible and tools.passengers,"Winch fully retrieves a loaded pod while the hull moves and turns at cruising speed")
		game.pilot.global_transform = before_motion
		runtime.outcome.dismiss()
		runtime.docked(6); check(not runtime.can_save(),"Factory docking cannot complete prisoner rescue")
		runtime.docked(city)
		check(not runtime.outcome.visible,"City reward/debrief does not replay the transfer success banner")
		check(runtime.can_save() and game.player_progress.status.credits == 103500,"Returning prisoners to either Procha city pays 3500")
		check(not runtime.last_response.contains("#bulletin"),"Debrief excludes following news bulletin source text")
		var snapshot: Dictionary = game._save_snapshot("After prisoners")
		var save_error: Error = game.save_games.write(0,snapshot)
		check(save_error == OK,"Saving resumes with resolved mission history: " + game.save_games.error)
		var saved: Dictionary = game.save_games.read(0)
		check(not saved.is_empty() and Progress.restore(saved.get("progress",{})).missions.completed.has("breakout" if city == 2 else "breakout2"),"Resolved variant and exclusion survive save data round-trip")
		await process_frame
		check(game.submarine_traffic.traders.size() == original_npcs,"Prison convoy cleaned after resolution")
	fresh(); port(2); runtime.accept(2); jobs._prison_arrived()
	check(runtime.can_save() and not game.player_progress.missions.completed.breakout.success,"Reaching Aquatraz before rescue fails")
	check(game.bounty_radio_queue.any(func(message: Dictionary) -> bool: return message.get("terminal",false)),"Final mission transmission survives actor cleanup")
	await process_frame
	fresh(); port(2); runtime.accept(2)
	jobs.target.take_weapon_damage_from(10000,game.pilot.global_position,game.pilot)
	check(runtime.can_save() and not game.player_progress.missions.completed.breakout.success,"Prison transport destruction before transfer fails and clears the mission")
	await process_frame
	fresh(); port(2); runtime.accept(2); jobs.passengers = true; runtime.docked(1)
	check(game.player_progress.missions.completed.breakout.success and game.player_progress.missions.completed.breakout.score == 0.5 and game.player_progress.status.credits == 103500,"Alternate Bohine prisoner return retains original rescue success, score and fixed reward")
	await process_frame
	fresh(); port(3); runtime.accept(3)
	check(jobs.target != null and jobs.target.loop_route and jobs.target.waypoints.size() == 2,"Covert scout uses recovered two-way route")
	check(runtime.target_marker.target_body() == jobs.target.body,"Big Ears mission assigns the scout its green world HUD target")
	check(not game.submarine_traffic.route(jobs.target.global_position,jobs.target.waypoints[0]).is_empty(),"Both covert patrol endpoints connect through navigable water")
	check(not jobs.attach_listening_device(game.pilot),"Tagging wrong actor does not advance objective")
	for agent in jobs.vessels: agent.set_physics_process(false)
	game.equipment.set_installed(["deep_sea_lights","bigears"])
	game.equipment.selected = 1
	var tool_display: Control = game.cockpit_hud.displays[1]
	check(tool_display.equipment_count() == 5 and tool_display.equipment_icon_index(game.equipment.current()) == 0,"Unattached Big Ears displays original LISTEN1 and a 05 ammunition counter")
	await capture("covert")
	game.pilot.global_position = jobs.target.body.global_position - Vector3(0,0,1.0)
	game.pilot.global_basis = Basis.looking_at(Vector3.BACK)
	game.equipment.support_tools.fire_listening()
	for frame in range(45): await physics_frame
	check(jobs.tapped and jobs.phase == "listen","Big Ears projectile attaches to the scout and starts interception")
	check(game.player_progress.ammunition.bigears == 4,"Listening shot consumes one of five probes")
	check(tool_display.equipment_count() == 4,"Big Ears HUD counter follows ammunition after firing")
	var listening_tools: Node = game.equipment.support_tools
	var probe: RigidBody3D = listening_tools.projectiles.back()
	check(probe.attached and probe.get_parent() == jobs.target.body and probe.freeze and probe.collision_layer == 0,"A physical Big Ears probe stays latched to its designated moving scout without pushing it")
	listening_tools._physics_process(0.01)
	check(game.equipment.available.any(func(item: Dictionary) -> bool: return item.id == "bigears" and item.get("icon_state",0) == 1),"Attached probe switches Big Ears to its original second HUD icon")
	check(tool_display.equipment_icon_index(game.equipment.current()) == 1,"Attached Big Ears actually renders LISTEN2 rather than using its momentary fire button state")
	game.pilot.global_position += Vector3(30,0,0)
	for frame in range(4): jobs._step_covert(8)
	check(jobs.vents.size() == 3,"Intercept reveals three base vents")
	for base_vent in jobs.vents:
		base_vent.set_process(false); base_vent.open = true; base_vent._process(0.5)
		check(base_vent.door_meshes.size() > 0 and base_vent.door.transform.is_equal_approx(base_vent.shut_pose),"Original vent uses its mesh opening animation without translating vertically")
		check(base_vent.door_meshes.all(func(mesh: MeshInstance3D) -> bool: return is_zero_approx(mesh.get_blend_shape_value(0))),"Vent reaches its original open base pose")
		base_vent.open = false; base_vent._process(0.5)
		check(base_vent.door_meshes.all(func(mesh: MeshInstance3D) -> bool: return is_equal_approx(mesh.get_blend_shape_value(0),1.0)),"Vent closes by bringing the morphed leaves together")
		base_vent.set_process(true)
	check(runtime.target_marker.target_body() == jobs.vents[0],"Green target transfers from the scout to the revealed base objective")
	check(jobs.actors.filter(func(actor: Node) -> bool: return actor.get_node_or_null("SceneryCollision") is StaticBody3D).size() == 3,"Revealed military installations have solid scenery collision")
	check(jobs.dialogue == 4 and not jobs.interception_instruction,"Original fourth line reveals the base at 800 ticks without the final instruction")
	jobs._step_covert(8)
	check(jobs.dialogue == 5 and not jobs.interception_instruction,"Fifth intercepted line plays at 1000 ticks; AF12 still waits")
	jobs._step_covert(7.99)
	check(not jobs.interception_instruction,"Final interception instruction does not play before tick 1200")
	jobs._step_covert(0.01)
	check(jobs.phase == "base","Full interception reaches base attack phase")
	check(jobs.interception_instruction and is_equal_approx(jobs.transfer,48.0),"AF12 plays at 48 seconds, 400 ticks after base reveal, without double-advancing the clock")
	for shot in range(3): listening_tools.fire_listening()
	check(tool_display.equipment_count() == 1,"Big Ears HUD shows the last remaining probe")
	listening_tools.fire_listening()
	check(game.player_progress.ammunition.bigears == 0 and not game.equipment.mounted.any(func(item: Dictionary) -> bool: return item.id == "bigears"),"Fifth shot removes the spent launcher but preserves the deployed probes")
	check(is_instance_valid(probe) and probe.attached and listening_tools.projectiles.size() == 5,"Exhausting ammunition does not delete attached or flying devices")
	check(tool_display.equipment_count() == -1,"Counter clears when the exhausted launcher is removed and another tool is selected")
	game.pilot.global_position = jobs.target.global_position + jobs.target.get_parent().global_basis.z.normalized()
	jobs.warned = true; jobs.clock = 0; jobs._step_covert(0)
	check(jobs.reinforcements and jobs.vessels.size() == 5 and not runtime.can_save(),"Being spotted after revealing the base summons four defenders rather than failing")
	for agent in jobs.vessels: agent.set_physics_process(false)
	var vent: Node3D = jobs.vents[0]
	game.player_progress.hold.depth = 0
	game.pilot.global_position = jobs.base_poses[0].origin + Vector3.UP * 2; jobs._step_covert(0)
	check(jobs.base_guidance,"Approaching the base explains the depth-charge objective")
	check(is_equal_approx(jobs.base_instruction_clock,6.0) and game.bounty_radio_queue.back().text == game.gameplay_catalogue.tables.radio_messages.records.af15.text,"Base arrival plays AF15 without immediately replacing its speech with the vent instruction")
	game.pilot.global_position = jobs.base_poses[0].origin + Vector3(0,20,0)
	jobs._step_covert(5.99)
	check(jobs.base_instruction_clock > 0.0,"Vent instruction preserves the original six-second delay")
	jobs._step_covert(0.02)
	check(jobs.base_instruction_clock < 0.0 and game.bounty_radio_queue.back().text == game.gameplay_catalogue.tables.radio_messages.records.af16.text,"Delayed missing-ammunition speech plays even after leaving the base trigger")
	await capture("base",vent)
	vent.open = false; vent.take_weapon_damage(10000); vent.depth_charge(3)
	check(not vent.dead,"Armour and closed vents reject direct fire and depth charges")
	vent.open = true
	vent._process(0.6)
	game.player_progress.hold.depth = 1; game.weapons.set_installed(["zapper","depthl"]); game.weapons.selected = 1
	game.pilot.active = true; game.pilot.controls_enabled = true
	game.pilot.global_position = vent.global_position + Vector3(0,0.3,-0.35); game.pilot.global_basis = Basis.IDENTITY
	game.pilot.linear_velocity = Vector3.ZERO
	game.weapons.update_fire(true,0.02)
	check(not game.player_progress.hold.has("depth") and not game.weapons.firing,"Weapon fire drops a charge, consumes ammo and leaves zapper off")
	check(game.equipment.support_tools.projectiles.back().process_mode == Node.PROCESS_MODE_PAUSABLE,"Support projectiles pause during menus and docking")
	for frame in range(100): await physics_frame
	check(vent.health < 1.5,"Actual falling depth charge enters the open hatch and damages its internal target")
	game.pilot.global_transform = Transform3D(Basis.IDENTITY,vent.global_position + Vector3(0,0.3,-0.35)); game.pilot.linear_velocity = Vector3.ZERO
	game.pilot.active = true; game.pilot.controls_enabled = true; game.weapons.selected = 1
	vent.open = true; vent._process(0.6)
	game.player_progress.hold.depth = 1; game.equipment.support_tools.depth_cooldown = 0
	game.weapons.update_fire(true,0.02)
	check(not game.player_progress.hold.has("depth"),"A second launcher shot consumes the next charge")
	for frame in range(100): await physics_frame
	check(vent.dead,"A further charge finishes the damaged internal target")
	var base_models: Array[Node3D] = []
	for defence in jobs.base_defences: base_models.append(defence.model)
	for other in jobs.vents:
		if not other.dead: other.open = true; other.depth_charge(3)
	jobs._step_covert(0)
	check(runtime.can_save() and game.player_progress.status.credits == 105000,"Destroying all three vents completes covert operation for 5000 credits")
	check(runtime.target_marker.target_body() == null,"Completed covert mission clears its green HUD target")
	var demolition := get_first_node_in_group("base_destruction")
	check(demolition != null and base_models.all(func(model: Node3D) -> bool: return is_instance_valid(model) and model.visible and not model.is_queued_for_deletion()),"Completed mission preserves buildings for staged demolition instead of immediately deleting them")
	if demolition != null:
		demolition.set_process(false)
		var first_bursts: int = demolition.explosions
		demolition._process(1.0)
		check(demolition.explosions > first_bursts and demolition.wrecks == 0 and base_models.all(func(model: Node3D) -> bool: return model.visible),"Explosions build across all buildings while their structures remain visible")
		if DisplayServer.get_name() != "headless":
			var focus := base_models[0].global_position + Vector3.UP
			game.camera.global_position = focus + Vector3(5,4,5); game.camera.look_at(focus); game.camera.make_current()
			for frame in range(6): await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tests/stage-two-base-demolition.png")
		demolition._process(1.5)
		check(demolition.explosions == 21 and demolition.wrecks == 3 and demolition.is_queued_for_deletion(),"Demolition finishes after roughly two seconds with seven bursts and submarine-style wreckage per building")
	await process_frame
	check(base_models.all(func(model: Variant) -> bool: return not is_instance_valid(model)),"Demolition removes its original building meshes after fragmentation")
	fresh(); port(3); runtime.accept(3)
	game.pilot.global_position = jobs.target.global_position + jobs.target.get_parent().global_basis.z.normalized() * 1.0
	jobs.clock = 0; jobs._step_covert(0); jobs.clock = 0; jobs._step_covert(0)
	check(runtime.can_save() and not game.player_progress.missions.completed.spytrad2.success,"Repeated clear sight by scout fails covert mission")
	check(game.player_progress.campaign_stage == 2,"Side missions do not accidentally advance the core campaign")
	await process_frame
	fresh(); port(3); runtime.accept(3)
	game.pilot.global_position = jobs.target.global_position + Vector3(30,0,0)
	jobs.attach_listening_device(jobs.target.body); jobs._step_covert(32)
	jobs.target.take_weapon_damage(1000)
	check(not runtime.can_save() and jobs.interception_cancelled and jobs.vents.size() == 3,"Losing the scout after base reveal cancels interception without failing the base objective")
	jobs._step_covert(16)
	check(jobs.dialogue == 4 and jobs.interception_instruction and jobs.phase == "base","Scout loss cancels the remaining intercepted line but preserves the separately scheduled final instruction")
	fresh(); await process_frame
	check(game.submarine_traffic.traders.size() == original_npcs,"All mission boats removed after failure")
	var beta := Progress.restore({"campaign_stage":2,"missions":{"version":1,"active":{},"completed":{"tradetrad":{"success":true,"city":1}}}})
	check(Rules.next_offer(beta,1) == "stranded" and beta.ammunition.bigears == 5,"Published-beta post-opening save gains stage-two offers without migration loss")
	game.queue_free(); await process_frame
	print("Stage-two missions: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
