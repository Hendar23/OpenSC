extends SceneTree
const Editor = preload("res://asset_editor.gd")
const Mods = preload("res://mod_registry.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Mods.initialize(false)
	var editor := Editor.new(); editor.remember_preferences = false; root.add_child(editor)
	await process_frame
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280, 720)
	editor._select_asset(editor.filtered_names.find("TURTLE.DFF"))
	editor.animation_playing = false; editor.auto_rotate.button_pressed = false
	editor.yaw = 0.6; editor.pitch = 0.25; editor._update_camera()
	for time in [0.0, 0.33]:
		editor.animation_time = time; editor._apply_animation()
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/turtle-pose-%d.png" % int(time * 100)))
	print("Turtle animation previews saved")
	quit()
