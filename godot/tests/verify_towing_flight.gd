extends SceneTree
const Pilot = preload("res://submarine_controller.gd")
class TestPilot extends Pilot:
 var pitch_input := 0.0
 var throttle := 1.0
 func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
  movement.velocity = state.linear_velocity; movement.angular_velocity = state.angular_velocity
  movement.step(state.step,state.transform.basis,throttle,0.0,0.0,pitch_input)
  state.linear_velocity = movement.velocity; state.angular_velocity = movement.angular_velocity
var checks := 0
var failures := 0
func check(ok: bool,message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func trial(object_mass: float,pitch: float,saved_profile: bool = false) -> Dictionary:
 var world := Node3D.new(); root.add_child(world); world.set_meta("surface_height",100.0)
 var pilot := TestPilot.new(); pilot.remember_settings = false; pilot.active = true; pilot.controls_enabled = true; world.add_child(pilot)
 pilot.global_position = Vector3(0,-2,0); pilot.pitch_input = pitch; pilot.surface_height = 100.0
 pilot.movement.load_settings(false,"res://submarine_tuning.cfg","res://submarine_tuning.cfg")
 pilot.visual = preload("res://clump_loader.gd").load_submarine("../Original Sub Culture/CLUMPS/SUB.DFF")
 pilot.visual.scale *= pilot.VISUAL_SCALE; pilot.visual.rotation.y = PI; pilot.add_child(pilot.visual); pilot.fit_collision_to_visual()
 var mount := Node3D.new(); mount.position = Vector3(0,-0.2,0.04); pilot.add_child(mount)
 preload("res://submarine_mounts.gd").apply(mount,pilot.visual,"magnet")
 var housing := preload("res://clump_loader.gd").load_clump("../Original Sub Culture/CLUMPS/MAGNET.DFF"); housing.scale *= pilot.VISUAL_SCALE; mount.add_child(housing)
 var magnet := preload("res://submarine_magnet.gd").new(); mount.add_child(magnet); magnet.setup(pilot,housing,"../Original Sub Culture")
 if saved_profile:
  var config := ConfigFile.new(); config.load("res://view_defaults.cfg")
  for pair in [["chain_length","magnet_length"],["speed","magnet_speed"],["water_drag","magnet_water_drag"],["cargo_weight","magnet_cargo_weight"],["pitch_influence","magnet_pitch_influence"]]:
   magnet.set(pair[0],float(config.get_value("view",pair[1],magnet.get(pair[0]))))
 pilot.freeze = true; magnet.set_enabled(true)
 for frame in range(100): await physics_frame
 if object_mass > 0:
  var body := preload("res://salvage_body.gd").new(); world.add_child(body)
  var stats: Dictionary = preload("res://object_definitions.gd").metal_types()[2]; stats.mass = object_mass
  var appearance := preload("res://clump_loader.gd").load_clump("../Original Sub Culture/CLUMPS/COIN.DFF"); appearance.scale *= 0.5
  body.setup(stats,appearance,0,100.0,true); body.global_position = magnet.head.global_position + Vector3.DOWN * 0.03
  magnet._attach(body)
 pilot.freeze = false
 for frame in range(600): await physics_frame
 var result := {"mass":object_mass,"input":pitch,"speed":Vector2(pilot.velocity.x,pilot.velocity.z).length(),"vertical":pilot.velocity.y,"pitch":rad_to_deg(asin(clampf(-pilot.global_basis.z.y,-1.0,1.0))),"cable":magnet.head.to_global(magnet.head_socket).distance_to(magnet.global_position)}
 print("Towing trial ",result)
 world.free(); await process_frame
 return result
func run() -> void:
 preload("res://mod_registry.gd").initialize(false)
 var empty: Dictionary = await trial(0.0,0.0)
 var level: Dictionary = await trial(1.5,0.0)
 var corrected: Dictionary = await trial(1.5,0.3)
 var heavy: Dictionary = await trial(3.0,0.3)
 check(absf(empty.vertical) < 0.01 and absf(empty.pitch) < 0.2,"Empty magnet keeps level forward flight")
 check(level.vertical < -0.1,"Forward flight with cargo and no correction loses height")
 check(absf(corrected.vertical) < 0.1 and corrected.speed > 0.5,"Modest nose-up input maintains roughly horizontal loaded flight")
 check(corrected.pitch > 0 and corrected.pitch < 25,"Corrected cargo flight uses a modest upward hull angle")
 check(heavy.vertical < corrected.vertical - 0.05,"Heavier cargo needs more nose-up correction")
 check(corrected.speed < empty.speed,"Towing cargo slows forward flight")
 check(corrected.cable < 0.45 and heavy.cable < 0.45,"Towing retains a stable cable length")
 var saved_corrected: Dictionary = await trial(1.5,0.1,true)
 check(absf(saved_corrected.vertical) < 0.12 and saved_corrected.pitch > 0.0,"Current saved magnet settings also allow gentle nose-up correction to hold height")
 print("Towing flight: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
