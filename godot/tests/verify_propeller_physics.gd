extends SceneTree

const Movement = preload("res://movement_model.gd")
const Controls = preload("res://pilot_input.gd")
const Pilot = preload("res://submarine_controller.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func integrate(model: RefCounted, basis: Basis, controls: Vector4, frames: int) -> Basis:
	for frame in range(frames):
		model.step(1.0 / 60.0, basis, controls.x, controls.y, controls.z, controls.w)
		var spin: Vector3 = model.angular_velocity
		if spin.length() > 0.000001: basis = (Basis(spin.normalized(), spin.length() / 60.0) * basis).orthonormalized()
	return basis

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _run() -> void:
	check(Controls.from_axes(Vector2(0.05, 0), Vector2(0, 0.05), 0.02, 0.02).is_zero_approx(), "Stick and trigger noise stays inside deadzones")
	var input := Controls.from_axes(Vector2(1, 0), Vector2(0, -0.575), 0, 0.525)
	check(is_equal_approx(input.x, 0.5) and is_equal_approx(input.y, 0.5) and is_equal_approx(input.z, -1), "Analogue gamepad axes produce half thrust and 45-degree pod command")
	check(is_equal_approx(Controls.from_axes(Vector2.ZERO, Vector2.ZERO, 1, 0).x, -1), "Left trigger reverses main propeller")
	check(is_equal_approx(Controls.from_axes(Vector2(0, -1), Vector2.ZERO, 0, 0).w, -1), "Left stick forward pitches nose downward")
	check(is_equal_approx(Controls.from_axes(Vector2(0, 1), Vector2.ZERO, 0, 0).w, 1), "Left stick back pitches nose upward")
	var model := Movement.new()
	model.settings.tilt_speed = 90.0
	for frame in range(9):
		model.step(0.1,Basis.IDENTITY,0,1,0)
		check(not model.pods_aligned and model.left_power == 0.0 and model.right_power == 0.0 and model.thrust_force.is_zero_approx() and model.velocity.is_zero_approx(),"Ascend waits for vertical pod alignment")
	model.step(0.1,Basis.IDENTITY,0,1,0)
	check(model.pods_aligned and model.left_power == 1.0 and model.right_power == 1.0 and model.thrust_force.y > 0.0 and absf(model.thrust_force.z) < 0.00001,"Aligned pods start thrust straight upward")
	model.step(0.1,Basis.IDENTITY,1,-1,1)
	check(not model.pods_aligned and model.thrust_torque.is_zero_approx() and model.left_power == 0.0 and model.right_power == 0.0 and is_equal_approx(model.thrust_force.z,-model.settings.main_forward),"Changing target stops side thrust and steering while main propeller remains independent")
	for frame in range(19): model.step(0.1,Basis.IDENTITY,0,-1,0)
	check(model.pods_aligned and model.thrust_force.y < 0.0 and absf(model.thrust_force.z) < 0.00001,"Reversal waits until pods face downward")
	model.step(0.1,Basis.IDENTITY,1,0,0)
	check(not model.pods_aligned and model.left_power == 0.0,"Returning pods to forward angle also waits")
	for frame in range(9): model.step(0.1,Basis.IDENTITY,1,0,0)
	check(model.pods_aligned and model.left_power == 1.0 and model.right_power == 1.0,"Forward pod thrust resumes after centering")
	model.reset_motion()
	model.step(0.1,Basis.IDENTITY,0,0.5,0)
	check(not model.pods_aligned and model.thrust_force.is_zero_approx(),"Partial stick deflection waits for its requested angle")
	for frame in range(4): model.step(0.1,Basis.IDENTITY,0,0.5,0)
	check(model.pods_aligned and is_equal_approx(model.tilt,PI / 4.0) and model.left_power == 0.5,"Partial stick thrust begins at the desired 45-degree angle")
	model = Movement.new()
	model.step(0.1, Basis.IDENTITY, 1, 0, 0)
	check(is_equal_approx(model.thrust_force.z, -900), "Centred pods add independent forward thrust to main propeller")
	var normal_acceleration: float = model.velocity.length()
	model.reset_motion()
	model.settings.mass = 200.0
	model.step(0.1, Basis.IDENTITY, 1, 0, 0)
	check(is_equal_approx(model.velocity.length(), normal_acceleration * 0.5), "Twice the mass halves thrust acceleration from rest")
	model.settings.mass = 100.0
	model.reset_motion()
	model.settings.side_thrust = 0.0
	model.step(0.1, Basis(Vector3.RIGHT, PI / 4), 1, 0, 0)
	check(model.velocity.y > 0.3 and model.velocity.z < -0.3, "Pitched hull directs main propeller thrust into vertical movement")
	model = Movement.new()
	model.tilt = PI / 2
	model.step(0.1, Basis.IDENTITY, 0, 1, 0)
	check(model.velocity.y > 0.0 and absf(model.velocity.z) < 0.00001, "Pods alone can ascend without main thrust")
	model.reset_motion()
	model.tilt = PI / 4
	model.step(0.01, Basis.IDENTITY, 0, 0.5, 1)
	check(absf(model.thrust_torque.y) > 0.1 and absf(model.thrust_torque.z) > 0.1, "45-degree pods mix yaw and roll torque")
	model.reset_motion()
	model.tilt = PI / 2
	model.step(0.01, Basis.IDENTITY, 0, 1, 1)
	check(absf(model.angular_velocity.z) > 0.001 and absf(model.angular_velocity.y) < 0.00001, "Vertical pods roll the hull instead of yawing")
	model.reset_motion()
	var rolled := integrate(model, Basis(Vector3.BACK, PI * 0.75), Vector4.ZERO, 600)
	check(rolled.y.dot(Vector3.UP) > 0.995 and model.angular_velocity.length() < 0.01, "Released rolled hull settles upright without snapping")
	model.reset_motion()
	var pitched := integrate(model, Basis.IDENTITY, Vector4(0, 0, 0, 1), 600)
	check(absf(asin(-pitched.z.y) - PI / 4) < 0.01, "Analogue pitch settles at 45 degrees")
	pitched = integrate(model, pitched, Vector4.ZERO, 600)
	check(pitched.y.dot(Vector3.UP) > 0.995, "Released pitched hull settles horizontal")
	model = Movement.new()
	model.velocity = Vector3(0, 0, -3)
	model.step(0.1, Basis.IDENTITY, 0, 0, 0)
	var forward_speed: float = model.velocity.length()
	model.velocity = Vector3(0, 3, 0)
	model.step(0.1, Basis.IDENTITY, 0, 0, 0)
	check(model.velocity.length() < forward_speed and forward_speed > 0, "Vertical drag exceeds forward drag and preserves coasting momentum")
	var legacy := ConfigFile.new()
	legacy.set_value("movement", "main_forward", 5.0)
	legacy.set_value("movement", "side_thrust", 2.0)
	var migrated: Dictionary = Movement.DEFAULTS.duplicate()
	Movement._apply_values(legacy, migrated)
	check(is_equal_approx(migrated.main_forward, 500) and is_equal_approx(migrated.side_thrust, 200) and is_equal_approx(migrated.main_reverse, 200), "Legacy exports convert acceleration to force while keeping missing defaults")
	var export_path := "res://tests/physics-export-test.cfg"
	model.load_settings(false)
	model.settings.mass = 175.0
	model.settings.main_forward = 650.0
	model.settings.upright_strength = 5.0
	model.save_settings(export_path)
	var reloaded := Movement.new()
	reloaded.load_settings(false, "res://tests/nonexistent-settings.cfg", export_path)
	check(is_equal_approx(reloaded.settings.mass, 175) and is_equal_approx(reloaded.settings.main_forward, 650) and is_equal_approx(reloaded.settings.upright_strength, 5), "New physics tuning exports and reloads without double-converting force")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(export_path))
	model = Movement.new()
	model.settings.forward_speed = 40.0
	model.velocity = Vector3(0, 20, -20)
	model.step(0.01, Basis(Vector3.RIGHT, PI / 4), 1, 0, 0)
	check(model.velocity.y <= 5.0001, "Vertical speed cap applies in world space even with pitched hull")
	var world := Node3D.new()
	root.add_child(world)
	var pilot := Pilot.new()
	pilot.remember_settings = false
	pilot.surface_height = 100
	world.add_child(pilot)
	pilot.reset_at(Vector3(0, 10, 0))
	pilot.active = true
	key(KEY_UP, true)
	var maximum_pitch := 0.0
	for frame in range(240):
		await physics_frame
		maximum_pitch = maxf(maximum_pitch, absf(asin(clampf(-pilot.global_basis.z.y, -1, 1))))
	key(KEY_UP, false)
	check(pilot is RigidBody3D and is_equal_approx(pilot.mass,float(pilot.movement.settings.mass)), "Live pilot is a rigid body with configured mass")
	check(maximum_pitch <= PI / 4 + 0.002 and maximum_pitch > 0.7, "Live rigid-body pitching obeys 45-degree limit")
	for frame in range(300): await physics_frame
	check(pilot.global_basis.y.dot(Vector3.UP) > 0.995, "Live rigid body levels after pitch input is released")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 2
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 20, 0.5)
	collider.shape = box
	wall.add_child(collider)
	world.add_child(wall)
	wall.position = Vector3(0, 10, -3)
	pilot.reset_at(Vector3(0, 10, 0))
	key(KEY_W, true)
	for frame in range(180): await physics_frame
	key(KEY_W, false)
	var contact_z: float = wall.position.z + box.size.z * 0.5 + Pilot.COLLIDER_SIZE.z * 0.5 - Pilot.COLLIDER_CENTER.z
	check(absf(pilot.position.z - contact_z) < 0.1, "Rigid-body thrust stops at scenery using the fitted submarine hull")
	wall.queue_free()
	pilot.reset_at(Vector3(0, 10, 0))
	key(KEY_E, true)
	key(KEY_A, true)
	var roll_rate := 0.0
	for frame in range(180):
		await physics_frame
		roll_rate = maxf(roll_rate, absf(pilot.angular_velocity.dot(-pilot.global_basis.z)))
	key(KEY_E, false)
	key(KEY_A, false)
	check(roll_rate > 1.0, "Live vertical pods produce deliberate barrel roll")
	for frame in range(600): await physics_frame
	check(pilot.global_basis.y.dot(Vector3.UP) > 0.99, "Live hull settles upright after releasing barrel roll")
	world.queue_free()
	await process_frame
	print("Propeller physics verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
