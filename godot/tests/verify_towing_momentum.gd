extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func trial(cargo_speed: float, cable_length: float) -> float:
 var world := Node3D.new(); root.add_child(world); world.set_meta("surface_height",100)
 var pilot := preload("res://submarine_controller.gd").new(); pilot.remember_settings = false; pilot.active = true; pilot.controls_enabled = false; world.add_child(pilot)
 pilot.global_position = Vector3(0,-10,0); pilot.surface_height = 100; pilot.collision_layer = 0; pilot.collision_mask = 0
 pilot.visual = Node3D.new(); pilot.add_child(pilot.visual)
 var magnet := preload("res://submarine_magnet.gd").new(); pilot.add_child(magnet)
 var housing := Node3D.new(); var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); mesh.scale = Vector3.ONE * .03; housing.add_child(mesh); pilot.add_child(housing)
 magnet.setup(pilot,housing,"../Original Sub Culture"); magnet.chain_length = cable_length; magnet.cargo_weight = 4; magnet.water_drag = .1
 magnet.set_physics_process(false); pilot.controls_enabled = true; magnet.set_enabled(true); pilot.controls_enabled = false; magnet.paid_length = cable_length; magnet.deploying = false; magnet.head.drop_limit = 0
 magnet.head.global_position = magnet.global_position + Vector3(0,-.8,-.6) - magnet.head_socket
 var cargo := preload("res://salvage_body.gd").new(); world.add_child(cargo)
 var stats: Dictionary = preload("res://object_definitions.gd").metal_types()[2]; stats.mass = 10
 cargo.setup(stats,Node3D.new(),0,100,true); cargo.global_position = magnet.head.global_position + Vector3.DOWN * .1; magnet._attach(cargo)
 await physics_frame; await physics_frame
 # Exercise the real submarine integrator. The clamp solver has not yet
 # propagated the cargo's momentum to the much lighter magnet head.
 pilot.linear_velocity = Vector3.ZERO; pilot.angular_velocity = Vector3.ZERO
 cargo.linear_velocity = Vector3(0,0,-cargo_speed); cargo.angular_velocity = Vector3.ZERO
 magnet.head.linear_velocity = Vector3.ZERO; magnet.head.angular_velocity = Vector3.ZERO
 magnet._constrain_cable(1.0 / 60)
 await physics_frame
 var speed := -pilot.linear_velocity.z
 print("Momentum trial: cargo speed ",cargo_speed," paid cable ",cable_length," sub forward tug ",speed)
 world.free(); await process_frame
 return speed
func run() -> void:
 preload("res://mod_registry.gd").initialize(false)
 var stationary := await trial(0,1)
 var moving := await trial(3,1)
 var slack := await trial(3,2)
 check(moving > .15,"A moving heavy load pulls the stopped submarine through a taut cable")
 check(moving > stationary + .15,"Cargo momentum produces an additional tug beyond static cable correction")
 check(absf(slack) < .001,"A slack chain transmits no pull before it becomes taut")
 print("Towing momentum: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
