extends "res://tests/test_scene_tree.gd"
const Walker = preload("res://mission_walker_body.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var chassis := Walker.new(); world.add_child(chassis)
	chassis.freeze = true; chassis.position.z = -2
	var shape := CollisionShape3D.new(); shape.shape = BoxShape3D.new(); chassis.add_child(shape)
	var head := RigidBody3D.new(); head.gravity_scale = 0; head.linear_damp = 0; head.can_sleep = false
	head.collision_layer = 9; head.collision_mask = 11
	var head_shape := CollisionShape3D.new(); head_shape.shape = SphereShape3D.new(); head_shape.shape.radius = 0.2
	head.add_child(head_shape); world.add_child(head)
	head.linear_velocity = Vector3.FORWARD * 4
	for tick in 45: await physics_frame
	check(head.position.z > -1.6,"Live walker chassis blocks salvage")
	chassis.hide()
	chassis.disable_chassis_collision()
	check(chassis.collision_layer == 0 and chassis.collision_mask == 0,"Retired chassis clears both collision filters")
	head.linear_velocity = Vector3.FORWARD * 4
	for tick in 60: await physics_frame
	check(shape.disabled,"Retired chassis disables its shapes")
	check(head.position.z < -4,"Salvage physically passes through the retired chassis")
	world.free()
	print("Destroyed walker collision: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
