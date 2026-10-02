extends SceneTree
const Mods = preload("res://mod_registry.gd")
const Game = preload("res://game.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Mods.initialize(false)
	Mods.apply(["test.remastered-submarine"], Mods.order, false)
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	if not game.startup_complete: quit(1); return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	game.set_physics_process(false)
	game.pilot.controls_enabled = false
	var target: Vector3 = game.pilot.global_position
	game.camera.global_position = target + Vector3(1.5, 1.0, 1.9)
	game.camera.look_at(target)
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/remastered-submarine-preview.png"))
	print("Remastered submarine preview saved")
	quit()
