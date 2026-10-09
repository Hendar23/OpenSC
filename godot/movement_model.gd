extends RefCounted

const FollowCamera = preload("res://follow_camera.gd")
const Mods = preload("res://mod_registry.gd")

# Newtons and kilograms in prototype world units. Legacy acceleration exports
# are converted using the previous implicit 100 kg reference mass.
const REFERENCE_MASS := 100.0
const POD_ARM := 0.4
const PITCH_LIMIT := PI / 4.0
const DEFAULTS := {
	"main_forward": 500.0, "main_reverse": 200.0, "side_thrust": 200.0,
	"forward_speed": 4.6, "reverse_speed": 2.3, "vertical_speed": 5.0,
	"forward_drag": 0.65, "lateral_drag": 0.95, "vertical_drag": 0.95,
	"turn_acceleration": 138.0, "turn_speed": 144.0,
	"turn_drag": 0.95, "tilt_speed": 100.0,
	"camera_distance": FollowCamera.DEFAULT_DISTANCE,
	"mass": 100.0, "water_resistance": 0.08,
	"pitch_acceleration": 90.0, "pitch_speed": 45.0,
	"upright_strength": 4.0, "upright_damping": 3.0,
	"propeller_spin_down": 0.7, "bubble_rate": 5.0,
	"impact_damage_threshold": 0.75, "impact_damage_scale": 1.0
}
var settings: Dictionary = DEFAULTS.duplicate()
var defaults: Dictionary = DEFAULTS.duplicate()
var base_settings := {}
var mod_values := {}
var mod_section := ""
var persistence_path := "user://submarine_tuning.cfg"
var velocity := Vector3.ZERO
var angular_velocity := Vector3.ZERO
var yaw_velocity: float:
	get: return angular_velocity.y
	set(value): angular_velocity.y = value
var thrust_force := Vector3.ZERO
var thrust_torque := Vector3.ZERO
var cargo_mass := 0.0
var tilt := 0.0
var pods_aligned := true
var main_power := 0.0
var left_power := 0.0
var right_power := 0.0

func reset_motion() -> void:
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	tilt = 0.0
	pods_aligned = true
	main_power = 0.0
	left_power = 0.0
	right_power = 0.0
	thrust_force = Vector3.ZERO
	thrust_torque = Vector3.ZERO

func step(delta: float, basis: Basis, throttle: float, vertical: float, turn: float, pitch: float = 0.0) -> void:
	throttle = clampf(throttle, -1.0, 1.0)
	vertical = clampf(vertical, -1.0, 1.0)
	turn = clampf(turn, -1.0, 1.0)
	pitch = clampf(pitch, -1.0, 1.0)
	var desired_tilt := vertical * PI * 0.5
	tilt = move_toward(tilt, desired_tilt, deg_to_rad(float(settings["tilt_speed"])) * delta)
	pods_aligned = is_equal_approx(tilt,desired_tilt)
	main_power = throttle
	# Vertical thrust remains available when the main propeller is idle.
	var common := throttle if is_zero_approx(vertical) else maxf(absf(throttle), absf(vertical))
	left_power = common - turn
	right_power = common + turn
	var divisor := maxf(1.0, maxf(absf(left_power), absf(right_power)))
	left_power /= divisor
	right_power /= divisor
	# The pod motors finish aiming before either side propeller applies thrust.
	if not pods_aligned:
		left_power = 0.0
		right_power = 0.0
	var pod_direction := Vector3(0.0, sin(tilt), -cos(tilt))
	var left_force := pod_direction * left_power * float(settings.side_thrust)
	var right_force := pod_direction * right_power * float(settings.side_thrust)
	var main_force := Vector3.FORWARD * throttle * float(settings.main_forward if throttle >= 0.0 else settings.main_reverse)
	thrust_force = basis * (main_force + left_force + right_force)
	# Forces at separate pod mounts naturally produce yaw, roll, or both.
	thrust_torque = basis * (Vector3(-POD_ARM, 0, 0).cross(left_force) + Vector3(POD_ARM, 0, 0).cross(right_force))
	var body_mass := maxf(1.0, float(settings.mass) + cargo_mass)
	var local := basis.inverse() * velocity
	var resistance := float(settings.water_resistance)
	# Directional linear and speed-dependent water drag. Mass changes the response.
	local.x *= exp(-(float(settings.lateral_drag) + resistance * absf(local.x)) * REFERENCE_MASS / body_mass * delta)
	local.y *= exp(-(float(settings.vertical_drag) + resistance * absf(local.y)) * REFERENCE_MASS / body_mass * delta)
	local.z *= exp(-(float(settings.forward_drag) + resistance * absf(local.z)) * REFERENCE_MASS / body_mass * delta)
	velocity = basis * local + thrust_force / body_mass * delta
	local = basis.inverse() * velocity
	local.z = clampf(local.z, -float(settings["forward_speed"]), float(settings["reverse_speed"]))
	local.y = clampf(local.y, -float(settings["vertical_speed"]), float(settings["vertical_speed"]))
	velocity = basis * local
	velocity.y = clampf(velocity.y, -float(settings.vertical_speed), float(settings.vertical_speed))
	var local_spin := basis.inverse() * angular_velocity
	local_spin *= exp(-float(settings.turn_drag) * delta)
	var inertia := rotational_inertia()
	var torque_accel := basis.inverse() * thrust_torque / inertia
	var turn_accel := deg_to_rad(float(settings.turn_acceleration))
	if torque_accel.length() > turn_accel: torque_accel = torque_accel.normalized() * turn_accel
	local_spin += torque_accel * delta
	var forward := -basis.z
	var elevation := asin(clampf(forward.y, -1.0, 1.0))
	var pitch_axis := basis.inverse() * forward.cross(Vector3.UP).normalized()
	var pitch_target := pitch * PITCH_LIMIT
	var pitch_rate := local_spin.dot(pitch_axis)
	var pitch_accel := (pitch_target - elevation) * float(settings.upright_strength) - pitch_rate * float(settings.upright_damping)
	var pitch_cap := deg_to_rad(float(settings.pitch_acceleration))
	local_spin += pitch_axis * clampf(pitch_accel, -pitch_cap, pitch_cap) * delta
	# Release roll assistance during deliberate rolling; restore upright on release.
	if not pods_aligned or absf(turn * sin(tilt)) < 0.05:
		var upright := (Vector3.UP - forward * forward.y).normalized()
		var roll_error := -atan2(forward.dot(basis.y.cross(upright)), basis.y.dot(upright))
		var restore := roll_error * float(settings.upright_strength) - local_spin.z * float(settings.upright_damping)
		local_spin.z += clampf(restore, -turn_accel, turn_accel) * delta
	pitch_rate = local_spin.dot(pitch_axis)
	var pitch_limit := deg_to_rad(float(settings.pitch_speed))
	local_spin += pitch_axis * (clampf(pitch_rate, -pitch_limit, pitch_limit) - pitch_rate)
	var turn_limit := deg_to_rad(float(settings.turn_speed))
	var steering := Vector2(local_spin.y, local_spin.z).limit_length(turn_limit)
	local_spin.y = steering.x
	local_spin.z = steering.y
	angular_velocity = basis * local_spin

