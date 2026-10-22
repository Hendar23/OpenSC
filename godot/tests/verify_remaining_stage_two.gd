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
			check(mission.rescuer.global_position.distance_to(departure) <= 0.9,"Faster distant rescue ship travels instead of teleporting to its host")
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
			mission.creature.set_physics_process(false)
			check(mission.eel_helpers.size() == 3 and jobs.vessels.size() == 3,"Three Bohine helpers exist from acceptance, before the approach trigger")
			var waiting: Array[Vector3] = []
			for helper in mission.eel_helpers:
				waiting.append(helper.global_position); helper.advance_abstract(1.0)
			check(mission.eel_helpers.all(func(helper: Node3D) -> bool: return not helper.running and helper.global_position == waiting[mission.eel_helpers.find(helper)]),"Helpers remain stationary before the player approaches")
			game.pilot.global_position = mission.structure.global_position+Vector3.RIGHT*30
			mission.step(8.1)
			check(not mission.flags.get("help",false),"Elapsed time alone does not activate distant helpers")
			game.pilot.global_position = mission.structure.global_position+Vector3.UP*4
			mission.step(0.1)
			check(jobs.vessels.size() == 3 and mission.eel_helpers.all(func(helper: Node3D) -> bool: return helper.running and not helper.waypoints.is_empty()),"Approach activates the same three ships without spawning replacements")
			check(mission.creature.get_child(1).get_meta("asset_source","").to_upper().contains("MEEL"),"First eel uses MEEL rather than a draft marker")
			check(not jobs.can_attach_pod(mission.structure),"Miners refuse rescue while the monster is alive")
			mission.creature.take_weapon_damage(1000,mission.creature.global_position)
			mission.step(6.1)
			check(is_instance_valid(mission.creature) and not mission.creature.dead,"Larger second eel appears after six seconds")
			var giant: Node3D = mission.creature
			giant.set_physics_process(false)
			check(giant.giant_eel and giant.collision_mask == 0 and giant.collision_layer == 8,"Real giant uses its original non-solid controller while remaining hittable")
			giant.global_position = giant.home+Vector3.RIGHT*10; giant.direction = Vector3.LEFT
			game.pilot.global_position = giant.home+Vector3.RIGHT*30
			var before: float = giant.global_position.distance_to(giant.home)
			giant._physics_process(1.0)
			check(giant.global_position.distance_to(giant.home) < before,"Giant actively approaches the mine rather than roaming at the ambush point")
			giant.global_position = giant.home+Vector3.RIGHT*3; giant.direction = Vector3.FORWARD
			game.pilot.global_position = giant.global_position+Vector3.FORWARD*0.5
			game.pilot.restore_health(); game.pilot.hull_rating = 100
			giant._physics_process(0.2)
			check(is_equal_approx(game.pilot.health,94.75),"Giant close-range attack applies recovered 0.3 raw strength per 25 Hz tick")
			check(is_equal_approx(giant.velocity.length(),1.5),"Giant doubles its speed when pursuing the nearby player")
			giant.velocity = Vector3.ZERO
			check(giant.submarine_contact_damage(Vector3.RIGHT*0.1,Vector3.LEFT) == 0,"Gentle brushing against giant eel causes no impact damage")
			check(is_equal_approx(giant.submarine_contact_damage(Vector3.RIGHT*2,Vector3.LEFT),10),"Giant eel collision damage scales with relative closing speed")
			check(giant.submarine_contact_damage(Vector3.RIGHT*2,Vector3.LEFT) == 0,"One bump cannot damage the player repeatedly each frame")
			giant.giant_impact_cooldown = 0
			check(giant.submarine_contact_damage(Vector3.LEFT*2,Vector3.LEFT) == 0,"Moving away from the giant eel cannot count as a damaging impact")
			check(giant.submarine_contact_damage(Vector3.RIGHT*20,Vector3.LEFT) == 20,"High-speed eel impact damage is capped")
			check(giant.death_flesh_texture != null and giant.death_flesh_texture == game.wildlife.death_flesh_texture,"Mission eel inherits the wildlife flesh texture")
			await capture("huge-eel")
			mission.creature.take_weapon_damage(1000,mission.creature.global_position)
			var chunks: Node3D = game.world_root.get_child(game.world_root.get_child_count()-1)
			check(chunks is CreatureDeath and not chunks.pieces.is_empty() and chunks.pieces.all(func(piece: Dictionary) -> bool: return piece.material is ShaderMaterial and piece.material.get_shader_parameter("has_backface_texture") == true and piece.material.get_shader_parameter("backface_texture") == game.wildlife.death_flesh_texture),"Every actual giant-eel death fragment has flesh on its reverse side")
			check(giant.death_particle_scale > 1 and not chunks.gore.is_empty() and not chunks.gore_frames.is_empty(),"Giant eel death emits original gore particles scaled for its larger body")
			check(chunks.gore.any(func(particle: Dictionary) -> bool: return particle.node.position.length() > 0.2),"Large eel gore starts across its skin instead of hidden inside centre chunks")
			check(chunks.bubbles != null and chunks.bubbles.emitting and chunks.bubbles.amount > 24,"Giant eel also produces a larger bubble burst")
			if DisplayServer.get_name() != "headless":
				for frame in range(3): await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://tests/remaining-eel-particles.png")
			check(jobs.can_attach_pod(mission.structure),"Escape Pod accepts mine after the second eel dies")
			game.equipment.set_installed(["escape"])
			var tools: Node3D = game.equipment.support_tools
			game.pilot.global_position = mission.structure.global_position+Vector3.UP
			tools.activate("escape",true); tools.pod_deployment = 0.6
			tools.pod.global_position = mission.structure.global_position+Vector3.UP*0.5
			tools._attach_pod(mission.structure)
			check(tools.pod_target == mission.structure and tools.pod_attached,"Physical Escape Pod seats on the mine hull through the real equipment contact handler")
			var rescued_mine: Node3D = mission.structure
			mission.step(12)
			check(not runtime.active().is_empty() and game.player_progress.status.credits == 100000 and not runtime.can_save(),"Miners boarding keeps rescue active and unpaid until docking")
			tools._physics_process(1.0)
			check(tools.passengers and not tools.pod_attached and game.equipment.available.any(func(item: Dictionary) -> bool: return item.id == "escape" and item.icon_state == 3),"Miners stay aboard and the Escape Pod HUD remains loaded while reeling in")
			check(is_instance_valid(rescued_mine) and rescued_mine.is_visible_in_tree(),"Rescued mine remains visible during return phase")
			var demolition: Node3D = rescued_mine.get_parent()
			demolition.set_process(false); demolition.age = 0
			demolition._process(2.9)
			check(demolition.explosions == 0 and rescued_mine.collision_layer != 0,"Intact mine and collision survive the three-second delay")
			demolition._process(0.2)
			check(demolition.explosions > 0 and rescued_mine.collision_layer == 0,"Mine starts exploding after the delay and stops blocking the player")
			demolition._process(2.2)
			check(demolition.explosions == 7 and demolition.wrecks == 1 and game.player_progress.status.credits == 100000,"Mine has six staged bursts and final collapse without prematurely paying reward")
			await physics_frame; await physics_frame
			mission.step(20); tools._physics_process(1.0)
			check(not runtime.active().is_empty() and tools.passengers,"Miners stay aboard after the demolished mine is gone")
			jobs.docked(3)
			check(runtime.active().is_empty() and game.player_progress.status.credits == 105000 and not tools.passengers,"Docking completes the rescue, pays once and unloads miners")
			jobs.docked(3)
			check(game.player_progress.status.credits == 105000,"Repeated dock notification cannot duplicate the rescue reward")
		elif id == "recontech":
			var mission: RefCounted = jobs.remaining
			var preplaced: Array = mission.recon_reinforcements.duplicate()
			var waiting_poses: Array[Transform3D] = []
			var vessel_count: int = jobs.vessels.size()
			check(preplaced.size() == 3 and vessel_count == 4,"All three Recon reinforcements exist with the initial guard at mission start")
			for index in preplaced.size():
				var agent: Node3D = preplaced[index]
				check(agent.get_parent().get_meta("editor_model") == ("TRAD2" if index == 0 else "TRAD-SUB"),"Preplaced reinforcement retains original model")
				var waiting_pose: Transform3D = agent.get_parent().global_transform
				waiting_poses.append(waiting_pose)
				check(waiting_pose.origin.distance_to(mission.poses[index].origin) < 8 and agent.home.is_equal_approx(waiting_pose),"Reinforcement uses original placement with normal hull clearance")
				agent.set_local_simulation(true); agent._physics_process(1.0)
				agent.local_simulation = false; agent.advance_abstract(1.0)
				agent.set_physics_process(false)
				check(agent.dormant and not agent.combat_enabled and agent.get_parent().global_transform.is_equal_approx(waiting_pose),"Dormant reinforcement stays still in local and offscreen simulation")
			check(mission.turrets.size() == 3,"Cave outpost has three destructible turrets")
			var mines: Array = jobs.actors.filter(func(actor: Node) -> bool: return actor is Mine)
			check(mines.is_empty(),"Unused ObjectID 3 rows do not add mines omitted by the released mission callback")
			check(is_instance_valid(mission.recon_cable) and mission.recon_cable.visible and mission.recon_cable.get_meta("exclude_from_debris",false),"Initial guard has the original outpost cable without making it debris")
			check(jobs.actors.any(func(actor: Node) -> bool: return actor.get_node_or_null("Beacon_Recon") != null),"ObjectID 4 creates the original pulse light rather than another cone")
			game.pilot.global_position = mission.structure.global_position+Vector3.RIGHT*30
			mission.step(8.1)
			check(not mission.flags.get("greeted",false) and not mission.flags.get("alarm",false),"Time alone does not announce or alarm the hidden cave outpost")
			game.pilot.global_position = mission.structure.global_position+Vector3.RIGHT*10
			mission.step(2.1)
			check(mission.flags.get("greeted",false) and not mission.flags.get("alarm",false),"Close first approach plays warning before triggering defenders")
			game.pilot.global_position = mission.structure.global_position+Vector3.RIGHT*30
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
				check(runtime.target_marker.target_point().is_finite(),"Green outpost target square projects through the active ROV camera")
				for frame in range(5): await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://tests/remaining-rov-view.png")
			mission.step(10.1)
			check(mission.flags.get("recorded",false) and mission.enemies.size() == 4,"Confirmed footage triggers original three reinforcements")
			check(jobs.vessels.size() == vessel_count and preplaced.all(func(agent: Node3D) -> bool: return mission.enemies.has(agent) and not agent.dormant and agent.running and agent.combat_enabled),"Alarm activates the exact preplaced ships without spawning replacements")
			for index in preplaced.size():
				check(preplaced[index].get_parent().global_transform.is_equal_approx(waiting_poses[index]),"Alarm does not teleport the waiting reinforcement")
			mission._recon_alarm()
			check(jobs.vessels.size() == vessel_count and mission.enemies.size() == 4,"Repeated Recon alarm cannot duplicate the wave")
			check(not is_instance_valid(mission.recon_cable) and mission.enemies.all(func(agent: Node3D) -> bool: return agent.engage_player and agent.pursue_offscreen),"Alarm releases guard cable and makes all four ships pursue the player")
			# The source wave targets the main submarine outside the cave, not
			# the remotely piloted ROV beside the underground outpost.
			game.pilot.global_position = Vector3(326,154,266)
			game.pilot.pending_reset = false; game.pilot.restore_health(10000)
			rov.set_physics_process(false)
			var attackers: Array = mission.enemies.slice(1)
			var fired := {}
			var hit_player := false
			for agent: Node3D in attackers: agent.set_local_simulation(true)
			for frame in range(1200):
				game.pilot.active = true; game.pilot.controls_enabled = true; game.pilot.restore_health(1000000)
				await physics_frame
				hit_player = hit_player or game.pilot.health < game.pilot.max_health
				for missile in get_nodes_in_group("turret_missiles"):
					if attackers.has(missile.source): fired[missile.source] = true
				if fired.size() == 3 and hit_player: break
			if fired.size() != 3:
				for agent: Node3D in attackers:
					print("Recon combat: ",agent.get_parent().get_meta("editor_model")," at ",agent.global_position," fired=",fired.has(agent)," dead=",agent.dead," dormant=",agent.dormant," running=",agent.running," local=",agent.local_simulation," processing=",agent.is_physics_processing()," path=",agent.path)
			check(fired.size() == 3,"All three original reinforcement ships engage and fire at the main sub at the cave approach")
			check(hit_player,"Reinforcement projectiles can hit the parked player while the ROV is controlled")
			for agent: Node3D in attackers: agent.set_physics_process(false)
			jobs.docked(2)
			check(runtime.active().is_empty() and game.player_progress.status.credits == 105000,"Recorded footage succeeds on returning to city")
			check(mission.enemies.is_empty() and game.submarine_traffic.traders.any(func(agent: Node3D) -> bool: return agent.has_meta("fishing_survivor") and agent.engage_player),"Live recon attackers persist after resolution with independent behavior")
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
	var attacked_recon: RefCounted = jobs.remaining
	game.pilot.global_position = attacked_recon.structure.global_position+Vector3.RIGHT*30
	attacked_recon.structure.take_weapon_damage(1)
	check(attacked_recon.flags.get("attacked",false) and not attacked_recon.flags.get("alarm",false) and attacked_recon.ship.engage_player and not is_instance_valid(attacked_recon.recon_cable),"Damaging distant outpost releases its guard but does not invent an immediate reinforcement wave")
	var passive_survivors: Array = attacked_recon.recon_reinforcements.duplicate()
	jobs.docked(4)
	check(runtime.active().is_empty() and game.player_progress.missions.completed.recontech2.score == 0 and runtime.last_response == runtime.text("recontech2",3),"Returning after attacking without footage gives original propaganda response and no reward")
	check(passive_survivors.all(func(agent: Node3D) -> bool: return is_instance_valid(agent) and agent.has_meta("fishing_survivor") and not agent.dormant and agent.running and agent.combat_enabled and not agent.engage_player),"Unalarmed preplaced ships survive early resolution as independent passive ships")
	await fresh("recontech2")
	var ambushed_recon: RefCounted = jobs.remaining
	var lost_reinforcement: Node3D = ambushed_recon.recon_reinforcements[0]
	lost_reinforcement.set_local_simulation(true)
	lost_reinforcement.take_weapon_damage_from(1000,lost_reinforcement.global_position,game.pilot)
	check(lost_reinforcement.dead,"Preplaced dormant reinforcement remains vulnerable to weapons")
	game.pilot.global_position = ambushed_recon.structure.global_position+Vector3.RIGHT*10
	ambushed_recon.step(8.1); ambushed_recon.step(2.1); ambushed_recon.step(0.5)
	check(ambushed_recon.flags.get("alarm",false) and jobs.vessels.size() == 4 and lost_reinforcement.dead and ambushed_recon.recon_reinforcements.filter(func(agent: Node3D) -> bool: return not agent.dead and not agent.dormant and agent.engage_player).size() == 2,"Proximity alarm activates surviving preplaced ships without replacing a destroyed defender")
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
