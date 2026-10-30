extends Node3D
var events := preload("res://gameplay_events.gd").new()
var session := preload("res://game_session.gd").new(self)
var game_settings := preload("res://game_settings.gd").new(self)
var developer_tools := preload("res://developer_tools.gd").new(self)
var game_world_setup := preload("res://game_world_setup.gd").new(self)
var game_camera := preload("res://game_camera.gd").new(self)
var game_lighting := preload("res://game_lighting.gd").new(self)
var game_dock := preload("res://game_dock.gd").new(self)
var game_radio := preload("res://game_radio.gd").new(self)
var game_map_ui := preload("res://game_map_ui.gd").new(self)
var game_input := preload("res://game_input.gd").new(self)
var game_runtime := preload("res://game_runtime.gd").new(self)
var game_wildlife := preload("res://game_wildlife.gd").new(self)
var game_controls := preload("res://game_controls.gd").new(self)
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
const MapDocument = preload("res://map_document.gd")
const Wildlife = preload("res://wildlife_population.gd")
const WaterParticles = preload("res://water_particles.gd")
const DayNight = preload("res://day_night_cycle.gd")
const HUD = preload("res://cockpit_hud.gd")
const Equipment = preload("res://submarine_equipment.gd")
const Weapons = preload("res://submarine_weapons.gd")
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
var capture_overlay: CanvasLayer
var photo_mode: Node3D
const PlantCurrent = preload("res://plant_current.gd")
const WaterVisuals = preload("res://water_visuals.gd")
const OriginalGameData = preload("res://original_game_data.gd")
var gameplay_catalogue := {}
var mission_runtime: Node
var water_visuals := WaterVisuals.new()
const NaturalLight = preload("res://natural_light.gd")
var natural_light := NaturalLight.new()
var natural_light_controls := {}
var water_controls := {}
var plant_current := PlantCurrent.new()
var plant_controls := {}
@export var show_start_menu := false
var front_end: Node
var fmv: CanvasLayer
var has_started_game := false
var menu_backdrop: Node3D
var sun_shafts: Node3D
var sun_shafts_brightness_slider: HSlider
const DEFAULT_VISIBILITY = preload("res://developer_tools.gd").DEFAULT_VISIBILITY

var pilot: RigidBody3D
var model: Node3D
var world_root: Node3D
var camera: Camera3D
var loaded_world_assets := ""
var scenery_seed := 0
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
var testing_all_equipment := false
var bounty_radio_queue: Array[Dictionary] = []
var bounty_port: Dictionary = {}
var bounty_remaining := 0.0
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
var developer_enabled := false
var camera_follow := FollowCamera.new()
var camera_was_frozen := false
const SUB_RENDER_LAYER := 2
var first_person := false
var first_person_cockpit: Node3D
var cockpit_camera_offset := Vector3(0,0.025,-0.16)
var fog_visibility := DEFAULT_VISIBILITY
var remember_preferences := true
var settings_save_pending := false
var settings_save_retries := 0
var settings_save_error := ""
var defaults_directory := ""
var use_map_overrides := true
var loading_preferences := false
var docking: Node
var radio_greeting := ""
var radio_status := ""
var radio_feed: Control
var radio_message_audio: AudioStreamPlayer
const RadioPortrait = preload("res://radio_portrait.gd")
var mod_panel: Window
var object_population: Node3D
var wildlife: Node3D
var wildlife_density_slider: HSlider
var wildlife_density_label: Label
var docked_screen: ColorRect
var docked_label: Label
var map_overlay: CanvasLayer
var expanded_map: Control
var map_screen: Control
var map_open := false
var cockpit_hud: CanvasLayer
var equipment: Node3D
var equipment_controls := {}
var hud_enabled: Array[bool] = [true,true,true,true,true]
var hud_map_zoom_slider: HSlider
var hud_map_zoom_label: Label
var map_reveal_slider: HSlider
var map_reveal_label: Label
var crt_reflection_slider: HSlider
var crt_reflection_label: Label
var market_speed_slider: HSlider
var dock_zapper_damage_slider: HSlider
var turret_system: Node
var submarine_traffic: Node
var ground_traffic: Node
var market_ui_elapsed := 0.0

