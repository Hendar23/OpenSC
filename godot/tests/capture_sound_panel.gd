extends SceneTree
const Game = preload("res://game.gd")
const Mods = preload("res://mod_registry.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Mods.initialize(false)
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	if not game.startup_complete: quit(1); return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	game._toggle_sound_tuning()
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/sound-panel-preview.png"))
	print("Sound panel preview saved")
	quit()
