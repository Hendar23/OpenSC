extends SceneTree
const Game = preload("res://game.gd")
const Editor = preload("res://asset_editor.gd")
const Mods = preload("res://mod_registry.gd")
func _initialize() -> void: call_deferred("_run")
func capture(path: String) -> void:
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/" + path))
func _run() -> void:
	root.gui_embed_subwindows = true
	Mods.initialize(false)
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	if game.pilot == null: quit(1); return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	game.mod_panel.open()
	await capture("mods-menu-preview.png")
	for checkbox in game.mod_panel.choices.values(): checkbox.button_pressed = true
	game.mod_panel._apply()
	for frame in range(1200):
		if not game.world_loading: break
		await physics_frame
	await capture("modded-submarine-preview.png")
	game.queue_free()
	await process_frame
	var editor := Editor.new()
	editor.remember_preferences = false
	root.add_child(editor)
	await process_frame
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	editor._select_asset(editor.filtered_names.find("SUB.DFF"))
	await capture("modded-asset-viewer-preview.png")
	editor.queue_free()
	await process_frame
	Mods.initialize(false)
	print("Rendered mod previews complete")
	quit()
