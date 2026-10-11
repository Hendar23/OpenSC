extends SceneTree
const Game = preload("res://game.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
 checks += 1
 if not ok: failures += 1; push_error(message)
func run():
 var game := Game.new(); game.remember_preferences = false; root.add_child(game)
 for frame in 1200:
  if game.startup_complete: break
  await physics_frame
 check(game.startup_complete,"World loads with sun shafts")
 if not game.startup_complete: quit(1); return
 game.set_process(false); game.set_physics_process(false)
 game.front_end.show_menu(false); game._show_main_menu()
 var shafts: Node3D = game.sun_shafts
 shafts.set_physics_process(false)
 shafts.random.seed = 42
 var view: Camera3D = game.menu_backdrop.view
 var original_pose := view.global_transform
 var surface: float = game.world_root.get_meta("surface_height")
 view.global_position = Vector3(game.world_root.get_meta("bounds").position.x - 60.0,surface - 6.0,game.world_root.get_meta("bounds").position.z - 60.0)
 view.look_at(view.global_position + Vector3(0,-0.2,-1))
 game.menu_backdrop.daylight.hour = 12.0; game._update_daylight()
 for frame in 100: shafts._physics_process(0.1)
 check(shafts.patches.size() == 8 and shafts.get_child_count() == 8,"Shaft pool is bounded to eight patches")
 check(shafts.patches.any(func(p: Dictionary) -> bool: return p.node.visible),"Daylight creates visible patches while in the paused menu")
 for p in shafts.patches:
  check(is_equal_approx(p.source.y,surface),"Patch starts at surface")
  check(p.node.global_basis.z.dot(-game.menu_backdrop.daylight.sun_direction()) > 0.999,"Shaft follows sun direction")
  check(p.node.mesh.size.z <= 45.0,"Shaft reach stays bounded")
 game.front_end.menu_layer.hide()
 for actor in game.menu_backdrop.actors: actor.node.set_physics_process(false)
 game.menu_backdrop.set_process(false)
 if DisplayServer.get_name() != "headless":
  for frame in 4: await process_frame
  await RenderingServer.frame_post_draw
  var on := root.get_texture().get_image()
  on.save_png("res://tests/sun-shafts-on.png")
  shafts.set_enabled(false)
  for frame in 4: await process_frame
  await RenderingServer.frame_post_draw
  var off := root.get_texture().get_image()
  off.save_png("res://tests/sun-shafts-off.png")
  var pixels := 0
  for y in range(on.get_height()):
   for x in range(on.get_width()):
    if on.get_pixel(x,y).is_equal_approx(off.get_pixel(x,y)) == false: pixels += 1
  print("Shaft image changed pixels ",pixels)
  check(pixels > 100,"Shaft shader renders a visible effect")
 shafts.set_enabled(false); check(not shafts.is_physics_processing() and shafts.patches.all(func(p: Dictionary) -> bool: return not p.node.visible),"Off stops updates and immediately hides all patches")
 shafts.set_enabled(true); shafts.set_physics_process(false)
 for frame in 50: shafts._physics_process(0.1)
 var patch: Dictionary = shafts.patches[0]
 patch.age = 1.0; patch.lifetime = 100.0
 var roof := StaticBody3D.new(); roof.collision_layer = 1
 var collision := CollisionShape3D.new(); collision.shape = BoxShape3D.new(); collision.shape.size = Vector3(8,0.2,8)
 roof.add_child(collision); game.world_root.add_child(roof); roof.global_position = patch.source + Vector3.DOWN * 2.0
 for frame in 2: await physics_frame
 shafts.cursor = 0; shafts.elapsed = 0.1; shafts._physics_process(0.1)
 check(patch.node.mesh.size.z < 2.1,"Solid overhead geometry clips the shaft before it passes through")
 roof.free()
 game.menu_backdrop.daylight.hour = 15.0
 shafts.cursor = 0; shafts.elapsed = 0.1; shafts._physics_process(0.1)
 check(patch.node.global_basis.z.dot(-game.menu_backdrop.daylight.sun_direction()) > 0.999,"Existing shaft follows the afternoon sun")
 shafts.set_enabled(true); game.menu_backdrop.daylight.hour = 0.0; shafts._physics_process(0.1)
 check(shafts.patches.all(func(p: Dictionary) -> bool: return not p.node.visible),"Night disables shafts")
 game.menu_backdrop.daylight.hour = 12.0; view.global_position.y = surface - 60.0; shafts._physics_process(0.1)
 check(shafts.patches.all(func(p: Dictionary) -> bool: return not p.node.visible),"Deep water disables shafts")
 view.global_transform = original_pose
 game.front_end.gameplay_menu._toggle_sun_shafts()
 check(not shafts.enabled,"General menu toggle applies immediately to the loaded world")
 game.free(); print("Sun shafts: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
