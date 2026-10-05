extends SceneTree
const Water = preload("res://water_visuals.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func changed_pixels(first: Image, second: Image) -> int:
	var changed := 0
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			if first.get_pixel(x,y) != second.get_pixel(x,y): changed += 1
	return changed
func snapshot(viewport: SubViewport) -> Image:
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func _run() -> void:
	var water := Water.new(); water.fog(1000000,0,1)
	var world := Node3D.new(); root.add_child(world)
	var floor := MeshInstance3D.new(); floor.mesh = PlaneMesh.new(); floor.mesh.size = Vector2(8,8)
	var original := StandardMaterial3D.new(); original.albedo_color = Color(0.2,0.3,0.22); floor.material_override = original
	world.add_child(floor); water.attach(world)
	# Per-surface overrides preserve the original material and add sunlight only.
	check(floor.get_active_material(0).next_pass != null and original.next_pass == null,"Caustics add a lighting pass without modifying the original material")
	water.configure({"caustics_strength":0.7,"wave_height":0.08})
	check(water.settings.caustics_strength == 0.7 and water.settings.wave_height == 0.08,"Water settings accept tuning")
	if DisplayServer.get_name() == "headless":
		world.queue_free(); await process_frame; print("Water visuals: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0); return
	var viewport := SubViewport.new(); viewport.size = Vector2i(512,512); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport); world.reparent(viewport)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color(0.02,0.12,0.16); environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color.WHITE; environment.environment.ambient_light_energy = 0.1; world.add_child(environment)
	var sun := DirectionalLight3D.new(); world.add_child(sun); sun.basis = Basis.looking_at(Vector3.DOWN,Vector3.FORWARD); sun.shadow_enabled = true; sun.shadow_bias = 0.01; sun.shadow_normal_bias = 0.02
	var roof := MeshInstance3D.new(); roof.mesh = BoxMesh.new(); roof.mesh.size = Vector3(1.6,0.1,1.6); roof.position = Vector3(-1,1,0); world.add_child(roof)
	var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(4,3,4); camera.look_at(Vector3.ZERO); camera.current = true
	water.lighting(2,Vector3.UP)
	for frame in range(120):
		if water.texture.get_image() != null: break
		await process_frame
	water.texture.get_image().save_png("res://tests/caustics-pattern.png")
	water.configure({"caustics_strength":0.0})
	var before: Image = await snapshot(viewport); before.save_png("res://tests/caustics-off.png")
	water.configure({"caustics_strength":0.8})
	var after: Image = await snapshot(viewport); after.save_png("res://tests/caustics-day.png")
	var changed := changed_pixels(before,after); check(changed > 1000,"Caustics visibly brighten sunlit surfaces")
	var pixel := Vector2i(camera.unproject_position(Vector3(-1,0,0.6)))
	var shadow_change := before.get_pixelv(pixel).v - after.get_pixelv(pixel).v
	check(absf(shadow_change) < 0.03,"Shadowed ground remains sheltered from caustics")
	await create_timer(0.5).timeout
	var animated: Image = await snapshot(viewport)
	check(changed_pixels(after,animated) > 500,"Caustics pattern animates")
	water.lighting(2,Vector3.DOWN); sun.light_energy = 0
	water.configure({"caustics_strength":0})
	before = await snapshot(viewport)
	water.configure({"caustics_strength":1.0})
	after = await snapshot(viewport)
	check(changed_pixels(before,after) == 0,"Caustics disappear at night")
	floor.hide(); roof.hide()
	var surface := MeshInstance3D.new(); surface.mesh = PlaneMesh.new(); surface.mesh.size = Vector2(12,12); surface.mesh.subdivide_width = 96; surface.mesh.subdivide_depth = 96; surface.position.y = 2; surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; world.add_child(surface)
	var material := ShaderMaterial.new(); material.shader = preload("res://water_surface.gdshader"); surface.material_override = material; water.surface = material
	water.lighting(2,Vector3.UP); camera.position = Vector3(0,0.5,1); camera.look_at(Vector3(0,2,0))
	water.configure({"wave_height":0.0,"surface_shine":0.5})
	before = await snapshot(viewport)
	water.configure({"wave_height":0.08,"wave_size":3,"wave_speed":1.2})
	after = await snapshot(viewport); after.save_png("res://tests/water-waves.png")
	check(changed_pixels(before,after) > 1000,"Small waves and ripple normals alter the rendered surface")
	print("Caustics changed pixels: ",changed)
	viewport.queue_free(); await process_frame
	print("Water visuals: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
