extends RefCounted
## Developer control construction and panel navigation. Live world state stays in the game context.

const Docking = preload("res://docking_controller.gd")
const ModPanel = preload("res://mod_panel.gd")
const WaterParticles = preload("res://water_particles.gd")
const DayNight = preload("res://day_night_cycle.gd")
const Equipment = preload("res://submarine_equipment.gd")
const Weapons = preload("res://submarine_weapons.gd")
const PlantCurrent = preload("res://plant_current.gd")
const WaterVisuals = preload("res://water_visuals.gd")
const NaturalLight = preload("res://natural_light.gd")
const DEFAULT_VISIBILITY := 35.0
const MIN_VISIBILITY := 1.0
const MAX_VISIBILITY := 2000.0

var game: Node

func _init(context: Node) -> void:
	game = context

func _build_interface() -> void:
	game.canvas = CanvasLayer.new()
	game.canvas.layer = 3
	game.canvas.visible = game.developer_ui_visible
	game.add_child(game.canvas)
	game.developer_menu = PanelContainer.new()
	game.developer_menu.minimum_size_changed.connect(func() -> void: game._resize_developer_menu.call_deferred())
	game.canvas.add_child(game.developer_menu)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	game.developer_menu.add_child(margin)
	game.controls = VBoxContainer.new()
	game.controls.add_theme_constant_override("separation", 10)
	margin.add_child(game.controls)
	var heading := HBoxContainer.new()
	game.controls.add_child(heading)
	var title := Label.new()
	title.text = "Developer menu"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := Button.new()
	close.text = "Close (F1)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(game._toggle_developer_ui)
	heading.add_child(close)
	game.developer_tabs = TabContainer.new()
	game.developer_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game.controls.add_child(game.developer_tabs)
	var export_row = HBoxContainer.new(); game.controls.add_child(export_row)
	game.export_all_button = Button.new(); game.export_all_button.text = "Export all settings"
	game.export_all_button.focus_mode = Control.FOCUS_NONE; game.export_all_button.disabled = true
	game.export_all_button.pressed.connect(func() -> void: game.export_all_dialog.popup_centered(Vector2i(850, 600)))
	export_row.add_child(game.export_all_button)
	game.export_all_message = Label.new(); game.export_all_message.text = "Movement, sound and graphics in one file."
	game.export_all_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.export_all_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_row.add_child(game.export_all_message)
	game.export_all_dialog = FileDialog.new()
	game.export_all_dialog.title = "Export all current settings"
	game.export_all_dialog.access = FileDialog.ACCESS_FILESYSTEM
	game.export_all_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	game.export_all_dialog.filters = PackedStringArray(["*.cfg ; All game settings"])
	game.export_all_dialog.current_dir = ProjectSettings.globalize_path("res://..")
	game.export_all_dialog.current_file = "opensubculture_settings.cfg"
	game.export_all_dialog.file_selected.connect(func(path: String) -> void:
		var result = game._export_all_settings(path)
		game.export_all_message.text = "All settings exported." if result == OK else "Export failed: " + error_string(result)
	)
	game.add_child(game.export_all_dialog)
	var graphics_tab := VBoxContainer.new(); graphics_tab.name = "Graphics"
	game.developer_tabs.add_child(graphics_tab)
	var graphics_scroll := ScrollContainer.new()
	graphics_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graphics_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	graphics_tab.add_child(graphics_scroll)
	game.graphics_controls = VBoxContainer.new()
	game.graphics_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.graphics_controls.add_theme_constant_override("separation", 12)
	graphics_scroll.add_child(game.graphics_controls)
	game.wildlife_density_label = Label.new(); game.graphics_controls.add_child(game.wildlife_density_label)
	game.wildlife_density_slider = HSlider.new(); game.wildlife_density_slider.scrollable = false
	game.wildlife_density_slider.min_value = 0; game.wildlife_density_slider.max_value = 300
	game.wildlife_density_slider.step = 5; game.wildlife_density_slider.value = 100
	game.wildlife_density_slider.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(game.wildlife_density_slider)
	game.wildlife_density_slider.value_changed.connect(func(_value: float) -> void: game._update_wildlife_density())
	game.wildlife_density_slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())
	game._update_wildlife_density()
	game.hud_scale_label = Label.new()
	game.graphics_controls.add_child(game.hud_scale_label)
	game.hud_scale_slider = HSlider.new(); game.hud_scale_slider.scrollable = false
	game.hud_scale_slider.min_value = 25.0
	game.hud_scale_slider.max_value = 150.0
	game.hud_scale_slider.step = 1.0
	game.hud_scale_slider.value = 50.0
	game.hud_scale_slider.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(game.hud_scale_slider)
	game.hud_scale_slider.value_changed.connect(func(_value: float) -> void: game._update_hud_scale())
	game.hud_scale_slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())
	game._update_hud_scale()
	game.hud_map_zoom_label = Label.new()
	game.graphics_controls.add_child(game.hud_map_zoom_label)
	game.hud_map_zoom_slider = HSlider.new(); game.hud_map_zoom_slider.scrollable = false
	game.hud_map_zoom_slider.min_value = 0.5
	game.hud_map_zoom_slider.max_value = 4.0
	game.hud_map_zoom_slider.step = 0.1
	game.hud_map_zoom_slider.value = 2.0
	game.hud_map_zoom_slider.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(game.hud_map_zoom_slider)
	game.hud_map_zoom_slider.value_changed.connect(func(_value: float) -> void: game._update_hud_scale())
	game.hud_map_zoom_slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())
	game.crt_reflection_label = Label.new()
	game.graphics_controls.add_child(game.crt_reflection_label)
	game.crt_reflection_slider = HSlider.new(); game.crt_reflection_slider.scrollable = false
	game.crt_reflection_slider.min_value = 0.0
	game.crt_reflection_slider.max_value = 100.0
	game.crt_reflection_slider.step = 1.0
	game.crt_reflection_slider.value = 25.0
	game.crt_reflection_slider.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(game.crt_reflection_slider)
	game.crt_reflection_slider.value_changed.connect(func(_value: float) -> void: game._update_hud_scale())
	game.crt_reflection_slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())
	game._update_hud_scale()
	game.map_reveal_label = Label.new()
	game.graphics_controls.add_child(game.map_reveal_label)
	game.map_reveal_slider = HSlider.new(); game.map_reveal_slider.scrollable = false
	game.map_reveal_slider.min_value = 2.0
	game.map_reveal_slider.max_value = 30.0
	game.map_reveal_slider.step = 0.5
	game.map_reveal_slider.value = 10.0
	game.map_reveal_slider.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(game.map_reveal_slider)
	game.map_reveal_slider.value_changed.connect(func(_value: float) -> void: game._update_hud_scale())
	game.map_reveal_slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())
	var reset_map := Button.new()
	reset_map.text = "Reset fog of war"
	reset_map.tooltip_text = "Clear discovered areas to test the current reveal radius. Smaller radii keep previous discoveries."
	reset_map.focus_mode = Control.FOCUS_NONE
	reset_map.pressed.connect(func() -> void:
		if game.cockpit_hud != null: game.cockpit_hud.map_data.reset_exploration()
	)
	var map_actions = HBoxContainer.new(); game.graphics_controls.add_child(map_actions)
	reset_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_actions.add_child(reset_map)
	var reveal_map := Button.new(); reveal_map.name = "RevealWholeMap"
	reveal_map.text = "Reveal whole map"; reveal_map.focus_mode = Control.FOCUS_NONE
	reveal_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reveal_map.pressed.connect(func() -> void:
		if game.cockpit_hud != null: game.cockpit_hud.map_data.reveal_all()
	)
	map_actions.add_child(reveal_map)
	game._update_hud_scale()
	game.fog_button = CheckButton.new()
	game.fog_button.text = "Underwater fog"
	game.fog_button.button_pressed = true
	game.fog_button.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(game.fog_button)
	game.fog_label = Label.new()
	game.graphics_controls.add_child(game.fog_label)
	game.fog_slider = HSlider.new(); game.fog_slider.scrollable = false
	game.fog_slider.min_value = MIN_VISIBILITY
	game.fog_slider.max_value = MAX_VISIBILITY
	game.fog_slider.step = 0.5
	game.fog_slider.value = DEFAULT_VISIBILITY
	game.fog_slider.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(game.fog_slider)
	var hint := Label.new()
	hint.text = "Spread fade start and view distance apart for a longer, gentler fade."
	hint.add_theme_font_size_override("font_size", 12)
	game.graphics_controls.add_child(hint)
	game.fog_slider.value_changed.connect(func(value: float) -> void:
		game.fog_visibility = value
		game._update_water_environment()
	)
	game.fog_slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())
	game.fog_button.toggled.connect(func(_enabled: bool) -> void:
		game._update_water_environment()
		game._save_preferences()
	)
	var presets := HBoxContainer.new()
	game.graphics_controls.add_child(presets)
	for preset in [["Original feel", DEFAULT_VISIBILITY], ["Clearer water", 100.0]]:
		var button := Button.new()
		button.text = preset[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			game.fog_slider.value = float(preset[1])
			game._save_preferences()
		)
		presets.add_child(button)
	game.fog_start_label = Label.new(); game.graphics_controls.add_child(game.fog_start_label)
	game.fog_start_slider = HSlider.new(); game.fog_start_slider.scrollable = false; game.fog_start_slider.min_value = 0.0; game.fog_start_slider.max_value = MAX_VISIBILITY - 0.5
	game.fog_start_slider.step = 0.5; game.fog_start_slider.value = 5.0; game.fog_start_slider.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(game.fog_start_slider)
	game.fog_curve_label = Label.new(); game.graphics_controls.add_child(game.fog_curve_label)
	game.fog_curve_slider = HSlider.new(); game.fog_curve_slider.scrollable = false; game.fog_curve_slider.min_value = 0.25; game.fog_curve_slider.max_value = 8.0
	game.fog_curve_slider.step = 0.1; game.fog_curve_slider.value = 1.8; game.fog_curve_slider.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(game.fog_curve_slider)
	for slider in [game.fog_start_slider, game.fog_curve_slider]:
		slider.value_changed.connect(func(_value: float) -> void: game._update_water_environment())
		slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())
	_build_daylight_controls()
	_build_natural_light_controls()
	_build_particle_controls()
	_build_plant_controls()
	_build_water_controls()
	_build_equipment_controls()
	_build_weapon_controls()
	game.bubble_controls = VBoxContainer.new()
	game.graphics_controls.add_child(game.bubble_controls)
	var graphics_hint := Label.new()
	graphics_hint.text = "Changes are saved automatically. Export all settings includes every developer tab."
	graphics_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.graphics_controls.add_child(graphics_hint)
	var system := VBoxContainer.new()
	system.name = "System"
	system.add_theme_constant_override("separation", 12)
	game.developer_tabs.add_child(system)
	game.status_label = Label.new()
	game.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	system.add_child(game.status_label)
	game.telemetry = Label.new()
	system.add_child(game.telemetry)
	var credits_button := Button.new(); credits_button.name = "GiveTestingCredits"
	credits_button.text = "Give player 100,000 credits"; credits_button.focus_mode = Control.FOCUS_NONE
	credits_button.pressed.connect(func() -> void:
		game.player_progress.status.credits += 100000
		if game.dock_interface != null and game.dock_interface.visible: game.dock_interface.rebuild()
	)
	system.add_child(credits_button)
	var market_speed_label := Label.new(); system.add_child(market_speed_label)
	game.market_speed_slider = HSlider.new(); game.market_speed_slider.name = "MarketSpeed"
	game.market_speed_slider.scrollable = false; game.market_speed_slider.focus_mode = Control.FOCUS_NONE
	game.market_speed_slider.min_value = 0; game.market_speed_slider.max_value = 200; game.market_speed_slider.step = 1; game.market_speed_slider.value = 50
	game.market_speed_slider.tooltip_text = "Speed of market price changes, production and traders. 100% uses the original timing; 0% pauses the market."
	system.add_child(game.market_speed_slider)
	game.market_speed_slider.value_changed.connect(func(value: float) -> void: market_speed_label.text = "Market speed: %.0f%%" % value)
	market_speed_label.text = "Market speed: %.0f%%" % game.market_speed_slider.value
	game.docking_radius_label = Label.new()
	system.add_child(game.docking_radius_label)
	game.docking_radius_slider = HSlider.new(); game.docking_radius_slider.scrollable = false
	game.docking_radius_slider.min_value = 0.5
	game.docking_radius_slider.max_value = 10.0
	game.docking_radius_slider.step = 0.1
	game.docking_radius_slider.value = Docking.APPROACH_RADIUS
	game.docking_radius_slider.focus_mode = Control.FOCUS_NONE
	system.add_child(game.docking_radius_slider)
	game.docking_radius_slider.value_changed.connect(func(_value: float) -> void: game._update_docking_radius())
	game.docking_radius_slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())
	game._update_docking_radius()
	var choose := Button.new()
	choose.text = "Choose Sub Culture folder…"
	choose.focus_mode = Control.FOCUS_NONE
	choose.pressed.connect(func() -> void:
		if not game.world_loading: game.folder_dialog.popup_centered(Vector2i(850, 600))
	)
	system.add_child(choose)
	game.folder_dialog = FileDialog.new()
	game.folder_dialog.use_native_dialog = true
	game.folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	game.folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	game.folder_dialog.title = "Choose your Sub Culture game folder"
	game.folder_dialog.dir_selected.connect(game._choose_game_folder)
	game.add_child(game.folder_dialog)
	game.folder_prompt = ConfirmationDialog.new()
	game.folder_prompt.title = "Locate original Sub Culture files"
	game.folder_prompt.ok_button_text = "Choose folder..."
	game.folder_prompt.cancel_button_text = "Exit"
	game.folder_prompt.confirmed.connect(func() -> void: game.folder_dialog.popup_centered(Vector2i(850,600)))
	game.folder_prompt.canceled.connect(func() -> void: game.get_tree().quit())
	game.folder_dialog.canceled.connect(func() -> void:
		if game.game_folder.is_empty(): game._prompt_game_folder("The original Sub Culture files are required to play. Choose the folder containing CLUMPS and DATA."))
	game.add_child(game.folder_prompt)
	game.mod_panel = ModPanel.new()
	game.mod_panel.persist_preferences = game.remember_preferences
	game.mod_panel.applied.connect(game._apply_mods)
	game.add_child(game.mod_panel)
	game.developer_tabs.tab_changed.connect(game._developer_tab_changed)
	game.get_viewport().size_changed.connect(game._resize_developer_menu)
	game._resize_developer_menu()
	for slider in game.developer_menu.find_children("*","HSlider",true,false):
		slider.value_changed.connect(func(_value: float) -> void: game._schedule_settings_save())

