extends Node3D
const Bindings = preload("res://input_bindings.gd")

const Assets = preload("res://clump_loader.gd")
const World = preload("res://world_loader.gd")
const Scenery = preload("res://scenery_loader.gd")
const Creatures = preload("res://creature_loader.gd")
const Docking = preload("res://docking_controller.gd")
const FollowCamera = preload("res://follow_camera.gd")
const Paths = preload("res://asset_paths.gd")
const Pilot = preload("res://submarine_controller.gd")
const Tuning = preload("res://tuning_panel.gd")
const SoundPanel = preload("res://sound_panel.gd")
const Mods = preload("res://mod_registry.gd")
const ModPanel = preload("res://mod_panel.gd")
const MapDocument = preload("res://map_document.gd")
const Wildlife = preload("res://wildlife_population.gd")
const WaterParticles = preload("res://water_particles.gd")
const DayNight = preload("res://day_night_cycle.gd")
const HUD = preload("res://cockpit_hud.gd")
const Equipment = preload("res://submarine_equipment.gd")
const Weapons = preload("res://submarine_weapons.gd")
const SessionDebris = preload("res://creature_death.gd")
const SessionExplosion = preload("res://mine_explosion.gd")
var weapons: Node3D
var weapon_controls := {}
var weapon_overrides := {}
var save_games := preload("res://save_games.gd").new()
var dock_interface: CanvasLayer
var dock_interface_active := false
var loading_save := false
const PlayerProgress = preload("res://player_progress.gd")
var player_progress := PlayerProgress.restore()
var submarine_explosion_frames: Array[Texture2D] = []
var submarine_explosion_sound: AudioStream
var submarine_bubble_texture: Texture2D
const FrontEnd = preload("res://front_end.gd")
const CaptureOverlay = preload("res://capture_overlay.gd")
const PlantCurrent = preload("res://plant_current.gd")
const WaterVisuals = preload("res://water_visuals.gd")
const OriginalGameData = preload("res://original_game_data.gd")
var gameplay_catalogue := {}
var water_visuals := WaterVisuals.new()
const NaturalLight = preload("res://natural_light.gd")
var natural_light := NaturalLight.new()
var natural_light_controls := {}
var water_controls := {}
var plant_current := PlantCurrent.new()
var plant_controls := {}
@export var show_start_menu := false
var front_end: Node
var has_started_game := false
var menu_backdrop: Node3D
const DEFAULT_VISIBILITY := 35.0
const MIN_VISIBILITY := 1.0
const MAX_VISIBILITY := 2000.0

var pilot: RigidBody3D
var model: Node3D
var world_root: Node3D
var camera: Camera3D
var loaded_world_assets := ""
var water_environment: Environment
var sun: DirectionalLight3D
var surface_material: ShaderMaterial
var day_night := DayNight.new()
var daylight_controls := {}
var clock_label: Label
var canvas: CanvasLayer
var loading_canvas: CanvasLayer
var loading_label: Label
var developer_menu: PanelContainer
var developer_tabs: TabContainer
var graphics_controls: VBoxContainer
var particle_controls := {}
var particles := WaterParticles.new()
var bubble_controls: VBoxContainer
var controls: VBoxContainer
var status_label: Label
var telemetry: Label
var tuning_panel: PanelContainer
var sound_panel: PanelContainer
var folder_prompt: ConfirmationDialog
var folder_dialog: FileDialog
var export_all_dialog: FileDialog
var export_all_button: Button
var export_all_message: Label
var fog_button: CheckButton
var fog_slider: HSlider
var fog_label: Label
var fog_start_slider: HSlider
var docking_radius_slider: HSlider
var docking_radius_label: Label
var fog_start_label: Label
var fog_curve_slider: HSlider
var fog_curve_label: Label
var game_folder := ""
var world_loading := false
var pilot_mode := false
var startup_complete := false
var developer_ui_visible := false
var camera_follow := FollowCamera.new()
var camera_was_frozen := false
const SUB_RENDER_LAYER := 2
var first_person := false
var cockpit_camera_offset := Vector3(0,0.025,-0.16)
var fog_visibility := DEFAULT_VISIBILITY
var remember_preferences := true
var use_map_overrides := true
var loading_preferences := false
var docking: Node
var docking_prompt: Label
const RadioPortrait = preload("res://radio_portrait.gd")
var docking_portrait: RadioPortrait
var mod_panel: Window
var object_population: Node3D
var wildlife: Node3D
var wildlife_density_slider: HSlider
var wildlife_density_label: Label
var docked_screen: ColorRect
var docked_label: Label
var map_overlay: CanvasLayer
var expanded_map: Control
var map_open := false
var cockpit_hud: CanvasLayer
var equipment: Node3D
var equipment_controls := {}
var hud_enabled: Array[bool] = [true,true,true,true,true]
var hud_scale_slider: HSlider
var hud_scale_label: Label
var hud_map_zoom_slider: HSlider
var hud_map_zoom_label: Label
var map_reveal_slider: HSlider
var map_reveal_label: Label
var crt_reflection_slider: HSlider
var crt_reflection_label: Label

func _ready() -> void:
	preload("res://input_bindings.gd").install()
	add_child(CaptureOverlay.new())
	# Only the physics-driven submarine interpolates; camera and scenery keep
	# their existing render-frame updates.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Mods.ensure(remember_preferences)
	get_window().title = "OpenSubCulture"
	get_window().mode = Window.MODE_FULLSCREEN
	get_window().min_size = Vector2i(1050, 600)
	water_environment = Environment.new()
	water_environment.background_mode = Environment.BG_COLOR
	water_environment.background_color = Color(0.025, 0.24, 0.29)
	water_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	water_environment.ambient_light_color = Color(0.37, 0.57, 0.62)
	water_environment.ambient_light_energy = 0.7
	water_environment.fog_light_color = water_environment.background_color
	water_environment.fog_sun_scatter = 0.05
	var environment := WorldEnvironment.new()
	environment.environment = water_environment
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -32, 0)
	add_child(sun)
	camera = Camera3D.new()
	camera.current = true
	camera.far = 4000.0
	camera.near = 0.03
	add_child(camera)
	particles.camera = camera
	add_child(particles)
	_build_interface()
	_load_preferences("res://view_defaults.cfg")
	_load_preferences()
	_update_water_environment()
	call_deferred("_bootstrap")

