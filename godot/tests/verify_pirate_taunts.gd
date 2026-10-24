extends "res://tests/test_scene_tree.gd"
var game: Node
var checks := 0
var failures := 0

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-pirate-taunts-fixtures"; storage.ensure_parent(storage.preferences_path())
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
	check(game.startup_complete,"World loads for roaming pirate radio checks")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game()
	game.set_process(false); game.set_physics_process(false); game.docking.set_physics_process(false)
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.pilot.pending_reset = false
	game.pilot.active = true; game.pilot.controls_enabled = true
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.wildlife.set_simulating(false); game.weapons.set_physics_process(false)
	game.photo_mode.replay.set_process(false)
	var traffic: Node = game.submarine_traffic
	for agent in traffic.traders:
		agent.set_physics_process(false); agent.running = false; agent.body.collision_layer = 0
	var population: Node3D = traffic.roaming_population
	population.random.seed = 1234
	var pirate: Node3D = population.ships[0]
	var messages: Array[Dictionary] = []
	population.transmission.connect(func(message: Dictionary) -> void: messages.append(message))
	game.pilot.global_position = Vector3(10000,game.pilot.surface_height-5,10000)
	var seen := {}
	for encounter in range(12):
		game.radio_feed.clear(); pirate.reset(); pirate.set_physics_process(false); pirate.running = true
		pirate.get_parent().global_position = game.pilot.global_position+Vector3(0,0,8)
		pirate.get_parent().global_basis = Basis(Vector3.UP,PI)
		pirate.victim = game.pilot
		await physics_frame; await physics_frame
		var before := messages.size()
		pirate.advance(0)
		check(messages.size() == before+1,"First unprovoked shot sends one taunt for a fresh pirate")
		if messages.size() == before: continue
		var message: Dictionary = messages.back()
		var line: String = message.text.trim_prefix("PIRATE : ")
		seen[line] = true
		check(population.TAUNTS.has(line) and message.text == "PIRATE : "+line and not line.begins_with('"') and not line.ends_with('"'),"Radio uses only an owner-provided line with the requested prefix and no quotation marks")
		check(message.portrait != null and message.distorted_portrait != null,"Taunt uses the original clear and distorted pirate radio portraits")
		check(game.radio_feed.entries.size() == 1 and game.radio_feed.entries[0].label.text == message.text,"Taunt appears in the normal radio feed presentation")
		pirate.cooldown = 0; pirate.shot_retry = 0; pirate.advance(0)
		check(messages.size() == before+1,"Continued firing does not repeat the taunt")
		pirate.set_local_simulation(false); pirate.set_local_simulation(true); pirate.set_physics_process(false)
		pirate.victim = game.pilot; pirate.advance(0)
		check(messages.size() == before+1,"Re-entering local simulation does not repeat a pirate's greeting")
	check(seen.size() > 1,"Separate pirates choose varied random taunts")
	var saved: Dictionary = traffic.snapshot()
	var id: String = preload("res://entity_identity.gd").of(pirate)
	check(traffic.valid_snapshot(saved),"Traffic saves with a sent taunt remain valid")
	pirate.player_attack_announced = false; traffic.restore(saved)
	check(pirate.player_attack_announced,"Save/load remembers a pirate has already taunted")
	for entry: Dictionary in saved.values(): entry.erase("player_attack_announced")
	check(traffic.valid_snapshot(saved),"Published beta traffic saves without the new optional flag still load")
	traffic.restore(saved)
	check(not pirate.player_attack_announced,"Older saves default to an unannounced pirate")
	saved[id].player_attack_announced = "invalid"
	check(not traffic.valid_snapshot(saved),"Malformed optional taunt state is rejected")
	game.free(); await process_frame
	print("Pirate taunts: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
