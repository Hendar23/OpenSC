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
	game._load_preferences("res://view_defaults.cfg")
	var defaults := ConfigFile.new(); defaults.load("res://view_defaults.cfg")
	check(is_equal_approx(game.fog_slider.value,defaults.get_value("view","fog_visibility")) and is_equal_approx(game.fog_start_slider.value,defaults.get_value("view","fog_start")) and is_equal_approx(game.fog_curve_slider.value,defaults.get_value("view","fog_curve")), "Preferred fog defaults load")
	check(is_equal_approx(game.docking.approach_radius,defaults.get_value("view","docking_radius")) and is_equal_approx(game.day_night.night_brightness,defaults.get_value("view","night_brightness")) and is_equal_approx(game.day_night.cycle_minutes,defaults.get_value("view","cycle_minutes")), "Preferred docking and day/night defaults load")
	game.pilot.movement.settings.camera_distance = 0.55
	game.pilot.movement.settings.bubble_rate = 9.0
	game.pilot.submarine_audio.tuning.settings.master_volume = -13.0
	game.fog_slider.value = 48.0
	game.particle_controls.count.value = 900
	game.particle_controls.enabled.button_pressed = false
	game.crt_reflection_slider.value = 55.0
	game.wildlife_density_slider.value = 150.0
	game.plant_controls.strength.value = 0.25
	game.plant_controls.speed.value = 0.65
	game.plant_controls.direction.value = 120
	game.plant_controls.variation.value = 0.8
	game.plant_controls.wavelength.value = 2.0; game.plant_controls.ripple.value = 0.3; game.plant_controls.twist.value = 0.7
	game.plant_controls.wash_strength.value = 0.9; game.plant_controls.wash_range.value = 6; game.plant_controls.wash_recovery.value = 2
	game.plant_controls.enabled.button_pressed = false
	game.water_controls.caustics_strength.value = 0.8; game.water_controls.wave_height.value = 0.075
	game.water_controls.surface_shine.value = 0.65
	game.weapon_controls.range.value = 5.5; game.weapon_controls.damage_per_second.value = 7.5
	game.weapon_controls.gore_amount.value = 45; game.weapon_controls.chunk_lifetime.value = 120
	game.weapon_controls.gore_settle_speed.value = 3.0; game.weapon_controls.gore_lifetime.value = 7.0
	game.natural_light_controls.sun_depth.value = 18.0; game.natural_light_controls.sun_falloff.value = 9.0
	check(is_equal_approx(game.cockpit_hud.crt_reflection_strength,0.55),"CRT reflection slider updates the HUD live")
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
	check(is_equal_approx(exported.get_value("view","crt_reflection_strength"),0.55),"CRT reflection strength exports")
	check(is_equal_approx(exported.get_value("view","wildlife_density"),1.5),"Wildlife density exports")
	check(is_equal_approx(exported.get_value("view","plants_strength"),0.25) and is_equal_approx(exported.get_value("view","plants_speed"),0.65) and exported.get_value("view","plants_direction") == 120 and is_equal_approx(exported.get_value("view","plants_variation"),0.8) and not exported.get_value("view","plants_enabled"),"All plant current settings export")
	check(is_equal_approx(exported.get_value("view","plants_wash_strength"),0.9) and exported.get_value("view","plants_wash_range") == 6 and exported.get_value("view","plants_wash_recovery") == 2,"Propeller wash tuning exports")
	check(is_equal_approx(exported.get_value("view","plants_wavelength"),2.0) and is_equal_approx(exported.get_value("view","plants_ripple"),0.3) and is_equal_approx(exported.get_value("view","plants_twist"),0.7),"Plant wave and twist controls export")
	complete = true
	for key in game.water_controls: complete = complete and is_equal_approx(float(exported.get_value("view",key)),game.water_controls[key].value)
	check(complete,"All caustic and surface wave settings export")
	check(exported.get_value("view","zapper_range") == 5.5 and exported.get_value("view","zapper_damage_per_second") == 7.5,"Zapper tuning exports")
	check(exported.get_value("view","zapper_gore_amount") == 45 and exported.get_value("view","zapper_chunk_lifetime") == 120,"Gore and debris lifetime export")
	check(is_equal_approx(exported.get_value("view","zapper_gore_settle_speed"),3.0) and is_equal_approx(exported.get_value("view","zapper_gore_lifetime"),7.0),"Gore settling and disappearance settings export")
	check(exported.get_value("view","sun_depth") == 18 and exported.get_value("view","sun_falloff") == 9,"Sunlight depth and falloff export")
	game.weapon_controls.range.value = 1
	game.water_controls.caustics_strength.value = 0; game.water_controls.wave_height.value = 0
	game.plant_controls.strength.value = 0.0; game.plant_controls.enabled.button_pressed = true
	game.plant_controls.wash_strength.value = 0
	game.plant_controls.wavelength.value = 1.0; game.plant_controls.ripple.value = 0; game.plant_controls.twist.value = 0
	game.wildlife_density_slider.value = 0.0
	game.crt_reflection_slider.value = 0.0
	game._load_preferences(path)
	check(game.weapons.settings.range == 5.5 and game.weapons.settings.damage_per_second == 7.5,"Zapper tuning reloads into the live weapon")
	check(is_equal_approx(game.water_visuals.settings.caustics_strength,0.8) and is_equal_approx(game.water_visuals.surface.get_shader_parameter("wave_height"),0.075),"Water tuning reloads into the live shaders")
	check(is_equal_approx(game.plant_controls.strength.value,0.25) and not game.plant_controls.enabled.button_pressed and not game.plant_current.materials[0].get_shader_parameter("sway_enabled"),"Plant current settings reload into the live world")
	check(is_equal_approx(game.plant_current.settings.wash_strength,0.9),"Propeller wash tuning reloads")
	check(is_equal_approx(game.plant_current.settings.wavelength,2.0) and is_equal_approx(game.plant_current.settings.ripple,0.3) and is_equal_approx(game.plant_current.settings.twist,0.7),"Plant wave and twist controls reload into the live shaders")
	check(is_equal_approx(game.wildlife_density_slider.value,150.0) and is_equal_approx(game.wildlife.density,1.5),"Wildlife density reloads into the live population")
	check(is_equal_approx(game.crt_reflection_slider.value,55.0) and is_equal_approx(game.cockpit_hud.crt_reflection_strength,0.55),"CRT reflection strength reloads")
	game.export_all_dialog.show(); game._update_mouse_pointer()
	check(game._desired_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "Combined export dialog restores pointer")
	game._physics_process(0.0); check(not game.pilot.controls_enabled, "Combined export dialog blocks piloting")
	game.developer_ui_visible = true; game._toggle_developer_ui(); check(not game.export_all_dialog.visible, "Closing developer menu closes export dialog")
	game.world_loading = true; check(game._export_all_settings(path) == ERR_UNAVAILABLE, "Export unavailable during reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.queue_free(); await process_frame
	print("Export all verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
