extends SceneTree
const Game = preload("res://game.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _run() -> void:
	Mods.initialize(false)
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete, "Game starts with particles")
	if not game.startup_complete: quit(1); return
	game._update_mouse_pointer(); check(game._desired_mouse_mode() == Input.MOUSE_MODE_HIDDEN, "Pointer hidden while piloting")
	game._toggle_developer_ui(); check(game._desired_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "Pointer restored immediately for F1")
	game._toggle_developer_ui(); check(game._desired_mouse_mode() == Input.MOUSE_MODE_HIDDEN, "Pointer hidden immediately after F1 closes")
	if DisplayServer.get_name() != "headless": check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "Native pointer mode changes while piloting")
	game.folder_dialog.show(); game._update_mouse_pointer(); check(game._desired_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "Folder dialog restores pointer")
	game.folder_dialog.hide()
	game.docking.stage = game.Docking.Stage.DOCKED; game._update_mouse_pointer(); check(game._desired_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "Docked screen restores pointer")
	game.docking.stage = game.Docking.Stage.IDLE
	var cloud := game.particles
	cloud.active = true; cloud.set_process(false)
	cloud.configure({"enabled": true, "count": 400.0, "drift": 0.0})
	check(cloud.multimesh.instance_count == 400 and cloud.positions.size() == 400, "Live density updates pooled instances")
	var point: Vector3 = cloud.positions[0]
	cloud._process(1.0); check(cloud.positions[0].is_equal_approx(point), "Zero drift freezes world-space specks")
	cloud.configure({"drift": 0.1}); cloud._process(1.0)
	check(cloud.positions[0].distance_to(point) > 0.001 and cloud.positions[0].distance_to(point) < 0.12, "Specks drift slowly")
	game.camera.global_position += Vector3(100, 0, 0); cloud._process(0.0)
	var contained := true
	for position in cloud.positions: contained = contained and position.distance_to(game.camera.global_position) <= float(cloud.settings.radius) + 0.001
	check(contained and cloud.custom_aabb.has_point(game.camera.global_position), "Camera teleport repopulates cloud and updates culling bounds")
	cloud.configure({"enabled": false}); check(not cloud.visible, "Disable hides particles")
	cloud.configure({"enabled": true, "count": 0.0}); check(cloud.multimesh.instance_count == 0, "Zero density supported")
	game.particle_controls.count.value = 800; game.particle_controls.size.value = 0.04
	game.particle_controls.drift.value = 0.12; game.particle_controls.radius.value = 18; game.particle_controls.visibility.value = 0.65
	check(cloud.settings.count == 800 and is_equal_approx(cloud.settings.size, 0.04) and is_equal_approx(cloud.settings.drift, 0.12) and cloud.settings.radius == 18 and is_equal_approx(cloud.settings.visibility, 0.65), "Graphics sliders update all particle settings live")
	var path := "res://tests/water-particles-settings.cfg"
	game.remember_preferences = true; game._save_preferences(path); game.remember_preferences = false
	game.particle_controls.count.value = 50; game._load_preferences(path)
	check(game.particle_controls.count.value == 800 and is_equal_approx(cloud.settings.visibility, 0.65), "Graphics settings survive config round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.queue_free(); await process_frame
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Leaving game restores pointer")
	print("Water particles verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
