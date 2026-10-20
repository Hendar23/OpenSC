extends "res://tests/test_scene_tree.gd"
const Mods = preload("res://mod_registry.gd")
const Cockpit = preload("res://first_person_cockpit.gd")
var checks := 0
var failures := 0
var study_capture: Node
var study_camera: Camera3D
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-canopy-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",ProjectSettings.globalize_path("res://../Original Sub Culture")); config.save(storage.preferences_path())
	Mods.initialize(false); call_deferred("run")
func snapshot(view: SubViewport) -> Image:
	for frame in range(14):
		if is_instance_valid(study_capture): study_capture.update_capture(0.06,true,study_camera)
		await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func brighter(first: Image, second: Image) -> int:
	var count := 0
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			if second.get_pixel(x,y).get_luminance() - first.get_pixel(x,y).get_luminance() > 0.01: count += 1
	return count
func run() -> void:
	var game := preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game loads the optional cockpit hook")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.set_process(false); game.pilot.set_physics_process(false); game.pilot.freeze = true; game.world_root.process_mode = Node.PROCESS_MODE_DISABLED
	check(game.first_person_cockpit.model == null,"No cockpit geometry is installed with the mod disabled")
	var preferences := FileAccess.get_file_as_string(Mods.preference_path)
	var enabled: Array[String] = ["bubble-cockpit"]
	check(Mods.apply(enabled,enabled,false) == OK and Mods.candidates("cockpit.first_person").size() == 1,"Canopy registers through normal mod discovery and priority")
	check(FileAccess.get_file_as_string(Mods.preference_path) == preferences,"Previewing the mod preserves actual settings")
	game.first_person_cockpit.free(); game.first_person_cockpit = Cockpit.new(); game.camera.add_child(game.first_person_cockpit); game.first_person_cockpit.setup(game)
	var canopy: Node3D = game.first_person_cockpit
	check(canopy.model != null and canopy.model.find_children("*","CollisionObject3D",true,false).is_empty(),"Self-contained canopy model loads without gameplay collision")
	var meshes: Array = canopy.model.find_children("*","MeshInstance3D",true,false)
	check(meshes.size() == 1 and meshes.all(func(mesh: MeshInstance3D) -> bool: return mesh.layers == Cockpit.RENDER_LAYER and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),"Rimless glass uses the dedicated non-shadow-casting camera layer")
	check(not canopy.visible,"Canopy stays hidden in third person")
	game._set_camera_mode(true)
	check(canopy.visible and not (game.camera.cull_mask & game.SUB_RENDER_LAYER),"First person shows glass while hiding the external hull")
	check(not (game.cockpit_hud.bottom_camera.cull_mask & Cockpit.RENDER_LAYER) and not (game.cockpit_hud.rear_camera.cull_mask & Cockpit.RENDER_LAYER) and not (game.menu_backdrop.view.cull_mask & Cockpit.RENDER_LAYER),"Auxiliary feeds and menu camera exclude cockpit geometry")
	var pose := canopy.global_transform
	game.pilot.global_basis = Basis.from_euler(Vector3(0.15,0.4,0.1)); game.pilot.reset_physics_interpolation(); game._update_follow_camera(0,true)
	check(canopy.transform == Transform3D.IDENTITY and not canopy.global_transform.is_equal_approx(pose),"Canopy follows camera pitch, heading and roll without separate simulation")
	game.front_end.menu_layer.show(); canopy.refresh(); check(not canopy.visible,"Pause/main menu hides the canopy")
	check(not canopy.refraction_layer.visible,"Menus also disable the refraction pass")
	game.front_end.menu_layer.hide(); game.dock_interface_active = true; canopy.refresh(); check(not canopy.visible,"Dock UI hides the canopy")
	game.dock_interface_active = false; game.map_open = true; canopy.refresh(); check(not canopy.visible,"Fullscreen map hides the canopy")
	game.map_open = false; canopy.refresh(); check(canopy.visible,"Returning to first-person piloting restores the canopy")
	for frame in range(3): await process_frame
	var panel: Node = game.developer_tabs.find_child("Mods",false,false)
	check(panel != null and not game.developer_tabs.is_tab_hidden(panel.get_index()) and panel.sliders.size() == Cockpit.CONTROLS.size(),"Enabled canopy exposes all live controls in the developer Mods tab")
	check(canopy.settings.scratch_count == 4.0,"Canopy starts with four individual scratches")
	panel.sliders.scratch_count.value = 3.0
	check(canopy.glass_materials[0].get_shader_parameter("scratch_count") == 3.0,"Scratch-count slider updates the actual glass immediately")
	panel.sliders.scratch_count.value = 4.0
	var previous_roughness: float = canopy.settings.roughness_value
	panel.sliders.roughness_value.value = 0.22
	game.remember_preferences = true; check(canopy.persist_settings() == OK,"Canopy controls save outside the mod manifest")
	var saved := ConfigFile.new(); saved.load(preload("res://current_settings.gd").path("canopy.cfg"))
	check(is_equal_approx(saved.get_value(canopy.pack_id,"roughness_value"),0.22),"Canopy tuning persists per mod pack")
	panel.sliders.roughness_value.value = previous_roughness; canopy.persist_settings(); game.remember_preferences = false
	if DisplayServer.get_name() != "headless":
		game.developer_enabled = true
		game._toggle_developer_ui(); game.developer_tabs.current_tab = panel.get_index()
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/canopy-dev-controls.png")
		game._toggle_developer_ui()
	var glass_mesh := canopy.model.find_child("Canopy_Glass",true,false) as MeshInstance3D
	var scratch_setting: float = Mods.candidates("cockpit.first_person")[0].glass.scratch_strength
	check(glass_mesh.material_override.shader == preload("res://cockpit_glass.gdshader") and is_equal_approx(glass_mesh.material_override.get_shader_parameter("scratch_strength"),scratch_setting),"Named glass mesh receives validated mod tuning")
	if DisplayServer.get_name() != "headless":
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/canopy-in-game.png")
		var view := SubViewport.new(); view.size = Vector2i(640,400); view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
		var preview: Node3D = canopy.model.duplicate(); view.add_child(preview); preview.global_transform = game.camera.global_transform
		var camera := Camera3D.new(); view.add_child(camera); camera.global_transform = game.camera.global_transform; camera.near = 0.03; camera.current = true
		var preview_glass := preview.find_child("Canopy_Glass",true,false) as MeshInstance3D
		preview_glass.material_override = preview_glass.material_override.duplicate()
		preview_glass.material_override.set_shader_parameter("scene_reflections_ready",false)
		study_capture = preload("res://canopy_reflections.gd").new(); view.add_child(study_capture)
		var study_materials: Array[ShaderMaterial] = [preview_glass.material_override]
		study_capture.setup(view.find_world_3d(),study_materials,camera); study_camera = camera
		study_capture.update_capture(1.0/120.0,true,camera)
		check(study_capture.views.all(func(face: SubViewport) -> bool: return face.render_target_update_mode == SubViewport.UPDATE_ALWAYS),"All reflection directions refresh every rendered frame")
		check(study_capture.views.size() == 6 and study_capture.views.all(func(face: SubViewport) -> bool: return face.size == Vector2i(256,256)),"Scene capture uses six bounded low-resolution faces")
		check(study_capture.cameras.all(func(face: Camera3D) -> bool: return not (face.cull_mask & (2 | Cockpit.RENDER_LAYER))),"Reflections exclude the player hull and canopy itself")
		var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color(0.12,0.25,0.3); view.add_child(environment)
		var sun := DirectionalLight3D.new(); view.add_child(sun); sun.light_energy = 0
		var dark: Image = await snapshot(view); dark.save_png("res://tests/canopy-unlit.png")
		sun.basis = camera.global_basis * Basis.looking_at(Vector3(-0.5,-0.4,-1),Vector3.UP); sun.light_energy = 1.2
		var lit: Image = await snapshot(view); lit.save_png("res://tests/canopy-sun.png")
		check(brighter(dark,lit) > 100,"Curved glass and scratches catch actual directional light")
		sun.basis = camera.global_basis * Basis.looking_at(Vector3(0.6,0.25,-1),Vector3.UP)
		var angled: Image = await snapshot(view); angled.save_png("res://tests/canopy-angle.png")
		check(brighter(lit,angled) > 100,"Reflection moves across the dome when the light angle changes")
		preview_glass.material_override.set_shader_parameter("scratch_strength",0.0)
		var polished: Image = await snapshot(view)
		polished.save_png("res://tests/canopy-polished.png")
		preview_glass.material_override.set_shader_parameter("grime_strength",0.0)
		var clean: Image = await snapshot(view)
		check(brighter(clean,polished) > 20,"Mottled smudges catch light separately from the scratches")
		check(brighter(dark,clean) < 100,"Clean smooth glass no longer produces the broad white direct-light glare")
		preview_glass.material_override.set_shader_parameter("grime_strength",0.5)
		print("Scratch glint pixels: ",brighter(polished,angled))
		check(brighter(polished,angled) > 20,"Fine surface scratches contribute their own light glints")
		preview_glass.material_override.set_shader_parameter("scratch_strength",scratch_setting)
		sun.light_energy = 0
		var lamp := OmniLight3D.new(); view.add_child(lamp); lamp.global_position = camera.to_global(Vector3(0.4,0.3,-0.2)); lamp.omni_range = 2; lamp.light_energy = 2
		var local: Image = await snapshot(view); local.save_png("res://tests/canopy-lamp.png")
		check(brighter(dark,local) > 100,"Nearby lamps illuminate the glass at night")
		check(dark.get_pixel(320,200).get_luminance() > 0.08,"Unlit centre stays clear rather than becoming an opaque cockpit")
		lamp.light_energy = 0
		preview_glass.material_override.set_shader_parameter("scratch_strength",0.0)
		preview_glass.material_override.set_shader_parameter("grime_strength",0.0)
		preview_glass.material_override.set_shader_parameter("reflection_strength",0.1)
		var reflection_baseline: Image = await snapshot(view)
		var rock := MeshInstance3D.new(); var rock_mesh := SphereMesh.new(); rock_mesh.radius = 0.35; rock_mesh.height = 0.65; rock_mesh.radial_segments = 8; rock_mesh.rings = 4; rock.mesh = rock_mesh
		var rock_material := ShaderMaterial.new(); var rock_shader := Shader.new()
		rock_shader.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO=vec3(1.0,0.19,0.01)*mix(0.25,1.0,step(0.3,fract(UV.y*5.0))); }"
		rock_material.shader = rock_shader; rock.material_override = rock_material; view.add_child(rock)
		rock.global_position = camera.to_global(Vector3(-0.65,0,-1.5))
		var reflected: Image = await snapshot(view); reflected.save_png("res://tests/canopy-orange-left.png")
		for face in range(6): study_capture.views[face].get_texture().get_image().save_png("res://tests/canopy-face-%d.png" % face)
		var orange_right := 0
		for y in range(400):
			for x in range(320,640):
				var color := reflected.get_pixel(x,y)
				var change: Color = color - reflection_baseline.get_pixel(x,y)
				if change.r > 0.01 and change.r > change.g * 1.4 and change.r > change.b * 1.5: orange_right += 1
		print("Opposite-side orange reflection pixels: ",orange_right)
		check(orange_right > 50,"A nearby orange object produces its coloured reflection on the opposite side of the dome")
		rock.global_position = camera.to_global(Vector3(0.65,0,-1.5))
		var opposite: Image = await snapshot(view); opposite.save_png("res://tests/canopy-orange-right.png")
		var orange_left := 0
		for y in range(400):
			for x in range(320):
				var change: Color = opposite.get_pixel(x,y) - reflection_baseline.get_pixel(x,y)
				if change.r > 0.01 and change.r > change.g * 1.4 and change.r > change.b * 1.5: orange_left += 1
		check(orange_left > 50,"Moving the orange object changes the reflection to the other side")
		rock.queue_free(); preview.hide()
		study_capture.update_capture(0.1,false,camera)
		check(study_capture.views.all(func(face: SubViewport) -> bool: return face.render_target_update_mode == SubViewport.UPDATE_DISABLED),"Hidden glass stops all reflection rendering")
		study_capture.free(); study_capture = null
		var grid := MeshInstance3D.new(); grid.mesh = QuadMesh.new(); grid.mesh.size = Vector2(12,8)
		var grid_material := ShaderMaterial.new(); var grid_shader := Shader.new()
		grid_shader.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO = vec3(mix(0.08,0.7,step(0.5,fract(UV.x*40.0)))); }"
		grid_material.shader = grid_shader; grid.material_override = grid_material
		view.add_child(grid); grid.global_transform = camera.global_transform; grid.position += -camera.global_basis.z * 4
		var straight: Image = await snapshot(view)
		var lens := Cockpit.create_refraction(0.6,0.025); view.add_child(lens)
		var warped: Image = await snapshot(view); warped.save_png("res://tests/canopy-refraction.png")
		check(brighter(straight,warped) > 1000,"Curved edges visibly refract the world")
		check(absf(straight.get_pixel(320,200).r - warped.get_pixel(320,200).r) < 0.01,"Centre sightline stays undistorted")
		var overlay := CanvasLayer.new(); view.add_child(overlay)
		var marker := ColorRect.new(); marker.position = Vector2(15,15); marker.size = Vector2(40,25); marker.color = Color(1,0,0); overlay.add_child(marker)
		var hud: Image = await snapshot(view)
		check(hud.get_pixel(20,20).r > 0.99 and hud.get_pixel(20,20).g < 0.01,"HUD remains sharp and is drawn after refraction")
		view.queue_free()
	var combined: Array[String] = ["bubble-cockpit","test-3d-map-instrument"]
	Mods.apply(combined,combined,false)
	game.cockpit_hud.free(); game.cockpit_hud = preload("res://cockpit_hud.gd").new(); game.add_child(game.cockpit_hud)
	game.cockpit_hud.setup(game.pilot,game.equipment,game.world_root,game.game_folder,game.weapons)
	game.cockpit_hud.setup_lighting(game.water_environment,game.sun)
	check(game.cockpit_hud.model_views.size() == 5 and canopy.visible,"Canopy and all five 3D HUD instruments work together")
	if DisplayServer.get_name() != "headless":
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/canopy-3d-hud.png")
	game._set_camera_mode(false); check(not canopy.visible,"Leaving first person removes the dome immediately")
	Mods.apply([],[],false); game.first_person_cockpit.free(); game.first_person_cockpit = Cockpit.new(); game.camera.add_child(game.first_person_cockpit); game.first_person_cockpit.setup(game)
	check(game.first_person_cockpit.model == null,"Disabling the mod restores the unobstructed original view")
	for frame in range(3): await process_frame
	check(game.developer_tabs.is_tab_hidden(panel.get_index()),"Developer Mods controls disappear when no canopy mod is enabled")
	game.queue_free(); await process_frame
	print("First-person cockpit: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
