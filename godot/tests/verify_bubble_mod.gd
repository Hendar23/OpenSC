extends SceneTree
const Mods = preload("res://mod_registry.gd")
const Visual = preload("res://bubble_visual.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	Mods.initialize(false)
	Mods.apply(["3d-bubbles"], Mods.order, false)
	check(Mods.candidates("model.bubble").size() == 1, "Mod discovers the isolated bubble")
	var mesh := Visual.replacement()
	check(mesh != null and mesh is ArrayMesh, "A real 3D mesh replaces the sprite")
	if mesh == null: quit(1); return
	check(mesh.get_aabb().get_center().length() < 0.01 and mesh.get_aabb().size.distance_to(Vector3.ONE) < 0.03, "Bubble is centred with the original particle diameter")
	check(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() < 2400, "Bubble geometry is reduced for instanced particle rendering")
	check(Visual.death_mesh(null) == mesh, "Death effects share the cached bubble model")
	check(mesh.surface_get_material(0) is ShaderMaterial and mesh.surface_get_material(0).get_shader_parameter("has_texture"), "Water-bubble shading retains the source texture")
	var wake := preload("res://propeller_bubbles.gd").new(); root.add_child(wake); wake.set_physics_process(false); wake.configure(null)
	check(wake.instances.mesh == mesh, "Propeller wakes use the model through MultiMesh")
	wake.emit_from(0, Vector3.ZERO, Vector3.BACK, 1, 10, 1); wake.advance(0.1)
	check(wake.instances.visible_instance_count == 8 and wake.particles[0].position.y > 0, "3D bubbles retain normal emission and rising motion")
	if DisplayServer.get_name() != "headless":
		var viewport := SubViewport.new(); viewport.size = Vector2i(640, 480); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
		var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.02, 0.2, 0.26); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.5, 0.8, 1); env.environment.ambient_light_energy = 0.8; viewport.add_child(env)
		var sun := DirectionalLight3D.new(); viewport.add_child(sun); sun.rotation_degrees = Vector3(-45, -30, 0)
		var camera := Camera3D.new(); viewport.add_child(camera); camera.position = Vector3(0, 0, 2.5); camera.current = true
		for i in range(3):
			var bubble := MeshInstance3D.new(); bubble.mesh = mesh; viewport.add_child(bubble); bubble.position = Vector3((i - 1) * 0.65, (i - 1) * 0.3, 0); bubble.scale = Vector3.ONE * (0.5 + i * 0.2)
		var small_wake := preload("res://propeller_bubbles.gd").new(); viewport.add_child(small_wake); small_wake.set_physics_process(false); small_wake.configure(null)
		for i in range(12): small_wake.particles.append({"position":Vector3(-0.8 + i * 0.15,-0.6,0),"drift":Vector3.ZERO,"rise":0.0,"age":0.0,"size":0.06})
		small_wake.advance(0)
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		var preview := viewport.get_texture().get_image(); preview.save_png("res://tests/bubble-mod-preview.png")
		var visible_bubbles := 0
		for particle in small_wake.particles:
			var centre := Vector2i(camera.unproject_position(particle.position))
			var contrast := 0.0
			var background := preview.get_pixelv(centre + Vector2i(0,12))
			for y in range(-5,6):
				for x in range(-5,6): contrast = maxf(contrast,preview.get_pixelv(centre + Vector2i(x,y)).v - background.v)
			if contrast > 0.08: visible_bubbles += 1
		check(visible_bubbles == 12, "Small faded wake bubbles have visible contrast against the sea")
		viewport.queue_free()
	var game := preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete and game.pilot.bubbles.instances.mesh == mesh and game.menu_backdrop.wake.instances.mesh == mesh, "The loaded game and live main menu use the enabled mod")
	var death := preload("res://submarine_death.gd").new(); game.world_root.add_child(death)
	death.setup_submarine(game.pilot, game.submarine_bubble_texture)
	check(death.bubbles != null and death.bubbles.mesh == mesh, "Submarine death uses the same 3D bubble surface")
	game.queue_free(); await process_frame
	Mods.apply([], Mods.order, false); wake.configure(null)
	check(wake.instances.mesh is QuadMesh and Visual.replacement() == null and Visual.death_mesh(null) is QuadMesh, "Disabling the mod restores sprites for wakes and death effects")
	wake.free()
	print("3D bubble mod: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
