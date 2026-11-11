extends "res://tests/test_scene_tree.gd"

const Game = preload("res://game.gd")
const Crosshair = preload("res://first_person_crosshair.gd")
var failures := 0
var checks := 0
class Target extends StaticBody3D:
	var dead := false
	func take_damage(_amount: float, _source: Vector3 = Vector3.ZERO) -> void: pass

func check(ok: bool, caption: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(caption)

func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "user://crosshair-fixture-" + str(OS.get_process_id())
	storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new()
	config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER"))
	config.save(storage.preferences_path())
	call_deferred("run")

func run() -> void:
	var game := Game.new(); game.remember_preferences = false
	root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game starts for crosshair test")
	if not game.startup_complete: quit(1); return
	var opened: Array[String] = []
	game.front_end.link_opener = func(url: String) -> Error: opened.append(url); return OK
	game.front_end._activate_button("discord")
	check(opened == ["https://discord.gg/drky2beUu"],"Discord button opens exactly the approved invite")
	var order: Array[String] = game.front_end._visible_button_order()
	check(order.find("discord") == order.find("mods") + 1,"Discord sits directly below Mods")
	game.front_end.gameplay_menu.fmvs_enabled = false
	await game._begin_new_game()
	game.pilot.reset_at(Vector3(1500,game.pilot.surface_height-12,1500),Basis.IDENTITY)
	await physics_frame; await physics_frame
	game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.pilot.reset_physics_interpolation()
	game._set_camera_mode(true)
	var sight: Control = game.first_person_crosshair
	var target := Target.new(); target.collision_layer = 8; target.collision_mask = 0
	game.world_root.add_child(target)
	var box := BoxShape3D.new(); box.size = Vector3(1.2,1.2,0.3)
	var collider := CollisionShape3D.new(); collider.shape = box; target.add_child(collider)
	var camera_point: Vector3 = game.camera.global_position
	target.position = camera_point + Vector3(0,0,-1.5)
	await physics_frame; await physics_frame
	sight._process(0); sight._physics_process(0)
	check(sight.visible and sight.on_target,"First-person crosshair turns red over a damageable target in zapper range")
	target.dead = true; sight._physics_process(0)
	check(not sight.on_target,"Destroyed target does not turn the crosshair red")
	target.dead = false
	target.position = camera_point + Vector3(0,0,-4.0)
	await physics_frame; await physics_frame
	sight._physics_process(0)
	check(not sight.on_target,"A target outside standard zapper range stays green")
	game.weapons.set_upgraded(true); sight._physics_process(0)
	check(sight.on_target,"Upgraded zapper uses its longer range")
	var wall := StaticBody3D.new(); wall.collision_layer = 1; wall.collision_mask = 0
	game.world_root.add_child(wall); wall.position = camera_point + Vector3(0,0,-1.0)
	var obstruction := CollisionShape3D.new(); obstruction.shape = box; wall.add_child(obstruction)
	await physics_frame; await physics_frame
	sight._physics_process(0)
	check(not sight.on_target,"Solid scenery blocks red targeting")
	wall.free()
	game.weapons.set_installed(["zapper","missile","homers","ripper","electro"])
	for id in ["missile","homers","ripper"]:
		game.weapons.select_id(id)
		var reach: float = preload("res://player_arsenal.gd").RIPPER_RANGE if id == "ripper" else preload("res://player_projectile.gd").powered_range(id)
		target.position = camera_point + Vector3(0,0,-reach + 0.5)
		await physics_frame; await physics_frame
		sight._physics_process(0)
		check(sight.on_target,"Selected " + id + " recognises a lined-up target inside its own range")
		target.position.z -= 2.0
		await physics_frame; await physics_frame
		sight._physics_process(0)
		check(not sight.on_target,"Selected " + id + " respects its range")
	game.weapons.select_id("electro")
	target.position = camera_point + Vector3(0,0,-12.0)
	await physics_frame; await physics_frame
	sight._physics_process(0)
	check(sight.on_target,"Electro Bolt recognises a lined-up distant target")
	game.pilot.remote_controlled = true; sight._process(0)
	check(not sight.visible,"Crosshair hides during ROV control")
	game.pilot.remote_controlled = false
	game.front_end.gameplay_menu.crosshair_enabled = false; sight._process(0)
	check(not sight.visible,"General option turns the crosshair Off")
	game.front_end.gameplay_menu.crosshair_enabled = true
	game._set_camera_mode(false); sight._process(0)
	check(not sight.visible,"Third person hides the crosshair")
	game._set_camera_mode(true)
	game.map_open = true; sight._process(0)
	check(not sight.visible,"Fullscreen map hides the crosshair")
	game.map_open = false
	paused = true; sight._process(0)
	check(not sight.visible,"Paused menus hide the crosshair")
	paused = false
	game.pilot.dead = true; sight._process(0)
	check(not sight.visible,"Player death hides the crosshair")
	game.pilot.dead = false; sight._process(0)
	check(sight.visible,"Crosshair returns during first-person piloting")
	if DisplayServer.get_name() != "headless":
		for frame in range(3): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../.local/first-person-crosshair.png")
	target.free(); game.queue_free(); await process_frame
	print("First-person crosshair: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
