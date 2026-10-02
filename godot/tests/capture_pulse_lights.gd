extends SceneTree
const Editor = preload("res://asset_editor.gd")
const Mods = preload("res://mod_registry.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Mods.initialize(false)
	var editor := Editor.new(); editor.remember_preferences = false; root.add_child(editor)
	await process_frame
	editor._set_mode(true)
	var map: HBoxContainer = editor.map_editor
	for frame in range(1800):
		if map.loaded: break
		await physics_frame
	if not map.loaded: quit(1); return
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1440, 900)
	var environment: Environment = map.scene.find_children("*", "WorldEnvironment", false, false)[0].environment
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.04, 0.27, 0.32)
	environment.fog_density = 3.0 / 30.0
	for key in map.document.entities:
		if map.document.entities[key].kind != "light" or map.document.entities[key].get("deleted", false): continue
		map.category.select(2); map.select(key)
		map.fields.light_mode.select(2); map.apply_properties()
		var light: OmniLight3D = map.world.get_node(NodePath(key))
		light.set_process(false); light.phase = 0; light.elapsed = 0; light.update_pulse()
		map.camera.position = light.global_position + Vector3(8, 3, 8)
		map.camera.look_at(light.global_position)
		break
	for frame in range(15): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/pulse-light-preview.png")
	print("Pulse light preview saved")
	quit()
