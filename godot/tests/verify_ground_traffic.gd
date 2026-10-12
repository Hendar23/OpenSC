extends SceneTree
const Vehicle = preload("res://ground_vehicle.gd")
const Traffic = preload("res://ground_traffic.gd")
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
	var config := ConfigFile.new(); config.set_value("game","folder",ProjectSettings.globalize_path("res://../Original Sub Culture")); config.save(storage.preferences_path())
	call_deferred("run")
func run() -> void:
	preload("res://mod_registry.gd").initialize(false)
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var world := Node3D.new(); root.add_child(world)
	var ground := StaticBody3D.new(); ground.name = "WorldCollision"; world.add_child(ground)
	var floor_shape := CollisionShape3D.new(); var floor_box := BoxShape3D.new(); floor_box.size = Vector3(30,1,30); floor_shape.shape = floor_box; floor_shape.position.y = -0.5; ground.add_child(floor_shape)
	var car := Document.load_model("TRADCAR",folder); car.set_meta("editor_model","TRADCAR"); world.add_child(car)
	var agent = Vehicle.install(car,{"npc_radius":4.0,"npc_wait_min":0.1,"npc_wait_max":0.2})
	var system := Traffic.new(); world.add_child(system); system.setup(world,folder)
	agent.set_physics_process(false)
	await physics_frame; await physics_frame
	agent.reset()
	check(not agent.graph_ready and agent.grid_cursor == 0,"Reset keeps route generation incremental")
	check(agent.grounded and absf(car.global_position.y + agent.bounds.position.y - 0.06) < 0.03,"Reset seats the vehicle before any route generation")
	for tick in range(100): agent._build_graph()
	check(agent.graph_ready and agent.graph.get_point_count() > 15,"Local walkable graph is built incrementally")
	var start := car.global_position
	for tick in range(900): agent.advance(0.05)
	check(car.global_position.distance_to(start) > 0.5 and agent.journeys > 0,"Vehicle completes local journeys with stops")
	check(Vector2(car.global_position.x,car.global_position.z).length() <= 4.3,"Vehicle remains in its operating area")
	check(absf(car.global_position.y + agent.bounds.position.y - 0.06) < 0.03,"Vehicle sits on its wheels rather than floating")
	var saved := system.snapshot(); check(Traffic.valid_snapshot(saved),"Traffic snapshot is valid")
	var malformed := saved.duplicate(true); malformed.values()[0].pose[0] = NAN
	check(not Traffic.valid_snapshot(malformed),"Non-finite saved poses are rejected")
	system.set_simulating(false); var paused_position := car.global_position; agent._physics_process(1)
	check(car.global_position == paused_position,"Editor simulation toggle stops NPC movement")
	system.set_simulating(true)
	agent.take_weapon_damage(10); check(is_equal_approx(agent.health.remaining,3),"Original vehicle damage multiplier is applied once")
	agent.take_weapon_damage(100); check(agent.dead and not car.visible,"Destroyed vehicle stops driving and colliding")
	var wreck: Node3D = world.get_node("VehicleWreck")
	check(wreck.pieces.size() > 1 and wreck.gore.is_empty(),"Vehicle breaks into its own metal pieces")
	check(wreck.bubbles != null and wreck.bubbles.amount == 96,"Vehicle destruction releases submarine-style bubbles")
	var wreck_count := get_nodes_in_group("ground_vehicle_wrecks").size(); agent.take_weapon_damage(100)
	check(get_nodes_in_group("ground_vehicle_wrecks").size() == wreck_count,"Destroyed vehicle cannot explode twice")
	check(Traffic.valid_snapshot(system.snapshot()),"Destroyed vehicles can be saved")
	agent.tuning.npc_respawn = false; agent._physics_process(200)
	check(agent.dead,"Respawning can be disabled")
	var observer := Node3D.new(); world.add_child(observer); agent.player = observer
	agent.tuning.npc_respawn = true; agent._physics_process(200)
	check(agent.dead,"Vehicle cannot respawn on top of the player")
	observer.position = Vector3(100,0,100); agent.mission_owner = "convoy"
	var mission_saved := system.snapshot(); agent.mission_owner = ""; system.restore(mission_saved)
	agent._physics_process(200)
	check(agent.dead and agent.mission_owner == "convoy","Saved mission ownership suppresses ground vehicle respawn")
	agent.mission_owner = ""; agent._physics_process(0.1)
	check(not agent.dead and agent.health.remaining == 4,"Vehicle respawns when player is away")
	system.restore(saved); check(not agent.dead and car.visible and agent.health.remaining == 4,"Traffic save restores position and health")
	system.reset(); check(agent.path.is_empty() and agent.health.remaining == 4,"New game resets traffic state")
	check(get_nodes_in_group("ground_vehicle_wrecks").is_empty(),"New game clears old vehicle pieces")
	world.free(); await process_frame
	var game := preload("res://game.gd").new(); game.remember_preferences = false; game.show_start_menu = true; root.add_child(game)
	for frame in range(1800):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Full game loads with traffic")
	if game.startup_complete:
		game.world_root.get_node("ActorActivity").set_physics_process(false)
		for vehicle in game.ground_traffic.vehicles: vehicle.set_local_simulation(true)
		check(game.ground_traffic.vehicles.size() == 8,"Three original cars and five trucks spawn")
		game.ground_traffic.reset()
		for vehicle in game.ground_traffic.vehicles:
			var floor_hit: Dictionary = vehicle.ground(vehicle.home.origin)
			check(not floor_hit.is_empty() and vehicle.get_parent().global_position.distance_to(vehicle._root_at(floor_hit)) < 0.03,"Original vehicle starts seated before its route grid: " + str(vehicle.get_parent().name))
			check(not vehicle.graph_ready,"Original vehicle does not need a completed route grid to seat")
		await physics_frame; await physics_frame
		for vehicle in game.ground_traffic.vehicles:
			vehicle.set_physics_process(false)
			for tick in range(120): vehicle._build_graph()
			var initial: Vector3 = vehicle.get_parent().global_position
			vehicle.advance(0.05)
			var travelled := 0.0
			for tick in range(2000):
				var previous: Vector3 = vehicle.get_parent().global_position
				vehicle.advance(0.05)
				travelled += previous.distance_to(vehicle.get_parent().global_position)
			print("Traffic ",vehicle.get_parent().name,": nodes=",vehicle.graph.get_point_count()," travelled=",travelled," journeys=",vehicle.journeys)
			check(travelled > 3,"Original placement keeps driving: " + str(vehicle.get_parent().name))
			var location: Vector3 = vehicle.get_parent().global_position - vehicle.home.origin
			check(Vector2(location.x,location.z).length() <= float(vehicle.tuning.npc_radius) + 0.8,"Original vehicle stays local")
		game.ground_traffic.vehicles[0].take_weapon_damage(1)
		check(game.player_progress.standing.get("1") == "bad","Attacking civilian traffic affects faction standing")
		game.docking.current = game.docking.ports[0]
		var snapshot: Dictionary = game._save_snapshot("Traffic test")
		check(game.save_games.valid(snapshot) and snapshot.ground_traffic.size() == 8,"Full game saves validate traffic")
		snapshot.erase("ground_traffic"); check(game.save_games.valid(snapshot),"Older saves remain valid")
	game.free(); await process_frame
	var editor := preload("res://asset_editor.gd").new(); editor.remember_preferences = false; root.add_child(editor)
	await process_frame; editor.game_folder = folder; editor._set_mode(true)
	var map = editor.map_editor
	for frame in range(1800):
		if map.loaded: break
		await process_frame
	check(map.loaded,"Editor loads traffic")
	if map.loaded:
		map.category.select(8); map._refresh_list()
		check(map.list_keys.filter(func(key: String) -> bool: return str(map.document.entities[key].get("model","")) in Vehicle.MODELS).size() == 8,"NPC category lists all eight ground vehicles alongside submarine NPCs")
		check(map.context_additions.filter(func(button: Button) -> bool: return button.visible).size() == 1,"NPC category offers placement from shared NPC types")
		map.category.select(6); map._refresh_list()
		check(map.context_additions.filter(func(button: Button) -> bool: return button.visible and button.text == "New object type").size() == 1,"Object types offers template creation")
		check(map.list_keys.all(func(key: String) -> bool: return key.begins_with("object_type:") or key.begins_with("entity_type:")),"Object types contains only shared templates")
		map.category.select(7); map._refresh_list()
		check(map.list_keys.all(func(key: String) -> bool: return key.begins_with("npc_type:")) and map.list_keys.filter(func(key: String) -> bool: return str(map.record(key).get("model","")) in Vehicle.MODELS).size() == 2,"NPC types lists car and truck templates alongside submarine templates")
		map.category.select(5); map._refresh_list()
		check(map.list_keys.filter(func(key: String) -> bool: return key.contains("TURRET")).size() == 22,"Turret placements appear under Objects")
		map.category.select(1); map._refresh_list()
		check(map.list_keys.all(func(key: String) -> bool: return str(map.document.entities[key].get("model","")) not in Vehicle.MODELS + ["TURRET"]),"Scenery category excludes NPCs and turrets")
		map._add_entity("model","TRADCAR")
		var key: String = map.selected
		check(map.category.selected == 8 and map.fields.has("npc_type") and not map.fields.has("npc_speed"),"Adding a car selects its NPC properties")
		map.fields.npc_radius.value = 5; map.apply_properties()
		var type_id: String = map.record().npc_type
		map.select("npc_type:" + type_id); map.fields.npc_speed.value = 0.65; map.apply_properties()
		map.select(key)
		var linked: Array = map.document.entities.keys().filter(func(item: String) -> bool: return map.document.entities[item].get("npc_type") == type_id and not map.document.entities[item].get("deleted",false))
		check(linked.size() >= 4 and linked.all(func(item: String) -> bool: return map.world.get_node(item).get_node("GroundVehicle").tuning.npc_speed == 0.65),"Shared speed reaches every linked car")
		map.select("npc_type:" + type_id); map.delete_selection()
		check(not map.record().is_empty(),"Used NPC type cannot be deleted")
		map.duplicate_selection(); var variant_id: String = map.record().id
		map.fields.npc_speed.value = 0.9; map.apply_properties()
		map.select(key); map.fields.npc_type.select(map.fields.npc_type.item_count - 1); map.apply_properties()
		check(map.record().npc_type == variant_id and map.world.get_node(key).get_node("GroundVehicle").tuning.npc_speed == 0.9,"Instance can select a separate shared variant")
		check(map.world.get_node(linked[0]).get_node("GroundVehicle").tuning.npc_speed == 0.65,"Variant edit leaves other type unchanged")
		map.select(key); map.fields.npc_type.select(0); map.apply_properties()
		check(map.world.get_node(key).get_node("GroundVehicle").tuning.npc_speed == 0.65,"Editor applies traffic properties")
		var original_health = map.world.get_node(key).get_node("GroundVehicle").health
		map.duplicate_selection()
		check(map.world.get_node(map.selected).get_node("GroundVehicle").health != original_health,"Duplicated vehicles have independent health")
		var copied_key: String = map.selected
		map.delete_selection(); map.undo()
		check(map.world.get_node(copied_key).has_node("GroundVehicle"),"Undo restores traffic controller")
		var file := "res://tests/cache-traffic-fixtures/traffic-map.json"
		check(Document.save(map.document,file) == OK and Document.EntityTypes.effective(Document.load_path(file),Document.load_path(file).entities[key]).npc_speed == 0.65,"Vehicle settings survive map save/load")
	editor.free(); await process_frame
	print("Ground traffic: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
