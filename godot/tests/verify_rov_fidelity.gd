extends "res://tests/test_scene_tree.gd"
const Shop = preload("res://equipment_shop.gd")
var game: Node
var checks := 0
var failures := 0

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-rov-fidelity-fixtures"; storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new()
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func key(code: Key) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = true
	game._input(event)

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game loads")
	if not game.startup_complete: quit(1); return
	create_timer(60).timeout.connect(func() -> void: push_error("ROV fidelity test did not finish"); quit(1))
	game._begin_new_game(); game.set_process(false); game.docking.set_physics_process(false)
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.weapons.set_physics_process(false)
	game.equipment.extra_tools.set_physics_process(false); game.equipment.support_tools.set_physics_process(false)
	game.pilot.active = true; game.pilot.controls_enabled = true; game.pilot.pending_reset = false
	game.pilot.global_position = Vector3(10000,game.pilot.surface_height-3,10000)
	game.pilot.rotation = Vector3.ZERO
	game.docking.stage = game.Docking.Stage.IDLE; game.docking.nearby = {}; game.docking.greeting_remaining = 0; game.docking.message = ""
	game.radio_feed.clear(); game.bounty_radio_queue.clear()
	game.equipment.set_installed(["rover"])
	var rov: Node3D = game.equipment.support_tools.rover
	rov.set_physics_process(false)
	for code in ["rover1","rover2","rover3","rover4"]:
		var expected: String = game.gameplay_catalogue.tables.radio_messages.records[code].text
		check(not expected.is_empty() and rov.transmission(code).text == expected,"ROV uses the exact original message: "+code)
	check(rov.find_children("*","Label",true,false).is_empty() and rov.find_children("*","CanvasLayer",true,false).is_empty(),"No invented instruction bar or recording countdown")
	game.equipment.toggle_selected(); rov.set_physics_process(false)
	check(rov.deployed and rov.launched and game.pilot.remote_controlled,"Equipment activation launches and transfers control")
	check(game.radio_feed.entries.back().message.text == rov.transmission("rover3").text,"Remote control is announced through normal ship-computer radio")
	rov.global_position = game.pilot.global_position+Vector3(0,0,80); rov._physics_process(0)
	check(rov.deployed and not rov.returning,"No invented 50-unit automatic recall")
	game.equipment.toggle_selected()
	check(not rov.deployed and rov.launched and not rov.returning and not game.pilot.remote_controlled,"Toggling away at distance leaves the ROV deployed")
	check(game.radio_feed.entries.back().message.text == rov.transmission("rover4").text,"Returning control uses the original ship message")
	var parked := rov.global_transform
	game.equipment.toggle_selected(); rov.set_physics_process(false)
	check(rov.deployed and rov.global_transform == parked,"Taking control again preserves the parked vehicle's position")
	rov.global_position = rov.docking_approach()+Vector3(0,0,.2); rov.check_docking_prompt()
	game._update_radio_messages(0)
	check(game._rov_prompt_active() and game.radio_feed.prompt.message.text == rov.transmission("rover1").text,"Original Y/N docking question is pinned in the normal radio feed")
	check(game.radio_feed.prompt.message.speaker == "ship" and game.radio_feed.prompt.message.portrait != null,"Docking question uses the original ship-computer portrait")
	key(KEY_N)
	check(not rov.docking_prompt and rov.deployed and not rov.returning,"N declines docking without taking away remote control")
	rov.check_docking_prompt(); check(not rov.docking_prompt,"Declined prompt stays dismissed while nearby")
	rov.global_position += Vector3(0,0,2); rov.check_docking_prompt()
	rov.global_position = rov.docking_approach(); rov.check_docking_prompt()
	check(rov.docking_prompt,"Leaving and re-entering the original approach sphere re-arms the question")
	var accept := InputEventJoypadButton.new(); accept.button_index = JOY_BUTTON_A; accept.pressed = true; game._input(accept)
	check(rov.returning and not rov.deployed and not rov.docking_prompt,"Controller accept starts docking")
	check(game.docking.stage == game.Docking.Stage.IDLE and game.radio_feed.entries.back().message.text == rov.transmission("rover2").text,"ROV docking announces the original line and does not dock the player sub")
	rov.health = 1.25
	rov.global_position = rov.socket().global_position+Vector3(0,.02,0); rov._physics_process(0)
	check(not rov.launched and not rov.visible and rov.socket().get_child(0).visible,"ROV returns to its real socket and restores the stowed model")
	check(rov.health == 1.25,"Docking does not grant an invented full repair")
	game.equipment.toggle_selected(); rov.set_physics_process(false)
	check(rov.health == 1.25,"Relaunching the same ROV preserves damage")
	rov.global_position = rov.docking_approach(); rov.check_docking_prompt(); key(KEY_Y)
	check(rov.returning and not rov.deployed,"Keyboard Y accepts docking")
	rov.reset(); game.equipment.toggle_selected(); rov.set_physics_process(false)
	rov.global_position = rov.docking_approach(); rov.check_docking_prompt()
	var decline := InputEventJoypadButton.new(); decline.button_index = JOY_BUTTON_B; decline.pressed = true; game._input(decline)
	check(not rov.docking_prompt and rov.deployed and not rov.returning,"Controller cancel declines docking")
	rov.recording = 4; rov.advance_recording(1)
	check(rov.recording == 3 and rov.find_children("*","Label",true,false).is_empty(),"Recording progresses without adding a timer or instructions")
	game.mission_runtime._cleanup(true)
	check(rov.deployed and rov.launched,"Mission resolution does not reclaim independently deployed equipment")
	rov.take_weapon_damage(100)
	check(rov.dead and not rov.launched and not Shop.installed(game.equipment,game.weapons).values().has("rover"),"Destroyed ROV is removed from installed equipment as in the original")
	rov.set_deployed(true); check(not rov.deployed,"Destroyed equipment cannot be freely respawned by toggling")
	game.player_progress.hold.rover = 1
	check(Shop.swap(game.player_progress,game.equipment,game.weapons,7,"rover").is_empty() and not rov.dead,"A replacement ROV can be purchased and mounted")
	game.equipment.toggle_selected(); rov.set_physics_process(false)
	check(rov.deployed and rov.health == 2,"Replacement ROV launches normally")
	rov.reset()
	# The same audit removed arbitrary per-weapon active-object caps and a bolt
	# timeout that did not occur in the original callbacks.
	var extras: Node3D = game.equipment.extra_tools
	for index in range(13):
		extras.flare_cooldown = 0; extras.activate("sflarel"); extras.flares.back().set_physics_process(false)
	check(extras.flares.size() == 13 and not extras.flares.front().is_queued_for_deletion(),"Launching a thirteenth flare does not delete the first")
	extras.reset()
	var arsenal: Node3D = game.weapons.arsenal
	for index in range(33): arsenal._launch("missile"); arsenal.shots.back().set_physics_process(false)
	game.weapons.set_installed(["missile"]); game.weapons.select_id("missile"); game.player_progress.hold.mammo = 2
	arsenal.cooldown = 0; arsenal.update(true,0)
	check(arsenal.shots.size() == 34 and game.player_progress.hold.mammo == 1,"Arbitrary active-shot cap does not block a loaded launcher")
	arsenal.reset(); arsenal._launch("electro")
	var bolt: Node3D = arsenal.shots.back(); bolt.set_physics_process(false); bolt.advance(12.1)
	check(not bolt.spent and not bolt.is_queued_for_deletion(),"Flying Electro Bolt is not deleted by an invented twelve-second timer")
	arsenal.reset()
	arsenal._launch("missile"); bolt = arsenal.shots.back()
	extras.flare_cooldown = 0; extras.activate("sflarel")
	var flare: Node3D = extras.flares.back()
	game.equipment.toggle_selected(); rov.global_position += Vector3(0,0,5)
	# Let newly spawned interpolated objects register before exercising pause.
	for frame in range(2): await physics_frame
	var pose := rov.global_transform; var bolt_age: float = bolt.age; var flare_age: float = flare.age
	paused = true
	for frame in range(3): await physics_frame
	check(rov.global_transform == pose,"ROV respects the original game's pause state")
	check(bolt.age == bolt_age and flare.age == flare_age,"Launched weapons and flares pause with the game")
	paused = false
	for frame in range(3): await physics_frame
	check(bolt.age > bolt_age and flare.age > flare_age,"Projectiles and flares resume normally")
	arsenal.reset(); extras.reset(); rov.reset()
	if DisplayServer.get_name() != "headless":
		game.equipment.toggle_selected(); rov.set_physics_process(false)
		rov.global_position = rov.docking_approach(); rov.check_docking_prompt(); game._update_radio_messages(0)
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../.local/rov-original-prompt.png")
	print("ROV original presentation: %d checks, %d failures" % [checks,failures])
	game.queue_free(); await process_frame; quit(1 if failures else 0)