func _build_interface() -> void:
	canvas = CanvasLayer.new()
	canvas.layer = 3
	canvas.visible = developer_ui_visible
	add_child(canvas)
	developer_menu = PanelContainer.new()
	developer_menu.minimum_size_changed.connect(func() -> void: _resize_developer_menu.call_deferred())
	canvas.add_child(developer_menu)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	developer_menu.add_child(margin)
	controls = VBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	margin.add_child(controls)
	var heading := HBoxContainer.new()
	controls.add_child(heading)
	var title := Label.new()
	title.text = "Developer menu"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := Button.new()
	close.text = "Close (F1)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_toggle_developer_ui)
	heading.add_child(close)
	developer_tabs = TabContainer.new()
	developer_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls.add_child(developer_tabs)
	var export_row := HBoxContainer.new(); controls.add_child(export_row)
	export_all_button = Button.new(); export_all_button.text = "Export all settings"
	export_all_button.focus_mode = Control.FOCUS_NONE; export_all_button.disabled = true
	export_all_button.pressed.connect(func() -> void: export_all_dialog.popup_centered(Vector2i(850, 600)))
	export_row.add_child(export_all_button)
	export_all_message = Label.new(); export_all_message.text = "Movement, sound and graphics in one file."
	export_all_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	export_all_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_row.add_child(export_all_message)
	export_all_dialog = FileDialog.new()
	export_all_dialog.title = "Export all current settings"
	export_all_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_all_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_all_dialog.filters = PackedStringArray(["*.cfg ; All game settings"])
	export_all_dialog.current_dir = ProjectSettings.globalize_path("res://..")
	export_all_dialog.current_file = "opensubculture_settings.cfg"
	export_all_dialog.file_selected.connect(func(path: String) -> void:
		var result := _export_all_settings(path)
		export_all_message.text = "All settings exported." if result == OK else "Export failed: " + error_string(result)
	)
	add_child(export_all_dialog)
	var graphics_tab := VBoxContainer.new(); graphics_tab.name = "Graphics"
	developer_tabs.add_child(graphics_tab)
	var graphics_scroll := ScrollContainer.new()
	graphics_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graphics_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	graphics_tab.add_child(graphics_scroll)
	graphics_controls = VBoxContainer.new()
	graphics_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics_controls.add_theme_constant_override("separation", 12)
	graphics_scroll.add_child(graphics_controls)
	wildlife_density_label = Label.new(); graphics_controls.add_child(wildlife_density_label)
	wildlife_density_slider = HSlider.new(); wildlife_density_slider.scrollable = false
	wildlife_density_slider.min_value = 0; wildlife_density_slider.max_value = 300
	wildlife_density_slider.step = 5; wildlife_density_slider.value = 100
	wildlife_density_slider.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(wildlife_density_slider)
	wildlife_density_slider.value_changed.connect(func(_value: float) -> void: _update_wildlife_density())
	wildlife_density_slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())
	_update_wildlife_density()
	hud_scale_label = Label.new()
	graphics_controls.add_child(hud_scale_label)
	hud_scale_slider = HSlider.new(); hud_scale_slider.scrollable = false
	hud_scale_slider.min_value = 25.0
	hud_scale_slider.max_value = 150.0
	hud_scale_slider.step = 1.0
	hud_scale_slider.value = 50.0
	hud_scale_slider.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(hud_scale_slider)
	hud_scale_slider.value_changed.connect(func(_value: float) -> void: _update_hud_scale())
	hud_scale_slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())
	_update_hud_scale()
	hud_map_zoom_label = Label.new()
	graphics_controls.add_child(hud_map_zoom_label)
	hud_map_zoom_slider = HSlider.new(); hud_map_zoom_slider.scrollable = false
	hud_map_zoom_slider.min_value = 0.5
	hud_map_zoom_slider.max_value = 4.0
	hud_map_zoom_slider.step = 0.1
	hud_map_zoom_slider.value = 2.0
	hud_map_zoom_slider.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(hud_map_zoom_slider)
	hud_map_zoom_slider.value_changed.connect(func(_value: float) -> void: _update_hud_scale())
	hud_map_zoom_slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())
	crt_reflection_label = Label.new()
	graphics_controls.add_child(crt_reflection_label)
	crt_reflection_slider = HSlider.new(); crt_reflection_slider.scrollable = false
	crt_reflection_slider.min_value = 0.0
	crt_reflection_slider.max_value = 100.0
	crt_reflection_slider.step = 1.0
	crt_reflection_slider.value = 25.0
	crt_reflection_slider.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(crt_reflection_slider)
	crt_reflection_slider.value_changed.connect(func(_value: float) -> void: _update_hud_scale())
	crt_reflection_slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())
	_update_hud_scale()
	map_reveal_label = Label.new()
	graphics_controls.add_child(map_reveal_label)
	map_reveal_slider = HSlider.new(); map_reveal_slider.scrollable = false
	map_reveal_slider.min_value = 2.0
	map_reveal_slider.max_value = 30.0
	map_reveal_slider.step = 0.5
	map_reveal_slider.value = 10.0
	map_reveal_slider.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(map_reveal_slider)
	map_reveal_slider.value_changed.connect(func(_value: float) -> void: _update_hud_scale())
	map_reveal_slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())
	var reset_map := Button.new()
	reset_map.text = "Reset fog of war"
	reset_map.tooltip_text = "Clear discovered areas to test the current reveal radius. Smaller radii keep previous discoveries."
	reset_map.focus_mode = Control.FOCUS_NONE
	reset_map.pressed.connect(func() -> void:
		if cockpit_hud != null: cockpit_hud.map_data.reset_exploration()
	)
	var map_actions := HBoxContainer.new(); graphics_controls.add_child(map_actions)
	reset_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_actions.add_child(reset_map)
	var reveal_map := Button.new(); reveal_map.name = "RevealWholeMap"
	reveal_map.text = "Reveal whole map"; reveal_map.focus_mode = Control.FOCUS_NONE
	reveal_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reveal_map.pressed.connect(func() -> void:
		if cockpit_hud != null: cockpit_hud.map_data.reveal_all()
	)
	map_actions.add_child(reveal_map)
	_update_hud_scale()
	fog_button = CheckButton.new()
	fog_button.text = "Underwater fog"
	fog_button.button_pressed = true
	fog_button.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(fog_button)
	fog_label = Label.new()
	graphics_controls.add_child(fog_label)
	fog_slider = HSlider.new(); fog_slider.scrollable = false
	fog_slider.min_value = MIN_VISIBILITY
	fog_slider.max_value = MAX_VISIBILITY
	fog_slider.step = 0.5
	fog_slider.value = DEFAULT_VISIBILITY
	fog_slider.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(fog_slider)
	var hint := Label.new()
	hint.text = "Spread fade start and view distance apart for a longer, gentler fade."
	hint.add_theme_font_size_override("font_size", 12)
	graphics_controls.add_child(hint)
	fog_slider.value_changed.connect(func(value: float) -> void:
		fog_visibility = value
		_update_water_environment()
	)
	fog_slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())
	fog_button.toggled.connect(func(_enabled: bool) -> void:
		_update_water_environment()
		_save_preferences()
	)
	var presets := HBoxContainer.new()
	graphics_controls.add_child(presets)
	for preset in [["Original feel", DEFAULT_VISIBILITY], ["Clearer water", 100.0]]:
		var button := Button.new()
		button.text = preset[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			fog_slider.value = float(preset[1])
			_save_preferences()
		)
		presets.add_child(button)
	fog_start_label = Label.new(); graphics_controls.add_child(fog_start_label)
	fog_start_slider = HSlider.new(); fog_start_slider.scrollable = false; fog_start_slider.min_value = 0.0; fog_start_slider.max_value = MAX_VISIBILITY - 0.5
	fog_start_slider.step = 0.5; fog_start_slider.value = 5.0; fog_start_slider.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(fog_start_slider)
	fog_curve_label = Label.new(); graphics_controls.add_child(fog_curve_label)
	fog_curve_slider = HSlider.new(); fog_curve_slider.scrollable = false; fog_curve_slider.min_value = 0.25; fog_curve_slider.max_value = 8.0
	fog_curve_slider.step = 0.1; fog_curve_slider.value = 1.8; fog_curve_slider.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(fog_curve_slider)
	for slider in [fog_start_slider, fog_curve_slider]:
		slider.value_changed.connect(func(_value: float) -> void: _update_water_environment())
		slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())
	_build_daylight_controls()
	_build_natural_light_controls()
	_build_particle_controls()
	_build_plant_controls()
	_build_water_controls()
	_build_equipment_controls()
	_build_weapon_controls()
	bubble_controls = VBoxContainer.new()
	graphics_controls.add_child(bubble_controls)
	var graphics_hint := Label.new()
	graphics_hint.text = "Graphics settings save on release. Bubbles save/export with movement settings."
	graphics_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	graphics_controls.add_child(graphics_hint)
	var graphics_save := Button.new()
	graphics_save.text = "Save graphics settings"
	graphics_save.focus_mode = Control.FOCUS_NONE
	graphics_save.pressed.connect(func() -> void:
		_save_preferences()
		if tuning_panel != null: tuning_panel._save()
	)
	graphics_tab.add_child(graphics_save)
	var system := VBoxContainer.new()
	system.name = "System"
	system.add_theme_constant_override("separation", 12)
	developer_tabs.add_child(system)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	system.add_child(status_label)
	telemetry = Label.new()
	system.add_child(telemetry)
	var credits_button := Button.new(); credits_button.name = "GiveTestingCredits"
	credits_button.text = "Give player 100,000 credits"; credits_button.focus_mode = Control.FOCUS_NONE
	credits_button.pressed.connect(func() -> void:
		player_progress.status.credits += 100000
		if dock_interface != null and dock_interface.visible: dock_interface.rebuild()
	)
	system.add_child(credits_button)
	docking_radius_label = Label.new()
	system.add_child(docking_radius_label)
	docking_radius_slider = HSlider.new(); docking_radius_slider.scrollable = false
	docking_radius_slider.min_value = 0.5
	docking_radius_slider.max_value = 10.0
	docking_radius_slider.step = 0.1
	docking_radius_slider.value = Docking.APPROACH_RADIUS
	docking_radius_slider.focus_mode = Control.FOCUS_NONE
	system.add_child(docking_radius_slider)
	docking_radius_slider.value_changed.connect(func(_value: float) -> void: _update_docking_radius())
	docking_radius_slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())
	_update_docking_radius()
	var choose := Button.new()
	choose.text = "Choose Sub Culture folder…"
	choose.focus_mode = Control.FOCUS_NONE
	choose.pressed.connect(func() -> void:
		if not world_loading: folder_dialog.popup_centered(Vector2i(850, 600))
	)
	system.add_child(choose)
	folder_dialog = FileDialog.new()
	folder_dialog.use_native_dialog = true
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.title = "Choose your Sub Culture game folder"
	folder_dialog.dir_selected.connect(_choose_game_folder)
	add_child(folder_dialog)
	folder_prompt = ConfirmationDialog.new()
	folder_prompt.title = "Locate original Sub Culture files"
	folder_prompt.ok_button_text = "Choose folder..."
	folder_prompt.cancel_button_text = "Exit"
	folder_prompt.confirmed.connect(func() -> void: folder_dialog.popup_centered(Vector2i(850,600)))
	folder_prompt.canceled.connect(func() -> void: get_tree().quit())
	folder_dialog.canceled.connect(func() -> void:
		if game_folder.is_empty(): _prompt_game_folder("The original Sub Culture files are required to play. Choose the folder containing CLUMPS and DATA."))
	add_child(folder_prompt)
	mod_panel = ModPanel.new()
	mod_panel.persist_preferences = remember_preferences
	mod_panel.applied.connect(_apply_mods)
	add_child(mod_panel)
	developer_tabs.tab_changed.connect(_developer_tab_changed)
	get_viewport().size_changed.connect(_resize_developer_menu)
	_resize_developer_menu()
	front_end = FrontEnd.new(); add_child(front_end)
	front_end.back_shortcut_busy = func(event: InputEvent) -> bool: return Bindings.pressed(event,"menu_cancel") and (map_open or developer_ui_visible or (dock_interface != null and dock_interface.visible))
	loading_canvas = front_end.loading_layer
	loading_label = front_end.loading_status
	front_end.new_game_requested.connect(_begin_new_game)
	front_end.resume_requested.connect(_resume_game)
	front_end.load_requested.connect(func() -> void: front_end.menu_layer.hide(); dock_interface.open("load"))
	front_end.mods_requested.connect(func() -> void: if not world_loading: mod_panel.open())
	mod_panel.visibility_changed.connect(func() -> void: if not mod_panel.visible: front_end.restore_button_focus("mods"))
	dock_interface = preload("res://dock_interface.gd").new(); add_child(dock_interface)
	dock_interface.action_requested.connect(_dock_ui_action)
	dock_interface.setup(game_folder,_dock_ui_model)
	front_end.toggle_menu_requested.connect(func() -> void:
		if front_end.menu_layer.visible: _resume_game()
		else: _show_main_menu()
	)
	front_end.exit_requested.connect(func() -> void: get_tree().quit())

func _bootstrap() -> void:
	front_end.show_loading()
	canvas.hide()
	# Present the loading screen before importing or searching original data.
	await get_tree().process_frame
	var folder := Paths.find_game_folder()
	if folder.is_empty():
		_prompt_game_folder("OpenSubCulture needs your original Sub Culture files. Choose the game folder containing CLUMPS and DATA.")
	else:
		await _start_game(folder)
		startup_complete = true
		if show_start_menu and pilot_mode: _show_main_menu()

func _prompt_game_folder(message: String) -> void:
	front_end.show_loading()
	front_end.loading_status.text = "Waiting for original Sub Culture files..."
	folder_prompt.dialog_text = message
	folder_prompt.popup_centered(Vector2i(520,180))

