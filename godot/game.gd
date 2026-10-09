extends Node3D
var events := preload("res://gameplay_events.gd").new()
var session := preload("res://game_session.gd").new(self)
var game_settings := preload("res://game_settings.gd").new(self)
var developer_tools := preload("res://developer_tools.gd").new(self)
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
const DEFAULT_VISIBILITY = preload("res://developer_tools.gd").DEFAULT_VISIBILITY

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
var settings_save_pending := false
var settings_save_retries := 0
var settings_save_error := ""
var defaults_directory := ""
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
var market_speed_slider: HSlider
var market_ui_elapsed := 0.0

func _ready() -> void:
	# Keep menus, settings and market quotes responsive while the physical
	# world is paused. Gameplay subtrees explicitly use PAUSABLE below.
	process_mode = Node.PROCESS_MODE_ALWAYS
	preload("res://input_bindings.gd").install()
	add_child(CaptureOverlay.new())
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
	_load_preferences()
	_update_water_environment()
	call_deferred("_bootstrap")

func _build_interface() -> void:
	developer_tools._build_interface()
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
	if pilot_mode: _show_main_menu()

func _begin_new_game() -> void:
	await session._begin_new_game()

func _world_asset_key() -> String:
	return session._world_asset_key()

func _can_reuse_world() -> bool:
	return session._can_reuse_world()

func _reset_loaded_world() -> void:
	session._reset_loaded_world()

func _clear_session_effects(node: Node) -> void:
	session._clear_session_effects(node)

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
	world_root.process_mode = Node.PROCESS_MODE_PAUSABLE
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
		pilot.process_mode = Node.PROCESS_MODE_PAUSABLE
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
	tuning_panel.settings_changed.connect(_schedule_settings_save)
	pilot.surface_height = float(world_root.get_meta("surface_height"))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bounds: AABB = world_root.get_meta("bounds")
	var point: Vector3 = world_root.get_meta("player_spawn", bounds.get_center())
	pilot.reset_at(point,world_root.get_meta("player_spawn_basis",Basis.IDENTITY))
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
	cockpit_hud.process_mode = Node.PROCESS_MODE_PAUSABLE
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
	dock_interface.audio_tuning = pilot.submarine_audio.tuning
	if sound_panel != null: sound_panel.free()
	sound_panel = SoundPanel.new()
	sound_panel.name = "Sound"
	developer_tabs.add_child(sound_panel)
	developer_tabs.move_child(sound_panel, 1)
	sound_panel.setup(pilot.submarine_audio, true)
	sound_panel.settings_changed.connect(_schedule_settings_save)
	_select_developer_tab(str(selected_tab))
	pilot.hull_rating = 100; pilot.radiation_rating = 0
	pilot.restore_health(); pilot.collision_layer = 2; pilot.collision_mask = 13
	pilot.active = true
	if docking != null: docking.free()
	docking = Docking.new()
	docking.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(docking)
	docking.setup(pilot, world_root, folder, camera,gameplay_catalogue)
	save_games.city_names.clear()
	for port in docking.ports: save_games.city_names[int(port.node.get_meta("city_id"))] = str(port.name)
	_update_docking_radius()
	if wildlife != null: wildlife.player = pilot
	object_population.player = pilot
	docking.docked.connect(_reset_docked_wildlife)
	docking.docked.connect(func() -> void: events.city_docked.emit(int(docking.current.node.get_meta("city_id"))))
	equipment.activated.connect(func(id: String, active: bool) -> void: events.equipment_activated.emit(id,active))
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
	docking_prompt.offset_left = 140.0
	docking_prompt.offset_right = -20.0
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
	docking_portrait.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	docking_portrait.offset_left = 20.0
	docking_portrait.offset_right = 116.0
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
	if get_tree().paused and front_end.menu_layer.visible: return
	if _delivery_prompt_active():
		if Bindings.pressed(event,"dock_accept") or Bindings.pressed(event,"menu_accept"):
			_answer_delivery(true); get_viewport().set_input_as_handled(); return
		if Bindings.pressed(event,"dock_decline") or Bindings.pressed(event,"menu_cancel"):
			_answer_delivery(false); get_viewport().set_input_as_handled(); return
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
	if get_tree().paused or not pilot_mode or world_loading or map_open or (dock_interface != null and dock_interface.visible): return
	if pilot.dead: return
	if not developer_ui_visible and docking.stage == Docking.Stage.IDLE:
		if Bindings.pressed(event,"bottom_camera_toggle") and cockpit_hud != null:
			cockpit_hud.set_bottom_camera_enabled(not cockpit_hud.bottom_camera_enabled)
			get_viewport().set_input_as_handled(); return
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
	if pilot == null or get_tree().paused: return
	var pointer := get_viewport().get_mouse_position()
	var over_ui := developer_ui_visible and controls.get_global_rect().has_point(pointer)
	if developer_ui_visible and tuning_panel.visible:
		over_ui = over_ui or tuning_panel.get_global_rect().has_point(pointer)
	if developer_ui_visible and sound_panel != null and sound_panel.visible:
		over_ui = over_ui or sound_panel.get_global_rect().has_point(pointer)
	pilot.controls_enabled = pilot_mode and not pilot.dead and not map_open and not world_loading and not developer_ui_visible and not over_ui and not folder_dialog.visible and not export_all_dialog.visible and not mod_panel.visible and not tuning_panel.export_dialog.visible and (sound_panel == null or not sound_panel.export_dialog.visible) and (docking == null or docking.stage == Docking.Stage.IDLE)

