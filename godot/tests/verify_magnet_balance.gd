extends SceneTree
const Magnet = preload("res://submarine_magnet.gd")
const Assets = preload("res://clump_loader.gd")
var failures := 0
var checks := 0
func check(ok: bool,message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 preload("res://mod_registry.gd").initialize(false)
 var world := Node3D.new(); root.add_child(world); world.set_meta("surface_height",0.0)
 var pilot := preload("res://tests/verify_magnet.gd").Pilot.new(); pilot.mass = 100; pilot.gravity_scale = 0; pilot.freeze = true; pilot.position.y = -2; world.add_child(pilot)
 pilot.visual = Node3D.new(); pilot.add_child(pilot.visual)
 var mount := Node3D.new(); pilot.visual.add_child(mount)
 var housing := Assets.load_clump("../Original Sub Culture/CLUMPS/MAGNET.DFF"); mount.add_child(housing)
 var magnet := Magnet.new(); mount.add_child(magnet); magnet.setup(pilot,housing,"../Original Sub Culture"); magnet.set_enabled(true)
 for tick in range(150): await physics_frame
 var coin := preload("res://salvage_body.gd").new(); world.add_child(coin)
 var definition: Dictionary = preload("res://object_definitions.gd").metal_types()[2]
 var appearance := preload("res://object_population.gd").appearance(definition,"../Original Sub Culture")
 coin.setup(definition,appearance,0,0.0,true)
 var bounds := preload("res://submarine_equipment.gd")._bounds(preload("res://submarine_equipment.gd")._meshes(appearance,Transform3D.IDENTITY))
 coin.global_position = magnet.head.global_position + Vector3(bounds.size.x * 0.48,0.08,0)
 magnet._attach(coin)
 var initial := magnet.head.global_transform.affine_inverse() * coin.global_transform
 var first_direction := (magnet._body_center(coin) - magnet.head.to_global(magnet.head_socket)).normalized()
 var maximum_error := 0.0
 for tick in range(900):
  await physics_frame
  var relative := magnet.head.global_transform.affine_inverse() * coin.global_transform
  maximum_error = maxf(maximum_error,relative.origin.distance_to(initial.origin))
 var socket := magnet.head.to_global(magnet.head_socket)
 var hanging := magnet._body_center(coin) - socket
 print("Coin balance: initial direction ",first_direction," final ",hanging.normalized()," spin ",coin.angular_velocity.length()," clamp drift ",maximum_error)
 check(first_direction.y > 0.0,"Fixture starts with an edge-attached coin's weight above the magnet")
 check(hanging.normalized().dot(Vector3.DOWN) > 0.9,"Coin rotates until its centre of gravity hangs below the magnet")
 check(coin.angular_velocity.length() < 0.15,"Water drag settles the hanging coin without continuous spinning")
 check(maximum_error < 0.025,"Magnet stays clamped to the same point while the load rotates")
 check(socket.distance_to(magnet.global_position) < magnet.chain_length + 0.04,"Flexible suspension keeps the configured cable length")
 if DisplayServer.get_name() != "headless":
  var camera := Camera3D.new(); world.add_child(camera); camera.position = socket + Vector3(1.8,0.7,2.2); camera.look_at(socket + Vector3.DOWN * 0.3); camera.current = true
  var light := DirectionalLight3D.new(); world.add_child(light); light.rotation_degrees = Vector3(-30,-20,0)
  for frame in range(6): await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://tests/magnet-balance-preview.png")
 magnet.set_enabled(false)
 check(magnet.target == null and magnet.retracting and not coin.freeze,"Balanced cargo still releases into the world and the magnet reels in")
 world.free(); await process_frame
 print("Magnet balance: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
