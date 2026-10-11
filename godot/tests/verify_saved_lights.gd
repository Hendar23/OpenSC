extends SceneTree
const Game = preload("res://game.gd")
const Document = preload("res://map_document.gd")
const Pulse = preload("res://pulse_light.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 preload("res://mod_registry.gd").initialize(false)
 var game = Game.new(); game.remember_preferences = false; root.add_child(game)
 for frame in range(1800):
  if game.startup_complete: break
  await physics_frame
 check(game.startup_complete,"World loads")
 if not game.startup_complete: quit(1); return
 var data = JSON.parse_string(FileAccess.get_file_as_string("res://../Maps/scen1.json"))
 var key := "Scenery/Light_69"
 var light = game.world_root.get_node_or_null(NodePath(key))
 check(light is Pulse,"Saved dock light 69 is restored even without a generated source node")
 if light != null:
  check(light.global_transform.is_equal_approx(Document.decode(data.entities[key].transform)),"User's repositioned light is preserved")
  var dock = game.world_root.get_node("Scenery/DOCKING_0")
  var tip := Vector3(-0.000226,1.681371,-1.903579)
  check(light.global_position.distance_to(dock.to_global(tip + Vector3.UP * 0.04)) < 0.001,"Light sits just above Touka dock's lamp spike")
  check(light.light_mode == "flashing" and light.is_processing(),"Restored light runs its saved flashing style")
  light.set_process(false); light.phase = 0; light.elapsed = 0; light.update_pulse()
  check(light.flare.visible and light.light_energy > 0,"Flare and illumination switch on")
  light._process(light.flash_on_time)
  check(not light.flare.visible and light.light_energy == 0,"Flare and illumination switch off")
  light._process(light.flash_off_time)
  check(light.flare.visible and light.light_energy > 0,"Flashing repeats")
  Document.apply_entities(game.world_root,game.game_folder,data)
  check(game.world_root.get_node(NodePath(key)) == light,"Reapplying map edits reuses the restored light")
  if DisplayServer.get_name() != "headless":
   paused = false; game.set_process(false); game.set_physics_process(false)
   game.front_end.hide_menu(); game.menu_backdrop.close(); game.cockpit_hud.hide()
   game.pilot.freeze = true; game.camera.global_position = dock.to_global(Vector3(4,4,-6))
   game.camera.look_at(dock.to_global(Vector3(0,1.2,0)))
   light.set_process(false); light.phase = 0; light.elapsed = 0; light.update_pulse()
   for frame in range(5): await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://tests/light69-on.png")
   light._process(light.flash_on_time)
   for frame in range(5): await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://tests/light69-off.png")
 for deleted in ["Scenery/Light_59","Scenery/Light_62","Scenery/Light_63","Scenery/Light_68","Scenery/Light_71"]:
  check(not game.world_root.has_node(NodePath(deleted)),"Deleted excess light stays deleted: " + deleted)
 game.queue_free(); await process_frame
 print("Saved lights: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
