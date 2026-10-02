extends SceneTree
const Game = preload("res://game.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(description)
func _run() -> void:
	Mods.initialize(false)
	Mods.apply(["test.remastered-submarine"], Mods.order, false)
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete, "Game starts with interpolation enabled")
	check(game.pilot.is_physics_interpolated_and_enabled(), "Submarine model interpolates physics movement")
	check(not game.camera.is_physics_interpolated_and_enabled(), "Render-frame camera avoids double interpolation")
	game.set_process(false)
	game.set_physics_process(false)
	game.pilot.controls_enabled = false
	game.pilot.movement.settings.forward_drag = 0.0
	game.pilot.movement.settings.water_resistance = 0.0
	game.pilot.reset_at(Vector3(10000, 100, 10000))
	await physics_frame
	await physics_frame
	game.pilot.velocity = Vector3(0, 0, -4.6)
	Engine.physics_ticks_per_second = 20
	Engine.max_fps = 120
	var worst_error := 0.0
	var largest_pose_gap := 0.0
	for frame in range(90):
		await process_frame
		game._process(1.0 / 120.0)
		var pose := game.pilot.get_global_transform_interpolated()
		var target := pose.origin + Vector3.UP * 0.35
		var look := -game.camera.global_basis.z
		var aim := (target - game.camera.global_position).normalized()
		worst_error = maxf(worst_error, look.distance_to(aim))
		largest_pose_gap = maxf(largest_pose_gap, pose.origin.distance_to(game.pilot.global_position))
	check(largest_pose_gap > 0.02, "High render rate samples poses between slower physics ticks")
	check(worst_error < 0.001, "Camera tracks the rendered hull without physics-step aiming jitter")
	game.pilot.reset_at(Vector3(12000, 100, 12000))
	await process_frame
	check(game.pilot.get_global_transform_interpolated().origin.distance_to(game.pilot.global_position) < 0.01, "Reset clears old interpolation history instead of streaking across the world")
	game.queue_free()
	await process_frame
	Mods.initialize(false)
	print("Camera interpolation verification: %d checks, %d failures; aim error=%f" % [checks, failures, worst_error])
	quit(1 if failures else 0)