func _build_daylight_controls() -> void:
	var run := CheckButton.new(); run.text = "Run day/night cycle"
	run.button_pressed = true; run.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(run); game.daylight_controls.cycle_enabled = run
	run.toggled.connect(func(on: bool) -> void: game.day_night.enabled = on; game._save_preferences())
	game.clock_label = Label.new(); game.graphics_controls.add_child(game.clock_label)
	for row in [["time_of_day", "Time of day", 0.0, 24.0, 0.1], ["cycle_minutes", "Full cycle length (minutes)", 1.0, 60.0, 1.0], ["night_brightness", "Night brightness", 0.02, 0.5, 0.01]]:
		var key: String = row[0]; var caption: String = row[1]
		var label = Label.new(); game.graphics_controls.add_child(label)
		var slider := HSlider.new(); slider.scrollable = false; slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]
		slider.value = float(DayNight.DEFAULTS[key]); slider.focus_mode = Control.FOCUS_NONE
		game.graphics_controls.add_child(slider); game.daylight_controls[key] = slider
		label.text = caption if key == "time_of_day" else "%s: %.2f" % [caption, slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			if key == "time_of_day": game.day_night.hour = fposmod(value, 24.0)
			elif key == "cycle_minutes": game.day_night.cycle_minutes = value
			else: game.day_night.night_brightness = value
			label.text = caption if key == "time_of_day" else "%s: %.2f" % [caption, value]
			game._update_daylight()
		)
		slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())
	var presets = HBoxContainer.new(); game.graphics_controls.add_child(presets)
	for preset in [["Day", 12.0], ["Sunset", 18.0], ["Night", 0.0], ["Sunrise", 6.0]]:
		var button := Button.new(); button.text = preset[0]; button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: game.daylight_controls.time_of_day.value = preset[1]; game._save_preferences())
		presets.add_child(button)
	var hint := Label.new(); hint.text = "Pause the cycle to hold a time. F1 pauses it while you adjust settings."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; game.graphics_controls.add_child(hint)

