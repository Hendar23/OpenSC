extends RefCounted
## Shared settings persistence and export, independent of session save files.

const Docking = preload("res://docking_controller.gd")
const HUD = preload("res://cockpit_hud.gd")
const MIN_VISIBILITY = preload("res://developer_tools.gd").MIN_VISIBILITY
const MAX_VISIBILITY = preload("res://developer_tools.gd").MAX_VISIBILITY

var game: Node

func _init(context: Node) -> void:
	game = context

func _load_preferences(path: String = "") -> void:
	if path.is_empty(): path = preload("res://current_settings.gd").path("view_defaults.cfg")
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	game.loading_preferences = true
	var market_speed: Variant = config.get_value("view","market_speed",game.market_speed_slider.value / 100.0)
	if (market_speed is float or market_speed is int) and is_finite(float(market_speed)):
		game.market_speed_slider.value = clampf(float(market_speed) * 100.0,game.market_speed_slider.min_value,game.market_speed_slider.max_value)
	var wildlife_density: Variant = config.get_value("view","wildlife_density",game.wildlife_density_slider.value / 100.0)
	if (wildlife_density is float or wildlife_density is int) and is_finite(float(wildlife_density)):
		game.wildlife_density_slider.value = clampf(float(wildlife_density) * 100.0,0.0,300.0)
	var hud_scale: Variant = config.get_value("view", "hud_scale", game.hud_scale_slider.value / 100.0)
	if (hud_scale is float or hud_scale is int) and is_finite(float(hud_scale)):
		game.hud_scale_slider.value = clampf(float(hud_scale) * 100.0, game.hud_scale_slider.min_value, game.hud_scale_slider.max_value)
	var map_zoom: Variant = config.get_value("view","hud_map_zoom",game.hud_map_zoom_slider.value)
	if (map_zoom is float or map_zoom is int) and is_finite(float(map_zoom)):
		game.hud_map_zoom_slider.value = clampf(float(map_zoom),game.hud_map_zoom_slider.min_value,game.hud_map_zoom_slider.max_value)
	var reveal_radius: Variant = config.get_value("view","map_reveal_radius",game.map_reveal_slider.value)
	if (reveal_radius is float or reveal_radius is int) and is_finite(float(reveal_radius)):
		game.map_reveal_slider.value = clampf(float(reveal_radius),game.map_reveal_slider.min_value,game.map_reveal_slider.max_value)
	var reflection: Variant = config.get_value("view","crt_reflection_strength",game.crt_reflection_slider.value / 100.0)
	if (reflection is float or reflection is int) and is_finite(float(reflection)):
		game.crt_reflection_slider.value = clampf(float(reflection) * 100.0,0.0,100.0)
	var value: Variant = config.get_value("view", "fog_visibility", game.fog_slider.value)
	if (value is float or value is int) and is_finite(float(value)):
		game.fog_slider.value = clampf(float(value), MIN_VISIBILITY, MAX_VISIBILITY)
	var enabled: Variant = config.get_value("view", "fog_enabled", game.fog_button.button_pressed)
	if enabled is bool: game.fog_button.button_pressed = enabled
	for row in [["fog_start", game.fog_start_slider, 5.0], ["fog_curve", game.fog_curve_slider, 1.8], ["docking_radius", game.docking_radius_slider, Docking.APPROACH_RADIUS]]:
		var setting: Variant = config.get_value("view", row[0], row[1].value)
		if (setting is float or setting is int) and is_finite(float(setting)):
			row[1].value = clampf(float(setting), row[1].min_value, row[1].max_value)
	for key in game.daylight_controls:
		var fallback: Variant = game.daylight_controls[key].button_pressed if key == "cycle_enabled" else game.daylight_controls[key].value
		var setting: Variant = config.get_value("view", key, fallback)
		if key == "cycle_enabled":
			if setting is bool: game.daylight_controls[key].button_pressed = setting
		elif (setting is float or setting is int) and is_finite(float(setting)):
			game.daylight_controls[key].value = clampf(float(setting), game.daylight_controls[key].min_value, game.daylight_controls[key].max_value)
	for key in game.natural_light_controls:
		var setting: Variant = config.get_value("view",key,game.natural_light_controls[key].value)
		if (setting is int or setting is float) and is_finite(float(setting)): game.natural_light_controls[key].value = clampf(float(setting),game.natural_light_controls[key].min_value,game.natural_light_controls[key].max_value)
	for key in game.particle_controls:
		var fallback: Variant = game.particle_controls[key].button_pressed if key == "enabled" else game.particle_controls[key].value
		var setting: Variant = config.get_value("view", "particles_" + str(key), fallback)
		if key == "enabled":
			if setting is bool: game.particle_controls[key].button_pressed = setting
		elif (setting is float or setting is int) and is_finite(float(setting)):
			game.particle_controls[key].value = clampf(float(setting), game.particle_controls[key].min_value, game.particle_controls[key].max_value)
	for key in game.plant_controls:
		var fallback: Variant = game.plant_controls[key].button_pressed if key == "enabled" else game.plant_controls[key].value
		var setting: Variant = config.get_value("view","plants_" + str(key),fallback)
		if key == "enabled":
			if setting is bool: game.plant_controls[key].button_pressed = setting
		elif (setting is float or setting is int) and is_finite(float(setting)):
			game.plant_controls[key].value = clampf(float(setting),game.plant_controls[key].min_value,game.plant_controls[key].max_value)
	for key in game.water_controls:
		var setting: Variant = config.get_value("view",key,game.water_controls[key].value)
		if (setting is float or setting is int) and is_finite(float(setting)):
			game.water_controls[key].value = clampf(float(setting),game.water_controls[key].min_value,game.water_controls[key].max_value)
	for key in game.weapon_controls:
		if not config.has_section_key("view","zapper_" + str(key)): continue
		var setting: Variant = config.get_value("view","zapper_" + str(key))
		if (setting is float or setting is int) and is_finite(float(setting)):
			game.weapon_overrides[key] = clampf(float(setting),game.weapon_controls[key].min_value,game.weapon_controls[key].max_value)
			game.weapon_controls[key].value = game.weapon_overrides[key]
	game._update_weapon_settings()
	for key in game.equipment_controls:
		var setting: Variant = config.get_value("view", key, game.equipment_controls[key].value)
		if (setting is float or setting is int) and is_finite(float(setting)):
			game.equipment_controls[key].value = clampf(float(setting), game.equipment_controls[key].min_value, game.equipment_controls[key].max_value)
	for index in range(5):
		var setting: Variant = config.get_value("view", "hud_" + str(HUD.DEFINITIONS[index].id), game.hud_enabled[index])
		if setting is bool:
			game.hud_enabled[index] = setting
			if game.cockpit_hud != null:
				game.cockpit_hud.set_enabled(index,setting,false)
	game.loading_preferences = false

