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
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete, "Game starts with tabbed controls")
	check(not game.has_method("_reset_submarine") and game.find_children("*","Button",true,false).all(func(button: Button) -> bool: return not button.text.begins_with("Reset submarine")),"Submarine reset feature and developer button are removed")
	var start_button := InputEventJoypadButton.new()
	start_button.button_index = JOY_BUTTON_START; start_button.pressed = true
	game._unhandled_input(start_button)
	check(not game.developer_ui_visible,"Controller Start does not open the developer menu")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_F1
	game._input(key)
	check(game.developer_ui_visible and game.canvas.visible, "F1 opens the developer menu")
	game._unhandled_input(start_button)
	check(game.developer_ui_visible,"Controller Start does not close the developer menu")
	check(game.developer_tabs.get_tab_count() == 6 and not game.mod_panel.embedded, "Developer tabs exclude Mods; mod management is a main-menu popup")
	check(game.fog_slider.max_value == 2000 and game.fog_start_slider.min_value == 0,"Visibility controls support a wide distance range")
	game.fog_slider.value = 500; game.fog_start_slider.value = 100
	check(game.fog_label.text.contains("Absolute view distance") and game.fog_start_label.text.contains("Fade start distance"),"Visibility controls identify both fade endpoints")
	check(is_equal_approx(game.camera.far,500) and is_equal_approx(game.water_environment.fog_depth_begin,100),"Both distance endpoints update the renderer live")
	game.fog_slider.value = 80
	check(game.fog_start_slider.value < 80 and game.fog_start_slider.max_value < 80,"Fade start stays below the absolute view limit")
	game.fog_slider.value = 500; game.fog_start_slider.value = 100
	game.pilot.global_position = game.docking.ports[0].entry + Vector3.RIGHT * 3.0
	game.pilot.velocity = Vector3.ZERO
	game.docking_radius_slider.value = 2.0
	game.docking.update_approach()
	check(game.docking.nearby.is_empty(), "Small docking radius requires a close approach even while a city greeting is displayed")
	game.docking_radius_slider.value = 4.0
	check(game.docking.message.contains("(Y/N)"), "Docking radius slider updates the live prompt")
	check(game.equipment_controls.som_radius.get_parent().get_parent().name == "Equipment", "Suction controls have their own Equipment tab")
	check(game.find_children("*","Slider",true,false).all(func(slider: Slider) -> bool: return not slider.scrollable), "Mouse wheel cannot adjust any slider, including weapons and all developer tabs")
	game.equipment_controls.som_radius.value = 0.4; game.equipment_controls.som_range.value = 1.5
	check(is_equal_approx(game.equipment.vacuum.intake_radius,0.4) and is_equal_approx(game.equipment.vacuum.range_metres,1.5), "Suction sliders update gameplay live")
	var radius_path := "res://tests/docking-radius-test.cfg"
	check(game._export_all_settings(radius_path) == OK, "Docking radius can be exported with all settings")
	game.equipment_controls.som_radius.value = 0.1; game.equipment_controls.som_range.value = 0.5
	game.docking_radius_slider.value = 1.0
	game._load_preferences(radius_path)
	check(is_equal_approx(game.docking.approach_radius, 4.0) and is_equal_approx(game._view_settings().docking_radius, 4.0), "Docking radius reloads from exported settings")
	check(is_equal_approx(game.equipment.vacuum.intake_radius,0.4) and is_equal_approx(game.equipment.vacuum.range_metres,1.5), "Suction settings survive export and reload")
	check(game.fog_start_slider.value == 100 and game.fog_slider.value == 500,"Wide fade endpoints survive settings export and reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(radius_path))
	game._physics_process(0.0)
	check(not game.pilot.controls_enabled, "Menu prevents steering while adjusting settings")
	check(game.tuning_panel.sliders.camera_distance.min_value == 0.35, "Camera slider permits much closer distances")
	game.tuning_panel.set_camera_distance(0.1)
	check(is_equal_approx(game.pilot.movement.settings.camera_distance, 0.35), "Wheel and slider share the closer camera limit")
	check(game.tuning_panel.sliders.bubble_rate.get_parent() == game.bubble_controls, "Bubble control is in Graphics")
	game.tuning_panel.sliders.bubble_rate.value = 7.0
	check(game.pilot.movement.settings.bubble_rate == 7.0, "Graphics bubble slider updates the live movement profile")
	var path := "res://tests/menu-settings-test.cfg"
	game.pilot.movement.save_settings(path)
	var saved := ConfigFile.new()
	saved.load(path)
	check(saved.get_value("movement", "bubble_rate") == 7.0 and is_equal_approx(saved.get_value("movement", "camera_distance"), 0.35), "Moved bubbles and closer camera still export")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game._select_developer_tab("Sound")
	game.sound_panel.preview_button.button_pressed = true
	game._select_developer_tab("Graphics")
	check(not game.pilot.submarine_audio.preview, "Changing tabs stops stationary sound preview")
	var window_mode := game.get_window().mode
	for old_key in [KEY_T, KEY_F6, KEY_F8, KEY_F11]:
		key.keycode = old_key
		game._input(key)
		game._unhandled_input(key)
	check(game.developer_tabs.get_current_tab_control().name == "Graphics", "Old separate-menu shortcuts no longer switch panels")
	check(game.get_window().mode == window_mode, "F11 does not switch game out of full screen")
	root.mode = Window.MODE_WINDOWED
	for window_size in [Vector2i(1280, 720), Vector2i(1050, 600)]:
		root.size = window_size
		for tab_name in ["Movement", "Sound", "Graphics", "Equipment", "Weapons", "System"]:
			game._select_developer_tab(tab_name)
			for frame in range(16): await process_frame
			var panel_rect: Rect2 = game.developer_menu.get_global_rect()
			var viewport_size: Vector2 = game.get_viewport().get_visible_rect().size
			check(panel_rect.end.y <= viewport_size.y and panel_rect.end.x <= viewport_size.x, "%s menu fits %s" % [tab_name, window_size])
	key.keycode = KEY_F1
	game._input(key)
	game._physics_process(0.0)
	check(not game.canvas.visible and game.pilot.controls_enabled, "F1 closes the menu and restores piloting")
	game.queue_free()
	await process_frame
	print("Developer menu verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
