extends "res://tests/test_scene_tree.gd"
const Traffic = preload("res://submarine_traffic.gd")
const Access = preload("res://dock_access.gd")
const Document = preload("res://map_document.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-traffic-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	var config := ConfigFile.new(); config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")
func run() -> void:
	var game = preload("res://game.gd").new(); game.remember_preferences = false; game.show_start_menu = true; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Full game loads with civilian submarine traffic")
	if not game.startup_complete: quit(1); return
	game.front_end.hide_menu(); paused = false
	var traffic: Node = game.submarine_traffic
	# This fixture exercises detailed journeys manually, independently of visibility.
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	for vessel in traffic.traders: vessel.set_local_simulation(true)
	await physics_frame
	traffic.set_physics_process(false)
	game.wildlife.set_simulating(false)
	# This manual reaction fixture needs detailed wildlife even with its player
	# parked far away; distance streaming deliberately suppresses such reactions.
	game.wildlife.streaming = false
	for creature in game.wildlife.get_children():
		if creature is CollisionObject3D: creature.collision_layer = 0
	game.pilot.active = false; game.pilot.controls_enabled = false
	game.pilot.global_position = Vector3(250,160,250)
	for agent in traffic.traders: agent.set_physics_process(false)
	traffic.roaming_population.set_physics_process(false)
	for vessel in traffic.roaming_population.ships: vessel.running = false
	var civilians: Array = traffic.traders.filter(func(vessel: Node3D) -> bool: return not vessel.has_method("configure_resources"))
	check(civilians.size() == 6,"Six civilian submarines spawn")
	check(traffic.graph.get_point_count() > 1000 and traffic.navigation_ready,"Shared water routes finish before loading completes")
	check(traffic.destinations(1) == [1,3,6] and traffic.destinations(2) == [2,4,6],"Own faction and Factory only; Aquatraz excluded")
	for agent in civilians:
		check(traffic.water_clear(agent.home.origin),"Trader starts in clear water: " + str(agent.get_parent().name))
		check(agent.health.remaining == 10 and agent.tuning.npc_sustain == 0.3,"Recovered civilian shield and sustain values")
		check(agent.body.is_in_group("npc_submarines") and preload("res://wildlife_combat.gd").alive(agent.body),"Wildlife can discover and attack each civilian sub")
	for faction in [1,2]:
		for first in traffic.destinations(faction):
			for last in traffic.destinations(faction):
				if first == last: continue
				var a: Dictionary = traffic.port_by_id(first); var b: Dictionary = traffic.port_by_id(last)
				var path: PackedVector3Array = traffic.route(a.entry,b.entry)
				check(not path.is_empty(),"Route exists %d to %d" % [first,last])
				var previous: Vector3 = a.entry
				var clear := true
				for point in path:
					clear = clear and traffic.segment_clear(previous,point); previous = point
				check(clear,"Entire route clears terrain and buildings %d to %d" % [first,last])
	var agent: Node3D = civilians[0]; var second: Node3D = civilians[1]
	var port: Dictionary = traffic.port_by_id(1)
	agent.get_parent().global_position = port.entry; agent.destination = 1; agent.wait = 0; agent.advance(0.1)
	check(agent.stage == "open" and Access.owner(port) == agent,"Arriving trader reserves the entrance")
	check(agent.dock_audio.players.sequence is AudioStreamPlayer3D and agent.dock_audio.players.sequence.playing,"NPC docking warning plays spatially")
	check(agent.dock_audio.spatial_origin == port.node and agent.dock_audio.sources.sequence.get_meta("asset_source") == game.docking.audio.sources.sequence.get_meta("asset_source"),"NPC warning uses the player docking sample at the dock")
	second.get_parent().global_position = port.entry + Vector3.RIGHT * 0.01; second.destination = 1; second.wait = 0; second.advance(0.1)
	check(second.stage == "travel" and Access.owner(port) == agent,"A second trader waits without stealing the entrance")
	game.pilot.global_position = port.entry; game.pilot.velocity = Vector3.ZERO
	game.docking.update_approach()
	check(game.docking.message.contains("currently in use") and not game.docking.request_docking(),"Player receives busy message and cannot enter an occupied dock")
	var saved: Dictionary = traffic.snapshot()
	check(Traffic.valid_snapshot(saved),"Traffic state validates while a trader opens the dock")
	traffic.restore(saved)
	check(Access.owner(port) == agent and agent.stage == "open","Restore reconstructs the entrance owner")
	for tick in range(120): agent.advance(0.1)
	check(agent.stage == "berth" and not agent.get_parent().visible,"Trader disappears only after entering and closing the hatch")
	check(Access.owner(port) == null and port.collision.collision_layer == 1,"Internal berths free the entrance and close its collision")
	check(not agent.dock_audio.players.sequence.playing and agent.dock_audio.players.door_stop.playing,"NPC warning stops once docked and door completion plays")
	saved = traffic.snapshot(); traffic.reset(); traffic.restore(saved)
	check(agent.stage == "berth" and Access.owner(port) == null,"Saved internal berth does not reserve the entrance")
	# A player can use an entrance while the civilian is parked inside.
	game.pilot.global_position = port.entry; game.pilot.velocity = Vector3.ZERO; game.pilot.angular_velocity = Vector3.ZERO
	check(game.docking.request_docking() and Access.owner(port) == game.docking,"Player can enter while NPC occupies an internal berth")
	agent.wait = 0; agent.advance(0.1)
	check(agent.stage == "berth","Departing trader waits for player transit")
	game.docking.cancel(); check(Access.owner(port) == null,"Cancelled player docking releases the entrance")
	agent.advance(0.1)
	check(agent.stage == "berth" and Access.owner(port) == null,"NPC still waits when the player is above the hatch without reserving it")
	game.pilot.global_position = port.entry+Vector3.RIGHT*5
	await physics_frame; await physics_frame
	agent.advance(0.3); check(agent.stage == "exit_open","Parked trader reserves the entrance to leave once the player hull is clear")
	saved = traffic.snapshot(); traffic.reset(); traffic.restore(saved)
	check(agent.stage == "exit_open" and Access.owner(port) == agent,"Exit transit restores its reservation")
	for tick in range(120): agent.advance(0.1)
	check(agent.stage == "travel" and Access.owner(port) == null and agent.body.collision_layer == 10,"Completed exit frees the entrance and restores hull collision")
	traffic.reset()
	var fish := preload("res://fish_controller.gd").new()
	fish.setup(Node3D.new(),agent.global_position + Vector3.FORWARD * 0.9,game.cockpit_hud.map_data.bounds,game.pilot.surface_height,0.2,42)
	fish.configure_combat({"food_role":"neutral","has_zapper":false}); fish.population = game.wildlife
	game.wildlife.add_child(fish); fish.set_physics_process(false); fish.response = "attack"; fish.swim_speed = 0
	fish.direction = Vector3.BACK; fish.combat.target = agent.body
	await physics_frame; await physics_frame
	var before_health: float = agent.health.remaining
	fish.combat.attack(0.1)
	check(agent.health.remaining < before_health and agent.flee > 0,"Wildlife bites a civilian submarine and makes it flee")
	check(is_equal_approx(before_health - agent.health.remaining,0.5),"Wildlife bite points convert to raw civilian shields once")
	fish.response = "flee"; fish.startle_timer = 0; fish.startle_cooldown = 0
	fish._physics_process(0.1)
	check(fish.fleeing,"Prey flees civilian submarines using its flee range")
	fish.free(); traffic.reset(); agent.wait = 0; agent.take_weapon_damage(1,agent.global_position - Vector3.RIGHT)
	check(agent.flee > 0 and is_equal_approx(agent.health.remaining,9.7),"Unarmed trader flees damage with original sustain")
	agent.take_weapon_damage(100)
	check(agent.dead and not agent.get_parent().visible and agent.body.collision_layer == 0,"Destroyed trader cannot travel or collide")
	var wrecks := get_nodes_in_group("trader_wrecks")
	check(wrecks.size() == 1 and wrecks[0].pieces.size() > 0 and wrecks[0].bubbles.amount == 96,"Civilian destruction produces submarine fragments and bubbles")
	var malformed: Dictionary = traffic.snapshot(); malformed.values()[0].destination = 5
	check(not Traffic.valid_snapshot(malformed),"Aquatraz destinations rejected from saved traffic")
	malformed = traffic.snapshot(); malformed.values()[0].pose[0] = NAN
	check(not Traffic.valid_snapshot(malformed),"Non-finite poses rejected")
	traffic.reset()
	game.docking.stage = game.Docking.Stage.DOCKED; game.docking.current = port
	Access.acquire(port,second)
	check(not game.docking.request_docking() and game.docking.launch_pending,"Player launch waits when an NPC owns the entrance")
	Access.release(port,second); game.docking._physics_process(0.01)
	check(game.docking.stage == game.Docking.Stage.EXIT_OPEN and not game.docking.launch_pending,"Waiting player launch begins automatically once the entrance is free")
	game.docking.cancel()
	game.pilot.global_position = Vector3(250,160,250)
	# Only civilians advance in this route fixture; frozen actors must not block them.
	for vessel in traffic.traders:
		if not civilians.has(vessel): vessel.body.collision_layer = 0
	for vessel in traffic.roaming_population.ships: vessel.body.collision_layer = 0
	for tick in range(4000):
		for ship in civilians: ship.advance(0.1)
		if tick % 20 == 0: await physics_frame
	for ship in civilians:
		print("Trader ",ship.get_parent().name," visits=",ship.journey_count," stage=",ship.stage," position=",ship.global_position," destination=",ship.destination," obstacle=",ship.last_obstacle)
		check(ship.journey_count >= 2,"Trader completes repeated dock visits: " + str(ship.get_parent().name))
	check(Traffic.valid_snapshot(traffic.snapshot()),"Journey state remains saveable after repeated visits")
	traffic.set_simulating(false); var pose: Transform3D = agent.get_parent().global_transform; agent._physics_process(1)
	check(agent.get_parent().global_transform == pose,"Editor simulation toggle stops traders")
	check(Document.valid(Document.load_active(false)),"Authored shared NPC templates and instances validate")
	var asset_folder: String = game.game_folder
	game.free(); await process_frame
	var editor := preload("res://map_editor.gd").new(); root.add_child(editor)
	await editor.open(asset_folder)
	check(editor.loaded and editor.submarine_traffic == null,"Editor loads traders without building unused simulation routes")
	editor.category.select(7); editor._refresh_list()
	check(editor.list_keys.has("npc_type:bohine_trader") and editor.list_keys.has("npc_type:procha_trader"),"Trader templates appear under NPC types")
	editor.category.select(8); editor._refresh_list()
	check(editor.list_keys.count("Added/Trader_1") == 1 and editor.list_keys.has("Added/Trader_6"),"Individual traders appear once under NPCs")
	editor.select("Added/Trader_1")
	check(editor.fields.has("npc_type") and editor.fields.has("npc_faction") and not editor.fields.has("npc_speed"),"Placed trader exposes template and affiliation rather than duplicating type tuning")
	editor.simulating = true; editor._start_submarine_preview()
	check(editor.submarine_traffic.traders.size() == 10 and editor.submarine_traffic.traders.all(func(agent: Node3D) -> bool: return agent.running),"Editor simulation activates six traders and four additional faction vessels")
	editor.submarine_traffic.set_simulating(false)
	check(not editor.submarine_traffic.traders[0].body.active,"Stopped editor preview does not present active wildlife targets")
	editor.free(); await process_frame
	print("Submarine traffic: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
