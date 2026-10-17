extends SceneTree
const Pilot = preload("res://submarine_controller.gd")
const Docking = preload("res://docking_controller.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var pilot := Pilot.new(); pilot.remember_settings = false; root.add_child(pilot)
	pilot.set_process(false); pilot.set_physics_process(false); pilot.active = false
	pilot.visual = Node3D.new(); pilot.add_child(pilot.visual)
	var controller := Docking.new(); root.add_child(controller); controller.set_physics_process(false)
	controller.pilot = pilot; controller.transit_settings = pilot.movement.settings.duplicate()
	# Reproduce docking after a powered approach with a long configured coast.
	pilot.movement.settings.propeller_spin_down = 5.0
	pilot.propeller_speeds = Vector3(1,0,0); pilot.movement.tilt = -PI/2
	pilot.velocity = Vector3.DOWN; controller.stage = Docking.Stage.DESCEND
	var main_angle := pilot.angles.x
	for frame in range(60): controller._animate_pilot(1.0/60.0)
	check(pilot.movement.main_power == 0 and pilot.propeller_speeds.x == 0 and is_equal_approx(pilot.angles.x,main_angle),"Vertical docking descent brakes the main propeller instead of carrying approach spin into the shaft")
	check(pilot.propeller_speeds.y > 0 and pilot.propeller_speeds.z > 0,"Lift propellers still power the docking descent")
	# Tiny horizontal residue must not switch the main propeller back on.
	pilot.velocity = Vector3(0.002,-1,0.002); controller._animate_pilot(0.2)
	check(pilot.movement.main_power == 0 and pilot.propeller_speeds.x == 0,"Descent does not drive the rear propeller for insignificant sideways position corrections")
	controller.stage = Docking.Stage.APPROACH; pilot.velocity = Vector3.FORWARD
	controller._animate_pilot(0.2)
	check(pilot.movement.main_power == 1 and pilot.propeller_speeds.x > 0,"Horizontal docking approach retains its main propeller animation")
	# Launching begins from rest and must retain its existing vertical animation.
	controller.stage = Docking.Stage.ASCEND; pilot.propeller_speeds = Vector3.ZERO
	pilot.velocity = Vector3.UP; pilot.movement.tilt = PI/2
	controller._animate_pilot(0.2)
	check(pilot.movement.main_power == 0 and pilot.propeller_speeds.x == 0 and pilot.propeller_speeds.y > 0 and pilot.propeller_speeds.z > 0,"Undocking still lifts on the side propellers with the main propeller stopped")
	pilot.free(); controller.free()
	print("Docking propellers: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
