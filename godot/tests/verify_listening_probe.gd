extends SceneTree
const Probe = preload("res://listening_probe.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var velocity := Vector3.ZERO
	var original := 0.0
	for tick in range(100):
		original = (original + 0.0005 / 0.01) * 0.9
		velocity = Probe.flight_velocity(velocity,Vector3.FORWARD,true,0.04)
	check(is_equal_approx(-velocity.z,original*25.0),"Probe acceleration and damping reproduce original 25 Hz velocity arithmetic")
	var halves := Probe.flight_velocity(Probe.flight_velocity(Vector3.RIGHT,Vector3.FORWARD,true,0.02),Vector3.FORWARD,true,0.02)
	check(halves.is_equal_approx(Probe.flight_velocity(Vector3.RIGHT,Vector3.FORWARD,true,0.04)),"Motor integration is independent of physics tick subdivision")
	var world := Node3D.new(); root.add_child(world)
	var wall := StaticBody3D.new(); world.add_child(wall); wall.position.z = -1
	var collision := CollisionShape3D.new(); collision.shape = BoxShape3D.new(); collision.shape.size = Vector3(2,2,0.1); wall.add_child(collision)
	var impact := Probe.new(); world.add_child(impact)
	for frame in range(60): await physics_frame
	check(impact.motor_remaining == 0 and not impact.attached and impact.position.z > -1.1,"Real contact with a wrong target stops thrust without attaching or tunnelling through scenery")
	check(is_instance_valid(impact) and not impact.is_queued_for_deletion(),"A wrong hit leaves a physical device instead of deleting the probe")
	var miss := Probe.new(); world.add_child(miss); miss.position.x = 10
	for frame in range(370): await physics_frame
	check(is_instance_valid(miss) and miss.age > 5.0,"A missed probe persists beyond the former arbitrary five-second lifetime")
	check(miss.motor_remaining == 0 and miss.linear_velocity.y < -0.1 and miss.position.y < -0.1,"After 100 powered ticks a missed probe coasts and sinks under original gravity and drag")
	var model := Node3D.new(); world.add_child(model)
	var hull := StaticBody3D.new(); model.add_child(hull)
	var visual := MeshInstance3D.new(); visual.mesh = BoxMesh.new(); model.add_child(visual)
	var seated := Probe.new(); world.add_child(seated); seated.position = Vector3(0,0,1)
	seated._seat_on_hull(hull)
	check(is_equal_approx(seated.global_position.z,0.55),"Attached device seats on visible hull with original .05 stand-off")
	world.free(); print("Listening probe: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
