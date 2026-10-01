extends SceneTree
const Follow = preload("res://follow_camera.gd")
const Movement = preload("res://movement_model.gd")
const Transit = preload("res://transit_motion.gd")
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var slow := Follow.new()
	var fast := Follow.new()
	for follow in [slow, fast]: follow.desired_position(Vector3.ZERO, 0.0, Vector3.ZERO, Vector3.FORWARD, 2.3, Follow.MIN_DISTANCE, 0.0, true)
	var slow_offset: Vector3
	var fast_offset: Vector3
	for frame in range(30):
		slow_offset = slow.desired_position(Vector3.ZERO, PI * 0.5, Vector3.ZERO, Vector3.LEFT, 2.3, Follow.MIN_DISTANCE, 1.0 / 60.0)
		fast_offset = fast.desired_position(Vector3.ZERO, PI * 0.5, Vector3.LEFT * 2.3, Vector3.LEFT, 2.3, Follow.MIN_DISTANCE, 1.0 / 60.0)
	check(rad_to_deg(PI * 0.5 - slow.orbit_yaw) > 70.0, "Stationary turn leaves submarine almost side-on after half a second")
	check(absf(PI * 0.5 - fast.orbit_yaw) < absf(PI * 0.5 - slow.orbit_yaw) * 0.4, "Forward movement pulls camera into alignment faster")
	check(is_equal_approx(Vector2(slow_offset.x, slow_offset.z).length(), 1.5), "Closest zoom is halved for smaller ship")
	slow.resume(Vector3(3, 1, 0), Vector3.ZERO)
	check(is_equal_approx(slow.orbit_yaw, PI * 0.5), "Reattachment seeds orbit from actual frozen camera position")
	for length in [0.0, 0.1, 4.0, 30.0]:
		var profile := Transit.plan(length, 2.3, 1.2)
		var max_speed := 0.0
		for frame in range(201): max_speed = maxf(max_speed, Transit.sample(profile, float(profile.duration) * frame / 200.0).y)
		check(max_speed <= 2.3001, "Transit profile respects speed cap")
		check(is_equal_approx(Transit.sample(profile, profile.duration).x, length) and is_zero_approx(Transit.sample(profile, profile.duration).y), "Transit reaches destination at rest without teleporting")
	var saved_path := "res://tests/movement-migration-test.cfg"
	var source_path := "res://tests/movement-source-test.cfg"
	var existing := ConfigFile.new()
	existing.set_value("movement", "turn_speed", 10.0)
	existing.save(saved_path)
	var source := ConfigFile.new()
	source.set_value("movement", "turn_speed", 144.0)
	source.save(source_path)
	var movement := Movement.new()
	movement.load_settings(true, saved_path, source_path)
	check(is_equal_approx(movement.settings.turn_speed, 144.0), "New exported defaults replace stale saved settings")
	check(is_equal_approx(movement.settings.camera_distance, 1.5), "Older exports without camera distance use closer default")
	movement.settings.turn_speed = 120.0
	movement.settings.camera_distance = 2.75
	movement.save_settings(saved_path)
	movement.load_settings(true, saved_path, source_path)
	check(is_equal_approx(movement.settings.turn_speed, 120.0), "Later saved tuning survives unchanged exported defaults")
	check(is_equal_approx(movement.settings.camera_distance, 2.75), "Saved camera distance survives reload")
	# The same file format is used for exports and saved preferences.
	movement.load_settings(false, "res://tests/nonexistent-settings.cfg", saved_path)
	check(is_equal_approx(movement.settings.camera_distance, 2.75), "Exported camera distance loads as project defaults")
	source.set_value("movement", "turn_speed", 130.0)
	source.save(source_path)
	movement.load_settings(true, saved_path, source_path)
	check(is_equal_approx(movement.settings.turn_speed, 130.0), "Changing default file applies fresh values once")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))
	print("Camera/settings verification: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