func rotational_inertia() -> float:
	return 0.4 * maxf(1.0,float(settings.mass) + cargo_mass) * 0.675 * 0.675

func load_settings(persist_update: bool = true, path: String = "user://submarine_tuning.cfg", source: String = "res://submarine_tuning.cfg") -> void:
	mod_values.clear(); mod_section = ""
	if path == "user://submarine_tuning.cfg" and source == "res://submarine_tuning.cfg":
		source = preload("res://current_settings.gd").path("submarine_tuning.cfg")
		path = source
	defaults = DEFAULTS.duplicate()
	var exported := ConfigFile.new()
	if exported.load(source) == OK: _apply_values(exported,defaults)
	persistence_path = path
	var config := ConfigFile.new()
	settings = defaults.duplicate()
	if config.load(persistence_path) == OK:
		_apply_values(config, settings)
	elif persist_update:
		var result := save_settings(persistence_path)
		if result != OK: push_warning("Could not persist updated movement defaults: " + error_string(result))
	base_settings = settings.duplicate()
	mod_values.clear(); mod_section = ""
	if not Mods.movement.is_empty():
		# Presets overlay the current shared tuning. Keep edited preset values in
		# the same file, scoped to the active mod order, so disabling a mod restores
		# the underlying tuning rather than leaving its values installed globally.
		mod_section = "mod_movement." + JSON.stringify(Mods.active_ids()).sha256_text().substr(0,16)
		var patch := ConfigFile.new(); patch.set_value("movement","physics_version",2)
		for key in Mods.movement: patch.set_value("movement",key,Mods.movement[key])
		_apply_values(patch,settings)
		for key in Mods.movement:
			if not settings.has(key): continue
			mod_values[key] = settings[key]
			patch.set_value("movement",key,config.get_value(mod_section,key,settings[key]))
		_apply_values(patch,settings)

static func _apply_values(config: ConfigFile, values: Dictionary) -> void:
	for key in DEFAULTS:
		var value: Variant = config.get_value("movement", key, values[key])
		if (value is float or value is int) and is_finite(float(value)):
			values[key] = maxf(0.0, float(value))
			if key in ["main_forward", "main_reverse", "side_thrust"] and config.has_section_key("movement", key) and int(config.get_value("movement", "physics_version", 1)) < 2:
				values[key] *= REFERENCE_MASS
	values.camera_distance = clampf(float(values.camera_distance), FollowCamera.MIN_DISTANCE, FollowCamera.MAX_DISTANCE)
	values.mass = maxf(1.0, float(values.mass))

func save_settings(path: String = "") -> Error:
	if path.is_empty(): path = persistence_path
	var config := ConfigFile.new()
	var values := settings.duplicate()
	if path == persistence_path:
		config.load(path)
		if not mod_section.is_empty():
			if config.has_section(mod_section): config.erase_section(mod_section)
			for key in mod_values:
				values[key] = base_settings[key]
				if not is_equal_approx(float(settings[key]),float(mod_values[key])): config.set_value(mod_section,key,settings[key])
	if config.has_section("defaults"): config.erase_section("defaults")
	config.set_value("movement", "physics_version", 2)
	for key in values:
		config.set_value("movement", key, values[key])
	config.set_value("settings", "unified", true)
	return config.save(path)
