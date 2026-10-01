extends SceneTree

const Editor = preload("res://asset_editor.gd")
const BMP = preload("res://legacy_bmp.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	var editor := Editor.new()
	editor.remember_preferences = false
	root.add_child(editor)
	await process_frame
	check(editor.catalog.values().filter(func(entry: Dictionary) -> bool: return entry.kind == "model" and not entry.has("mod_asset")).size() == 139, "All supplied 3D assets indexed")
	check(editor.asset_names.size() > 1000, "Image, audio and text assets indexed alongside models")
	check(editor.model != null, "Initial asset preview loads")
	check(is_equal_approx(editor.animation_speed.value, 0.5), "Editor defaults to preferred half-speed animation")
	check(editor.viewport.own_world_3d, "Editor preview uses an independent scene")
	editor.category.select(1)
	editor._filter_assets()
	check(editor.filtered_names.size() == 5, "Plants filter contains all bushes and reeds")
	editor.search.text = "bush"
	editor._filter_assets()
	check(editor.filtered_names.size() == 4, "Search combines with plant filter")
	editor.search.text = "nothing-matches"
	editor._filter_assets()
	check(editor.filtered_names.is_empty(), "Empty search results handled")
	editor.search.text = ""
	editor.category.select(0)
	editor._filter_assets()
	for name in ["SUB.DFF", "BUSH4.DFF", "DOCKING.DFF", "STARSHIP.DFF", "BIGLITE.DFF"]:
		editor._select_asset(editor.filtered_names.find(name))
		check(editor.model != null and editor.camera.position.is_finite(), name + " loads and auto frames")
	var previous := editor.camera.position
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(30, 10)
	editor.dragging = true
	editor._preview_input(drag)
	check(editor.camera.position.distance_to(previous) > 0.001, "Mouse drag orbits asset")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var distance: float = editor.distance
	editor._preview_input(wheel)
	check(editor.distance < distance, "Mouse wheel zooms")
	editor._frame_model()
	check(is_equal_approx(editor.distance, editor.base_distance), "Frame asset restores framing")
	for sample in [["ANGEL.DFF", 2], ["ANGLER.DFF", 4], ["PIRANHA.DFF", 5], ["STINGRAY.DFF", 3]]:
		editor._select_asset(editor.filtered_names.find(sample[0]))
		check(editor.animation_playing and editor.animated_meshes.size() == 1, sample[0] + " starts playback")
		var instance: MeshInstance3D = editor.animated_meshes[0]
		check(instance.mesh.get_blend_shape_count() == sample[1] - 1, sample[0] + " retains all original poses")
		var rest: PackedVector3Array = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var posed: PackedVector3Array = instance.mesh.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
		check(rest.size() == posed.size() and rest != posed, sample[0] + " has distinct compatible pose vertices")
		for vertex in posed:
			if not instance.mesh.custom_aabb.grow(0.0001).has_point(vertex):
				check(false, sample[0] + " pose lies within animation bounds")
		check(not editor.animation_button.disabled, sample[0] + " enables playback controls")
	editor._select_asset(editor.filtered_names.find("ANGEL.DFF"))
	var fish: MeshInstance3D = editor.animated_meshes[0]
	editor.animation_time = 0.25
	editor._apply_animation()
	check(is_equal_approx(fish.get_blend_shape_value(0), 0.5), "Halfway between stored poses interpolates evenly")
	editor.animation_time = 0.5
	editor._apply_animation()
	check(is_equal_approx(fish.get_blend_shape_value(0), 1.0), "Second pose receives full weight")
	editor.animation_time = 0.75
	editor._apply_animation()
	check(is_equal_approx(fish.get_blend_shape_value(0), 0.5), "Loop blends back to resting pose")
	editor._toggle_animation()
	var paused_time: float = editor.animation_time
	editor._process(0.1)
	check(is_equal_approx(editor.animation_time, paused_time) and editor.animation_button.text == "Play", "Pause holds current pose")
	editor.animation_speed.value = 2.0
	editor._toggle_animation()
	editor._process(0.1)
	check(is_equal_approx(editor.animation_time, paused_time + 0.2), "Speed slider scales playback time")
	editor.animation_time = 0.0
	editor._apply_animation()
	check(is_zero_approx(fish.get_blend_shape_value(0)), "Restart returns to resting pose")
	for name in ["SUB.DFF", "BUSH2.DFF", "SEAHORSE.DFF", "TURTLE.DFF"]:
		editor._select_asset(editor.filtered_names.find(name))
		check(editor.animated_meshes.is_empty() and not editor.animation_playing and editor.animation_button.disabled, name + " remains static without morph poses")
	if DisplayServer.get_name() != "headless":
		check(editor.get_window().mode == Window.MODE_FULLSCREEN, "Editor starts full screen")
		var key := InputEventKey.new()
		key.keycode = KEY_F11
		key.pressed = true
		editor._input(key)
		check(editor.get_window().mode == Window.MODE_WINDOWED, "F11 returns editor to window")
	var folder := preload("res://asset_paths.gd").find_game_folder().path_join("GAMETEX")
	var rle := BMP.load_image(folder.path_join("BLADES.BMP"))
	check(rle != null and rle.get_size() == Vector2i(128, 128), "RLE8 texture decodes")
	var odd_header := BMP.load_image(folder.path_join("STARTOPB.BMP"))
	check(odd_header != null and odd_header.get_size() == Vector2i(210, 180), "Incorrect legacy BMP size field tolerated")
	var original := Image.load_from_file(folder.path_join("SUB1.BMP"))
	var decoded := BMP.load_image(folder.path_join("SUB1.BMP"))
	check(original != null and decoded != null, "Standard texture decodes")
	for point in [Vector2i(0, 0), Vector2i(32, 40), Vector2i(127, 127)]:
		check(original.get_pixelv(point).is_equal_approx(decoded.get_pixelv(point)), "Indexed texture color and orientation match native decoder")
	editor.queue_free()
	await process_frame
	print("Editor verification: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
