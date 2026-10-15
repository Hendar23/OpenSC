extends SceneTree
const Particles = preload("res://water_particles.gd")
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(text)
func _initialize() -> void: call_deferred("run")
func snapshot(view: SubViewport) -> Image:
 for frame in range(4): await process_frame
 await RenderingServer.frame_post_draw
 return view.get_texture().get_image()
func lit_pixels(image: Image) -> int:
 var count := 0
 for y in range(image.get_height()):
  for x in range(image.get_width()):
   if image.get_pixel(x,y).v > 0.04: count += 1
 return count
func run() -> void:
 var view := SubViewport.new(); view.size = Vector2i(256,256); view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
 var camera := Camera3D.new(); view.add_child(camera); camera.current = true
 var particles := Particles.new(); view.add_child(particles)
 particles.camera = camera; particles.active = true; particles.configure({"count":600})
 particles.set_process(false)
 check(particles.multimesh.instance_count == ceili(600.0 * 6.0 / PI),"Periodic cube preserves spherical density")
 var buffer := particles.multimesh.buffer
 particles._process(1.0)
 check(particles.multimesh.buffer == buffer,"Animation never rewrites per-instance transforms/custom data")
 check(is_equal_approx(particles.drift_distance,0.06),"Drift advances in game time")
 camera.position = Vector3(500,-200,800); particles._process(0)
 check(particles.global_position == camera.global_position and particles.material.get_shader_parameter("cloud_center") == camera.global_position,"Cloud bounds and shader follow distant camera")
 check(particles.custom_aabb.has_point(Vector3(12,0,0)),"Culling bounds include shader positions")
 particles.configure({"drift":0.0,"radius":3.0}); particles._process(100)
 check(is_equal_approx(particles.drift_distance,0.06),"Zero drift preserves current phase")
 check(particles.multimesh.buffer == buffer,"Radius/drift changes do not rebuild instances")
 var clock := particles.drift_distance; particles.active = false; particles._process(10)
 check(not particles.visible and particles.drift_distance == clock,"Inactive effects neither render nor advance")
 particles.active = true; particles.configure({"enabled":false}); particles._process(10)
 check(not particles.visible and particles.drift_distance == clock,"Disabled settings freeze animation")
 particles.configure({"enabled":true,"count":4000,"size":0.08,"radius":3.0,"visibility":1.0,"drift":0.3}); particles._process(0)
 if DisplayServer.get_name() != "headless":
  var still := await snapshot(view)
  check(lit_pixels(still) > 100,"GPU cloud renders after long-distance camera travel")
  particles._process(2.0)
  var moving := await snapshot(view); var changed := 0
  for y in range(moving.get_height()):
   for x in range(moving.get_width()):
    if moving.get_pixel(x,y) != still.get_pixel(x,y): changed += 1
  check(changed > 100,"Shader drift visibly moves specks without CPU transform uploads")
 particles.configure({"count":0}); particles._process(1)
 check(particles.multimesh.instance_count == 0,"Zero density clears all instances")
 view.free()
 print("GPU water particles: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
