extends SceneTree
const Game = preload("res://game.gd")
const Mods = preload("res://mod_registry.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _run() -> void:
	Mods.initialize(false)
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Game starts with weapon and combat data")
	if not game.startup_complete: game.queue_free(); await process_frame; quit(1); return
	check(game.weapons.mounted.size() == 1 and game.cockpit_hud.displays[3].weapons == game.weapons and game.cockpit_hud.displays[3].weapons.icon != null,"Weapon display uses mounted zapper in both HUD modes")
	var emitter := game.weapons.muzzle.get_node("Emitter") as Node3D
	check(game.pilot.to_local(emitter.global_position).z < 0,"Live game mounts the zapper at the forward bow")
	game.gameplay_catalogue.tables.weapon_tuning.records.zapper.range = 6.0
	game.gameplay_catalogue.tables.creature_stats.records.angel.health = 17.0
	var sample := preload("res://submarine_weapons.gd").new(); game.pilot.add_child(sample); sample.setup(game.pilot,game.game_folder,game.camera,game.gameplay_catalogue); sample.set_physics_process(false)
	check(sample.settings.range == 6.0,"Mounted weapon reads modified gameplay tuning")
	sample.queue_free()
	game._set_camera_mode(true)
	check(game.weapons.beam.layers == 1,"First-person camera can render the beam independently of hidden submarine geometry")
	var pop: Node3D = game.wildlife
	var fish: Node3D = pop.get_children()[0]
	check(fish.health > 0 and fish.health == fish.max_health and fish.collision_layer == 8,"Live wildlife starts healthy and responds to weapon queries")
	var species: String = fish.get_meta("species")
	var group: String = fish.get_meta("spawn_group")
	fish.take_damage(fish.health)
	check(fish.dead and not fish.visible and not fish.is_physics_processing(),"Damaged world creature dies and stops simulation")
	pop._set_awake(fish,true); pop.set_simulating(true); pop._stream_update(true)
	check(fish.dead and not fish.visible and not fish.is_physics_processing(),"Streaming and editor simulation cannot reactivate a dead creature")
	for frame in range(5): await physics_frame
	var peers: Array = pop.get_children().filter(func(peer: Node3D) -> bool: return peer != fish and not peer.dead)
	for peer in peers: peer._physics_process(1.0 / 60)
	check(peers.all(func(peer: Node3D) -> bool: return peer.group_members.all(func(member: Node3D) -> bool: return is_instance_valid(member))),"Shoals retain safe references after member death")
	game.pilot.active = true; game.pilot.controls_enabled = true; game.weapons.update_fire(true,0)
	game._show_main_menu()
	check(not game.weapons.firing and not game.weapons.audio.playing,"Opening the main menu stops weapon effects")
	game._resume_game()
	var random := RandomNumberGenerator.new(); random.seed = 12
	var definition: Dictionary = pop.definitions[species]
	var home: Vector3 = pop._random_home(definition,random)
	pop.document.groups = [{"id":group,"species":species,"position":[home.x,home.y,home.z],"chance":100,"count_min":1,"count_max":1,"radius":5}]
	pop.reroll(false)
	check(pop.get_children().any(func(peer: Node3D) -> bool: return not peer.dead and peer.health == peer.max_health),"World population reset creates healthy creatures again")
	game.queue_free(); await process_frame
	print("Weapon world: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
