extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
var game: Node
var jobs: Node
var runtime: Node
var checks := 0
var failures := 0
func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-distress-fixtures"; storage.ensure_parent(storage.preferences_path())
	var cfg := ConfigFile.new(); cfg.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER")); cfg.save(storage.preferences_path())
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func fresh(id: String) -> RefCounted:
	runtime._cleanup(); await process_frame
	game.equipment.magnet.reset(); game.pilot.restore_health(); game.pilot.active = true; game.pilot.controls_enabled = true
	game.player_progress = Progress.restore({"campaign_stage":4}); game.player_progress.status.credits = 0
	game.equipment.set_installed(["magnet"])
	var city := Rules.offering_city(id)
	var prior: String = Rules.STAGE_FOUR[city][0]
	game.player_progress.missions.completed[prior] = {"success":true,"city":city}
	check(Rules.next_offer(game.player_progress,city) == id,"Distress follows the original local stage-four mission")
	game.docking.current = game.submarine_traffic.port_by_id(city); game.docking.stage = game.Docking.Stage.DOCKED
	check(runtime.accept(city,id).is_empty(),"Accept city variant "+id)
	game.docking.stage = game.Docking.Stage.IDLE; game.dock_interface.dismiss(); paused = false
	jobs.set_physics_process(false)
	var m = jobs.controller
	for mine in m.watched: mine.set_physics_process(false)
	return m
func attach(m: RefCounted) -> void:
	var magnet: Node3D = game.equipment.magnet
	magnet.set_enabled(true); magnet.set_physics_process(false); magnet._attach(m.ship); m.step(0)
	check(m.jammed and magnet.target == m.ship,"Actual Magnet grab activates the pirate trap")
func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	while not game.startup_complete: await process_frame
	await game._begin_new_game()
	game.set_process(false); game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	game.wildlife.set_simulating(false); game.world_root.get_node("ActorActivity").set_physics_process(false)
	for agent in game.submarine_traffic.traders: agent.set_physics_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	for id in Rules.DISTRESS:
		var m = await fresh(id)
		check(m.ship.health == 50 and m.ship.freeze and m.ship.release_on_tow and m.mines.size() == 12,"Original crippled shuttle and twelve mines")
		attach(m)
		var magnet: Node3D = game.equipment.magnet
		magnet.set_enabled(false); magnet.release()
		check(magnet.enabled and magnet.target == m.ship,"Jammer blocks switch-off and direct release")
		check(m.delivery(m.ship,1) and magnet.target == m.ship,"City refuses the trapped sub")
		m.mines[0].global_position = magnet.head.global_position; m.mines[0].detonate()
		check(m.jammed and m.blast_hits == 1,"First close blast leaves the original two-hit jammer counter armed")
		m.mines[1].global_position = magnet.head.global_position; m.mines[1].detonate()
		check(m.freed and not m.jammed and magnet.target == null and not magnet.release_guard.is_valid(),"Second close blast releases the Magnet")
		game.pilot.global_position = m.ship.global_position+Vector3.UP*30
		m.step(11.3)
		check(m.ship.dead and not runtime.active().is_empty(),"Released bomb explodes before original success delay")
		m.step(0.8); await process_frame
		check(runtime.active().is_empty() and game.player_progress.status.credits == 2000 and game.player_progress.campaign_stage == 4,"Original reward paid once without advancing stage")
		check(jobs.actors.is_empty(),"Success cleans up encounter actors")
		for city in [1,2,3,4]: check(Rules.next_offer(game.player_progress,city) not in Rules.DISTRESS,"All variants excluded after resolving the trap")
	var m = await fresh("backstab")
	attach(m)
	var old_ship: Node3D = m.ship
	runtime.finish(false); await process_frame
	check(not is_instance_valid(old_ship) and not game.equipment.magnet.release_guard.is_valid() and game.equipment.magnet.target == null,"Abort cleans up ship and releases jammer")
	check(game.player_progress.status.credits == 0,"Abort pays no reward")
	m = await fresh("backstab3"); attach(m)
	game.events.session_started.emit(false); await process_frame
	check(not game.equipment.magnet.release_guard.is_valid() and jobs.actors.is_empty(),"Session reset cannot retain the jammer")
	m = await fresh("backstab4")
	game.pilot.global_position = m.ship.global_position+Vector3.UP*4
	attach(m)
	var wall := StaticBody3D.new(); game.world_root.add_child(wall); wall.global_position = m.ship.global_position+Vector3.UP*2
	var collider := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(6,0.3,6); collider.shape = box; wall.add_child(collider)
	await physics_frame; await physics_frame
	m.step(120)
	check(not game.pilot.dead and m.cover_escape,"Original solid-cover alternative protects the player from the trap")
	m.step(6.1); await process_frame
	check(runtime.active().is_empty() and game.player_progress.status.credits == 2000,"Surviving behind solid cover resolves the original success branch")
	wall.free()
	m = await fresh("backstab")
	game.pilot.global_position = m.ship.global_position+Vector3.UP*2
	attach(m); m.step(120); await process_frame
	check(game.pilot.dead and runtime.active().is_empty() and game.player_progress.status.credits == 0,"Ignoring the original countdown destroys an exposed player without reward")
	check(not game.equipment.magnet.release_guard.is_valid(),"Fatal outcome releases jammer callbacks")
	game.free(); await process_frame
	print("Allied distress: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