func _ready() -> void:
	mission_runtime = preload("res://mission_runtime.gd").new(); add_child(mission_runtime); mission_runtime.setup(self)
	events.mission_available.connect(func(id: String, available: bool) -> void: preload("res://mailbox.gd").set_mission_available(player_progress,id,available))
	events.mission_completed.connect(func(id: String, score: float) -> void: preload("res://mailbox.gd").mission_completed(player_progress,id,score))
	# Keep menus, settings and market quotes responsive while the physical
	# world is paused. Gameplay subtrees explicitly use PAUSABLE below.
	process_mode = Node.PROCESS_MODE_ALWAYS
	preload("res://input_bindings.gd").install()
	capture_overlay = CaptureOverlay.new(); add_child(capture_overlay)
	# Only the physics-driven submarine interpolates; camera and scenery keep
	# their existing render-frame updates.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Mods.ensure(remember_preferences)
	if remember_preferences:
		var active_mods := Mods.active_ids()
		var sound_profile := "user://submarine_sound.cfg" if active_mods.is_empty() else "user://sound-mod-%s.cfg" % JSON.stringify(active_mods).sha256_text().substr(0,16)
		preload("res://current_settings.gd").migrate_legacy(Mods.movement_profile(),sound_profile)
	get_window().title = "OpenSubCulture"
	get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN
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
	particles.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(particles)
	_build_interface()
	photo_mode = preload("res://photo_mode.gd").new(); add_child(photo_mode); photo_mode.setup(self)
	fmv = preload("res://fmv_player.gd").new(); add_child(fmv); fmv.setup(self)
	_load_preferences()
	_update_water_environment()
	call_deferred("_bootstrap")

func _build_interface() -> void:
	developer_tools._build_interface()
	front_end = FrontEnd.new(); front_end.remember_preferences = remember_preferences; add_child(front_end)
	front_end.player_graphics.changed.connect(func() -> void: _update_hud_settings(); _update_daylight())
	front_end.gameplay_menu.auto_aim_changed.connect(func(enabled: bool) -> void:
		if weapons != null: weapons.auto_aim_enabled = enabled)
	front_end.gameplay_menu.wildlife_limit_changed.connect(func(limit: int) -> void:
		if wildlife != null: wildlife.set_active_limit(limit))
	front_end.gameplay_menu.sun_shafts_changed.connect(func(enabled: bool) -> void:
		if is_instance_valid(sun_shafts): sun_shafts.set_enabled(enabled))
	front_end.back_shortcut_busy = func(event: InputEvent) -> bool: return Bindings.pressed(event,"menu_cancel") and (map_open or developer_ui_visible or (dock_interface != null and dock_interface.back_shortcut_busy()))
	loading_canvas = front_end.loading_layer
	loading_label = front_end.loading_status
	front_end.new_game_requested.connect(_begin_new_game)
	front_end.resume_requested.connect(_continue_game)
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
		if show_start_menu and is_instance_valid(world_root): _show_main_menu()

func _prompt_game_folder(message: String) -> void:
	front_end.show_loading()
	front_end.loading_status.text = "Waiting for original Sub Culture files..."
	folder_prompt.dialog_text = message
	folder_prompt.popup_centered(Vector2i(520,180))

func _show_main_menu() -> void:
	if photo_mode != null and photo_mode.active: photo_mode.leave()
	_set_map_open(false)
	if world_loading: return
	if weapons != null: weapons.update_fire(false,0)
	if developer_ui_visible: _toggle_developer_ui()
	dock_interface.dismiss()
	var has_save: bool = save_games.latest_slot() >= -1
	front_end.buttons.load.set_meta("available",has_save)
	front_end.buttons.load.tooltip_text = "" if front_end.is_button_available("load") else "No saved games yet"
	front_end.show_menu(has_started_game and (pilot == null or not pilot.dead),not has_started_game and has_save)
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
	if show_start_menu and not has_started_game and is_instance_valid(world_root): _show_main_menu()