func _process(delta: float) -> void:
	var in_dock_menu: bool = docking != null and docking.stage == Docking.Stage.DOCKED and dock_interface_active and dock_interface.visible and dock_interface.page != "load"
	if pilot_mode and not world_loading and not front_end.menu_layer.visible and (not get_tree().paused or in_dock_menu):
		preload("res://commodity_market.gd").advance(gameplay_catalogue,player_progress,delta * market_speed_slider.value / 100.0)
		market_ui_elapsed += delta
		if market_ui_elapsed >= 0.3:
			market_ui_elapsed = 0.0
			if dock_interface_active and dock_interface.visible and dock_interface.page == "goods": dock_interface.refresh_market()
	_update_mouse_pointer()
	if get_tree().paused or world_loading: return
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
				_collect_city_deliveries(int(docking.current.node.get_meta("city_id")))
				dock_interface.open("home"); dock_interface_active = true
			elif not dock_interface.visible: dock_interface.show()
			get_tree().paused = true
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
		if _delivery_prompt_active(): docking_prompt.text = "CITY DROP POINT : Do you want attached object to be automatically retrieved? (Y/N)"
		docking_prompt.visible = not docking_prompt.text.is_empty()
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
	if cockpit_hud != null and cockpit_hud.bottom_camera != null: cockpit_hud.bottom_camera.far = camera.far
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

func _update_daylight() -> void:
	var lighting_cycle: RefCounted = menu_backdrop.daylight if menu_backdrop != null and menu_backdrop.active else day_night
	lighting_cycle.apply(water_environment, sun, surface_material)
	get_tree().call_group("building_searchlights", "set_daylight", lighting_cycle.daylight())
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

func _update_equipment_settings() -> void:
	if equipment == null: return
	for key in equipment_controls: equipment.settings[key] = equipment_controls[key].value
	equipment.apply_settings()

func _update_weapon_settings() -> void:
	if weapons == null: return
	var values := {}
	for key in weapon_controls: values[key] = weapon_controls[key].value
	weapons.configure(values)
	for key in weapon_controls: weapon_controls[key].get_meta("label").text = "%s: %.2f" % [weapon_controls[key].get_meta("caption"),weapon_controls[key].value]

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
			fish.dead = false; fish.health = fish.max_health; fish.visible = true; fish.collision_layer = 8; fish.collision_mask = 7
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
	return session._map_signature()

