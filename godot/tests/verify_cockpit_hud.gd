extends SceneTree
const Game = preload("res://game.gd")
const Mods = preload("res://mod_registry.gd")
const HUD = preload("res://cockpit_hud.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func key(code: int) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true
	get_root().get_child(0)._unhandled_input(event)
func advance_slide(hud: CanvasLayer,index: int,seconds: float) -> void:
	# Step a known interval: initial GPU uploads can otherwise stall a frame
	# long enough to skip the intermediate position under test.
	var tween: Tween = hud.slide_tweens[index]
	if tween != null:
		tween.pause()
		tween.custom_step(seconds)
func seabed_height(world: Node3D, point: Vector3) -> float:
	var height := -INF
	for node in world.find_children("Material_*", "MeshInstance3D",true,false):
		var inverse: Transform3D = node.global_transform.affine_inverse()
		var start: Vector3 = inverse * (point + Vector3.UP * 50.0)
		var end: Vector3 = inverse * (point - Vector3.UP * 50.0)
		var faces: PackedVector3Array = node.mesh.get_faces()
		for index in range(0,faces.size(),3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(start,end,faces[index],faces[index + 1],faces[index + 2])
			if hit is Vector3:
				var y: float = (node.global_transform * hit).y
				height = maxf(height,y)
	return height
func _run() -> void:
	Mods.initialize(false)
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete, "Game loads with cockpit instruments")
	if not game.startup_complete: quit(1); return
	game.pilot.set_physics_process(false)
	game.pilot.freeze = true
	var hud: CanvasLayer = game.cockpit_hud
	check(hud.instruments.size() == 5 and hud.model_views.is_empty(), "Five original sprite instruments are the default")
	game.hud_scale_slider.value = 50.0
	var viewport_size: Vector2 = root.get_visible_rect().size
	var old_scale := minf(2.0, (viewport_size.x - 16.0) / 641.0)
	check(is_equal_approx(hud.holder.scale.x, old_scale * 0.5) and is_equal_approx(hud.holder.position.x + 641.0 * hud.holder.scale.x * 0.5, viewport_size.x * 0.5) and is_zero_approx(hud.holder.position.y), "HUD is half size and stays centred at the top")
	game.hud_scale_slider.value = 75.0
	check(is_equal_approx(hud.holder.scale.x, old_scale * 0.75), "Graphics HUD slider updates instrument size live")
	game.hud_map_zoom_slider.value = 3.0
	check(is_equal_approx(hud.displays[2].map_span,140.0 / 3.0), "Minimap zoom updates the live terrain display")
	for i in range(5):
		hud.set_enabled(i,true,false); game.hud_enabled[i] = true
		check(hud.displays[i].frame != null and hud.displays[i].frame.get_image().get_pixel(0, 0).a < 0.01, "Original instrument %d has a transparent mask" % i)
	var original_position: Vector3 = game.pilot.global_position
	var original_basis: Basis = game.pilot.global_basis
	game.pilot.global_basis = Basis.from_euler(Vector3(0.4,1.2,0.2))
	game.pilot.reset_physics_interpolation()
	hud.displays[0]._process(0.0)
	check(is_equal_approx(hud.displays[0].tilt_angle,0.4) and hud.displays[0].sub_icon is ImageTexture, "Attitude rotates the original side-view bitmap with pitch")
	game.pilot.global_basis = original_basis
	game.pilot.reset_physics_interpolation()
	check(hud.map_data.texture != null and hud.map_data.height_samples.count(-INF) < hud.map_data.height_samples.size() * 0.5, "Minimap rasterises actual terrain coverage")
	var heights: Array = Array(hud.map_data.height_samples).filter(func(height: float) -> bool: return is_finite(height))
	check(heights.max() - heights.min() > 5.0, "Terrain heights remain varied instead of being covered by the water surface")
	check(hud.map_data.markers.size() == game.docking.ports.size(), "Minimap marks all live dock locations")
	check(hud.map_data.uv(hud.map_data.bounds.position).is_equal_approx(Vector2.ZERO) and hud.map_data.uv(hud.map_data.bounds.end).is_equal_approx(Vector2.ONE), "World and minimap coordinates agree at both bounds")
	var equipment: Node3D = game.equipment
	check(equipment.mounted.size() == 1 and equipment.current().id == "deep_sea_lights", "Deep-Sea Lights are starting modular equipment")
	check(equipment.current().icons[0] != null and equipment.current().icons[1] != null and equipment.get_node("DeepSeaLightsMount").get_child_count() == 2, "Original model and both equipment sprites load")
	var mount: Node3D = equipment.get_node("DeepSeaLightsMount")
	var hull_bounds: AABB = equipment._bounds(equipment._meshes(game.pilot.visual,Transform3D.IDENTITY,true))
	var lamp_bounds: AABB = equipment._bounds(equipment._meshes(mount.get_child(0),Transform3D.IDENTITY))
	check(mount.position.z + lamp_bounds.end.z < hull_bounds.get_center().z and mount.position.y + lamp_bounds.position.y < hull_bounds.end.y - hull_bounds.size.y * 0.2, "Headlight sits against the front canopy rim below the roof")
	check(not equipment.bulb_materials.is_empty() and not equipment.bulb_materials[0].emission_enabled, "Original recessed lens is separate and unlit when switched off")
	check(not equipment.lamp.visible, "Lights start switched off")
	equipment.cycle(1); equipment.cycle(-1)
	check(equipment.selected == 0, "Equipment selection wraps safely with one mounted item")
	key(KEY_L)
	check(equipment.current().enabled and equipment.lamp.visible, "Keyboard toggles real headlights")
	check(equipment.bulb_materials[0].emission_enabled and equipment.bulb_materials[0].albedo_color == Color.WHITE, "Switching on makes the bulb white and emissive")
	await process_frame
	await process_frame
	for i in range(5):
		key(KEY_1 + i)
		await advance_slide(hud,i,0.1)
		check(hud.instruments[i].visible and hud.instruments[i].position.y < 0.0 and hud.instruments[i].position.y > -HUD.DEFINITIONS[i].size.y - 4.0, "Instrument %d slides upward before disappearing" % i)
		await advance_slide(hud,i,0.25)
		check(not hud.instruments[i].visible and hud.enabled.count(false) == 1 and equipment.lamp.visible, "Key %d only hides its instrument without switching equipment off" % (i + 1))
		key(KEY_1 + i)
		await advance_slide(hud,i,0.35)
		check(hud.instruments[i].visible and is_zero_approx(hud.instruments[i].position.y), "Instrument %d slides back down to its original position" % i)
	key(KEY_1); await advance_slide(hud,0,0.1); key(KEY_1); await advance_slide(hud,0,0.35)
	check(hud.enabled[0] and hud.instruments[0].visible and is_zero_approx(hud.instruments[0].position.y), "Reversing a slide honours the latest key press")
	game.pilot.global_position = Vector3(120,120,120)
	game.docking.update_approach()
	var button := InputEventJoypadButton.new(); button.button_index = JOY_BUTTON_B; button.pressed = true
	game._unhandled_input(button)
	check(not equipment.current().enabled, "Controller B toggles selected equipment during normal piloting")
	game.pilot.global_position = game.docking.ports[0].entry
	game.pilot.velocity = Vector3.ZERO
	game.docking.update_approach()
	game._unhandled_input(button)
	check(not equipment.current().enabled and game.docking.nearby.is_empty(), "Docking prompt takes priority over equipment B")
	game.equipment_controls.light_energy.value = 4.5
	game.equipment_controls.light_range.value = 24.0
	game.equipment_controls.light_down_angle.value = 40.0
	check(is_equal_approx(equipment.lamp.light_energy, 4.5) and is_equal_approx(equipment.lamp.spot_range, 24.0) and is_equal_approx(equipment.lamp.rotation_degrees.x, -40.0), "F1 sliders update brightness, range and aim")
	var path := "res://tests/hud-settings-test.cfg"
	key(KEY_2)
	check(game._export_all_settings(path) == OK, "HUD and light settings export")
	key(KEY_2); game.equipment_controls.light_range.value = 10.0
	game._load_preferences(path)
	check(is_equal_approx(game.cockpit_hud.scale_multiplier, 0.75), "HUD scale reloads from the combined export")
	check(is_equal_approx(game.cockpit_hud.map_zoom,3.0), "Minimap zoom reloads from the combined export")
	game.hud_scale_slider.value = 50.0
	game.hud_map_zoom_slider.value = 2.0
	check(not hud.instruments[1].visible and is_equal_approx(equipment.lamp.spot_range, 24.0), "Exported HUD visibility and lights reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	key(KEY_2)
	game.pilot.global_position = original_position
	game.daylight_controls.time_of_day.value = 12.0
	game.daylight_controls.cycle_enabled.button_pressed = false
	game._update_follow_camera(0.0, true)
	if DisplayServer.get_name() != "headless":
		for frame in range(600):
			if hud.map_data.scenery_baked: break
			await process_frame
		check(hud.map_data.scenery_baked and hud.map_data.texture.get_width() == 2048, "Minimap bakes detailed terrain and static scenery from the actual world")
		root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280,720)
		await create_timer(0.4).timeout
		for frame in range(30): await process_frame
		root.get_texture().get_image().save_png("res://tests/cockpit-hud-preview.png")
		game.daylight_controls.time_of_day.value = 0.0
		# Use a broad beam consistently, regardless of personal preferences,
		# so the capture also exposes grazing-angle terrain shadow artefacts.
		game.equipment_controls.light_angle.value = 45.0
		game.particle_controls.enabled.button_pressed = false
		if game.wildlife != null: game.wildlife.process_mode = Node.PROCESS_MODE_DISABLED
		for frame in range(20): await process_frame
		var unlit := root.get_texture().get_image()
		equipment.toggle_selected()
		for frame in range(20): await process_frame
		var lit := root.get_texture().get_image()
		lit.save_png("res://tests/cockpit-lights-night-preview.png")
		var illuminated_pixels := 0
		for y in range(260,720,4):
			for x in range(0,1280,4):
				if lit.get_pixel(x,y).get_luminance() - unlit.get_pixel(x,y).get_luminance() > 0.015: illuminated_pixels += 1
		check(illuminated_pixels > 20, "Deep-Sea Lights visibly illuminate the world at night")
		var floor_point: Vector3 = original_position + Vector3(6.0,0,-5.0)
		var floor_height := seabed_height(game.world_root,floor_point)
		check(is_finite(floor_height), "Close-range light preview locates the actual seabed")
		if is_finite(floor_height):
			for clearance in [0.35,0.7]:
				game.pilot.global_position = Vector3(floor_point.x,floor_height + clearance,floor_point.z)
				game.pilot.reset_physics_interpolation()
				game._update_follow_camera(0.0,true)
				for frame in range(20): await process_frame
				root.get_texture().get_image().save_png("res://tests/headlight-seabed-%s.png" % str(clearance))
		game.pilot.global_position = original_position
		game.pilot.reset_physics_interpolation()
		game.daylight_controls.time_of_day.value = 12.0
		game.particle_controls.enabled.button_pressed = true
		game.set_process(false)
		var camera_pose: Transform3D = game.camera.global_transform
		game.camera.global_position = game.pilot.global_position + Vector3(0.4,0.2,-1.0)
		game.camera.look_at(game.pilot.global_position + Vector3.UP * 0.04)
		for frame in range(15): await process_frame
		root.get_texture().get_image().save_png("res://tests/headlight-front-preview.png")
		game.camera.global_transform = camera_pose
		game.set_process(true)
	var ids: Array[String] = ["test-3d-map-instrument"]
	check(Mods.apply(ids, ids, false) == OK and Mods.candidates("hud.map").size() == 1, "Optional 3D instrument registers through normal mods")
	hud.free()
	game.cockpit_hud = HUD.new(); root.get_child(0).add_child(game.cockpit_hud)
	game.cockpit_hud.setup(game.pilot, equipment, game.world_root, game.game_folder)
	hud = game.cockpit_hud
	check(hud.model_views.size() == 1 and hud.displays[2].screen_only, "3D minimap binds the same live map display")
	var mesh := hud.model_views[0].find_child("Screen_Display", true, false) as MeshInstance3D
	check(mesh != null and mesh.material_override.albedo_texture is ViewportTexture, "Supplied physical screen displays the live viewport texture")
	key(KEY_3)
	await advance_slide(hud,2,0.35)
	check(not hud.instruments[2].visible, "Key 3 also hides the modded instrument")
	key(KEY_3)
	if DisplayServer.get_name() != "headless":
		await create_timer(0.4).timeout
		for frame in range(45): await process_frame
		root.get_texture().get_image().save_png("res://tests/cockpit-3d-map-preview.png")
	game.queue_free(); await process_frame
	print("Cockpit HUD verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
