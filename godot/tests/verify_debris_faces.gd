extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var natural := preload("res://natural_light.gd")
	natural.ensure_globals()
	RenderingServer.global_shader_parameter_set("osc_natural_enabled",false)
	RenderingServer.global_shader_parameter_set("osc_natural_ambient",Vector4(1,1,1,1))
	RenderingServer.global_shader_parameter_set("osc_natural_fog",Vector3(1000000,0,1))
	var viewport := SubViewport.new(); viewport.size = Vector2i(128,128); viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var camera := Camera3D.new(); camera.position.z = 2; camera.current = true; viewport.add_child(camera)
	var mesh := MeshInstance3D.new(); mesh.mesh = QuadMesh.new(); viewport.add_child(mesh)
	var front := Image.create(2,2,false,Image.FORMAT_RGBA8); front.fill(Color.GREEN)
	var back := Image.create(2,2,false,Image.FORMAT_RGBA8); back.fill(Color.RED)
	var material := ShaderMaterial.new(); material.shader = natural.alpha_shader()
	material.set_shader_parameter("has_texture",true)
	material.set_shader_parameter("albedo_texture",ImageTexture.create_from_image(front))
	material.set_shader_parameter("has_backface_texture",true)
	material.set_shader_parameter("backface_texture",ImageTexture.create_from_image(back))
	mesh.material_override = material
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	var front_pixel := viewport.get_texture().get_image().get_pixel(64,64)
	check(front_pixel.g > 0.9 and front_pixel.r < 0.1,"Front face retains the original skin texture")
	mesh.rotation.y = PI
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var back_pixel := viewport.get_texture().get_image().get_pixel(64,64)
	check(back_pixel.r > 0.9 and back_pixel.g < 0.1,"Reverse face renders its separate flesh texture")
	material.set_shader_parameter("opacity",0.0)
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var faded := viewport.get_texture().get_image().get_pixel(64,64)
	check(faded.r < 0.1,"Reverse face obeys the debris fade")
	print("Debris faces: 3 checks, %d failures" % failures)
	quit(1 if failures else 0)
