extends SceneTree
const Game = preload("res://game.gd")

func _initialize() -> void: call_deferred("_run")

func capture(game: Node, filename: String) -> void:
	game._process(0.0)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/" + filename))

func advance(controller: Node, expected: int) -> void:
	for frame in range(2000):
		if controller.stage == expected: return
		controller._physics_process(0.05)
	push_error("Capture could not reach docking stage")

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
	var port: Dictionary = game.docking.ports[0]
	game.pilot.global_position = port.entry
	game.pilot.velocity = Vector3.ZERO
	game.docking.update_approach()
	game._update_follow_camera(0.0, true)
	await capture(game, "docking-prompt-preview.png")
	game.pilot.velocity = Vector3(0, 0, game.docking.maximum_docking_speed() + 0.1)
	game.docking.update_approach()
	await capture(game, "docking-warning-preview.png")
	game.pilot.velocity = Vector3.ZERO
	game.docking.request_docking()
	advance(game.docking, game.docking.Stage.OPEN)
	game.docking._physics_process(0.6)
	await capture(game, "docking-opening-preview.png")
	game.docking._physics_process(0.6)
	game.docking._physics_process(float(game.docking.travel_profile.duration) * 0.5)
	await capture(game, "docking-descent-preview.png")
	advance(game.docking, game.docking.Stage.CLOSE)
	game.docking._physics_process(0.6)
	await capture(game, "docking-closing-preview.png")
	game.docking._physics_process(0.6)
	await capture(game, "docked-preview.png")
	game.docking.request_docking()
	game.docking._physics_process(0.6)
	await capture(game, "docking-departure-opening-preview.png")
	game.queue_free()
	await process_frame
	print("Docking captures complete")
	quit()