func _exploration_matches_map(signature: String) -> bool:
	return session._exploration_matches_map(signature)

func _delivery_prompt_active() -> bool:
	if not pilot_mode or world_loading or get_tree().paused or map_open or developer_ui_visible or pilot == null or pilot.dead or docking == null or docking.stage != Docking.Stage.IDLE: return false
	if equipment == null or equipment.towing_tool() == null: return false
	var magnet: Node3D = equipment.towing_tool()
	if not is_instance_valid(magnet.delivery_point) or not is_instance_valid(magnet.target): return false
	var terms := _delivery_terms(magnet.target)
	return not terms.commodity.is_empty() and terms.quantity > 0

func _delivery_terms(body: RigidBody3D) -> Dictionary:
	var stats: Dictionary = body.get("stats") if body.get("stats") is Dictionary else {}
	var defaults := preload("res://object_definitions.gd").delivery_defaults(stats)
	if int(body.get("shard")) != 0: return {"commodity":"","quantity":0}
	return {"commodity":str(stats.get("delivery_commodity",defaults.commodity)).to_lower(),"quantity":int(stats.get("delivery_quantity",defaults.quantity))}

func _answer_delivery(accepted: bool) -> void:
	if not _delivery_prompt_active(): return
	var magnet: Node3D = equipment.towing_tool()
	if not accepted: magnet.decline_delivery(); return
	var body: RigidBody3D = magnet.target
	var terms := _delivery_terms(body)
	var city := str(int(magnet.delivery_point.city_id))
	if not player_progress.pending_deliveries.has(city): player_progress.pending_deliveries[city] = {}
	var goods: Dictionary = player_progress.pending_deliveries[city]
	goods[terms.commodity] = int(goods.get(terms.commodity,0)) + terms.quantity
	magnet.set_enabled(false)
	body.set_meta("delivery_city",int(city))
	body.set_meta("metal_tow_target",false)
	body.set_meta("grapple_tow_target",false)
	events.delivery_accepted.emit(preload("res://entity_identity.gd").of(body),int(city),terms.commodity,terms.quantity)

func _collect_city_deliveries(city_id: int) -> void:
	var goods: Dictionary = player_progress.pending_deliveries.get(str(city_id),{}).duplicate(true)
	object_population.collect_delivered_objects(city_id)
	PlayerProgress.collect_deliveries(player_progress,city_id)
	if not loading_save and not goods.is_empty(): events.deliveries_collected.emit(city_id,goods)

func _dock_ui_model() -> Dictionary:
	var port: Dictionary = docking.current if docking != null else {}
	var city_id := str(int(port.node.get_meta("city_id"))) if port.get("node") != null else ""
	var city: Dictionary = gameplay_catalogue.get("tables",{}).get("city_info",{}).get("records",{}).get(city_id,{})
	var standing: String = player_progress.standing.get(str(port.get("race",1)),"neutral")
	var description_id := "%s%d.%s" % [city.get("description_key",""),player_progress.campaign_stage,standing]
	var description: String = gameplay_catalogue.get("tables",{}).get("city_descriptions",{}).get("records",{}).get(description_id,{}).get("text","")
	return {"city":port.get("name","Dock"),"city_id":city_id,"title_bitmap":city.get("title_bitmap",""),"welcome":description,"standing":{"bad":"Hostile","neutral":"Neutral","good":"Friendly"}.get(standing,"Neutral"),"mission":player_progress.mission,"status":player_progress.status.duplicate(),"race":port.get("race",1),"repair_offer":preload("res://equipment_shop.gd").shield_repair(gameplay_catalogue,city_id,player_progress.campaign_stage),"offers":preload("res://equipment_shop.gd").offers(gameplay_catalogue,city_id,player_progress.campaign_stage),"installed":preload("res://equipment_shop.gd").installed(equipment,weapons),"hold":player_progress.hold.duplicate(),"commodity_offers":preload("res://commodity_market.gd").offers(gameplay_catalogue,player_progress,city_id),"cargo":player_progress.cargo.duplicate(),"slots":save_games.slots() if dock_interface != null and dock_interface.page in ["save","load"] else []}

