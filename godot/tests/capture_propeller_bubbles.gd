extends SceneTree
const Game = preload("res://game.gd")
const Mods = preload("res://mod_registry.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Mods.initialize(false)
	Mods.apply(["example.glb-submarine", "example.png-texture"], Mods.order, false)
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	if game.pilot == null: quit(1); return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	game.pilot.controls_enabled = false
	game.pilot.reset_at(game.pilot.spawn + Vector3.UP * 3)
	game.pilot.active = false
	game.pilot.set_physics_process(false)
	game.pilot.bubbles.random.seed = 123
	for frame in range(70):
		game.pilot.global_position += Vector3.FORWARD * 0.03
		game.pilot.movement.main_power = 1
		game.pilot.movement.left_power = 1
		game.pilot.movement.right_power = 1
		game.pilot._update_animation(1.0 / 60)
		await physics_frame
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/propeller-bubbles-preview.png"))
	print("Propeller bubble preview saved")
	quit()
