extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var wall := StaticBody3D.new(); world.add_child(wall); wall.position.x = 2
	var collider := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = Vector3(1,10,10)
	collider.shape = shape; wall.add_child(collider)
	var robot := preload("res://fishbot.gd").new()
	var visual := MeshInstance3D.new(); var primitive := BoxMesh.new(); primitive.size = Vector3(0.5,0.5,1)
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,primitive.surface_get_arrays(0)); visual.mesh = mesh
	robot.setup(visual,Vector3.ZERO,AABB(Vector3.ONE*-10,Vector3.ONE*20),10,0.2,42)
	world.add_child(robot); robot.set_physics_process(false); robot.set_process(false)
	var hull: Shape3D = robot.get_child(0).shape
	await physics_frame; await physics_frame
	robot.direction = Vector3.RIGHT; robot._steer(Vector3.RIGHT,1,720)
	check(robot.direction.x < -0.99,"Fishbot turns away before contacting a wall inside its original two-unit probe")
	robot._steer(Vector3.FORWARD,1,720)
	check(robot.direction.z < -0.99,"Unobstructed pursuit direction remains unchanged")
	robot.position.x = -2; robot._steer(Vector3.RIGHT,1,720)
	check(robot.direction.x > 0.99,"Obstacle avoidance does not extend beyond the original probe distance")
	check(robot.get_child(0).shape == hull and hull is ConvexPolygonShape3D,"Avoidance retains the fitted physical hull")
	world.free(); print("Fishbot avoidance: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
