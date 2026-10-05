extends SceneTree
const Natural = preload("res://natural_light.gd")
var checks := 0
var failures := 0
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("_run")
func block(world: Node3D, position: Vector3, size: Vector3) -> MeshInstance3D:
	var body := StaticBody3D.new(); body.collision_layer = 1 | 16; body.position = position; world.add_child(body)
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = size; shape.shape = box; body.add_child(shape)
	var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); mesh.mesh.size = size
	var material := StandardMaterial3D.new(); material.albedo_color = Color(0.6,0.6,0.6); material.roughness = 1; mesh.material_override = material; body.add_child(mesh)
	return mesh
func snapshot(viewport: SubViewport) -> Image:
	await process_frame; await RenderingServer.frame_post_draw; await process_frame; await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func _run() -> void:
	var viewport := SubViewport.new(); viewport.own_world_3d = true; viewport.size = Vector2i(640,480); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var world := Node3D.new(); viewport.add_child(world); world.set_meta("bounds",AABB(Vector3(-6,-1,-6),Vector3(12,11,12))); world.set_meta("surface_height",10.0)
	block(world,Vector3(0,-0.1,0),Vector3(12,0.2,12)); block(world,Vector3(-2,2,0),Vector3(3,0.2,3))
	var glow := MeshInstance3D.new(); glow.mesh = SphereMesh.new(); glow.mesh.radius = 0.12; glow.mesh.height = 0.24; glow.position = Vector3(-2,0.5,-0.8)
	var glow_material := StandardMaterial3D.new(); glow_material.emission_enabled = true; glow_material.emission = Color(0.05,0.2,1); glow_material.emission_energy_multiplier = 2; glow.material_override = glow_material; world.add_child(glow)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color.BLACK; environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color.WHITE; environment.environment.ambient_light_energy = 0.32; world.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees.x = -90; sun.light_energy = 1.2; world.add_child(sun)
	var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(0,1,7); camera.look_at(Vector3.ZERO); camera.current = true
	var lamp := OmniLight3D.new(); lamp.position = Vector3(-2,0.8,0); lamp.omni_range = 2; lamp.light_energy = 3; world.add_child(lamp); lamp.hide()
	await physics_frame; await physics_frame
	var natural := Natural.new(); natural.configure({"sun_depth":20.0,"sun_falloff":5.0,"cave_ambient":0.0}); await natural.build(world,Callable(),128); natural.attach(world); natural.lighting(environment.environment,1000000,5,1.8)
	check(natural.visibility(Vector3(2,0,0)) > 0.99,"Open shallow water receives natural illumination")
	check(natural.visibility(Vector3(-2,0,0)) < 0.01,"Roof blocks ambient light beneath it")
	natural.configure({"sun_depth":5.0,"sun_falloff":3.0})
	check(natural.visibility(Vector3(2,1,0)) == 0,"Depth falloff reaches complete darkness")
	check(natural.visibility(Vector3(2,4,0)) > 0 and natural.visibility(Vector3(2,4,0)) < 1,"Depth fade transitions gradually")
	if DisplayServer.get_name() != "headless":
		natural.configure({"sun_depth":20.0,"sun_falloff":5.0})
		var daylight: Image = await snapshot(viewport); daylight.save_png("res://tests/natural-light-shallow.png")
		var cave_pixel := Vector2i(camera.unproject_position(Vector3(-2,0,0))); var open_pixel := Vector2i(camera.unproject_position(Vector3(2,0,0)))
		print("Natural light pixels: cave=",daylight.get_pixelv(cave_pixel).v," open=",daylight.get_pixelv(open_pixel).v)
		check(daylight.get_pixelv(cave_pixel).v < 0.02 and daylight.get_pixelv(open_pixel).v > 0.2,"Rendered cave is black while open seabed stays illuminated")
		natural.configure({"cave_ambient":0.25})
		var ambient: Image = await snapshot(viewport)
		check(ambient.get_pixelv(cave_pixel).v > daylight.get_pixelv(cave_pixel).v + 0.05,"Cave ambient adjustment lights sheltered surfaces")
		natural.configure({"cave_ambient":0.0})
		var glow_pixel := Vector2i(camera.unproject_position(glow.global_position))
		check(daylight.get_pixelv(glow_pixel).b > 0.3,"Emissive objects remain bright inside dark caves")
		lamp.show(); var lit: Image = await snapshot(viewport); lit.save_png("res://tests/natural-light-cave-lamp.png")
		check(lit.get_pixelv(cave_pixel).v > 0.1,"Local lights can illuminate a sheltered cave")
		natural.configure({"sun_depth":2.0,"sun_falloff":3.0}); var deep: Image = await snapshot(viewport); deep.save_png("res://tests/natural-light-deep-lamp.png")
		check(deep.get_pixelv(open_pixel).v < 0.02 and deep.get_pixelv(cave_pixel).v > 0.1,"Deep water remains black while local light still works")
	viewport.queue_free(); await process_frame
	print("Natural lighting: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
