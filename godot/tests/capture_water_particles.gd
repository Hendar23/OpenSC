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
	game.particles.configure(game.WaterParticles.DEFAULTS)
	game.particle_controls.enabled.button_pressed = true
	game.particle_controls.count.value = 1000; game.particle_controls.visibility.value = 0.7
	for frame in range(45): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/water-particles-preview.png")
	game._toggle_developer_ui(); game._select_developer_tab("Graphics")
	for frame in range(15): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/water-particles-controls.png")
	print("Water particle previews saved")
	quit()