func _show_main_menu() -> void:
	_set_map_open(false)
	if world_loading: return
	if weapons != null: weapons.update_fire(false,0)
	if developer_ui_visible: _toggle_developer_ui()
	dock_interface.dismiss()
	front_end.buttons.load.set_meta("available",save_games.slots().any(func(slot: Dictionary) -> bool: return slot.valid))
	front_end.buttons.load.tooltip_text = "" if front_end.is_button_available("load") else "No saved games yet"
	front_end.show_menu(has_started_game and (pilot == null or not pilot.dead))
	if menu_backdrop != null:
		menu_backdrop.open(); _update_daylight()
	get_tree().paused = true

func _choose_game_folder(folder: String) -> void:
	if not Paths.valid_game_folder(folder):
		if game_folder.is_empty(): _prompt_game_folder("That folder does not contain CLUMPS/SUB.DFF and DATA/SCEN1.BSP. Please choose the original Sub Culture game folder.")
		else: status_label.text = "That folder does not contain CLUMPS/SUB.DFF and DATA/SCEN1.BSP."
		return
	await _start_game(folder)
	startup_complete = true
	if show_start_menu and not has_started_game and pilot_mode: _show_main_menu()

func _resume_game() -> void:
	if not has_started_game or world_loading or pilot.dead: return
	front_end.hide_menu()
	if menu_backdrop != null: menu_backdrop.close()
	if dock_interface != null: dock_interface.dismiss()
	get_tree().paused = false
	_update_daylight()
	_update_mouse_pointer()

func _apply_mods() -> void:
	if world_loading: return
	front_end.hide_menu()
	has_started_game = false
	front_end.can_resume = false
	# Loading awaits physics frames, which cannot advance in the paused menu.
	get_tree().paused = false
	_set_camera_mode(false)
	await _start_game(game_folder)
	if pilot_mode: _show_main_menu()

func _begin_new_game() -> void:
	if world_loading: return
	front_end.hide_menu()
	if menu_backdrop != null: menu_backdrop.close()
	if dock_interface != null: dock_interface.dismiss()
	get_tree().paused = false
	if not _can_reuse_world():
		await _start_game(game_folder)
	if not pilot_mode: return
	_reset_loaded_world()
	day_night.hour = 12.0
	player_progress = PlayerProgress.restore()
	_update_daylight()
	has_started_game = true
	front_end.can_resume = true
	cockpit_hud.map_data.reset_exploration()
	_update_mouse_pointer()

func _world_asset_key() -> String:
	return JSON.stringify([game_folder,Mods.layers,Mods.movement])

func _can_reuse_world() -> bool:
	return pilot_mode and is_instance_valid(world_root) and loaded_world_assets == _world_asset_key()

func _reset_loaded_world() -> void:
	if menu_backdrop != null: menu_backdrop.close()
	dock_interface.dismiss(); dock_interface_active = false
	_set_map_open(false)
	docking.cancel()
	docking.nearby = {}; docking.declined_port = null; docking.message = ""
	docking.greeted_ports.clear(); docking.greeting_port = {}; docking.greeting_remaining = 0.0
	if docking_portrait != null: docking_portrait.reset_signal()
	if docked_screen != null: docked_screen.hide()
	weapons.update_fire(false,0); weapons.selected = 0; weapons.elapsed = 0.0
	for particle in weapons.hit_blood.particles: particle.node.free()
	weapons.hit_blood.particles.clear()
	for patch in plant_current.patches:
		patch.bend = Vector3.ZERO
		for material in patch.materials: material.set_shader_parameter("propeller_bend",Vector3.ZERO)
	_clear_session_effects(world_root)
	pilot.restore_health(); pilot.collision_layer = 2
	pilot.collision_mask = 5; pilot.active = true; pilot.controls_enabled = true
	weapons.show()
	pilot.visual.show()
	pilot.reset_at(world_root.get_meta("player_spawn",world_root.get_meta("bounds").get_center()))
	pilot._update_animation(0)
	equipment.vacuum.reset()
	equipment.selected = 0
	for item in equipment.mounted:
		item.enabled = false
		item.mount.transform = item.mount.get_meta("default_mount")
		preload("res://submarine_mounts.gd").apply(item.mount,pilot.visual,item.id)
	weapons.muzzle.transform = weapons.muzzle.get_meta("default_mount")
	preload("res://submarine_mounts.gd").apply(weapons.muzzle,pilot.visual,"zapper")
	equipment.apply_settings()
	if wildlife != null: wildlife.reroll()
	else: _reset_provisional_wildlife()
	object_population.reset_population()
	cockpit_hud.map_data.reset_exploration()
	camera_was_frozen = false
	_set_camera_mode(false)

func _clear_session_effects(node: Node) -> void:
	for child in node.get_children():
		if child is SessionDebris or child is SessionExplosion:
			child.free()
		else: _clear_session_effects(child)

func _start_game(folder: String) -> void:
	if menu_backdrop != null:
		menu_backdrop.close(); menu_backdrop.free(); menu_backdrop = null
	if dock_interface != null: dock_interface.dismiss(); dock_interface_active = false
	_set_map_open(false)
	if map_overlay != null:
		map_overlay.free(); map_overlay = null; expanded_map = null
	if world_loading: return
	if not Paths.valid_game_folder(folder):
		_fail_startup("Could not find CLUMPS/SUB.DFF and DATA/SCEN1.BSP in that folder.")
		return
	world_loading = true
	front_end.load_art(folder)
	front_end.show_loading()
	await get_tree().process_frame
	gameplay_catalogue = OriginalGameData.load_catalogue(folder)
	for warning in gameplay_catalogue.warnings: Mods.note(warning)
	export_all_button.disabled = true
	export_all_dialog.hide()
	pilot_mode = false
	if docking_prompt != null: docking_prompt.hide()
	if docking_portrait != null: docking_portrait.reset_signal()
	if docking != null:
		docking.cancel()
		docking.free()
		docking = null
	if pilot != null: pilot.active = false
	if cockpit_hud != null:
		cockpit_hud.free()
		cockpit_hud = null
	if equipment != null:
		equipment.free()
		equipment = null
	if weapons != null:
		weapons.free(); weapons = null
	loading_canvas.visible = true
	game_folder = folder
	if model != null:
		model.free()
		model = null
	if world_root != null:
		world_root.free()
		world_root = null
	model = Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF"))
	if model == null:
		_fail_startup("The submarine model could not be read.")
		return
	world_root = await World.load_world(folder.path_join("DATA/SCEN1.BSP"), get_tree(), _progress)
	if world_root == null:
		model.free()
		model = null
		_fail_startup("The map could not be read.")
		return
	add_child(world_root)
	await World.add_collision(world_root, get_tree(), _progress)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await Scenery.populate(world_root, folder, get_tree(), _progress)
	var map_data := MapDocument.load_active() if use_map_overrides else {}
	wildlife = null
	if not map_data.is_empty(): MapDocument.apply_entities(world_root, folder, map_data)
	OriginalGameData.apply_city_names(world_root,gameplay_catalogue)
	plant_current.attach(world_root)
	_add_water_surface()
	await get_tree().physics_frame
	await natural_light.build(world_root,_progress)
	if map_data.is_empty():
		await Creatures.populate(world_root, folder, get_tree(), _progress)
		var stats: Dictionary = gameplay_catalogue.tables.creature_stats.records
		var death_frames := preload("res://creature_death.gd").load_gore(folder)
		var death_flesh := Assets._load_texture(folder,"BEEF2","",{})
		for fish in world_root.get_node("AmbientFish").get_children():
			fish.configure_health(float(stats.get(str(fish.get_meta("species","")).to_lower(),{}).get("health",10)))
			fish.death_texture = Assets._load_texture(folder,"BUBBLE","BUBBLEM",{})
			fish.death_sound = Weapons._sound(folder,"audio.creature.death","SPLAT")
			fish.death_frames = death_frames
			fish.death_flesh_texture = death_flesh
	else:
		wildlife = Wildlife.new()
		wildlife.gameplay_catalogue = gameplay_catalogue
		wildlife.name = "AmbientFish"
		world_root.add_child(wildlife)
		wildlife.density = wildlife_density_slider.value / 100.0
		wildlife.view_camera = camera
		wildlife.visibility_range = fog_visibility if fog_button.button_pressed else camera.far
		wildlife.setup(world_root, folder, map_data,true)
	object_population = preload("res://object_population.gd").new()
	object_population.name = "MapObjects"; world_root.add_child(object_population)
	object_population.setup(folder,map_data)
	water_visuals.materials.clear()
	water_visuals.attach(world_root)
	if wildlife != null:
		for template in wildlife.templates.values(): water_visuals.attach(template)
	water_visuals.sync_plants(plant_current)
	natural_light.materials.clear(); natural_light.attach(world_root)
	if wildlife != null:
		for template in wildlife.templates.values(): natural_light.attach(template)
	if pilot == null:
		pilot = Pilot.new()
		pilot.name = "PlayerSubmarine"
		pilot.remember_settings = remember_preferences
		add_child(pilot)
		pilot.health_changed.connect(_submarine_health_changed)
		pilot.destroyed.connect(_submarine_destroyed)
	else: pilot.movement.load_settings(remember_preferences)
	var selected_tab: StringName = developer_tabs.get_current_tab_control().name if tuning_panel != null and developer_tabs.get_current_tab_control() != null else &"Movement"
	for child in bubble_controls.get_children(): child.free()
	if tuning_panel != null: tuning_panel.free()
	tuning_panel = Tuning.new()
	tuning_panel.name = "Movement"
	developer_tabs.add_child(tuning_panel)
	developer_tabs.move_child(tuning_panel, 0)
	tuning_panel.setup(pilot.movement, true, bubble_controls)
	pilot.surface_height = float(world_root.get_meta("surface_height"))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bounds: AABB = world_root.get_meta("bounds")
	var point: Vector3 = world_root.get_meta("player_spawn", bounds.get_center())
	pilot.reset_at(point)
	model.scale *= Pilot.VISUAL_SCALE
	model.rotation.y = PI
	pilot.add_child(model)
	pilot.visual = model
	pilot.fit_collision_to_visual()
	equipment = Equipment.new()
	pilot.add_child(equipment)
	equipment.setup(pilot, folder)
	equipment.vacuum.population = object_population
	# Keep lights and equipment working while excluding the sub geometry
	# from the cockpit camera. Visibility still belongs to docking.
	for node in pilot.find_children("*","MeshInstance3D",true,false): node.layers = SUB_RENDER_LAYER
	weapons = Weapons.new(); pilot.add_child(weapons); weapons.setup(pilot,folder,camera,gameplay_catalogue)
	var weapon_values: Dictionary = weapons.settings.duplicate(); weapon_values.merge(weapon_overrides,true)
	for key in weapon_controls: weapon_controls[key].set_value_no_signal(weapon_values[key])
	_update_weapon_settings()
	var hull_bounds := Equipment._bounds(Equipment._meshes(pilot.visual,Transform3D.IDENTITY,true))
	cockpit_camera_offset = Vector3(hull_bounds.get_center().x,hull_bounds.position.y + hull_bounds.size.y * 0.48,hull_bounds.position.z + hull_bounds.size.z * 0.25)
	_update_equipment_settings()
	natural_light.attach(pilot)
	cockpit_hud = HUD.new()
	add_child(cockpit_hud)
	cockpit_hud.setup(pilot, equipment, world_root, folder,weapons)
	cockpit_hud.setup_lighting(water_environment,sun)
	cockpit_hud.natural_light = natural_light
	_build_expanded_map()
	_update_hud_scale()
	for index in range(5):
		cockpit_hud.set_enabled(index,hud_enabled[index],false)
	pilot.reset_physics_interpolation()
	submarine_bubble_texture = Assets._load_texture(folder,"BUBBLE","BUBBLEM",{})
	pilot.bubbles.configure(submarine_bubble_texture)
	submarine_explosion_frames = SessionExplosion.load_frames(folder)
	submarine_explosion_sound = Weapons._sound(folder,"audio.submarine.explosion","EXPLODE1")
	pilot.submarine_audio.setup(pilot, folder)
	front_end.audio_tuning = pilot.submarine_audio.tuning
	if sound_panel != null: sound_panel.free()
	sound_panel = SoundPanel.new()
	sound_panel.name = "Sound"
	developer_tabs.add_child(sound_panel)
	developer_tabs.move_child(sound_panel, 1)
	sound_panel.setup(pilot.submarine_audio, true)
	_select_developer_tab(str(selected_tab))
	pilot.restore_health(); pilot.collision_layer = 2; pilot.collision_mask = 5
	pilot.active = true
	if docking != null: docking.free()
	docking = Docking.new()
	add_child(docking)
	docking.setup(pilot, world_root, folder, camera,gameplay_catalogue)
	save_games.city_names.clear()
	for port in docking.ports: save_games.city_names[int(port.node.get_meta("city_id"))] = str(port.name)
	_update_docking_radius()
	if wildlife != null: wildlife.player = pilot
	object_population.player = pilot
	docking.docked.connect(_reset_docked_wildlife)
	if docking_prompt == null: _build_docking_prompt()
	dock_interface.setup(folder,_dock_ui_model)
	pilot_mode = true
	world_loading = false
	loaded_world_assets = _world_asset_key()
	export_all_button.disabled = false
	status_label.text = str(world_root.get_meta("scenery_summary", "Piloting ready."))
	_update_follow_camera(0.0, true)
	particles.material.set_shader_parameter("surface_height", pilot.surface_height)
	particles._rebuild()
	_update_water_environment()
	menu_backdrop = preload("res://menu_backdrop.gd").new()
	add_child(menu_backdrop); menu_backdrop.setup(self)
	front_end.progress_bar.value = 95.0
	if show_start_menu and DisplayServer.get_name() != "headless":
		for frame in range(600):
			if cockpit_hud.map_data.scenery_baked: break
			await get_tree().process_frame
	front_end.progress_bar.value = 100.0
	loading_canvas.visible = false
	_save_preferences()

