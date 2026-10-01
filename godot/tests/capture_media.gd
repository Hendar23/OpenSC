extends SceneTree
const Editor = preload("res://asset_editor.gd")
func _initialize() -> void: call_deferred("_run")
func capture(name: String) -> void:
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/" + name))
func choose(editor: Node, name: String, category: int) -> void:
	editor.category.select(category)
	editor._filter_assets()
	editor._select_asset(editor.filtered_names.find(name))
func _run() -> void:
	var editor := Editor.new()
	editor.remember_preferences = false
	root.add_child(editor)
	await process_frame
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	choose(editor, "GAMETEX/RTFACTH.BMP", 3)
	await capture("editor-bmp-preview.png")
	choose(editor, "WAVES/DOCK.RAW", 4)
	await capture("editor-audio-preview.png")
	choose(editor, "OST/01_Ambient.mp3", 4)
	await capture("editor-music-preview.png")
	choose(editor, "INTROTEX/2SUB.BMP", 3)
	await capture("editor-raster-preview.png")
	editor.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Media captures complete")
	quit()