func _continue_game() -> void:
	if world_loading or loading_save: return
	if has_started_game: _resume_game(); return
	var slot: int = save_games.latest_slot()
	if slot < -1: _show_main_menu(); return
	if not await _load_saved_game(slot):
		var message: String = dock_interface.status
		front_end.hide_menu(); dock_interface.open("load"); dock_interface.report(message)

func _resume_game() -> void:
	if not has_started_game or world_loading or pilot.dead: return
	front_end.hide_menu()
	if menu_backdrop != null: menu_backdrop.close()
	if dock_interface != null: dock_interface.dismiss()
	get_tree().paused = false
	if docking != null and docking.stage == Docking.Stage.DOCKED:
		dock_interface.open("home"); dock_interface_active = true
		get_tree().paused = true
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
	if is_instance_valid(world_root): _show_main_menu()

func _begin_new_game() -> void:
	if world_loading or loading_save or (fmv != null and fmv.active): return
	if photo_mode != null and photo_mode.active: photo_mode.leave()
	await session._begin_new_game()
	if pilot_mode and has_started_game and fmv != null and fmv.request("intro"): await fmv.idle

func _world_asset_key() -> String:
	return session._world_asset_key()

func _can_reuse_world() -> bool:
	return session._can_reuse_world()

func _reset_loaded_world() -> void:
	if photo_mode != null: photo_mode.replay.clear()
	session._reset_loaded_world()

func _clear_session_effects(node: Node) -> void:
	session._clear_session_effects(node)

func _start_game(folder: String) -> void:
	await game_world_setup._start_game(folder)

func _progress(message: String) -> void:
	front_end.update_progress(message)

func _build_radio_feed() -> void:
	game_radio._build_radio_feed()

func _fail_startup(message: String) -> void:
	world_loading = false
	loading_canvas.visible = false
	developer_ui_visible = developer_enabled
	canvas.visible = developer_enabled
	status_label.text = message
	if not developer_enabled: _prompt_game_folder(message)

func _input(event: InputEvent) -> void:
	if fmv != null and fmv.active: return
	game_input._input(event)

func _unhandled_input(event: InputEvent) -> void:
	game_input._unhandled_input(event)

func _build_expanded_map() -> void:
	game_map_ui._build_expanded_map()

func _map_ui_model() -> Dictionary:
	return game_map_ui._map_ui_model()

func _set_map_open(open: bool) -> void:
	game_map_ui._set_map_open(open)

func _toggle_developer_ui() -> void:
	developer_tools._toggle_developer_ui()

func _resize_developer_menu() -> void:
	developer_tools._resize_developer_menu()

func _developer_tab_changed(index: int) -> void:
	developer_tools._developer_tab_changed(index)

func _select_developer_tab(tab_name: String) -> void:
	developer_tools._select_developer_tab(tab_name)

func _toggle_tuning() -> void:
	developer_tools._toggle_tuning()

func _toggle_sound_tuning() -> void:
	developer_tools._toggle_sound_tuning()

func _physics_process(_delta: float) -> void:
	game_input._physics_process(_delta)

func _process(delta: float) -> void:
	game_runtime._process(delta)

func _autosave_docked() -> void:
	game_dock._autosave_docked()

func _update_radio_messages(delta: float) -> void:
	game_radio._update_radio_messages(delta)

func _update_follow_camera(delta: float, snap: bool = false) -> void:
	game_camera._update_follow_camera(delta,snap)

func _set_camera_mode(cockpit: bool) -> void:
	game_camera._set_camera_mode(cockpit)

func _request_docking() -> void:
	game_runtime._request_docking()

func _update_water_environment() -> void:
	game_lighting._update_water_environment()

func _update_daylight() -> void:
	game_lighting._update_daylight()