func _progress(message: String) -> void:
	front_end.update_progress(message)

func _build_docking_prompt() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 2
	add_child(hud)
	docked_screen = ColorRect.new()
	docked_screen.color = Color(0.02, 0.055, 0.075, 1.0)
	docked_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	docked_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	docked_screen.visible = false
	hud.add_child(docked_screen)
	docked_label = Label.new()
	docked_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	docked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	docked_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	docked_label.add_theme_font_size_override("font_size", 28)
	docked_screen.add_child(docked_label)
	docking_prompt = Label.new()
	docking_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	docking_prompt.offset_top = -85.0
	docking_prompt.offset_bottom = -25.0
	docking_prompt.offset_left = 20.0
	docking_prompt.offset_right = -140.0
	docking_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	docking_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	docking_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	docking_prompt.add_theme_font_size_override("font_size", 22)
	docking_prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	docking_prompt.add_theme_constant_override("shadow_offset_x", 2)
	docking_prompt.add_theme_constant_override("shadow_offset_y", 2)
	docking_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(docking_prompt)
	docking_portrait = preload("res://radio_portrait.gd").new()
	docking_portrait.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	docking_portrait.offset_left = -116.0
	docking_portrait.offset_right = -20.0
	docking_portrait.offset_top = -150.0
	docking_portrait.offset_bottom = -30.0
	docking_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	docking_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	docking_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	docking_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(docking_portrait)

func _fail_startup(message: String) -> void:
	world_loading = false
	loading_canvas.visible = false
	developer_ui_visible = true
	canvas.visible = true
	status_label.text = message

func _input(event: InputEvent) -> void:
	if Bindings.pressed(event,"map_toggle") and pilot_mode and not world_loading and not get_tree().paused and not developer_ui_visible and docking.stage == Docking.Stage.IDLE:
		_set_map_open(not map_open)
		get_viewport().set_input_as_handled()
	elif map_open and Bindings.pressed(event,"menu_cancel"):
		_set_map_open(false)
		get_viewport().set_input_as_handled()
	elif Bindings.pressed(event,"developer_toggle"):
		_set_map_open(false)
		_toggle_developer_ui()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not pilot_mode or world_loading or map_open or (dock_interface != null and dock_interface.visible): return
	if pilot.dead: return
	if not developer_ui_visible and docking.stage == Docking.Stage.IDLE:
		if Bindings.pressed(event,"camera_toggle"):
			_set_camera_mode(not first_person)
			get_viewport().set_input_as_handled()
			return
	if not developer_ui_visible and cockpit_hud != null:
		for index in range(5):
			if Bindings.pressed(event,"hud_%d" % (index + 1)):
				cockpit_hud.toggle(index)
				hud_enabled[index] = cockpit_hud.enabled[index]
				_save_preferences()
				get_viewport().set_input_as_handled()
				return
	if not developer_ui_visible and equipment != null and docking.stage == Docking.Stage.IDLE:
		if Bindings.pressed(event,"weapon_previous") and weapons != null: weapons.cycle(-1)
		elif Bindings.pressed(event,"weapon_next") and weapons != null: weapons.cycle(1)
		if Bindings.pressed(event,"equipment_previous"): equipment.cycle(-1)
		elif Bindings.pressed(event,"equipment_next"): equipment.cycle(1)
		elif Bindings.pressed(event,"equipment_toggle"):
			if not Bindings.pressed(event,"dock_decline") or docking.nearby.is_empty(): equipment.toggle_selected()
	if Bindings.pressed(event,"dock_accept"):
		_request_docking()
		get_viewport().set_input_as_handled()
	elif Bindings.pressed(event,"dock_decline"):
		docking.decline_docking()
		get_viewport().set_input_as_handled()
	elif Bindings.pressed(event,"menu_cancel") and developer_ui_visible: _toggle_developer_ui()
	elif event is InputEventMouseButton and event.pressed:
		if developer_ui_visible and developer_menu.get_global_rect().has_point(get_viewport().get_mouse_position()): return
		var distance := float(pilot.movement.settings.camera_distance)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: tuning_panel.set_camera_distance(distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: tuning_panel.set_camera_distance(distance * 1.1)

func _build_expanded_map() -> void:
	map_overlay = CanvasLayer.new(); map_overlay.layer = 50; add_child(map_overlay)
	var backdrop := ColorRect.new(); backdrop.color = Color(0.002,0.005,0.015)
	map_overlay.add_child(backdrop); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	expanded_map = preload("res://hud_display.gd").new()
	expanded_map.pilot = pilot; expanded_map.map_data = cockpit_hud.map_data
	expanded_map.screen_only = true; expanded_map.full_world = true
	map_overlay.add_child(expanded_map)
	expanded_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	expanded_map.offset_left = 40; expanded_map.offset_top = 40
	expanded_map.offset_right = -40; expanded_map.offset_bottom = -40
	expanded_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_overlay.hide()

func _set_map_open(open: bool) -> void:
	map_open = open and map_overlay != null
	if map_overlay != null: map_overlay.visible = map_open
	if map_open and pilot != null: pilot.controls_enabled = false
	if map_open and weapons != null: weapons.update_fire(false,0)
	_update_mouse_pointer()

func _toggle_developer_ui() -> void:
	developer_ui_visible = not developer_ui_visible
	canvas.visible = developer_ui_visible
	_update_mouse_pointer()
	if not developer_ui_visible:
		folder_dialog.hide()
		export_all_dialog.hide()
		if tuning_panel != null: tuning_panel.export_dialog.hide()
		if sound_panel != null:
			sound_panel.stop_preview()
			sound_panel.export_dialog.hide()

func _resize_developer_menu() -> void:
	var viewport := get_viewport().get_visible_rect().size
	developer_menu.position = Vector2(maxf(18.0, (viewport.x - 740.0) / 2.0), 18.0)
	developer_menu.size = Vector2(minf(740.0, viewport.x - 36.0), minf(850.0, viewport.y - 36.0))

func _developer_tab_changed(index: int) -> void:
	_resize_developer_menu.call_deferred()
	if sound_panel != null and developer_tabs.get_current_tab_control() != sound_panel: sound_panel.stop_preview()

func _select_developer_tab(tab_name: String) -> void:
	for index in range(developer_tabs.get_tab_count()):
		if developer_tabs.get_tab_title(index) == tab_name:
			developer_tabs.current_tab = index
			break
	for index in range(developer_tabs.get_tab_count()): developer_tabs.get_tab_control(index).visible = index == developer_tabs.current_tab

# Retained for capture/test scripts; F1 is the only menu keyboard shortcut.
func _toggle_tuning() -> void:
	if not pilot_mode: return
	if cockpit_hud != null: cockpit_hud.visible = not world_loading and docking.stage != Docking.Stage.DOCKED
	developer_ui_visible = true
	canvas.visible = true
	_select_developer_tab("Movement")

func _toggle_sound_tuning() -> void:
	if not pilot_mode: return
	developer_ui_visible = true
	canvas.visible = true
	_select_developer_tab("Sound")

func _physics_process(_delta: float) -> void:
	if pilot == null: return
	var pointer := get_viewport().get_mouse_position()
	var over_ui := developer_ui_visible and controls.get_global_rect().has_point(pointer)
	if developer_ui_visible and tuning_panel.visible:
		over_ui = over_ui or tuning_panel.get_global_rect().has_point(pointer)
	if developer_ui_visible and sound_panel != null and sound_panel.visible:
		over_ui = over_ui or sound_panel.get_global_rect().has_point(pointer)
	pilot.controls_enabled = pilot_mode and not pilot.dead and not map_open and not world_loading and not developer_ui_visible and not over_ui and not folder_dialog.visible and not export_all_dialog.visible and not mod_panel.visible and not tuning_panel.export_dialog.visible and (sound_panel == null or not sound_panel.export_dialog.visible) and (docking == null or docking.stage == Docking.Stage.IDLE)

func _process(delta: float) -> void:
	_update_mouse_pointer()
	particles.active = pilot_mode and not world_loading
	if pilot_mode and not world_loading and not developer_ui_visible: day_night.step(delta)
	_update_daylight()
	if not pilot_mode: return
	if not world_loading: plant_current.update_wash(pilot,delta)
	if docked_screen != null:
		docked_screen.visible = docking.stage == Docking.Stage.DOCKED
		if docked_screen.visible and not front_end.menu_layer.visible:
			if not dock_interface_active:
				equipment.vacuum.transfer_to(player_progress.cargo)
				dock_interface.open("home"); dock_interface_active = true
			elif not dock_interface.visible: dock_interface.show()
		elif docking.stage != Docking.Stage.DOCKED and dock_interface_active:
			dock_interface.dismiss(); dock_interface_active = false
	if docking != null and docking.camera_frozen():
		camera.global_position = docking.cinematic_camera
		var target := pilot.get_global_transform_interpolated().origin + Vector3.UP * 0.35
		if camera.global_position.distance_to(target) > 0.01: camera.look_at(target, Vector3.UP)
		camera_was_frozen = true
	else:
		if camera_was_frozen:
			camera_follow.resume(camera.global_position, pilot.get_global_transform_interpolated().origin + Vector3.UP * 0.35)
			camera_was_frozen = false
		_update_follow_camera(delta)
	if docking_prompt != null:
		docking_prompt.text = docking.message
		docking_prompt.visible = not docking.message.is_empty()
		docking_portrait.update_signal(docking.portrait_texture() if docking_prompt.visible else null,docking.distorted_portrait_texture(),docking.radio_static,delta)
	if developer_ui_visible:
		var state: RefCounted = pilot.movement
		telemetry.text = "Speed: %.2f · Vertical: %.2f units/s\nPod tilt: %.1f° · Hull pitch: %.1f°\nDocking limit: %.2f units/s" % [state.velocity.length(), state.velocity.y, rad_to_deg(state.tilt), rad_to_deg(asin(clampf(-pilot.global_basis.z.y, -1.0, 1.0))), docking.maximum_docking_speed()]

func _update_follow_camera(delta: float, snap: bool = false) -> void:
	var pose := pilot.global_transform if snap else pilot.get_global_transform_interpolated()
	if first_person:
		camera.global_transform = pose * Transform3D(Basis.IDENTITY,cockpit_camera_offset)
		return
	var target := pose.origin + Vector3.UP * 0.35
	var forward := -pose.basis.z
	var heading := atan2(-forward.x, -forward.z)
	var desired := camera_follow.desired_position(target, heading, pilot.velocity, forward,
		float(pilot.movement.settings.forward_speed), float(pilot.movement.settings.camera_distance), delta, snap)
	var next := desired if snap else camera.global_position.lerp(desired, 1.0 - exp(-7.0 * delta))
	var query := PhysicsRayQueryParameters3D.create(target, next, 5)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): next = hit.position - (next - target).normalized() * 0.4
	next.y = minf(next.y, pilot.surface_height - 0.2)
	camera.global_position = next
	if next.distance_to(target) > 0.01: camera.look_at(target, Vector3.UP)

