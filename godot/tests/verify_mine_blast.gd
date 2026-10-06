extends SceneTree
const Pilot = preload("res://submarine_controller.gd")
const Population = preload("res://object_population.gd")
class FakeJoy extends RefCounted:
	var calls := 0
	func get_connected_joypads() -> Array: return [0]
	func start_joy_vibration(_device: int, _weak: float, _strong: float, _duration: float) -> void: calls += 1
	func stop_joy_vibration(_device: int) -> void: pass
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var pilot := Pilot.new(); pilot.remember_settings = false; root.add_child(pilot)
	pilot.set_physics_process(false); pilot.mass = 100.0; pilot.active = true
	pilot.visual = Node3D.new(); pilot.add_child(pilot.visual)
	var joy := FakeJoy.new(); pilot.impact_rumble.joy_input = joy
	var population := Population.new(); root.add_child(population); population.player = pilot
	pilot.position = Vector3.RIGHT
	await physics_frame; await physics_frame
	population._exploded(Vector3.ZERO,30.0,2.0,300.0)
	await physics_frame; await physics_frame
	check(pilot.linear_velocity.x > 1.2 and absf(pilot.linear_velocity.z) < 0.01, "Blast pushes the real rigid body away with distance falloff")
	check(joy.calls == 1, "Blast damage triggers controller feedback once")
	var before := pilot.linear_velocity.x
	population._exploded(Vector3(-10,0,0),30.0,2.0,300.0)
	check(joy.calls == 1 and is_equal_approx(pilot.linear_velocity.x,before), "Outside the blast radius there is no force or rumble")
	population._exploded(pilot.position - Vector3.RIGHT,30.0,2.0,0.0)
	check(joy.calls == 2 and is_equal_approx(pilot.linear_velocity.x,before), "Zero blast impulse disables movement independently of damage feedback")
	population._exploded(pilot.position - Vector3.RIGHT,0.0,2.0,300.0)
	await physics_frame; await physics_frame
	check(pilot.linear_velocity.x > before + 1.2 and joy.calls == 2, "Zero damage still allows force without damage rumble")
	pilot.controls_enabled = false
	before = pilot.linear_velocity.x
	population._exploded(pilot.position - Vector3.RIGHT,30.0,2.0,300.0)
	check(joy.calls == 2 and is_equal_approx(pilot.linear_velocity.x,before), "Docking manoeuvres are not interrupted by explosions")
	pilot.free(); population.free()
	print("Mine blast: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
