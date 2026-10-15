extends SceneTree
const Document = preload("res://map_document.gd")
const Patrol = preload("res://patrol_submarine.gd")
const Stream = preload("res://bubble_stream.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-traffic-fixtures"; storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new(); config.set_value("game","folder",ProjectSettings.globalize_path("res://../Original Sub Culture")); config.save(storage.preferences_path())
	call_deferred("run")
func run() -> void:
	var game = preload("res://game.gd").new(); game.remember_preferences = false; game.show_start_menu = true; root.add_child(game)
	for frame in range(3000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Complete world starts")
	if not game.startup_complete: quit(1); return
	game.front_end.hide_menu(); paused = false
	var data: Dictionary = Document.load_path(Document.DEFAULT_PATH)
	check(Document.valid(data),"Extended authored map validates")
	for id in ["mutant_lionfish","mutant_jackfish","mutant_silverback"]:
		check(game.wildlife.definitions.has(id) and game.wildlife.templates.has(id),"Separate mutant type and loaded model: " + id)
		check(data.species.any(func(s: Dictionary) -> bool: return s.id == id and s.random_spawn and s.health == 30),"Mutant joins automatic wildlife population: " + id)
	var streams: Array = game.world_root.find_children("Startup_BUBBLESTREAM_*","Node3D",true,false)
	check(not streams.is_empty() and streams.size() <= 50,"Original bubble stream placement attempts create seabed emitters")
	check(not game.world_root.find_children("Startup_REED_*","Node3D",true,false).is_empty(),"Extra scattered reeds restored")
	check(not game.world_root.find_children("Startup_BUSH4_*","Node3D",true,false).is_empty(),"Extra scattered bushes restored")
	var captured := Document.capture(game.world_root,game.gameplay_catalogue)
	check(Document.valid(captured),"Captured extended world remains a valid editable map")
	check(captured.entities.values().any(func(e: Dictionary) -> bool: return e.kind == "bubbles"),"Streams captured as editable objects")
	var stream = streams[0]
	stream.configure(game.game_folder,{"emission_rate":40,"lifetime":0.5,"start_size":0.2,"end_size":0.4,"rise_speed":1.2,"opacity":0.9})
	stream.renderer.surface_height = INF
	stream.global_position = game.pilot.global_position
	stream._physics_process(0.1)
	check(stream.renderer.particles.size() > 0 and is_equal_approx(stream.renderer.particles[0].size,0.2),"Edited emitter settings affect actual bubbles")
	stream.renderer.advance(1.0)
	check(stream.renderer.particles.is_empty(),"Bubbles obey configured lifetime")
	check(stream.renderer.capacity == 128 and stream.renderer.instances.instance_count == 128,"Emitter storage remains bounded")
	# Explicitly exercise local combat/docking; visibility has its own regression.
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	for agent in game.submarine_traffic.traders: agent.set_local_simulation(true)
	await physics_frame
	var vessels: Array = game.submarine_traffic.traders.filter(func(agent: Node3D) -> bool: return agent is Patrol)
	check(vessels.size() == 4,"Four additional faction vessels spawned")
	for agent in vessels:
		agent.set_physics_process(false)
		check(agent.roaming and agent.body.get_meta("faction") == int(agent.tuning.npc_faction),"Faction vessel roams with matching marker affiliation")
		var before: Vector3 = agent.global_position
		for tick in range(120): agent.advance(1.0 / 60.0)
		check(agent.global_position.distance_to(before) > 0.05,"Additional vessel navigates from its starting placement")
	var armed: Array = vessels.filter(func(agent: Node3D) -> bool: return agent.tuning.npc_armed)
	var unarmed: Array = vessels.filter(func(agent: Node3D) -> bool: return not agent.tuning.npc_armed)
	check(armed.size() == 2 and unarmed.size() == 2,"Only combat ships are armed")
	for agent in armed:
		var enemy = armed.filter(func(other: Node3D) -> bool: return other != agent)[0]
		check(not agent._valid_target(enemy.body),"Combat patrol leaves opposing faction in peace")
		var pirate = game.submarine_traffic.roaming_population.ships[0]
		check(agent._valid_target(pirate.body),"Combat patrol targets pirates")
		check(not agent._valid_target(game.pilot),"Neutral player is not acquired by faction patrols")
	for agent in unarmed: check(not agent._valid_target(armed[1].body),"Shuttle/prison ship never acquires combat targets")
	var alerts := [0]
	armed[0].attacked.connect(func(_faction: int) -> void: alerts[0] += 1)
	var health_before: float = armed[0].health.remaining
	armed[0].take_weapon_damage_from(1.0,armed[1].global_position,armed[1])
	check(armed[0].health.remaining < health_before and alerts[0] == 0,"NPC combat deals damage without blaming player")
	armed[0].take_weapon_damage_from(1.0,game.pilot.global_position,game.pilot)
	check(alerts[0] == 1,"Player attacks still alert faction defences")
	var saved: Dictionary = game.submarine_traffic.snapshot()
	check(game.submarine_traffic.valid_snapshot(saved),"Additional vessels participate in normal save snapshots")
	var traffic = game.submarine_traffic
	for agent in traffic.traders:
		agent.set_physics_process(false)
		agent.take_weapon_damage_from(100000,game.pilot.global_position,null)
		agent.advance(1000)
	check(traffic.traders.all(func(agent: Node3D) -> bool: return agent.dead and not agent.get_parent().visible and agent.body.collision_layer == 0),"All destroyed submarine types remain hidden and non-colliding after a long swim")
	saved = traffic.snapshot(); traffic.restore(saved)
	check(traffic.traders.all(func(agent: Node3D) -> bool: return agent.dead),"Save/restore retains destroyed subs awaiting docking")
	game._process(0.01)
	check(traffic.traders.all(func(agent: Node3D) -> bool: return agent.dead),"Ordinary swimming does not replenish subs")
	game.docking.stage = game.Docking.Stage.DOCKED
	game.docking.current = game.docking.ports[0]
	game.dock_interface_active = true; game.dock_interface.show(); game.dock_interface.page = "load"
	paused = true
	game._process(0.01)
	check(traffic.traders.all(func(agent: Node3D) -> bool: return agent.dead),"Load screen cannot trigger replacements")
	game.dock_interface.page = "home"
	game._process(0.01)
	check(traffic.traders.all(func(agent: Node3D) -> bool: return not agent.dead and agent.get_parent().visible and agent.body.collision_layer == 10 and agent.health.remaining == float(agent.tuning.npc_health)),"Paused dock menu restores every submarine with full health and collision")
	var poses: Array = traffic.traders.map(func(agent: Node3D) -> Transform3D: return agent.get_parent().global_transform)
	game._process(0.01)
	check(traffic.traders.map(func(agent: Node3D) -> Transform3D: return agent.get_parent().global_transform) == poses,"Subsequent dock frames leave live submarines in place")
	check(traffic.valid_snapshot(traffic.snapshot()),"Replenished fleet remains saveable")
	game.dock_interface_active = false; game.dock_interface.hide(); game.docking.stage = game.Docking.Stage.IDLE; paused = false
	game.queue_free(); await process_frame
	print("Ambient additions: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