func _set_camera_mode(cockpit: bool) -> void:
	if pilot.dead: cockpit = false
	first_person = cockpit
	if cockpit: camera.cull_mask &= ~SUB_RENDER_LAYER
	else: camera.cull_mask |= SUB_RENDER_LAYER
	_update_follow_camera(0.0,true)

func _request_docking() -> void:
	if pilot.dead: return
	var launching: bool = docking.stage == Docking.Stage.DOCKED
	if docking.request_docking():
		if first_person:
			_set_camera_mode(false)
			if not launching: docking.cinematic_camera = camera.global_position
		if launching: camera.global_position = docking.cinematic_camera

func _update_water_environment() -> void:
	camera.far = fog_visibility if fog_button.button_pressed else 4000.0
	if menu_backdrop != null: menu_backdrop.view.far = camera.far
	if wildlife != null: wildlife.visibility_range = fog_visibility if fog_button.button_pressed else camera.far
	water_environment.fog_enabled = fog_button.button_pressed
	water_environment.fog_mode = Environment.FOG_MODE_DEPTH
	water_environment.fog_density = 1.0
	if fog_start_slider != null:
		fog_start_slider.max_value = fog_visibility - 0.5
		water_environment.fog_depth_begin = fog_start_slider.value
		water_environment.fog_depth_curve = fog_curve_slider.value
		fog_start_label.text = "Fade start distance: %.1f units" % fog_start_slider.value
		fog_curve_label.text = "Fog build-up curve: %.1f" % fog_curve_slider.value
	water_environment.fog_depth_end = fog_visibility
	water_environment.fog_sun_scatter = 0.0
	fog_label.text = "Absolute view distance: %.1f units" % fog_visibility
	_update_daylight()

func _build_daylight_controls() -> void:
	var run := CheckButton.new(); run.text = "Run day/night cycle"
	run.button_pressed = true; run.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(run); daylight_controls.cycle_enabled = run
	run.toggled.connect(func(on: bool) -> void: day_night.enabled = on; _save_preferences())
	clock_label = Label.new(); graphics_controls.add_child(clock_label)
	for row in [["time_of_day", "Time of day", 0.0, 24.0, 0.1], ["cycle_minutes", "Full cycle length (minutes)", 1.0, 60.0, 1.0], ["night_brightness", "Night brightness", 0.02, 0.5, 0.01]]:
		var key: String = row[0]; var caption: String = row[1]
		var label := Label.new(); graphics_controls.add_child(label)
		var slider := HSlider.new(); slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]
		slider.value = float(DayNight.DEFAULTS[key]); slider.focus_mode = Control.FOCUS_NONE
		graphics_controls.add_child(slider); daylight_controls[key] = slider
		label.text = caption if key == "time_of_day" else "%s: %.2f" % [caption, slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			if key == "time_of_day": day_night.hour = fposmod(value, 24.0)
			elif key == "cycle_minutes": day_night.cycle_minutes = value
			else: day_night.night_brightness = value
			label.text = caption if key == "time_of_day" else "%s: %.2f" % [caption, value]
			_update_daylight()
		)
		slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())
	var presets := HBoxContainer.new(); graphics_controls.add_child(presets)
	for preset in [["Day", 12.0], ["Sunset", 18.0], ["Night", 0.0], ["Sunrise", 6.0]]:
		var button := Button.new(); button.text = preset[0]; button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: daylight_controls.time_of_day.value = preset[1]; _save_preferences())
		presets.add_child(button)
	var hint := Label.new(); hint.text = "Pause the cycle to hold a time. F1 pauses it while you adjust settings."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; graphics_controls.add_child(hint)

func _build_natural_light_controls() -> void:
	for row in [["sun_depth","Sunlight fade begins at depth",0.0,100.0,0.5],["sun_falloff","Sunlight falloff distance",0.5,100.0,0.5],["cave_ambient","Cave ambient light",0.0,0.5,0.005]]:
		var key: String = row[0]; var caption: String = row[1]
		var label := Label.new(); graphics_controls.add_child(label)
		var slider := HSlider.new(); slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]; slider.value = NaturalLight.DEFAULTS[key]; slider.focus_mode = Control.FOCUS_NONE
		graphics_controls.add_child(slider); natural_light_controls[key] = slider
		label.text = "%s: %.1f%%" % [caption,slider.value * 100] if key == "cave_ambient" else "%s: %.1f units" % [caption,slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			natural_light.configure({key:value}); label.text = "%s: %.1f%%" % [caption,value * 100] if key == "cave_ambient" else "%s: %.1f units" % [caption,value]; _update_daylight())
		slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())

func _update_daylight() -> void:
	var lighting_cycle: RefCounted = menu_backdrop.daylight if menu_backdrop != null and menu_backdrop.active else day_night
	lighting_cycle.apply(water_environment, sun, surface_material)
	# Materials already own distance fog. Engine sky fog would recolour the
	# sheltered background blue even after its cave exposure was applied.
	water_environment.fog_sky_affect = 0.0
	if fog_slider != null:
		natural_light.lighting(water_environment,fog_visibility,fog_start_slider.value,fog_curve_slider.value)
	var lighting_camera: Camera3D = menu_backdrop.view if menu_backdrop != null and menu_backdrop.active else camera
	if is_instance_valid(lighting_camera) and natural_light.image != null:
		var exposure := natural_light.visibility(lighting_camera.global_position,true)
		# Empty space behind cave geometry must match sheltered water, while
		# the actual surface keeps its daylight material through cave exits.
		water_environment.background_color = water_environment.background_color * exposure + Color(0.75,0.8,0.88) * float(natural_light.settings.cave_ambient) * (1.0 - exposure)
	water_visuals.lighting(float(world_root.get_meta("surface_height")) if is_instance_valid(world_root) and world_root.has_meta("surface_height") else 0.0,lighting_cycle.sun_direction())
	if fog_slider != null: water_visuals.fog(fog_visibility if fog_button.button_pressed else 1000000.0,fog_start_slider.value,fog_curve_slider.value)
	if clock_label != null:
		var minutes := int(day_night.hour * 60.0) % 1440
		clock_label.text = "World time: %02d:%02d" % [minutes / 60, minutes % 60]
		daylight_controls.time_of_day.set_value_no_signal(day_night.hour)

