extends SceneTree
const Editor = preload("res://asset_editor.gd")
const Mods = preload("res://mod_registry.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Mods.initialize(false)
	var editor := Editor.new(); editor.remember_preferences = false; root.add_child(editor)
	await process_frame
	editor._set_mode(true)
	for frame in range(1800):
		if editor.map_editor.loaded: break
		await physics_frame
	if not editor.map_editor.loaded: quit(1); return
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1440, 900)
	var map: HBoxContainer = editor.map_editor
	map.category.select(3); map.select("group:" + map.document.groups[0].id); map.frame_selection()
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/map-editor-preview.png"))
	map.category.select(4); map.select("species:" + map.document.species[0].id)
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/species-editor-preview.png"))
	root.size = Vector2i(1050, 650)
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/map-editor-small-preview.png"))
	print("Map editor previews saved")
	quit()
