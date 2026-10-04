extends SceneTree
const Game = preload("res://game.gd")
const Cycle = preload("res://day_night_cycle.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _run() -> void:
	var cycle := Cycle.new()
	cycle.step(1200.0); check(is_equal_approx(cycle.hour, 12.0), "Twenty-minute cycle wraps correctly")
	cycle.hour = 23.9; cycle.step(10.0); check(is_equal_approx(cycle.hour, 0.1), "Midnight wraps without losing time")
	cycle.enabled = false; cycle.step(100.0); check(is_equal_approx(cycle.hour, 0.1), "Paused cycle holds time")
	cycle.hour = 12; check(cycle.daylight() == 1.0, "Noon has full daylight")
	cycle.hour = 0; check(cycle.daylight() == 0.0, "Midnight has full night")
	cycle.hour = 6; var sunrise := cycle.daylight(); cycle.hour = 18
	check(sunrise > 0.0 and sunrise < 1.0 and is_equal_approx(sunrise, cycle.daylight()), "Sunrise and sunset blend smoothly")
	Mods.initialize(false)
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete, "Game loads with daylight controls")
	if not game.startup_complete: quit(1); return
	check(game.water_environment.fog_mode == Environment.FOG_MODE_DEPTH and game.water_environment.fog_depth_begin == game.fog_start_slider.value and game.water_environment.fog_depth_end == game.fog_visibility and game.water_environment.fog_density == 1.0, "Fog starts beyond clear-water distance and builds to configured visibility")
	game.fog_start_slider.value = 7.0; game.fog_curve_slider.value = 2.2
	check(game.water_environment.fog_depth_begin == 7.0 and is_equal_approx(game.water_environment.fog_depth_curve, 2.2), "Clear-water and build-up controls apply live")
	game.daylight_controls.cycle_enabled.button_pressed = false
	game.daylight_controls.time_of_day.value = 12
	game._update_daylight()
	var day_energy := game.water_environment.ambient_light_energy
	var day_color := game.water_environment.fog_light_color
	game.daylight_controls.time_of_day.value = 0; game._update_daylight()
	check(game.water_environment.ambient_light_energy < day_energy * 0.3 and game.water_environment.fog_light_color.b > game.water_environment.fog_light_color.g and game.water_environment.fog_light_color.get_luminance() < day_color.get_luminance() * 0.15, "Night is darker deep blue water")
	check(game.surface_material.get_shader_parameter("daylight") == 0.0 and game.sun.light_energy < 0.1, "Surface and sunlight follow night")
	game.fog_button.button_pressed = false; game._update_daylight(); check(not game.water_environment.fog_enabled, "Cycle respects fog toggle")
	game.daylight_controls.cycle_minutes.value = 4
	game.daylight_controls.night_brightness.value = 0.2
	game.daylight_controls.time_of_day.value = 22
	game.daylight_controls.cycle_enabled.button_pressed = true
	game.developer_ui_visible = true; game._process(10.0)
	check(is_equal_approx(game.day_night.hour, 22), "Developer menu pauses cycle while tuning")
	game.developer_ui_visible = false; game._process(10.0)
	check(is_equal_approx(game.day_night.hour, 23), "Configured four-minute cycle advances correctly")
	var path := "res://tests/daylight-export.cfg"
	check(game._export_all_settings(path) == OK, "Combined export includes daylight settings")
	var exported := ConfigFile.new(); exported.load(path)
	check(exported.get_value("view", "cycle_minutes") == 4 and exported.get_value("view", "time_of_day") == 23 and is_equal_approx(exported.get_value("view", "night_brightness"), 0.2) and exported.get_value("view", "cycle_enabled"), "Export stores current clock and lighting preferences")
	check(exported.get_value("view", "fog_start") == 7.0 and is_equal_approx(exported.get_value("view", "fog_curve"), 2.2), "New fog controls export with all settings")
	game._load_preferences(path)
	check(game.day_night.cycle_minutes == 4 and is_equal_approx(game.day_night.night_brightness, 0.2), "Daylight settings reload")
	check(game.fog_start_slider.value == 7.0 and is_equal_approx(game.fog_curve_slider.value, 2.2), "New fog controls reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.queue_free(); await process_frame
	print("Day/night verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
