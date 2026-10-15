extends SceneTree
const Natural = preload("res://natural_light.gd")
var failures := 0
var checks := 0
func check(ok: bool, text: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(text)
func _initialize() -> void: call_deferred("run")
func snapshot(view: SubViewport) -> Image:
 for frame in range(6): await process_frame
 await RenderingServer.frame_post_draw
 return view.get_texture().get_image()
func run() -> void:
 var view := SubViewport.new(); view.size = Vector2i(256,256); view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
 var world := Node3D.new(); view.add_child(world)
 var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.fog_enabled = true; env.environment.fog_mode = Environment.FOG_MODE_DEPTH; env.environment.fog_depth_begin = 1; env.environment.fog_depth_end = 10; env.environment.fog_sky_affect = 0; world.add_child(env)
 var camera := Camera3D.new(); camera.far = 200; world.add_child(camera); camera.current = true
 var wall := MeshInstance3D.new(); wall.mesh = QuadMesh.new(); wall.mesh.size = Vector2(20,40); wall.position = Vector3(-10,0,-20); world.add_child(wall)
 var original := StandardMaterial3D.new(); original.albedo_color = Color.BLACK; wall.material_override = original
 var natural := Natural.new(); natural.attach(wall)
 if DisplayServer.get_name() != "headless":
  for colour in [Color(0.005,0.48,0.56),Color(0.006,0.02,0.055),Color(0.0225,0.024,0.0264)]:
   env.environment.background_color = Natural.background_colour(colour); env.environment.fog_light_color = colour; natural.lighting(env.environment,10,1,1)
   var frame := await snapshot(view); var fog := frame.get_pixel(80,128); var background := frame.get_pixel(180,128)
   check(Vector3(fog.r,fog.g,fog.b).distance_to(Vector3(background.r,background.g,background.b)) < 0.015,"Fully fogged geometry matches clear water by day, night and in caves")
 wall.free(); camera.position.z = 6; env.environment.background_color = Color.BLACK; env.environment.fog_enabled = false; natural.lighting(env.environment,1000000,0,1)
 var beam := MeshInstance3D.new(); beam.mesh = BoxMesh.new(); beam.mesh.size = Vector3(3,3,4); world.add_child(beam)
 var shader := ShaderMaterial.new(); shader.shader = preload("res://sun_shafts.gdshader"); shader.set_shader_parameter("beam_width",3.0); shader.set_shader_parameter("beam_length",4.0); shader.set_shader_parameter("strength",5.0); shader.set_shader_parameter("surface_height",10.0); shader.set_shader_parameter("view_range",100.0); beam.material_override = shader
 var blocker := MeshInstance3D.new(); blocker.mesh = BoxMesh.new(); blocker.mesh.size = Vector3(4,4,0.2); blocker.position.z = 3; world.add_child(blocker)
 var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = Color.BLACK; blocker.material_override = material
 if DisplayServer.get_name() != "headless":
  var blocked := await snapshot(view)
  check(blocked.get_pixel(100,128).v < 0.015,"Opaque foreground clips a light volume in this renderer")
  material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL; natural.attach(blocker)
  blocked = await snapshot(view)
  check(blocked.get_pixel(100,128).v < 0.015,"Natural-light surfaces also occlude the volume")
  blocker.hide(); var open := await snapshot(view)
  check(open.get_pixel(100,128).v > 0.03,"Removing the blocker reveals the ray-marched volume")
 view.free()
 print("Renderer water/depth: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
