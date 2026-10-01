extends SceneTree
const Game = preload("res://game.gd")

func _initialize() -> void: call_deferred("_run")
func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func capture(filename: String) -> void:
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
	key(KEY_UP, true)
	for frame in range(150): await physics_frame
	key(KEY_UP, false)
	await capture("hull-pitch-preview.png")
	key(KEY_E, true)
	key(KEY_A, true)
	for frame in range(90): await physics_frame
	await capture("hull-roll-preview.png")
	key(KEY_E, false)
	key(KEY_A, false)
	for frame in range(360): await physics_frame
	await capture("hull-ballast-preview.png")
	game.queue_free()
	await process_frame
	print("Live propeller physics captures complete")
	quit()
