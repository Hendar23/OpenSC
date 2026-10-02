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
	check(game.startup_complete and not game.export_all_button.disabled, "Export available after game loads")
	if not game.startup_complete: quit(1); return
	game.pilot.movement.settings.camera_distance = 0.55
	game.pilot.movement.settings.bubble_rate = 9.0
	game.pilot.submarine_audio.tuning.settings.master_volume = -13.0
	game.fog_slider.value = 48.0
	game.particle_controls.count.value = 900
	game.particle_controls.enabled.button_pressed = false
	var path := "res://tests/export-all-settings.cfg"
	check(game._export_all_settings(path) == OK, "Combined export writes successfully")
	var exported := ConfigFile.new(); check(exported.load(path) == OK, "Combined export reads as CFG")
	var complete := true
	for key in game.pilot.movement.settings: complete = complete and exported.get_value("movement", key) == game.pilot.movement.settings[key]
	check(complete and exported.get_value("movement", "physics_version") == 2, "Every current movement value exported, including camera and bubbles")
	complete = true
	for key in game.pilot.submarine_audio.tuning.settings: complete = complete and exported.get_value("sound", key) == game.pilot.submarine_audio.tuning.settings[key]
	check(complete, "Every current sound value exported")
	check(exported.get_value("view", "fog_visibility") == 48 and exported.get_value("view", "particles_count") == 900 and exported.get_value("view", "particles_enabled") == false, "Current fog and particle settings exported")
	check(not exported.has_section("game") and not exported.has_section("mods"), "Export contains tuning rather than machine paths or active mod choices")
	game.export_all_dialog.show(); game._update_mouse_pointer()
	check(game._desired_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "Combined export dialog restores pointer")
	game._physics_process(0.0); check(not game.pilot.controls_enabled, "Combined export dialog blocks piloting")
	game.developer_ui_visible = true; game._toggle_developer_ui(); check(not game.export_all_dialog.visible, "Closing developer menu closes export dialog")
	game.world_loading = true; check(game._export_all_settings(path) == ERR_UNAVAILABLE, "Export unavailable during reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.queue_free(); await process_frame
	print("Export all verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
