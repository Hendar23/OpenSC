extends "res://tests/test_scene_tree.gd"
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var model := Node3D.new(); world.add_child(model); model.position.z = -2
	var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); model.add_child(mesh)
	preload("res://scenery_loader.gd")._add_prop_collision(model)
	var turret = preload("res://gun_turret.gd").install(model)
	turret.set_physics_process(false)
	var system := preload("res://turret_system.gd").new(); world.add_child(system); system.turrets.append(turret)
	var player := RigidBody3D.new(); player.gravity_scale = 0; player.linear_damp = 0; player.can_sleep = false
	player.collision_layer = 2; player.collision_mask = 13
	var collider := CollisionShape3D.new(); var shape := SphereShape3D.new(); shape.radius = 0.4; collider.shape = shape
	player.add_child(collider); world.add_child(player)
	player.linear_velocity = Vector3.FORWARD * 6
	for tick in range(60): await physics_frame
	check(player.position.z > -1.5,"Live turret physically blocks the player")
	turret.take_weapon_damage(100)
	check(turret.dead and turret.hitbox.collision_layer == 0 and turret.hitbox.collision_mask == 0,"Destroyed turret immediately clears both physics filters")
	var saved := system.snapshot()
	player.linear_velocity = Vector3.FORWARD * 6
	for tick in range(60): await physics_frame
	check(player.position.z < -5.5,"Player physically passes through the destroyed turret position")
	check(turret.collision_shapes.all(func(node):return node.disabled),"Destroyed turret shapes are disabled")
	turret.set_local_simulation(false); turret.set_local_simulation(true)
	check(turret.hitbox.collision_mask == 0,"Activity changes leave destroyed turret non-solid")
	system.reset(); turret.set_physics_process(false)
	player.position = Vector3.ZERO; player.linear_velocity = Vector3.FORWARD * 6
	for tick in range(60): await physics_frame
	check(not turret.dead and turret.hitbox.collision_mask == 2 and player.position.z > -1.5,"Session reset restores a solid live turret")
	system.restore(saved)
	player.linear_velocity = Vector3.FORWARD * 6
	for tick in range(60): await physics_frame
	check(turret.dead and player.position.z < -5.5,"Loading destroyed state also removes physical collision")
	world.free(); print("Destroyed turret collision: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