func _update_hud_scale() -> void:
	hud_scale_label.text = "HUD size: %.0f%%" % hud_scale_slider.value
	if cockpit_hud != null: cockpit_hud.scale_multiplier = hud_scale_slider.value / 100.0
	if crt_reflection_slider != null:
		crt_reflection_label.text = "CRT reflection strength: %.0f%%" % crt_reflection_slider.value
		if cockpit_hud != null: cockpit_hud.crt_reflection_strength = crt_reflection_slider.value / 100.0
	if hud_map_zoom_slider != null:
		hud_map_zoom_label.text = "Minimap zoom: %.1f×" % hud_map_zoom_slider.value
		if cockpit_hud != null: cockpit_hud.map_zoom = hud_map_zoom_slider.value
	if map_reveal_slider != null:
		map_reveal_label.text = "Minimap reveal radius: %.1f units" % map_reveal_slider.value
		if cockpit_hud != null: cockpit_hud.map_data.reveal_radius = map_reveal_slider.value

func _build_equipment_controls() -> void:
	var hint := Label.new()
	hint.text = "Deep-Sea Lights · D-pad left/right: select · B: toggle\nKeyboard: [ / ] select · L toggle · 1–5 hide/show HUD instruments\nV / controller Y: switch cockpit view"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	graphics_controls.add_child(hint)
	for row in [["light_energy", "Light brightness", 0.1, 12.0, 0.1], ["light_range", "Light range", 2.0, 60.0, 1.0], ["light_angle", "Light beam angle", 5.0, 75.0, 1.0], ["light_down_angle", "Light downward angle", 0.0, 80.0, 1.0]]:
		var key: String = row[0]
		var caption: String = row[1]
		var label := Label.new()
		graphics_controls.add_child(label)
		var slider := HSlider.new()
		slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]
		slider.value = Equipment.DEFAULTS[key]; slider.focus_mode = Control.FOCUS_NONE
		equipment_controls[key] = slider
		graphics_controls.add_child(slider)
		label.text = "%s: %.1f" % [caption, slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			label.text = "%s: %.1f" % [caption, value]
			_update_equipment_settings()
		)
		slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())

func _update_equipment_settings() -> void:
	if equipment == null: return
	for key in equipment_controls: equipment.settings[key] = equipment_controls[key].value
	equipment.apply_settings()

func _build_weapon_controls() -> void:
	var scroll := ScrollContainer.new(); scroll.name = "Weapons"; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; developer_tabs.add_child(scroll)
	var tab := VBoxContainer.new(); tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(tab)
	var hint := Label.new(); hint.text = "Zapper · Hold controller X / Space to fire\nD-pad up/down selects mounted weapons. Unlimited firing."; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tab.add_child(hint)
	for row in [["auto_aim_cone","Auto aim cone (degrees, full width; 0 = off)",0.0,120.0,1.0],["range","Zapper range",0.5,15.0,0.25],["damage_per_second","Zapper damage per second",0.0,50.0,0.5],["beam_width","Beam width",0.02,0.6,0.01],["animation_speed","Lightning animation speed",1.0,40.0,1.0],["volume_db","Zapper volume (dB)",-60.0,0.0,1.0],["gore_amount","Gore particles per death",0.0,100.0,1.0],["gore_settle_speed","Gore settling speed",0.1,5.0,0.1],["gore_lifetime","Gore lifetime (seconds)",0.2,10.0,0.1],["chunk_lifetime","Chunk lifetime before fading (seconds)",2.0,300.0,1.0]]:
		var key: String = row[0]; var caption: String = row[1]
		var label := Label.new(); tab.add_child(label)
		var slider := HSlider.new(); slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]; slider.value = Weapons.DEFAULTS[key]; slider.focus_mode = Control.FOCUS_NONE; tab.add_child(slider); weapon_controls[key] = slider
		label.text = "%s: %.2f" % [caption,slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			label.text = "%s: %.2f" % [caption,value]; weapon_overrides[key] = value; _update_weapon_settings())
		slider.set_meta("caption",caption); slider.set_meta("label",label)
		slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())

func _update_weapon_settings() -> void:
	if weapons == null: return
	var values := {}
	for key in weapon_controls: values[key] = weapon_controls[key].value
	weapons.configure(values)
	for key in weapon_controls: weapon_controls[key].get_meta("label").text = "%s: %.2f" % [weapon_controls[key].get_meta("caption"),weapon_controls[key].value]

func _build_particle_controls() -> void:
	var enabled := CheckButton.new(); enabled.text = "Floating water particles"
	enabled.button_pressed = true; enabled.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(enabled); particle_controls.enabled = enabled
	enabled.toggled.connect(func(on: bool) -> void:
		particles.configure({"enabled": on}); _save_preferences()
	)
	for row in [["count", "Particle count", 0.0, 4000.0, 50.0], ["size", "Particle size", 0.005, 0.08, 0.005], ["drift", "Particle drift speed", 0.0, 0.3, 0.01], ["radius", "Particle viewing radius", 3.0, 30.0, 0.5], ["visibility", "Particle brightness", 0.0, 1.0, 0.05]]:
		var key: String = row[0]
		var caption: String = row[1]
		var label := Label.new(); graphics_controls.add_child(label)
		var slider := HSlider.new(); slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]
		slider.value = float(WaterParticles.DEFAULTS[key]); slider.focus_mode = Control.FOCUS_NONE
		graphics_controls.add_child(slider); particle_controls[key] = slider
		label.text = "%s: %.3f" % [caption, slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			label.text = "%s: %.3f" % [caption, value]
			particles.configure({key: value})
		)
		slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())
	particles.configure({})

func _build_plant_controls() -> void:
	var enabled := CheckButton.new(); enabled.text = "Plants sway in current"
	enabled.button_pressed = true; enabled.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(enabled); plant_controls.enabled = enabled
	enabled.toggled.connect(func(on: bool) -> void: plant_current.configure({"enabled":on}); _save_preferences())
	for row in [["strength","Plant sway strength",0.0,0.5,0.01],["speed","Plant sway speed",0.0,2.0,0.05],["direction","Plant current direction (degrees)",0.0,360.0,5.0],["variation","Plant sway variation",0.0,1.0,0.05],["wavelength","Plant wave length (plant heights)",0.4,4.0,0.1],["ripple","Plant ripple strength",0.0,1.0,0.01],["twist","Plant twist strength",0.0,2.0,0.05],["wash_strength","Propeller wash strength",0.0,1.5,0.05],["wash_range","Propeller wash range",0.5,12.0,0.25],["wash_recovery","Plant wash recovery (seconds)",0.1,4.0,0.1]]:
		var key: String = row[0]; var caption: String = row[1]
		var label := Label.new(); graphics_controls.add_child(label)
		var slider := HSlider.new(); slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]
		slider.value = PlantCurrent.DEFAULTS[key]; slider.focus_mode = Control.FOCUS_NONE
		graphics_controls.add_child(slider); plant_controls[key] = slider
		label.text = "%s: %.2f" % [caption,slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			label.text = "%s: %.2f" % [caption,value]; plant_current.configure({key:value})
		)
		slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())

func _build_water_controls() -> void:
	for row in [["caustics_strength","Sun caustics strength",0.0,2.0,0.05],["caustics_size","Caustics pattern size",0.5,8.0,0.25],["caustics_speed","Caustics animation speed",0.0,2.0,0.05],["caustics_depth","Caustics depth reach",2.0,80.0,1.0],["wave_height","Surface wave height",0.0,0.15,0.005],["wave_size","Surface wave size",1.0,12.0,0.25],["wave_speed","Surface wave speed",0.0,3.0,0.05],["wave_direction","Wave direction (degrees)",0.0,360.0,5.0],["surface_shine","Water surface shine",0.0,2.0,0.05]]:
		var key: String = row[0]; var caption: String = row[1]
		var label := Label.new(); graphics_controls.add_child(label)
		var slider := HSlider.new(); slider.min_value = row[2]; slider.max_value = row[3]; slider.step = row[4]; slider.value = WaterVisuals.DEFAULTS[key]; slider.focus_mode = Control.FOCUS_NONE
		graphics_controls.add_child(slider); water_controls[key] = slider
		label.text = "%s: %.3f" % [caption,slider.value]
		slider.value_changed.connect(func(value: float) -> void:
			label.text = "%s: %.3f" % [caption,value]; water_visuals.configure({key:value})
		)
		slider.drag_ended.connect(func(_changed: bool) -> void: _save_preferences())

func _desired_mouse_mode() -> int:
	var menus := map_open or developer_ui_visible or (folder_dialog != null and folder_dialog.visible) or (mod_panel != null and mod_panel.visible)
	menus = menus or (front_end != null and front_end.menu_layer.visible)
	menus = menus or (export_all_dialog != null and export_all_dialog.visible)
	menus = menus or (tuning_panel != null and tuning_panel.export_dialog.visible) or (sound_panel != null and sound_panel.export_dialog.visible)
	var docked: bool = docking != null and docking.stage == Docking.Stage.DOCKED
	return Input.MOUSE_MODE_HIDDEN if pilot_mode and not world_loading and not menus and not docked else Input.MOUSE_MODE_VISIBLE

func _update_mouse_pointer() -> void:
	var mode := _desired_mouse_mode()
	if Input.mouse_mode != mode: Input.mouse_mode = mode

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _reset_docked_wildlife() -> void:
	# Cover the world before changing populations, after the doors finish closing.
	if docked_screen != null: docked_screen.visible = true
	if wildlife != null:
		wildlife.reroll()
	else:
		# Until a map is authored, reroll the provisional population as well.
		_reset_provisional_wildlife()