func _schedule_settings_save() -> void:
	if not game.remember_preferences or game.loading_preferences or game.world_loading or not game.startup_complete or game.settings_save_pending: return
	game.settings_save_retries = 0
	game.settings_save_pending = true
	game._save_all_preferences.call_deferred()

func _save_all_preferences() -> void:
	game.settings_save_pending = false
	if not game.remember_preferences or game.loading_preferences or game.world_loading or game.pilot == null: return
	var view_result = game._save_preferences()
	var movement_path = preload("res://current_settings.gd").path("submarine_tuning.cfg") if game.defaults_directory.is_empty() else game.defaults_directory.path_join("submarine_tuning.cfg")
	var sound_path = preload("res://current_settings.gd").path("submarine_audio.cfg") if game.defaults_directory.is_empty() else game.defaults_directory.path_join("submarine_audio.cfg")
	var movement_result: Error = game.pilot.movement.save_settings(movement_path)
	var sound_result: Error = game.pilot.submarine_audio.tuning.save_settings(sound_path)
	if movement_result != OK: game._report_settings_error(movement_path,movement_result)
	if sound_result != OK: game._report_settings_error(sound_path,sound_result)
	if view_result != OK or movement_result != OK or sound_result != OK:
		if game.settings_save_retries < 3:
			game.settings_save_retries += 1
			game.settings_save_pending = true
			game.get_tree().create_timer(0.25,true,false,true).timeout.connect(game._save_all_preferences)
	else:
		game.settings_save_retries = 0
		if game.status_label.text == game.settings_save_error:
			game.status_label.text = ""; game.status_label.tooltip_text = ""
		game.settings_save_error = ""