func _build_natural_light_controls() -> void:
	for row in [["sun_depth","Sunlight fade begins at depth",0.0,100.0,0.5],["sun_falloff","Sunlight falloff distance",0.5,100.0,0.5],["cave_ambient","Cave ambient light",0.0,0.5,0.005]]:
		var key: String = row[0]; var caption: String = row[1]
		var label = Label.new(); game.graphics_controls.add_child(label)
		var slider := HSlider.new(); slider.scrollable = false; slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]; slider.value = NaturalLight.DEFAULTS[key]; slider.focus_mode = Control.FOCUS_NONE
		game.graphics_controls.add_child(slider); game.natural_light_controls[key] = slider
		label.text = "%s: %.1f%%" % [caption,slider.value * 100] if key == "cave_ambient" else "%s: %.1f units" % [caption,slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			game.natural_light.configure({key:value}); label.text = "%s: %.1f%%" % [caption,value * 100] if key == "cave_ambient" else "%s: %.1f units" % [caption,value]; game._update_daylight())
		slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())

func _build_equipment_controls() -> void:
	var scroll := ScrollContainer.new(); scroll.name = "Equipment"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	game.developer_tabs.add_child(scroll)
	var tab := VBoxContainer.new(); tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 12); scroll.add_child(tab)
	for section in [
		["Suck-O-Matic", [["som_range", "Suction depth", 0.1, 10.0, 0.05], ["som_radius", "Suction radius", 0.05, 3.0, 0.01], ["som_pull_speed", "Pull speed", 0.1, 10.0, 0.1], ["som_pull_strength", "Pull strength", 0.1, 50.0, 0.1], ["som_capture_distance", "Pickup distance", 0.02, 1.0, 0.01], ["som_volume_db", "Vacuum volume (dB)", -60.0, 0.0, 1.0]]],
		["Grappling Hook", [["grapple_length", "Rope length", 0.05, 5.0, 0.01], ["grapple_speed", "Deployment / retraction speed", 0.1, 5.0, 0.1], ["grapple_water_drag", "Water drag", 0.1, 20.0, 0.1], ["grapple_cargo_weight", "Cargo weight multiplier", 1.0, 100.0, 1.0], ["grapple_pitch_influence", "Towing pitch influence", 0.0, 2.0, 0.05], ["grapple_volume_db", "Grapple volume (dB)", -60.0, 0.0, 1.0]]],
		["Magnet", [["magnet_length", "Chain length", 0.05, 5.0, 0.01], ["magnet_speed", "Deployment / retraction speed", 0.1, 5.0, 0.1], ["magnet_water_drag", "Water drag", 0.1, 20.0, 0.1], ["magnet_cargo_weight", "Cargo weight multiplier", 1.0, 100.0, 1.0], ["magnet_pitch_influence", "Towing pitch influence", 0.0, 2.0, 0.05], ["magnet_volume_db", "Magnet volume (dB)", -60.0, 0.0, 1.0]]],
		["Deep-Sea Lights", [["light_energy", "Light brightness", 0.1, 12.0, 0.1], ["light_range", "Light range", 2.0, 60.0, 1.0], ["light_angle", "Light beam angle", 5.0, 75.0, 1.0], ["light_down_angle", "Light downward angle", 0.0, 80.0, 1.0]]]
	]:
		var heading := Label.new(); heading.text = section[0]; tab.add_child(heading)
		for row in section[1]:
			var key: String = row[0]; var caption: String = row[1]
			var label := Label.new(); tab.add_child(label)
			var slider := HSlider.new(); slider.scrollable = false
			slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]
			slider.value = Equipment.DEFAULTS[key]; slider.focus_mode = Control.FOCUS_NONE
			game.equipment_controls[key] = slider; tab.add_child(slider)
			label.text = "%s: %.2f" % [caption, slider.value]
			slider.value_changed.connect(func(value: float) -> void:
				label.text = "%s: %.2f" % [caption, value]
				game._update_equipment_settings()
			)
			slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())