func _reset_provisional_wildlife() -> void:
	world_root.set_meta("wildlife_generation", int(world_root.get_meta("wildlife_generation", 0)) + 1)
	var population := world_root.get_node_or_null("AmbientFish")
	if population == null: return
	var random := RandomNumberGenerator.new()
	random.seed = 8675309 + int(world_root.get_meta("wildlife_generation")) * 104729
	for fish in population.get_children():
		fish.health = fish.max_health
		if fish.dead:
			fish.dead = false; fish.health = fish.max_health; fish.visible = true; fish.collision_layer = 8; fish.collision_mask = 5
			fish.get_child(0).set_deferred("disabled",false); fish.set_physics_process(true); fish.set_process(true)
		for attempt in range(24):
			var point: Vector3 = fish.home + Vector3(random.randf_range(-3, 3), random.randf_range(-0.5, 0.5), random.randf_range(-3, 3))
			if point.y + fish.radius >= pilot.surface_height or not Creatures._clear(world_root, point, fish.radius): continue
			fish.position = point
			fish.rng.seed = random.randi()
			fish._choose_goal()
			fish.reset_physics_interpolation()
			break

func _update_docking_radius() -> void:
	docking_radius_label.text = "Docking prompt radius: %.1f units" % docking_radius_slider.value
	if docking != null:
		docking.approach_radius = docking_radius_slider.value
		docking.update_approach()

func _update_wildlife_density() -> void:
	wildlife_density_label.text = "Wildlife density: %.0f%%" % wildlife_density_slider.value
	if wildlife != null: wildlife.set_density(wildlife_density_slider.value / 100.0)

func _load_preferences(path: String = "user://opensubculture.cfg") -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	loading_preferences = true
	var wildlife_density: Variant = config.get_value("view","wildlife_density",wildlife_density_slider.value / 100.0)
	if (wildlife_density is float or wildlife_density is int) and is_finite(float(wildlife_density)):
		wildlife_density_slider.value = clampf(float(wildlife_density) * 100.0,0.0,300.0)
	var hud_scale: Variant = config.get_value("view", "hud_scale", hud_scale_slider.value / 100.0)
	if (hud_scale is float or hud_scale is int) and is_finite(float(hud_scale)):
		hud_scale_slider.value = clampf(float(hud_scale) * 100.0, hud_scale_slider.min_value, hud_scale_slider.max_value)
	var map_zoom: Variant = config.get_value("view","hud_map_zoom",hud_map_zoom_slider.value)
	if (map_zoom is float or map_zoom is int) and is_finite(float(map_zoom)):
		hud_map_zoom_slider.value = clampf(float(map_zoom),hud_map_zoom_slider.min_value,hud_map_zoom_slider.max_value)
	var reveal_radius: Variant = config.get_value("view","map_reveal_radius",map_reveal_slider.value)
	if (reveal_radius is float or reveal_radius is int) and is_finite(float(reveal_radius)):
		map_reveal_slider.value = clampf(float(reveal_radius),map_reveal_slider.min_value,map_reveal_slider.max_value)
	var reflection: Variant = config.get_value("view","crt_reflection_strength",crt_reflection_slider.value / 100.0)
	if (reflection is float or reflection is int) and is_finite(float(reflection)):
		crt_reflection_slider.value = clampf(float(reflection) * 100.0,0.0,100.0)
	var value: Variant = config.get_value("view", "fog_visibility", fog_slider.value)
	if (value is float or value is int) and is_finite(float(value)):
		fog_slider.value = clampf(float(value), MIN_VISIBILITY, MAX_VISIBILITY)
	var enabled: Variant = config.get_value("view", "fog_enabled", fog_button.button_pressed)
	if enabled is bool: fog_button.button_pressed = enabled
	for row in [["fog_start", fog_start_slider, 5.0], ["fog_curve", fog_curve_slider, 1.8], ["docking_radius", docking_radius_slider, Docking.APPROACH_RADIUS]]:
		var setting: Variant = config.get_value("view", row[0], row[1].value)
		if (setting is float or setting is int) and is_finite(float(setting)):
			row[1].value = clampf(float(setting), row[1].min_value, row[1].max_value)
	for key in daylight_controls:
		var fallback: Variant = daylight_controls[key].button_pressed if key == "cycle_enabled" else daylight_controls[key].value
		var setting: Variant = config.get_value("view", key, fallback)
		if key == "cycle_enabled":
			if setting is bool: daylight_controls[key].button_pressed = setting
		elif (setting is float or setting is int) and is_finite(float(setting)):
			daylight_controls[key].value = clampf(float(setting), daylight_controls[key].min_value, daylight_controls[key].max_value)
	for key in natural_light_controls:
		var setting: Variant = config.get_value("view",key,natural_light_controls[key].value)
		if (setting is int or setting is float) and is_finite(float(setting)): natural_light_controls[key].value = clampf(float(setting),natural_light_controls[key].min_value,natural_light_controls[key].max_value)
	for key in particle_controls:
		var fallback: Variant = particle_controls[key].button_pressed if key == "enabled" else particle_controls[key].value
		var setting: Variant = config.get_value("view", "particles_" + str(key), fallback)
		if key == "enabled":
			if setting is bool: particle_controls[key].button_pressed = setting
		elif (setting is float or setting is int) and is_finite(float(setting)):
			particle_controls[key].value = clampf(float(setting), particle_controls[key].min_value, particle_controls[key].max_value)
	for key in plant_controls:
		var fallback: Variant = plant_controls[key].button_pressed if key == "enabled" else plant_controls[key].value
		var setting: Variant = config.get_value("view","plants_" + str(key),fallback)
		if key == "enabled":
			if setting is bool: plant_controls[key].button_pressed = setting
		elif (setting is float or setting is int) and is_finite(float(setting)):
			plant_controls[key].value = clampf(float(setting),plant_controls[key].min_value,plant_controls[key].max_value)
	for key in water_controls:
		var setting: Variant = config.get_value("view",key,water_controls[key].value)
		if (setting is float or setting is int) and is_finite(float(setting)):
			water_controls[key].value = clampf(float(setting),water_controls[key].min_value,water_controls[key].max_value)
	for key in weapon_controls:
		if not config.has_section_key("view","zapper_" + str(key)): continue
		var setting: Variant = config.get_value("view","zapper_" + str(key))
		if (setting is float or setting is int) and is_finite(float(setting)):
			weapon_overrides[key] = clampf(float(setting),weapon_controls[key].min_value,weapon_controls[key].max_value)
			weapon_controls[key].value = weapon_overrides[key]
	_update_weapon_settings()
	loading_preferences = false
	for key in equipment_controls:
		var setting: Variant = config.get_value("view", key, equipment_controls[key].value)
		if (setting is float or setting is int) and is_finite(float(setting)):
			equipment_controls[key].value = clampf(float(setting), equipment_controls[key].min_value, equipment_controls[key].max_value)
	for index in range(5):
		var setting: Variant = config.get_value("view", "hud_" + str(HUD.DEFINITIONS[index].id), hud_enabled[index])
		if setting is bool:
			hud_enabled[index] = setting
			if cockpit_hud != null:
				cockpit_hud.set_enabled(index,setting,false)

func _save_preferences(path: String = "user://opensubculture.cfg") -> void:
	if not remember_preferences or loading_preferences: return
	var config := ConfigFile.new()
	config.load(path)
	if not game_folder.is_empty(): config.set_value("game", "folder", game_folder)
	var view := _view_settings()
	for key in view: config.set_value("view", key, view[key])
	if config.save(path) != OK: status_label.text = "Visibility settings could not be saved."

func _view_settings() -> Dictionary:
	var settings := {"fog_visibility": fog_visibility, "fog_enabled": fog_button.button_pressed, "fog_start": fog_start_slider.value, "fog_curve": fog_curve_slider.value}
	settings.merge(day_night.settings())
	settings.merge(natural_light.settings)
	settings["wildlife_density"] = wildlife_density_slider.value / 100.0
	settings["docking_radius"] = docking_radius_slider.value
	settings["hud_scale"] = hud_scale_slider.value / 100.0
	settings["hud_map_zoom"] = hud_map_zoom_slider.value
	settings["map_reveal_radius"] = map_reveal_slider.value
	settings["crt_reflection_strength"] = crt_reflection_slider.value / 100.0
	for key in equipment_controls: settings[key] = equipment_controls[key].value
	for key in weapon_controls: settings["zapper_" + str(key)] = weapon_controls[key].value
	for index in range(5): settings["hud_" + str(HUD.DEFINITIONS[index].id)] = hud_enabled[index]
	for key in particle_controls:
		settings["particles_" + str(key)] = particle_controls[key].button_pressed if key == "enabled" else particle_controls[key].value
	for key in plant_controls:
		settings["plants_" + str(key)] = plant_controls[key].button_pressed if key == "enabled" else plant_controls[key].value
	for key in water_controls: settings[key] = water_controls[key].value
	return settings

func _export_all_settings(path: String) -> Error:
	if pilot == null or world_loading or pilot.submarine_audio == null: return ERR_UNAVAILABLE
	var config := ConfigFile.new()
	config.set_value("export", "schema_version", 1)
	config.set_value("movement", "physics_version", 2)
	for key in pilot.movement.settings: config.set_value("movement", key, pilot.movement.settings[key])
	for key in pilot.submarine_audio.tuning.settings: config.set_value("sound", key, pilot.submarine_audio.tuning.settings[key])
	var view := _view_settings()
	for key in view: config.set_value("view", key, view[key])
	return config.save(path)

func _add_water_surface() -> void:
	var bounds: AABB = world_root.get_meta("bounds")
	var surface := MeshInstance3D.new()
	surface.name = "WaterSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(bounds.size.x + 40.0, bounds.size.z + 40.0)
	plane.subdivide_width = clampi(ceili(plane.size.x / 2.0),32,256)
	plane.subdivide_depth = clampi(ceili(plane.size.y / 2.0),32,256)
	surface.mesh = plane
	# Sunlight passes through the water; the visual surface must not shadow
	# the entire underwater world like an opaque roof.
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.position = Vector3(bounds.get_center().x, float(world_root.get_meta("surface_height")), bounds.get_center().z)
	var material := ShaderMaterial.new()
	material.shader = preload("res://water_surface.gdshader")
	surface_material = material
	water_visuals.surface = material
	water_visuals.configure({})
	surface.extra_cull_margin = 0.2
	_update_daylight()
	surface.material_override = material
	world_root.add_child(surface)

