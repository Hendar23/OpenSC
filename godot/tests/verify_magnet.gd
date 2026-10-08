extends SceneTree
const Magnet = preload("res://submarine_magnet.gd")
const Assets = preload("res://clump_loader.gd")
const Salvage = preload("res://salvage_body.gd")
class Pilot extends RigidBody3D:
 var active := true
 var controls_enabled := true
 var dead := false
 var visual: Node3D
 var submarine_audio: Node
 var cargo_mass := 0.0
 func set_towed_mass(value: float) -> void:
  cargo_mass = value; mass = 100.0 + value
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 preload("res://mod_registry.gd").initialize(false)
 var world := Node3D.new(); world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF; root.add_child(world); world.set_meta("surface_height",0.0)
 var pilot := Pilot.new(); pilot.mass = 100; pilot.gravity_scale = 0; pilot.freeze = true; pilot.position.y = -2; world.add_child(pilot)
 pilot.visual = Node3D.new(); pilot.add_child(pilot.visual)
 var mount := Node3D.new(); pilot.visual.add_child(mount)
 var housing := Assets.load_clump("../Original Sub Culture/CLUMPS/MAGNET.DFF"); mount.add_child(housing)
 var magnet := Magnet.new(); mount.add_child(magnet); magnet.setup(pilot,housing,"../Original Sub Culture")
 check(magnet.chain_template != null and magnet.deploy_audio.stream != null and magnet.clamp_audio.stream != null,"Original chain and both magnet sounds load")
 check(magnet.chain_has_pose and is_equal_approx(magnet.chain_bounds.size.y,1.0),"Original CHAIN stretch pose is loaded")
 magnet.set_enabled(true)
 check(magnet.enabled and magnet.links.size() == 4 and not housing.visible,"Deploying creates four original chain links and hides the mounted head")
 for tick in range(6): await physics_frame
 var early_length: float = magnet.head.to_global(magnet.head_socket).distance_to(magnet.global_position)
 check(early_length > 0.001 and early_length < 0.1,"Chain lowers progressively instead of appearing at full length")
 for tick in range(144): await physics_frame
 var distance: float = magnet.head.global_position.distance_to(magnet.global_position)
 check(distance > 0.22 and distance < 0.4,"Physics unfolds the chain to its configured length: %f" % distance)
 var chain_query := PhysicsShapeQueryParameters3D.new(); var probe := SphereShape3D.new(); probe.radius = 0.001
 chain_query.shape = probe; chain_query.collision_mask = Magnet.CHAIN_LAYER
 chain_query.transform.origin = magnet.link_colliders[1].get_parent().global_position
 check(not world.get_world_3d().direct_space_state.intersect_shape(chain_query).is_empty(),"Physics detects contact against the middle of the deployed chain")
 chain_query.transform.origin += Vector3.RIGHT * 0.1
 check(world.get_world_3d().direct_space_state.intersect_shape(chain_query).is_empty(),"Chain contact stays narrow instead of blocking the surrounding water")
 for link in magnet.links:
  var meshes: Array[MeshInstance3D] = []; preload("res://morph_animation.gd").collect(link,meshes)
  check(not meshes.is_empty() and meshes[0].get_blend_shape_value(0) > 0.95,"Each deployed segment uses the original extended pose")
 var previous: Vector3 = magnet.head.global_position
 magnet.head.angular_velocity = Vector3(10,5,8)
 for tick in range(120): await physics_frame
 check(magnet.head.angular_velocity.length() < 0.1 and magnet.head.global_position.distance_to(previous) < 0.06,"Water resistance settles an empty magnet without persistent bouncing")
 pilot.freeze = false
 var empty_position: Vector3 = pilot.position
 magnet.head.linear_velocity += Vector3(0.4,0,0)
 for tick in range(120): await physics_frame
 check(pilot.position.is_equal_approx(empty_position) and pilot.linear_velocity.length() < 0.00001 and pilot.cargo_mass == 0.0 and pilot.mass == 100.0,"An empty deployed magnet adds neither mass nor downward/sideways force")
 check(magnet.head.linear_velocity.length() < 0.02,"Empty magnet sideways motion settles slowly in water")
 pilot.freeze = true
 var hull := CollisionShape3D.new(); var hull_shape := SphereShape3D.new(); hull_shape.radius = 0.09; hull.shape = hull_shape
 pilot.collision_layer = 2; pilot.collision_mask = 13; pilot.add_child(hull)
 magnet.head.global_position = pilot.global_position + Vector3.DOWN * 0.18
 magnet.head.linear_velocity = Vector3.UP * 3.0
 var highest_head := -INF
 for tick in range(45):
  await physics_frame
  highest_head = maxf(highest_head,magnet.head.global_position.y - pilot.global_position.y)
 check(highest_head < -hull_shape.radius + 0.01,"The deployed magnet stops at the hull within contact tolerance instead of passing through: %f" % highest_head)
 hull.free()
 for tick in range(120): await physics_frame
 var metal := Salvage.new(); world.add_child(metal)
 var appearance := Assets.load_clump("../Original Sub Culture/CLUMPS/COIN.DFF")
 metal.setup(preload("res://object_definitions.gd").metal_types()[2],appearance,0,0.0,true)
 metal.global_position = magnet.head.global_position + Vector3.DOWN * 0.03
 for tick in range(20): await physics_frame
 check(magnet.target == metal and is_instance_valid(magnet.clamp_joint),"Touching compatible salvage automatically clamps it")
 check(not metal.freeze,"Attached salvage remains a physical body")
 check(metal.is_physics_interpolated() and magnet.head.is_physics_interpolated() and magnet.links.all(func(link: Node3D) -> bool: return link.is_physics_interpolated()),"Cargo, magnet and chain render smoothly even under non-interpolated world scenery")
 check(bool(metal.collision_mask & Magnet.CHAIN_LAYER) and magnet.link_colliders.size() == 4,"Carried salvage collides with all four animated chain segments")
 check(is_equal_approx(pilot.cargo_mass,metal.mass * magnet.cargo_weight) and is_equal_approx(pilot.mass,100.0 + pilot.cargo_mass),"Clamping cargo adds its weight to the submarine engine load")
 var unloaded := preload("res://movement_model.gd").new(); var loaded := preload("res://movement_model.gd").new(); loaded.cargo_mass = pilot.cargo_mass
 unloaded.step(0.1,Basis.IDENTITY,1.0,0.0,0.0,0.0); loaded.step(0.1,Basis.IDENTITY,1.0,0.0,0.0,0.0)
 check(loaded.velocity.length() < unloaded.velocity.length() * 0.9,"The same engine thrust accelerates a cargo-loaded submarine more slowly")
 var before: Vector3 = metal.global_position
 var clamp_offset: Vector3 = magnet.head.to_local(metal.global_position)
 var clamp_error := 0.0
 for tick in range(90):
  pilot.position.x += 0.004
  await physics_frame
  clamp_error = maxf(clamp_error,magnet.head.to_local(metal.global_position).distance_to(clamp_offset))
 check(metal.global_position.x > before.x + 0.1,"The chain physically tows salvage as the sub moves")
 check(metal.global_position.distance_to(pilot.global_position) < 0.65,"Towed salvage stays constrained by the chain")
 check(clamp_error < 0.015,"Physical clamp stays stable while towing with chain collisions: %f" % clamp_error)
 if DisplayServer.get_name() != "headless":
  var camera := Camera3D.new(); world.add_child(camera); camera.position = pilot.position + Vector3(0.7,0.2,1); camera.look_at(pilot.position + Vector3.DOWN * 0.2); camera.current = true
  var light := DirectionalLight3D.new(); world.add_child(light); light.rotation_degrees = Vector3(-30,-20,0)
  for tick in range(5): await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://tests/magnet-preview.png")
 pilot.freeze = false
 for tick in range(60): await physics_frame
 check(pilot.linear_velocity.y < -0.005,"Only attached cargo transmits downward cable tension")
 pilot.freeze = true
 var release_socket: Vector3 = magnet.head.to_global(magnet.head_socket)
 var release_distance: float = release_socket.distance_to(magnet.global_position)
 magnet.set_enabled(false)
 check(is_instance_valid(magnet.rig) and not housing.visible and magnet.retracting and magnet.head.to_global(magnet.head_socket).is_equal_approx(release_socket),"Detaching begins retraction without snapping the magnet")
 magnet.set_physics_process(false)
 magnet._physics_process(0.05)
 check(is_equal_approx(magnet.head.to_global(magnet.head_socket).distance_to(magnet.global_position),maxf(0.0,release_distance - magnet.speed * 0.05)),"Released magnet retracts at its configured normal speed")
 magnet.set_physics_process(true)
 check(not bool(metal.collision_mask & Magnet.CHAIN_LAYER),"Release restores the object's original chain collision mask")
 check(magnet.target == null and not is_instance_valid(magnet.clamp_joint) and not metal.freeze,"Reactivation releases salvage without freezing it")
 check(pilot.cargo_mass == 0.0 and pilot.mass == 100.0,"Releasing cargo restores the original submarine mass")
 for tick in range(120): await physics_frame
 check(not is_instance_valid(magnet.rig) and housing.visible,"Released magnet retracts to its mount")
 metal.set_meta("metal_tow_target",false)
 magnet.set_enabled(true); magnet._attach(metal)
 check(magnet.target == null,"The editor compatibility flag prevents attachment")
 metal.set_meta("metal_tow_target",true); magnet._attach(metal)
 check(magnet.target == metal,"Enabling compatibility permits attachment")
 var pad := preload("res://drop_off_point.gd").new(); world.add_child(pad); pad.configure(0.2,0); pad.global_position = metal.global_position
 magnet.drop_points.append(pad)
 await physics_frame; await physics_frame
 check(magnet.enabled and magnet.target == metal and magnet.delivery_point == pad,"Entering a drop-off zone requests confirmation and retains the load")
 magnet.decline_delivery(); await physics_frame; await physics_frame
 check(magnet.delivery_point == null and magnet.target == metal,"Declining keeps cargo attached without repeating the prompt in the same zone")
 pad.free(); magnet.reset()
 check(housing.visible and not is_instance_valid(magnet.rig) and is_instance_valid(metal),"Reset clears the chain and preserves released world objects")
 pilot.controls_enabled = false; magnet.set_enabled(true)
 check(not magnet.enabled,"The magnet cannot deploy while submarine controls are disabled")
 pilot.controls_enabled = true; magnet.set_enabled(true); magnet._attach(metal); pilot.dead = true
 await physics_frame; await physics_frame
 check(not magnet.enabled and magnet.target == null and not is_instance_valid(magnet.rig),"Submarine destruction releases cargo and removes the chain")
 world.free(); await process_frame
 print("Magnet: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