func _build_weapon_controls() -> void:
	var scroll = ScrollContainer.new(); scroll.name = "Weapons"; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; game.developer_tabs.add_child(scroll)
	var tab := VBoxContainer.new(); tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(tab)
	for row in [["auto_aim_cone","Auto aim cone (degrees, full width; 0 = off)",0.0,120.0,1.0],["range","Zapper range",0.5,15.0,0.25],["damage_per_second","Zapper damage per second",0.0,50.0,0.5],["beam_width","Beam width",0.02,0.6,0.01],["animation_speed","Lightning animation speed",1.0,40.0,1.0],["volume_db","Zapper volume (dB)",-60.0,0.0,1.0],["gore_amount","Gore particles per death",0.0,100.0,1.0],["gore_settle_speed","Gore settling speed",0.1,5.0,0.1],["gore_lifetime","Gore lifetime (seconds)",0.2,10.0,0.1],["chunk_lifetime","Chunk lifetime before fading (seconds)",2.0,300.0,1.0]]:
		var key: String = row[0]; var caption: String = row[1]
		var label := Label.new(); tab.add_child(label)
		var slider = HSlider.new(); slider.scrollable = false; slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]; slider.value = Weapons.DEFAULTS[key]; slider.focus_mode = Control.FOCUS_NONE; tab.add_child(slider); game.weapon_controls[key] = slider
		label.text = "%s: %.2f" % [caption,slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			label.text = "%s: %.2f" % [caption,value]; game.weapon_overrides[key] = value; game._update_weapon_settings())
		slider.set_meta("caption",caption); slider.set_meta("label",label)
		slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())

