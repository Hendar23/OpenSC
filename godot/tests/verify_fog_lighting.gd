extends SceneTree
const Natural = preload("res://natural_light.gd")
var failures := 0
var checks := 0
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func capture(view: SubViewport) -> Image:
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func close_colour(a: Color,b: Color) -> bool:
	return Vector3(a.r - b.r,a.g - b.g,a.b - b.b).length() < 0.025
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(0); return
	var view := SubViewport.new(); view.own_world_3d = true; view.size = Vector2i(640,480); view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var world := Node3D.new(); view.add_child(world)
	world.set_meta("bounds",AABB(Vector3(-6,0,-6),Vector3(12,10,12))); world.set_meta("surface_height",10.0)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	var env := environment.environment; env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02,0.12,0.2); env.fog_light_color = env.background_color
	env.fog_enabled = true; env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_energy = 0
	# The material owns fog; prevent the test viewport adding it twice.
	env.fog_density = 0
	world.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.light_energy = 2; world.add_child(sun)
	var camera := Camera3D.new(); camera.position = Vector3(0,3,6); world.add_child(camera); camera.look_at(Vector3(0,3,0)); camera.current = true
	var sphere := MeshInstance3D.new(); sphere.mesh = SphereMesh.new(); sphere.mesh.radius = 0.8; sphere.mesh.height = 1.6; sphere.position = Vector3(0,3,0)
	var glossy := StandardMaterial3D.new(); glossy.albedo_color = Color.BLACK; glossy.roughness = 0.02; glossy.metallic_specular = 1
	sphere.material_override = glossy; world.add_child(sphere)
	var roof := StaticBody3D.new(); roof.collision_layer = 16; roof.position = Vector3(-2,2.5,0); world.add_child(roof)
	var roof_shape := CollisionShape3D.new(); roof_shape.shape = BoxShape3D.new(); roof_shape.shape.size = Vector3(2,0.2,6); roof.add_child(roof_shape)
	var sheltered := MeshInstance3D.new(); sheltered.mesh = BoxMesh.new(); sheltered.mesh.size = Vector3.ONE; sheltered.position = Vector3(-2,1,0)
	var dull := StandardMaterial3D.new(); dull.albedo_color = Color(0.5,0.5,0.5); dull.roughness = 1; sheltered.material_override = dull; world.add_child(sheltered)
	var glow := MeshInstance3D.new(); glow.mesh = SphereMesh.new(); glow.mesh.radius = 0.25; glow.mesh.height = 0.5; glow.position = Vector3(2,3,0)
	var luminous := StandardMaterial3D.new(); luminous.emission_enabled = true; luminous.emission = Color(0.8,0.1,0.1); luminous.emission_energy_multiplier = 3; glow.material_override = luminous; world.add_child(glow)
	await physics_frame; await physics_frame
	var natural := Natural.new(); natural.configure({"sun_depth":20.0,"sun_falloff":5.0}); await natural.build(world,Callable(),32); natural.attach(world)
	natural.lighting(env,1000000,0,1)
	var near := await capture(view)
	var center := Vector2i(camera.unproject_position(sphere.global_position))
	check(near.get_pixelv(center).v > 0.4,"Nearby glossy material retains a visible highlight")
	var converted := sphere.get_active_material(0) as ShaderMaterial
	converted.set_shader_parameter("roughness_value",0.7); converted.set_shader_parameter("specular_value",0.5)
	var matte := await capture(view)
	check(matte.get_pixelv(center).v < 0.2 and matte.get_pixelv(center).v < near.get_pixelv(center).v * 0.3,"Default rough material has a subdued dielectric highlight")
	converted.set_shader_parameter("roughness_value",0.02); converted.set_shader_parameter("specular_value",1.0)
	natural.lighting(env,4,1,1)
	var far := await capture(view); far.save_png("res://tests/fog-lighting-fixed.png")
	var background := far.get_pixel(10,10)
	check(close_colour(far.get_pixelv(center),background),"Fully fogged specular highlights match background water")
	check(close_colour(far.get_pixelv(Vector2i(camera.unproject_position(glow.global_position))),background),"Emission also disappears into full fog")
	check(natural.visibility(sheltered.global_position) == 0,"Sheltered test object receives no natural light")
	camera.position = Vector3(-2,1,6); camera.look_at(sheltered.global_position)
	var hidden_view := await capture(view)
	check(close_colour(hidden_view.get_pixelv(Vector2i(camera.unproject_position(sheltered.global_position))),background),"Fully fogged shelter converges to outdoor water instead of revealing distant fragments")
	natural.lighting(env,10,1,1)
	sheltered.get_active_material(0).set_shader_parameter("albedo_color",Color.BLACK)
	var entrance_view := await capture(view); entrance_view.save_png("res://tests/fog-entrance-outside.png")
	var entrance := entrance_view.get_pixelv(Vector2i(camera.unproject_position(sheltered.global_position)))
	check(entrance.b < background.b * 0.9,"Outdoor view into shelter reduces blue fog along the covered part of the view")
	var mixed_edge := false
	for step in range(40):
		var edge := Vector3(-1.3 + step * 0.02,1,0)
		if natural.visibility(edge) > 0.5 and natural.visibility(edge,true) < natural.visibility(edge) * 0.6: mixed_edge = true
	check(mixed_edge,"Mixed roof edge loses blue fog before it loses all surface illumination")
	# View from below the roof: distant exposed samples must not paint blue
	# emission onto the interior. A matte black sphere isolates the fog term.
	camera.position = Vector3(-2,1,0); camera.look_at(Vector3(0,3,0))
	glossy.metallic_specular = 0; glossy.metallic = 0; glossy.roughness = 1
	sphere.get_active_material(0).set_shader_parameter("specular_value",0.0)
	sphere.get_active_material(0).set_shader_parameter("roughness_value",1.0)
	natural.configure({"cave_ambient":0.0}); natural.lighting(env,1,0,1)
	var interior := await capture(view)
	interior.save_png("res://tests/fog-entrance-interior.png")
	check(interior.get_pixelv(Vector2i(camera.unproject_position(sphere.global_position))).v < 0.02,"Sheltered viewer cannot see blue fog glow on an exposed distant surface")
	print("Fog lighting: %d checks, %d failures" % [checks,failures])
	view.queue_free(); await process_frame; quit(1 if failures else 0)
