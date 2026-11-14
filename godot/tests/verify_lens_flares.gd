extends "res://tests/test_scene_tree.gd"
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func capture(viewport: SubViewport) -> Image:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func brightness(image: Image) -> float:
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width(): total += image.get_pixel(x,y).v
	return total
func run() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(640,360); viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var world := Node3D.new(); viewport.add_child(world)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color.BLACK; world.add_child(env)
	var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(0,0,4); camera.current = true
	var manager := preload("res://lens_flares.gd").new(); world.add_child(manager)
	var transient := OmniLight3D.new(); world.add_child(transient); transient.free()
	var light := OmniLight3D.new(); light.light_energy = 3; light.light_color = Color(1,0.6,0.2); world.add_child(light)
	for frame in range(3): await process_frame
	var flare := light.get_node_or_null("LensFlare")
	check(flare != null,"New local lights automatically receive an optical flare")
	check(preload("res://lens_flare.gd").attach(light) == flare and light.get_child_count() == 1,"Repeated discovery does not duplicate flare meshes")
	check(flare.flare_material.get_shader_parameter("flare_color") == Vector3(1,0.6,0.2),"Flare follows the source colour")
	light.light_energy = 0; flare.update_light()
	check(not flare.visible,"Switched-off light has no optical flare")
	light.light_energy = 3; flare.update_light()
	var history := preload("res://replay_visual.gd").new(); history.setup(flare,0.0); history.record(0,0.0)
	light.light_energy = 1; light.light_color = Color.BLUE; flare.update_light(); history.record(1,0.05)
	var proxies := Node3D.new(); world.add_child(proxies)
	history.show_at(proxies,0,0,0)
	check(history.proxy.material_override.get_shader_parameter("flare_color") == Vector3(1,0.6,0.2),"Replay restores earlier flare colour")
	history.show_at(proxies,1,0,0.05)
	check(history.proxy.material_override.get_shader_parameter("flare_color") == Vector3(0,0,1) and is_equal_approx(history.proxy.material_override.get_shader_parameter("brightness"),0.9),"Replay retains animated flare brightness and colour")
	proxies.free(); light.light_energy = 3; light.light_color = Color(1,0.6,0.2); flare.update_light()
	var spot := SpotLight3D.new(); spot.position.x = 1; spot.light_energy = 3; world.add_child(spot)
	for frame in range(3): await process_frame
	check(spot.get_node("LensFlare").flare_material.get_shader_parameter("forward_sign") == -1.0,"Spotlight flare uses the real forward direction")
	var disabled := OmniLight3D.new(); disabled.process_mode = Node.PROCESS_MODE_DISABLED; world.add_child(disabled)
	for frame in range(3): await process_frame
	check(not disabled.has_node("LensFlare"),"Replay light proxies do not acquire duplicate live flares")
	var housing := Node3D.new(); world.add_child(housing)
	var aperture := MeshInstance3D.new(); aperture.name = "IlluminatedLens"; aperture.mesh = QuadMesh.new(); aperture.position = Vector3(2,0,0); aperture.hide(); housing.add_child(aperture)
	var headlamp := SpotLight3D.new(); headlamp.name = "DeepSeaBeam"; headlamp.position = Vector3(2,0,0.3); headlamp.light_energy = 0; housing.add_child(headlamp)
	for frame in range(3): await process_frame
	check(headlamp.get_node("LensFlare").global_position.is_equal_approx(aperture.global_position+Vector3(0,0,-0.004)),"Deep-sea flare is seated at the real illuminated aperture, outside its housing")
	housing.free()
	var pulse := preload("res://pulse_light.gd").new(); pulse.peak_energy = 3; world.add_child(pulse); pulse.update_pulse()
	for frame in range(3): await process_frame
	pulse.set_process(false); pulse.elapsed = 0.75; pulse.update_pulse(); pulse.get_node("LensFlare").update_light()
	check(not pulse.get_node("LensFlare").visible,"Beacon flashing also switches its optical flare off")
	pulse.free()
	var search := preload("res://searchlight.gd").new(); world.add_child(search); search.configure("",{})
	for frame in range(3): await process_frame
	check(search.pivot.has_node("LensFlare"),"Building searchlight receives a flare on its sweeping pivot")
	search.configure("",{})
	for frame in range(3): await process_frame
	check(search.pivot.has_node("LensFlare"),"Reconfiguring a searchlight restores its flare")
	search.free(); disabled.free()
	spot.hide()
	if DisplayServer.get_name() != "headless":
		var clear := await capture(viewport); clear.save_png("res://tests/lens-flare-clear.png")
		var clear_level := brightness(clear)
		check(clear_level > 5,"Visible point light renders its halo and streaks")
		paused = true; preload("res://lens_flare.gd").set_enabled(false)
		check(brightness(await capture(viewport)) < 0.01,"General option immediately disables rendered optical effects even while paused")
		preload("res://lens_flare.gd").set_enabled(true)
		check(brightness(await capture(viewport)) > clear_level*0.9,"General option restores rendered optical effects while paused")
		paused = false
		var wall := MeshInstance3D.new(); wall.mesh = BoxMesh.new(); wall.mesh.size = Vector3(3,3,0.2); wall.position.z = 1.0
		var black := StandardMaterial3D.new(); black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; black.albedo_color = Color.BLACK; wall.material_override = black; world.add_child(wall)
		var blocked := await capture(viewport); blocked.save_png("res://tests/lens-flare-blocked.png")
		check(brightness(blocked) < clear_level*0.01,"Opaque scenery hides the complete flare, including streaks beyond the source")
		wall.free(); light.hide(); spot.show()
		var back := brightness(await capture(viewport))
		spot.rotation.y = PI
		var front := await capture(viewport); front.save_png("res://tests/lens-flare-spot.png")
		check(brightness(front) > 5 and back < brightness(front)*0.01,"Spotlight flare appears only when its beam faces the camera")
		spot.light_energy = 0
		check(brightness(await capture(viewport)) < 0.01,"Turning a spotlight off removes the rendered flare")
		spot.light_energy = 3; spot.spot_range = 0.2
		check(brightness(await capture(viewport)) < 0.01,"Distant sources fade out rather than keeping a screen-sized flare")
		spot.hide()
		env.environment.background_color = Color(0.03,0.28,0.35)
		light.position = Vector3(0.8,0.3,0); light.light_energy = 0.7; light.show()
		var daytime := await capture(viewport); daytime.save_png("res://tests/lens-flare-daytime.png")
		light.hide(); var daytime_plain := await capture(viewport)
		var source_pixel := camera.unproject_position(light.global_position); var ghost_pixels := 0
		for y in daytime.get_height():
			for x in daytime.get_width():
				if Vector2(x,y).distance_to(source_pixel) < 40: continue
				var optical := daytime.get_pixel(x,y)-daytime_plain.get_pixel(x,y)
				if maxf(optical.r,maxf(optical.g,optical.b)) > 0.015: ghost_pixels += 1
		check(ghost_pixels > 100,"Coloured optical reflections are visibly distinct from the source glow against daytime water")
		env.environment.background_color = Color.BLACK
		var sun := DirectionalLight3D.new(); sun.light_energy = 1.2
		sun.basis = Basis.looking_at(-Vector3(0.25,0.968,0).normalized(),Vector3.FORWARD); world.add_child(sun)
		camera.position = Vector3(0,-2,0); camera.look_at(Vector3(0,0,0),Vector3.FORWARD)
		var water := MeshInstance3D.new(); water.mesh = PlaneMesh.new(); water.mesh.size = Vector2(20,20)
		var dark := StandardMaterial3D.new(); dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; dark.albedo_color = Color.BLACK; dark.cull_mode = BaseMaterial3D.CULL_DISABLED
		water.material_override = dark; world.add_child(water)
		var solar_image := await capture(viewport); solar_image.save_png("res://tests/lens-flare-sun.png")
		var solar_level := brightness(solar_image)
		check(sun.has_node("LensFlare") and solar_level > 30,"Sunlight produces a visible optical flare through the water surface")
		dark.albedo_color = Color(0.14,0.55,0.65)
		var bright_solar := await capture(viewport)
		var solar_mesh: MeshInstance3D = sun.get_node("LensFlare"); solar_mesh.set_process(false); solar_mesh.hide()
		var bright_plain := await capture(viewport); var solar_ghost_pixels := 0
		for y in bright_solar.get_height():
			for x in range(350,550):
				var optical := bright_solar.get_pixel(x,y)-bright_plain.get_pixel(x,y)
				if maxf(optical.r,maxf(optical.g,optical.b)) > 0.03: solar_ghost_pixels += 1
		check(solar_ghost_pixels > 100,"Solar reflections retain visible contrast away from the sun on bright daytime water")
		bright_solar.save_png("res://tests/lens-flare-sun-bright.png")
		solar_mesh.show(); solar_mesh.set_process(true); dark.albedo_color = Color.BLACK
		var roof := MeshInstance3D.new(); roof.mesh = BoxMesh.new(); roof.mesh.size = Vector3(20,0.2,20); roof.position.y = -1; roof.material_override = dark; world.add_child(roof)
		check(brightness(await capture(viewport)) < solar_level*0.01,"A roof below the surface blocks all solar rings and reflections")
		roof.free(); sun.light_energy = 0
		check(brightness(await capture(viewport)) < 0.01,"Sunset/night clears solar optical effects")
		sun.light_energy = 1.2; camera.look_at(camera.position+Vector3.DOWN,Vector3.FORWARD)
		check(brightness(await capture(viewport)) < 0.01,"Looking away from the sun clears solar optical effects")
		camera.position = Vector3(0,2,0); camera.look_at(camera.position+Vector3.UP,Vector3.FORWARD)
		check(brightness(await capture(viewport)) > 30,"Photo camera above water retains the unobstructed solar flare")
		sun.free(); water.free()
	light.queue_free(); await process_frame; await process_frame
	check(not is_instance_valid(flare),"Removing a source also frees its flare")
	viewport.free(); print("Lens flares: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