func _build_particle_controls() -> void:
	var enabled := CheckButton.new(); enabled.text = "Floating water particles"
	enabled.button_pressed = true; enabled.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(enabled); game.particle_controls.enabled = enabled
	enabled.toggled.connect(func(on: bool) -> void:
		game.particles.configure({"enabled": on}); game._save_preferences()
	)
	for row in [["count", "Particle count", 0.0, 4000.0, 50.0], ["size", "Particle size", 0.005, 0.08, 0.005], ["drift", "Particle drift speed", 0.0, 0.3, 0.01], ["radius", "Particle viewing radius", 3.0, 30.0, 0.5], ["visibility", "Particle brightness", 0.0, 1.0, 0.05]]:
		var key: String = row[0]
		var caption: String = row[1]
		var label = Label.new(); game.graphics_controls.add_child(label)
		var slider := HSlider.new(); slider.scrollable = false; slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]
		slider.value = float(WaterParticles.DEFAULTS[key]); slider.focus_mode = Control.FOCUS_NONE
		game.graphics_controls.add_child(slider); game.particle_controls[key] = slider
		label.text = "%s: %.3f" % [caption, slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			label.text = "%s: %.3f" % [caption, value]
			game.particles.configure({key: value})
		)
		slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())
	game.particles.configure({})