func _report_settings_error(path: String, result: Error) -> void:
	game.settings_save_error = "Could not save %s: %s" % [path.get_file(),error_string(result)]
	game.status_label.text = game.settings_save_error
	game.status_label.tooltip_text = ProjectSettings.globalize_path(path)
	push_warning(game.settings_save_error + " — " + ProjectSettings.globalize_path(path))

func _save_preferences(path: String = "") -> Error:
	if not game.remember_preferences or game.loading_preferences: return OK
	if path.is_empty(): path = preload("res://current_settings.gd").path("view_defaults.cfg") if game.defaults_directory.is_empty() else game.defaults_directory.path_join("view_defaults.cfg")
	var config := ConfigFile.new(); config.load(path)
	var view = game._view_settings()
	for key in view: config.set_value("view",key,view[key])
	config.set_value("settings","unified",true)
	var result := config.save(path)
	if result != OK: game._report_settings_error(path,result)
	# The original asset folder is machine-specific, independent of tuning.
	if not game.game_folder.is_empty() and game.defaults_directory.is_empty():
		var preferences := preload("res://player_storage.gd").preferences_path()
		var directory_result := preload("res://player_storage.gd").ensure_parent(preferences)
		var paths := ConfigFile.new(); paths.load(preferences)
		paths.set_value("game","folder",game.game_folder)
		var preference_result := paths.save(preferences) if directory_result == OK else directory_result
		if preference_result != OK: game._report_settings_error(preferences,preference_result); return preference_result
	return result

func _view_settings() -> Dictionary:
	var settings = {"fog_visibility": game.fog_visibility, "fog_enabled": game.fog_button.button_pressed, "fog_start": game.fog_start_slider.value, "fog_curve": game.fog_curve_slider.value}
	settings.merge(game.day_night.settings())
	settings.merge(game.natural_light.settings)
	settings["market_speed"] = game.market_speed_slider.value / 100.0
	settings["wildlife_density"] = game.wildlife_density_slider.value / 100.0
	settings["docking_radius"] = game.docking_radius_slider.value
	settings["hud_scale"] = game.hud_scale_slider.value / 100.0
	settings["hud_map_zoom"] = game.hud_map_zoom_slider.value
	settings["map_reveal_radius"] = game.map_reveal_slider.value
	settings["crt_reflection_strength"] = game.crt_reflection_slider.value / 100.0
	for key in game.equipment_controls: settings[key] = game.equipment_controls[key].value
	for key in game.weapon_controls: settings["zapper_" + str(key)] = game.weapon_controls[key].value
	for index in range(5): settings["hud_" + str(HUD.DEFINITIONS[index].id)] = game.hud_enabled[index]
	for key in game.particle_controls:
		settings["particles_" + str(key)] = game.particle_controls[key].button_pressed if key == "enabled" else game.particle_controls[key].value
	for key in game.plant_controls:
		settings["plants_" + str(key)] = game.plant_controls[key].button_pressed if key == "enabled" else game.plant_controls[key].value
	for key in game.water_controls: settings[key] = game.water_controls[key].value
	return settings

func _export_all_settings(path: String) -> Error:
	if game.pilot == null or game.world_loading or game.pilot.submarine_audio == null: return ERR_UNAVAILABLE
	var config := ConfigFile.new()
	config.set_value("export", "schema_version", 1)
	config.set_value("movement", "physics_version", 2)
	for key in game.pilot.movement.settings: config.set_value("movement", key, game.pilot.movement.settings[key])
	for key in game.pilot.submarine_audio.tuning.settings: config.set_value("sound", key, game.pilot.submarine_audio.tuning.settings[key])
	var view = game._view_settings()
	for key in view: config.set_value("view", key, view[key])
	return config.save(path)

