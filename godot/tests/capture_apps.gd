extends SceneTree

const Game = preload("res://game.gd")
const Editor = preload("res://asset_editor.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func capture(path: String) -> void:
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		failures += 1
		return
	image.save_png(ProjectSettings.globalize_path(path))

func _run() -> void:
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.pilot_mode, "Automatic game startup")
	check(root.mode == Window.MODE_FULLSCREEN, "Game full-screen startup")
	var key := InputEventKey.new()
	key.keycode = KEY_F11
	key.pressed = true
	game._input(key)
	check(root.mode == Window.MODE_WINDOWED, "Game F11 window toggle")
	root.size = Vector2i(1280, 720)
	game.set_physics_process(false)
	game.pilot.controls_enabled = false
	game.fog_slider.value = 35.0
	await capture("res://tests/game-preview.png")
	game._toggle_tuning()
	await capture("res://tests/developer-preview.png")
	game._toggle_developer_ui()
	game.fog_slider.value = 150.0
	await capture("res://tests/clear-water-preview.png")
	game.set_process(false)
	var fish: CharacterBody3D = game.world_root.get_node("AmbientFish").get_child(0)
	var original_position := game.camera.position
	var original_rotation := game.camera.rotation
	game.camera.position = fish.global_position + Vector3(4.0, 1.0, 5.0)
	game.camera.position.y = minf(game.camera.position.y, game.pilot.surface_height - 0.5)
	game.camera.look_at(fish.global_position, Vector3.UP)
	await capture("res://tests/world-fish-preview.png")
	check(not fish.meshes.is_empty() and fish.animation_time > 0.0, "Ambient fish animate in the rendered world")
	game.camera.position = original_position
	game.camera.rotation = original_rotation
	game.queue_free()
	await process_frame
	var editor := Editor.new()
	editor.remember_preferences = false
	root.add_child(editor)
	await process_frame
	check(root.mode == Window.MODE_FULLSCREEN, "Editor full-screen startup")
	editor._input(key)
	check(root.mode == Window.MODE_WINDOWED, "Editor F11 window toggle")
	root.size = Vector2i(1280, 720)
	editor.category.select(1)
	editor._filter_assets()
	editor._select_asset(editor.filtered_names.find("BUSH2.DFF"))
	await capture("res://tests/editor-plants-preview.png")
	editor.category.select(0)
	editor._filter_assets()
	editor._select_asset(editor.filtered_names.find("SUB.DFF"))
	await capture("res://tests/editor-submarine-preview.png")
	editor._select_asset(editor.filtered_names.find("STARSHIP.DFF"))
	await capture("res://tests/editor-starship-preview.png")
	editor._select_asset(editor.filtered_names.find("PIRANHA.DFF"))
	editor._toggle_animation()
	editor.animation_time = 0.0
	editor._apply_animation()
	await capture("res://tests/editor-fish-rest.png")
	var resting := editor.viewport.get_texture().get_image()
	editor.animation_time = 0.5
	editor._apply_animation()
	await capture("res://tests/editor-fish-preview.png")
	var posed := editor.viewport.get_texture().get_image()
	check(resting.get_data() != posed.get_data(), "Stored fish pose changes rendered geometry")
	editor._toggle_animation()
	var start_time: float = editor.animation_time
	for frame in range(15): await process_frame
	check(editor.animation_time > start_time, "Fish playback advances in rendered app")
	editor.queue_free()
	await process_frame
	print("Rendered app verification: %d failures" % failures)
	quit(0 if failures == 0 else 1)