func _build_plant_controls() -> void:
	var enabled := CheckButton.new(); enabled.text = "Plants sway in current"
	enabled.button_pressed = true; enabled.focus_mode = Control.FOCUS_NONE
	game.graphics_controls.add_child(enabled); game.plant_controls.enabled = enabled
	enabled.toggled.connect(func(on: bool) -> void: game.plant_current.configure({"enabled":on}); game._save_preferences())
	for row in [["strength","Plant sway strength",0.0,0.5,0.01],["speed","Plant sway speed",0.0,2.0,0.05],["direction","Plant current direction (degrees)",0.0,360.0,5.0],["variation","Plant sway variation",0.0,1.0,0.05],["wavelength","Plant wave length (plant heights)",0.4,4.0,0.1],["ripple","Plant ripple strength",0.0,1.0,0.01],["twist","Plant twist strength",0.0,2.0,0.05],["wash_strength","Propeller wash strength",0.0,1.5,0.05],["wash_range","Propeller wash range",0.5,12.0,0.25],["wash_recovery","Plant wash recovery (seconds)",0.1,4.0,0.1]]:
		var key: String = row[0]; var caption: String = row[1]
		var label = Label.new(); game.graphics_controls.add_child(label)
		var slider := HSlider.new(); slider.scrollable = false; slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]
		slider.value = PlantCurrent.DEFAULTS[key]; slider.focus_mode = Control.FOCUS_NONE
		game.graphics_controls.add_child(slider); game.plant_controls[key] = slider
		label.text = "%s: %.2f" % [caption,slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			label.text = "%s: %.2f" % [caption,value]; game.plant_current.configure({key:value})
		)
		slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())