func _save_snapshot(name: String) -> Dictionary:
	return session._save_snapshot(name)

func _dock_ui_action(action: String, payload: Dictionary) -> void:
	match action:
		"buy_commodity","sell_commodity":
			if docking.stage != Docking.Stage.DOCKED: return
			var city_id := str(int(docking.current.node.get_meta("city_id")))
			var id := str(payload.get("item",""))
			var credits_before := int(player_progress.status.credits)
			var result := preload("res://commodity_market.gd").trade(gameplay_catalogue,player_progress,city_id,id,action == "buy_commodity")
			dock_interface.transaction_feedback(result,"commodity_trade")
			if result.is_empty(): events.commodity_traded.emit(int(city_id),id,1 if action == "buy_commodity" else -1,int(player_progress.status.credits) - credits_before)
		"equipment_slot":
			if docking.stage != Docking.Stage.DOCKED: return
			var incoming := str(payload.get("item",""))
			var installing: bool = preload("res://equipment_shop.gd").SLOTS.get(incoming,0) == int(payload.slot) and int(player_progress.hold.get(incoming,0)) > 0
			dock_interface.transaction_feedback(preload("res://equipment_shop.gd").swap(player_progress,equipment,weapons,int(payload.slot),incoming),"install",installing)
		"buy_equipment","sell_equipment":
			if docking.stage != Docking.Stage.DOCKED: return
			var id := str(payload.get("item",""))
			var offer: Dictionary = _dock_ui_model().offers.get(id,{})
			if offer.is_empty(): dock_interface.transaction_feedback("Item unavailable.","equipment_trade"); return
			if action == "buy_equipment":
				if id != "shield" and preload("res://equipment_shop.gd").owned(player_progress,equipment,weapons,id) >= int(offer.maximum):
					dock_interface.transaction_feedback("Already owned.","equipment_trade"); return
				dock_interface.transaction_feedback(preload("res://equipment_shop.gd").buy(player_progress,offer),"equipment_trade")
			elif int(player_progress.hold.get(id,0)) > 0 and int(offer.sell_price) > 0:
				player_progress.hold[id] -= 1
				if player_progress.hold[id] == 0: player_progress.hold.erase(id)
				player_progress.status.credits += int(offer.sell_price)
				dock_interface.transaction_feedback("","equipment_trade")
			else: dock_interface.transaction_feedback("Item cannot be sold.","equipment_trade")
		"use_repair":
			if docking.stage != Docking.Stage.DOCKED: return
			var id := str(payload.get("item","shield"))
			var previous_count := int(player_progress.hold.get(id,0))
			var result := preload("res://equipment_shop.gd").use_item(player_progress,pilot,id)
			dock_interface.transaction_feedback(result,"repair",int(player_progress.hold.get(id,0)) < previous_count)
			if int(player_progress.hold.get(id,0)) < previous_count: events.item_used.emit(id)
		"launch":
			if docking.stage == Docking.Stage.DOCKED:
				get_tree().paused = false
				dock_interface.dismiss(); dock_interface_active = false; _request_docking()
		"close": dock_interface.dismiss(); front_end.show_menu(has_started_game)
		"save_slot":
			if docking.stage != Docking.Stage.DOCKED: dock_interface.report("Save games are available while docked."); return
			var result := save_games.write(int(payload.slot),_save_snapshot(str(payload.name)))
			dock_interface.report("" if result == OK else save_games.error)
		"load_slot": _load_saved_game(int(payload.slot))

func _load_saved_game(slot: int) -> bool:
	return await session._load_saved_game(slot)

func _submarine_health_changed(remaining: float, capacity: float) -> void:
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
	equipment.reset_towing()
	weapons.hide(); equipment.hide()
	_set_camera_mode(false)