func _map_signature() -> String:
	# Editable placements and type stats are not map identity. The underlying
	# terrain remains the same when objects, wildlife or spawn points change.
	return "terrain-v1:" + FileAccess.get_sha256(game_folder.path_join("DATA/SCEN1.BSP"))

func _exploration_matches_map(signature: String) -> bool:
	# This only controls restoration of map exploration, never save validity.
	return signature == _map_signature()

# UI reads a view of game state and submits named actions; layouts never
# mutate docking, inventory or save data directly.
func _dock_ui_model() -> Dictionary:
	var port: Dictionary = docking.current if docking != null else {}
	var items: Array = []
	for item in equipment.mounted if equipment != null else []: items.append(item.name)
	var arms: Array = []
	for item in weapons.mounted if weapons != null else []: arms.append(item.name)
	var shop: Array = []
	for item in gameplay_catalogue.get("tables",{}).get("equipment",{}).get("records",{}).values():
		if item is Dictionary: shop.append(str(item.get("name",item.get("Name",item.get("id","Equipment")))))
	var goods: Array = gameplay_catalogue.get("tables",{}).get("economy_commodities",{}).get("records",{}).keys()
	goods.clear()
	for item in gameplay_catalogue.get("tables",{}).get("economy_commodities",{}).get("records",{}).values():
		var name := str(item.get("name",""))
		if not name.is_empty() and not goods.has(name): goods.append(name)
	var city_id := str(int(port.node.get_meta("city_id"))) if port.get("node") != null else ""
	var city: Dictionary = gameplay_catalogue.get("tables",{}).get("city_info",{}).get("records",{}).get(city_id,{})
	var standing: String = player_progress.standing.get(str(port.get("race",1)),"neutral")
	var description_id := "%s%d.%s" % [city.get("description_key",""),player_progress.campaign_stage,standing]
	var description: String = gameplay_catalogue.get("tables",{}).get("city_descriptions",{}).get("records",{}).get(description_id,{}).get("text","")
	return {"city":port.get("name","Dock"),"city_id":city_id,"title_bitmap":city.get("title_bitmap",""),"welcome":description,"standing":{"bad":"Hostile","neutral":"Neutral","good":"Friendly"}.get(standing,"Neutral"),"mission":player_progress.mission,"status":player_progress.status.duplicate(),"race":port.get("race",1),"equipment":items,"weapons":arms,"shop_items":shop,"repair_offer":preload("res://equipment_shop.gd").shield_repair(gameplay_catalogue,city_id,player_progress.campaign_stage),"hold":player_progress.hold.duplicate(),"commodities":goods,"cargo":player_progress.cargo.duplicate(),"slots":save_games.slots(),"submarine":pilot.visual if pilot != null else null}

func _save_snapshot(name: String) -> Dictionary:
	player_progress.suckomat = equipment.vacuum.storage.duplicate()
	var items: Array = []
	for item in equipment.mounted: items.append({"id":item.id,"enabled":item.enabled})
	var arms: Array = []
	for item in weapons.mounted: arms.append(item.id)
	var explored := cockpit_hud.map_data.explored.duplicate() as Image
	explored.convert(Image.FORMAT_L8)
	return {"version":save_games.VERSION,"name":name.left(64),"saved_at":Time.get_datetime_string_from_system(),"dock":{"id":int(docking.current.node.get_meta("city_id")),"name":docking.current.name},"pose":MapDocument.encode(pilot.global_transform),"hour":day_night.hour,"equipment":items,"weapons":arms,"equipment_selected":equipment.current().get("id",""),"weapon_selected":weapons.current().get("id",""),"explored":Marshalls.raw_to_base64(explored.get_data()),"map_signature":_map_signature(),"mods":Mods.active_ids(),"progress":player_progress.duplicate(true),"objects":object_population.snapshot()}

func _dock_ui_action(action: String, payload: Dictionary) -> void:
	match action:
		"buy_repair","use_repair","sell_repair":
			if docking.stage != Docking.Stage.DOCKED: return
			var offer: Dictionary = _dock_ui_model().repair_offer
			if action == "buy_repair": dock_interface.report(preload("res://equipment_shop.gd").buy(player_progress,offer))
			elif action == "use_repair": dock_interface.report(preload("res://equipment_shop.gd").consume_repair(player_progress,pilot))
			elif int(player_progress.hold.get("shield",0)) > 0 and int(offer.sell_price) > 0:
				player_progress.hold.shield -= 1
				if player_progress.hold.shield == 0: player_progress.hold.erase("shield")
				player_progress.status.credits += int(offer.sell_price)
				dock_interface.report("Shield Repair sold.")
		"launch":
			if docking.stage == Docking.Stage.DOCKED:
				dock_interface.dismiss(); dock_interface_active = false; _request_docking()
		"close": dock_interface.dismiss(); front_end.show_menu(has_started_game)
		"save_slot":
			if docking.stage != Docking.Stage.DOCKED: dock_interface.report("Save games are available while docked."); return
			var result := save_games.write(int(payload.slot),_save_snapshot(str(payload.name)))
			dock_interface.report("Game saved." if result == OK else save_games.error)
		"load_slot": _load_saved_game(int(payload.slot))

func _load_saved_game(slot: int) -> bool:
	if loading_save or world_loading: return false
	var data := save_games.read(slot)
	if data.is_empty(): dock_interface.report(save_games.error); return false
	var port_exists: bool = docking.ports.any(func(port: Dictionary) -> bool: return int(port.node.get_meta("city_id")) == int(data.dock.id))
	if not port_exists: dock_interface.report("The saved dock is not present in this map."); return false
	for item in data.equipment:
		if not equipment.mounted.any(func(mounted: Dictionary) -> bool: return mounted.id == item.id): dock_interface.report("Required equipment is unavailable: " + item.id); return false
	for id in data.weapons:
		if not weapons.mounted.any(func(mounted: Dictionary) -> bool: return mounted.id == id): dock_interface.report("Required weapon is unavailable: " + id); return false
	loading_save = true
	front_end.hide_menu(); dock_interface.dismiss(); get_tree().paused = false
	_set_camera_mode(false)
	if not _can_reuse_world(): await _start_game(game_folder)
	if not pilot_mode: loading_save = false; return false
	_reset_loaded_world()
	var port: Dictionary = {}
	for candidate in docking.ports:
		if int(candidate.node.get_meta("city_id")) == int(data.dock.id): port = candidate; break
	if port.is_empty():
		loading_save = false; _show_main_menu(); dock_interface.open("load"); dock_interface.report("The saved dock is unavailable."); return false
	docking.current = port; docking.saved_collision_mask = pilot.collision_mask
	pilot.active = false; pilot.controls_enabled = false; pilot.collision_mask = 0
	pilot.global_transform = MapDocument.decode(data.pose); pilot.global_position = port.inside
	pilot.velocity = Vector3.ZERO; pilot.angular_velocity = Vector3.ZERO
	pilot.pending_reset = false
	pilot.visual.visible = false; pilot.reset_physics_interpolation()
	# A restored save has no approach-camera position to reuse. Place it at
	# launch height, behind/right of the upright sub, above the dock's roof.
	var launch_basis := Docking.upright_basis(pilot.global_basis)
	var launch_distance := maxf(2.0,float(pilot.movement.settings.camera_distance))
	docking.cinematic_camera = port.entry + launch_basis.z * launch_distance + launch_basis.x * launch_distance * 0.3
	camera.global_position = docking.cinematic_camera
	camera.look_at(pilot.global_position + Vector3.UP * 0.35,Vector3.UP)
	docking._set_open(0); port.collision.collision_layer = 1; docking._transition(Docking.Stage.DOCKED)
	day_night.hour = float(data.hour); _update_daylight()
	for item in data.equipment:
		for index in range(equipment.mounted.size()):
			if equipment.mounted[index].id == item.id:
				equipment.mounted[index].enabled = item.enabled
				if item.id == data.get("equipment_selected",""): equipment.selected = index
	equipment.apply_settings()
	for index in range(weapons.mounted.size()):
		if weapons.mounted[index].id == data.get("weapon_selected",""): weapons.selected = index
	if _exploration_matches_map(data.map_signature):
		var bytes := Marshalls.base64_to_raw(data.explored)
		cockpit_hud.map_data.explored = Image.create_from_data(HUD.Map.RESOLUTION,HUD.Map.RESOLUTION,false,Image.FORMAT_L8,bytes)
		cockpit_hud.map_data.exploration_texture.update(cockpit_hud.map_data.explored)
		cockpit_hud.map_data.last_explored = Vector2(INF,INF)
	else: cockpit_hud.map_data.reset_exploration()
	has_started_game = true; front_end.can_resume = true
	if data.has("objects"): object_population.restore_snapshot(data.objects)
	player_progress = PlayerProgress.restore(data.get("progress",{}))
	equipment.vacuum.storage.assign(player_progress.suckomat)
	equipment.vacuum.transfer_to(player_progress.cargo)
	var capacity := float(player_progress.status.hull_strength)
	pilot.restore_health(capacity,capacity * float(player_progress.status.shields) / 100.0)
	dock_interface.open("home"); dock_interface_active = true
	loading_save = false; _update_mouse_pointer(); return true

func _submarine_health_changed(remaining: float, capacity: float) -> void:
	player_progress.status.hull_strength = int(round(capacity))
	player_progress.status.shields = int(round(remaining / capacity * 100.0))

func _submarine_destroyed() -> void:
	_set_map_open(false)
	weapons.update_fire(false,0)
	var wreck := preload("res://submarine_death.gd").new(); world_root.add_child(wreck)
	wreck.global_position = pilot.global_position
	var mounts: Array[Node3D] = [weapons.muzzle]
	for item in equipment.mounted: mounts.append(item.mount)
	wreck.setup_submarine(pilot,submarine_bubble_texture,mounts)
	var burst := SessionExplosion.new(); world_root.add_child(burst); burst.global_position = pilot.global_position
	burst.setup(submarine_explosion_frames,maxf(1.0,pilot.collision_height() * 3.0),submarine_explosion_sound)
	weapons.hide(); equipment.hide()
	_set_camera_mode(false)