func _update_hud_settings() -> void:
	game_controls._update_hud_settings()

func _update_equipment_settings() -> void:
	game_controls._update_equipment_settings()

func _update_weapon_settings() -> void:
	game_controls._update_weapon_settings()

func _desired_mouse_mode() -> int:
	return game_input._desired_mouse_mode()

func _update_mouse_pointer() -> void:
	game_input._update_mouse_pointer()

func _exit_tree() -> void:
	if is_instance_valid(model) and model.get_parent() == null: model.free(); model = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _reset_docked_wildlife() -> void:
	game_wildlife._reset_docked_wildlife()

func _reset_provisional_wildlife() -> void:
	game_wildlife._reset_provisional_wildlife()

func _update_docking_radius() -> void:
	game_controls._update_docking_radius()

func _update_wildlife_density() -> void:
	game_wildlife._update_wildlife_density()

func _load_preferences(path: String = "") -> void:
	game_settings._load_preferences(path)

func _schedule_settings_save() -> void:
	game_settings._schedule_settings_save()

func _save_all_preferences() -> void:
	game_settings._save_all_preferences()

func _report_settings_error(path: String, result: Error) -> void:
	game_settings._report_settings_error(path, result)

func _save_preferences(path: String = "") -> Error:
	return game_settings._save_preferences(path)

func _view_settings() -> Dictionary:
	return game_settings._view_settings()

func _export_all_settings(path: String) -> Error:
	return game_settings._export_all_settings(path)

func _add_water_surface() -> void:
	game_lighting._add_water_surface()

func _map_signature() -> String:
	return session._map_signature()

func _exploration_matches_map(signature: String) -> bool:
	return session._exploration_matches_map(signature)

func _rov_prompt_active() -> bool:
	if not pilot_mode or world_loading or get_tree().paused or map_open or developer_ui_visible or pilot == null or pilot.dead or docking == null or docking.stage != Docking.Stage.IDLE: return false
	return equipment != null and equipment.support_tools != null and is_instance_valid(equipment.support_tools.rover) and equipment.support_tools.rover.docking_prompt

func _delivery_prompt_active() -> bool:
	if not pilot_mode or world_loading or get_tree().paused or map_open or developer_ui_visible or pilot == null or pilot.dead or docking == null or docking.stage != Docking.Stage.IDLE: return false
	if equipment == null or equipment.towing_tool() == null: return false
	var magnet: Node3D = equipment.towing_tool()
	if not is_instance_valid(magnet.delivery_point) or not is_instance_valid(magnet.target): return false
	if magnet.target.get_meta("mission_delivery",false) and str(magnet.target.get_meta("mission_owner","")) == str(mission_runtime.active().get("id","")):
		return true
	var terms := _delivery_terms(magnet.target)
	return not terms.commodity.is_empty() and terms.quantity > 0

func _delivery_terms(body: RigidBody3D) -> Dictionary:
	return game_dock._delivery_terms(body)

func _answer_delivery(accepted: bool) -> void:
	game_dock._answer_delivery(accepted)

func _collect_city_deliveries(city_id: int) -> void:
	game_dock._collect_city_deliveries(city_id)

func _dock_ui_model() -> Dictionary:
	return game_dock._dock_ui_model()

func _save_snapshot(name: String) -> Dictionary:
	return session._save_snapshot(name)

func _dock_ui_action(action: String, payload: Dictionary) -> void:
	game_dock._dock_ui_action(action,payload)

func _load_saved_game(slot: int) -> bool:
	if photo_mode != null and photo_mode.active: photo_mode.leave()
	return await session._load_saved_game(slot)

func _submarine_health_changed(remaining: float, capacity: float) -> void:
	game_runtime._submarine_health_changed(remaining,capacity)

func _submarine_destroyed() -> void:
	game_runtime._submarine_destroyed()

func _age_radio(delta: float) -> void:
	game_radio._age_radio(delta)

func _pirate_bounty(point: Vector3) -> void:
	game_radio._pirate_bounty(point)
