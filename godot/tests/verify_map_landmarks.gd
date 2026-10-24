extends "res://tests/test_scene_tree.gd"
const Landmarks = preload("res://map_landmarks.gd")
var game: Node
var checks := 0
var failures := 0

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-map-landmarks-fixtures"; storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new()
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads with original landmarks")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game()
	game.set_process(false); game.set_physics_process(false); game.docking.set_physics_process(false)
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.pilot.pending_reset = false
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.wildlife.set_simulating(false); game.photo_mode.replay.set_process(false)
	var map: RefCounted = game.cockpit_hud.map_data
	var places: RefCounted = map.landmarks
	check(places.markers.size() == 20 and map.markers.size() == 6,"Original twenty landmarks coexist with the six authored city markers")
	var names := {}
	for marker in places.markers: names[marker.id] = marker
	check(names.Cave.name == "TOUKA\nCAVES" and names.Can.name == "METAL\nARTEFACT" and names.Tunnel.name == "TRYTON\nCAVES","Original multiline landmark labels retain their exact names")
	check(names.Abyss.position == Vector3(234,142,261) and names.Abyss.radius == 12,"Original Abyss coordinates and discovery radius are recovered")
	check(names.Ribs.position == Vector3(272,154,238) and map.bounds.has_point(names.Cave.position) and map.bounds.has_point(names.Abyss.position) and names.Flats.radius == 25,"Landmarks retain their own original positions and differing radii")
	check(places.markers.all(func(marker: Dictionary) -> bool: return not places.known(marker)),"New game starts without landmark labels")
	# Both label types use the same inclusive horizontal radius, ignoring depth.
	var comparison = preload("res://hud_map.gd").new()
	comparison.markers.assign([{"id":1,"name":"City","position":names.Cave.position}])
	for distance in [11.99,12.0,12.01]:
		comparison.discovered_cities.clear(); places.reset()
		var point: Vector3 = names.Cave.position+Vector3(distance,100,0)
		comparison.discover_cities(point); places.discover(point,map.CITY_DISCOVERY_RANGE)
		check(places.known(names.Cave) == comparison.city_known(comparison.markers[0]),"Landmark and city reveal agree at horizontal distance %s regardless of height" % distance)
		check(places.known(names.Cave) == (distance <= 12),"City discovery radius is inclusive at twelve units")
	places.discover(names.Outlet.position,map.CITY_DISCOVERY_RANGE)
	check(places.known(names.Outlet),"Landmark without an original mission route reveals normally on proximity")
	places.discover(names.Abyss.position,map.CITY_DISCOVERY_RANGE)
	places.discover(names.Can.position,map.CITY_DISCOVERY_RANGE)
	var snapshot: Dictionary = places.snapshot()
	check(Landmarks.valid_snapshot(snapshot),"Landmark snapshot validates")
	var json: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	places.reset(); places.restore(json,map)
	check(places.known(names.Can) and places.known(names.Abyss),"Discovered landmark names survive JSON roundtrip")
	check(not Landmarks.valid_snapshot({"visited":[1],"enabled":[]}) and not Landmarks.valid_snapshot({"visited":[],"enabled":"all"}),"Malformed landmark save fields are rejected")
	game.docking.current = game.submarine_traffic.port_by_id(2)
	var saved: Dictionary = game._save_snapshot("Landmarks")
	check(game.save_games.valid(saved) and saved.map_landmarks == snapshot,"Real game save includes landmark state without changing beta save version")
	check(game.save_games.write(0,saved) == OK,"Landmark save writes to the isolated test slot")
	places.reset()
	check(await game._load_saved_game(0),"Real save restores successfully")
	check(places.known(names.Can) and places.known(names.Abyss),"Loading a real save restores discovered landmark labels")
	# Recover legacy exploration after a beta save without the optional field.
	saved.erase("map_landmarks"); saved.progress.missions.completed = {"eel":{"success":true,"city":3,"score":1.0}}
	map.explored.fill(Color.WHITE); saved.explored = Marshalls.raw_to_base64(map.explored.get_data())
	check(game.save_games.valid(saved),"Published beta saves without landmark fields remain accepted")
	game.save_games.write(0,saved)
	check(await game._load_saved_game(0),"Legacy save loads without a format migration")
	check(places.known(names.Abyss) and places.known(names.Can) and places.known(names.Cave),"Legacy explored areas recover landmark names independently of mission history")
	var view: Control = game.map_screen.map
	check(view.map_data.landmarks == game.cockpit_hud.displays[2].map_data.landmarks,"Minimap and full map share the same landmark state")
	map.reveal_all()
	check(places.markers.all(func(marker: Dictionary) -> bool: return places.known(marker)),"Existing reveal-map developer action also reveals landmarks")
	await game._begin_new_game()
	check(places.visited.is_empty(),"New game resets landmark discovery")
	game.free(); await process_frame
	print("Original map landmarks: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