func _build_water_controls() -> void:
	for row in [["caustics_strength","Sun caustics strength",0.0,2.0,0.05],["caustics_size","Caustics pattern size",0.5,8.0,0.25],["caustics_speed","Caustics animation speed",0.0,2.0,0.05],["caustics_depth","Caustics depth reach",2.0,80.0,1.0],["wave_height","Surface wave height",0.0,0.15,0.005],["wave_size","Surface wave size",1.0,12.0,0.25],["wave_speed","Surface wave speed",0.0,3.0,0.05],["wave_direction","Wave direction (degrees)",0.0,360.0,5.0],["surface_shine","Water surface shine",0.0,2.0,0.05]]:
		var key: String = row[0]; var caption: String = row[1]
		var label = Label.new(); game.graphics_controls.add_child(label)
		var slider := HSlider.new(); slider.scrollable = false; slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]; slider.value = WaterVisuals.DEFAULTS[key]; slider.focus_mode = Control.FOCUS_NONE
		game.graphics_controls.add_child(slider); game.water_controls[key] = slider
		label.text = "%s: %.3f" % [caption,slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			label.text = "%s: %.3f" % [caption,value]; game.water_visuals.configure({key:value})
		)
		slider.drag_ended.connect(func(_changed: bool) -> void: game._save_preferences())

func _toggle_developer_ui() -> void:
	game.developer_ui_visible = not game.developer_ui_visible
	game.canvas.visible = game.developer_ui_visible
	game._update_mouse_pointer()
	if not game.developer_ui_visible:
		game.folder_dialog.hide()
		game.export_all_dialog.hide()
		if game.tuning_panel != null: game.tuning_panel.export_dialog.hide()
		if game.sound_panel != null:
			game.sound_panel.stop_preview()
			game.sound_panel.export_dialog.hide()

func _resize_developer_menu() -> void:
	var viewport = game.get_viewport().get_visible_rect().size
	game.developer_menu.position = Vector2(maxf(18.0, (viewport.x - 740.0) / 2.0), 18.0)
	game.developer_menu.size = Vector2(minf(740.0, viewport.x - 36.0), minf(850.0, viewport.y - 36.0))

func _developer_tab_changed(index: int) -> void:
	game._resize_developer_menu.call_deferred()
	if game.sound_panel != null and game.developer_tabs.get_current_tab_control() != game.sound_panel: game.sound_panel.stop_preview()

func _select_developer_tab(tab_name: String) -> void:
	for index in range(game.developer_tabs.get_tab_count()):
		if game.developer_tabs.get_tab_title(index) == tab_name:
			game.developer_tabs.current_tab = index
			break
	for index in range(game.developer_tabs.get_tab_count()): game.developer_tabs.get_tab_control(index).visible = index == game.developer_tabs.current_tab

# Retained for capture/test scripts; F1 is the only menu keyboard shortcut.
func _toggle_tuning() -> void:
	if not game.pilot_mode: return
	if game.cockpit_hud != null: game.cockpit_hud.visible = not game.world_loading and game.docking.stage != Docking.Stage.DOCKED
	game.developer_ui_visible = true
	game.canvas.visible = true
	game._select_developer_tab("Movement")

func _toggle_sound_tuning() -> void:
	if not game.pilot_mode: return
	game.developer_ui_visible = true
	game.canvas.visible = true
	game._select_developer_tab("Sound")

