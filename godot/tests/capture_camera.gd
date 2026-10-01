extends SceneTree
const Game = preload("res://game.gd")

func _initialize() -> void: call_deferred("_run")

func capture(game: Node, filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/" + filename))

func _run() -> void:
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	if not game.startup_complete:
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	game.set_process(false)
	game.set_physics_process(false)
	game.pilot.set_physics_process(false)
	game.pilot.freeze = true
	game.docking.set_physics_process(false)
	game.pilot.velocity = Vector3.ZERO
	game._update_follow_camera(0.0, true)
	await process_frame
	await capture(game, "camera-closest-preview.png")
	for frame in range(40):
		game.pilot.rotation.y = minf(PI * 0.5, game.pilot.rotation.y + deg_to_rad(144.0) / 60.0)
		game._process(1.0 / 60.0)
		await process_frame
	await capture(game, "camera-turn-lag-preview.png")
	for frame in range(90):
		game.pilot.velocity = -game.pilot.global_basis.z * float(game.pilot.movement.settings.forward_speed)
		game.pilot.global_position += game.pilot.velocity / 60.0
		game._process(1.0 / 60.0)
		await process_frame
	await capture(game, "camera-forward-follow-preview.png")
	game.queue_free()
	await process_frame
	print("Camera captures complete")
	quit()
