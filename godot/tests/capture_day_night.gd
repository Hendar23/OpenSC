extends SceneTree
const Game = preload("res://game.gd")
const Mods = preload("res://mod_registry.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Mods.initialize(false)
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1800):
		if game.startup_complete: break
		await physics_frame
	if not game.startup_complete: quit(1); return
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280, 720)
	game.fog_button.button_pressed = true
	game.fog_slider.value = 24.0
	game._update_water_environment()
	game.day_night.enabled = false
	for preset in [["day", 12.0], ["night", 0.0]]:
		game.day_night.hour = preset[1]; game._update_daylight()
		for frame in range(20): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/" + preset[0] + "-preview.png")
	print("Day/night previews saved")
	quit()
