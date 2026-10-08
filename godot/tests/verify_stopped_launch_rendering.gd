extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 if DisplayServer.get_name() == "headless": push_error("This test requires a renderer"); quit(1); return
 preload("res://mod_registry.gd").initialize(false)
 var viewport := SubViewport.new(); viewport.size = Vector2i(256,256); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
 var environment := WorldEnvironment.new(); var settings := Environment.new(); settings.background_mode = Environment.BG_COLOR; settings.background_color = Color.BLACK; environment.environment = settings; viewport.add_child(environment)
 var pilot := preload("res://submarine_controller.gd").new(); pilot.remember_settings = false; viewport.add_child(pilot); pilot.set_physics_process(false)
 var folder := preload("res://asset_paths.gd").find_game_folder()
 pilot.visual = preload("res://clump_loader.gd").load_submarine(folder.path_join("CLUMPS/SUB.DFF")); pilot.add_child(pilot.visual)
 var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.current = true; viewport.add_child(camera)
 var meshes := pilot.visual.find_children("*","MeshInstance3D",true,false)
 var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = Color(1,.4,0); material.cull_mode = BaseMaterial3D.CULL_DISABLED
 for mesh in meshes: mesh.material_override = material
 pilot.visual.hide(); pilot.global_position = Vector3(210,150,130)
 pilot.movement.reset_motion(); pilot.angles = Vector3.ZERO; pilot.refresh_visual_pose()
 check(not pilot.visual.visible,"Refreshing a loaded pose keeps the docked sub hidden")
 pilot.reveal_visual()
 for frame in range(4): await process_frame
 for part in pilot.visual.find_children("*","Node3D",true,false): part.get_global_transform_interpolated()
 pilot.visual.hide(); pilot.global_transform = Transform3D(Basis(Vector3.UP,1.1),Vector3(310,152,255))
 var visual_id := pilot.visual.get_instance_id()
 pilot.reset_visual_history(); pilot.reveal_visual()
 for part in pilot.visual.find_children("*","Node3D",true,false):
  check(part.get_global_transform_interpolated().is_equal_approx(part.global_transform),"Loading another dock clears the entire cached display pose: " + str(part.name))
 check(pilot.visual.get_instance_id() == visual_id and meshes.all(func(mesh: MeshInstance3D) -> bool: return is_instance_valid(mesh) and mesh.is_inside_tree()),"Clearing display history preserves the original model and its mesh references")
 var position_before := pilot.global_position
 check(pilot.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,"Frozen launch renders the whole submarine without interpolation")
 var roles := ["Hull/LeftPod/Mesh_2","Hull/RightPod/Mesh_4","Hull/LeftPod/LeftPropeller/Mesh_1","Hull/RightPod/RightPropeller/Mesh_3","Hull/RearPropeller/Mesh_0"]
 for path in roles:
  for mesh in meshes: mesh.hide()
  var mesh := pilot.visual.get_node(path) as MeshInstance3D; mesh.show()
  var bounds: AABB = mesh.global_transform * mesh.get_aabb(); var center := bounds.get_center()
  camera.size = maxf(bounds.size.length() * 1.5,.1); camera.global_position = center + Vector3(.4,.3,.8); camera.look_at(center)
  for frame in range(3): await process_frame
  # Check actual pixels rather than trusting each part's visibility flag.
  pilot.reveal_visual()
  for frame in range(4): await process_frame
  await RenderingServer.frame_post_draw
  var image := viewport.get_texture().get_image(); var pixels := 0
  for y in range(image.get_height()):
   for x in range(image.get_width()):
    if image.get_pixel(x,y).r > .5: pixels += 1
  check(pixels > 100,"Stopped saved-launch part is actually rendered: " + path)
  print(path," rendered pixels ",pixels)
  image.save_png("res://tests/stopped-" + path.get_file() + ".png")
 check(pilot.global_position == position_before and pilot.angles == Vector3.ZERO and pilot.linear_velocity == Vector3.ZERO,"All launch parts render without moving the hull or spinning a propeller")
 pilot.active = true
 check(pilot.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON,"Piloting restores interpolation after the frozen launch")
 viewport.queue_free(); await process_frame
 print("Stopped launch rendering: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
