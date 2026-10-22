extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func brightness(image: Image) -> float:
	var total := 0.0
	var samples := 0
	for y in range(int(image.get_height()*0.4),int(image.get_height()*0.6)):
		for x in range(int(image.get_width()*0.4),int(image.get_width()*0.6)):
			var color := image.get_pixel(x,y)
			if RenderingServer.get_current_rendering_method() != "gl_compatibility": color = color.srgb_to_linear()
			total += (color.r+color.g+color.b)/3.0
			samples += 1
	return total/maxi(1,samples)
func capture(material: ShaderMaterial, value: float) -> Image:
	material.set_shader_parameter("strength",value)
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run() -> void:
	preload("res://natural_light.gd").ensure_globals()
	RenderingServer.global_shader_parameter_set("osc_replay_active",true)
	RenderingServer.global_shader_parameter_set("osc_replay_time",0.0)
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(256,256)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color.BLACK; root.add_child(environment)
	var camera := Camera3D.new(); root.add_child(camera); camera.position = Vector3(0,0,8); camera.current = true
	var volume := MeshInstance3D.new(); volume.mesh = BoxMesh.new(); volume.mesh.size = Vector3(4,4,20); volume.position.z = -5; root.add_child(volume)
	var shader := Shader.new(); shader.code = preload("res://sun_shafts.gdshader").code
	var material := ShaderMaterial.new(); material.shader = shader; volume.material_override = material
	var settings := {"beam_length":20.0,"beam_width":4.0,"surface_height":20.0,"depth_start":25.0,"depth_end":45.0,"view_range":60.0,"seed":3.0}
	for setting in settings: material.set_shader_parameter(setting,settings[setting])
	var half := await capture(material,0.5); var full := await capture(material,1.0); var off := await capture(material,0.0)
	var faint := brightness(half)-brightness(off); var bright := brightness(full)-brightness(off)
	print("Scattering brightness: half=",faint," full=",bright," ratio=",bright/maxf(faint,0.000001))
	check(faint > 0.005,"Low-strength rays remain visible in clear daytime water")
	check(bright > faint*1.7 and bright < faint*2.3,"Doubling brightness doubles scattering density without gamma dimming")
	check(brightness(off) < 0.001,"Disabled rays add no light")
	volume.free(); camera.free(); environment.free(); await process_frame
	print("Sunshaft density: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
