extends Node3D

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
const DEFAULT_VISIBILITY := 35.0
const MIN_VISIBILITY := 10.0
const MAX_VISIBILITY := 250.0

var pilot: RigidBody3D
var model: Node3D
var world_root: Node3D
var camera: Camera3D
var water_environment: Environment
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
var folder_dialog: FileDialog
var export_all_dialog: FileDialog
var export_all_button: Button
var export_all_message: Label
var fog_button: CheckButton
var fog_slider: HSlider
var fog_label: Label
var game_folder := ""
var world_loading := false
var pilot_mode := false
var startup_complete := false
var developer_ui_visible := false
var camera_follow := FollowCamera.new()
var camera_was_frozen := false
var fog_visibility := DEFAULT_VISIBILITY
var remember_preferences := true
var use_map_overrides := true
var loading_preferences := false
var docking: Node
var docking_prompt: Label
var docking_portrait: TextureRect
var mod_panel: Window
var wildlife: Node3D
var docked_screen: ColorRect
var docked_label: Label

func _ready() -> void:
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
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -32, 0)
	light.light_energy = 1.0
	add_child(light)
	camera = Camera3D.new()
	camera.current = true
	camera.far = 4000.0
	camera.near = 0.03
	add_child(camera)
	particles.camera = camera
	add_child(particles)
	_build_interface()
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
	fog_button = CheckButton.new()
	fog_button.text = "Underwater fog"
	fog_button.button_pressed = true
	fog_button.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(fog_button)
	fog_label = Label.new()
	graphics_controls.add_child(fog_label)
	fog_slider = HSlider.new()
	fog_slider.min_value = MIN_VISIBILITY
	fog_slider.max_value = MAX_VISIBILITY
	fog_slider.step = 1.0
	fog_slider.value = DEFAULT_VISIBILITY
	fog_slider.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(fog_slider)
	var hint := Label.new()
	hint.text = "Shorter distance = denser fog. Saved on release."
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
	_build_particle_controls()
	bubble_controls = VBoxContainer.new()
	graphics_controls.add_child(bubble_controls)
	var graphics_hint := Label.new()
	graphics_hint.text = "Fog and particles save on release. Bubbles save/export with movement settings."
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
	var mods_tab := VBoxContainer.new()
	mods_tab.name = "Mods"
	developer_tabs.add_child(mods_tab)
	var system := VBoxContainer.new()
	system.name = "System"
	system.add_theme_constant_override("separation", 12)
	developer_tabs.add_child(system)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	system.add_child(status_label)
	telemetry = Label.new()
	system.add_child(telemetry)
	var reset := Button.new()
	reset.text = "Reset submarine (R)"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_reset_submarine)
	system.add_child(reset)
	var choose := Button.new()
	choose.text = "Choose Sub Culture folder…"
	choose.focus_mode = Control.FOCUS_NONE
	choose.pressed.connect(func() -> void:
		if not world_loading: folder_dialog.popup_centered(Vector2i(850, 600))
	)
	system.add_child(choose)
	folder_dialog = FileDialog.new()
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.title = "Choose your Sub Culture game folder"
	folder_dialog.dir_selected.connect(_start_game)
	add_child(folder_dialog)
	mod_panel = ModPanel.new()
	mod_panel.persist_preferences = remember_preferences
	mod_panel.applied.connect(func() -> void: _start_game(game_folder))
	add_child(mod_panel)
	mod_panel.embed(mods_tab)
	developer_tabs.tab_changed.connect(_developer_tab_changed)
	get_viewport().size_changed.connect(_resize_developer_menu)
	_resize_developer_menu()
	loading_canvas = CanvasLayer.new()
	add_child(loading_canvas)
	loading_label = Label.new()
	loading_label.text = "Loading OpenSubCulture…"
	loading_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	loading_label.position = Vector2(30, 30)
	loading_canvas.add_child(loading_label)

func _bootstrap() -> void:
	var folder := Paths.find_game_folder()
	if folder.is_empty():
		_fail_startup("Choose the folder containing CLUMPS and DATA to begin.")
		folder_dialog.popup_centered(Vector2i(850, 600))
		startup_complete = true
	else:
		await _start_game(folder)
		startup_complete = true

func _start_game(folder: String) -> void:
	if world_loading: return
	if not Paths.valid_game_folder(folder):
		_fail_startup("Could not find CLUMPS/SUB.DFF and DATA/SCEN1.BSP in that folder.")
		return
	world_loading = true
	export_all_button.disabled = true
	export_all_dialog.hide()
	pilot_mode = false
	if docking_prompt != null: docking_prompt.hide()
	if docking_portrait != null: docking_portrait.hide()
	if docking != null:
		docking.cancel()
		docking.free()
		docking = null
	if pilot != null: pilot.active = false
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
	_add_water_surface()
	await get_tree().physics_frame
	if map_data.is_empty():
		await Creatures.populate(world_root, folder, get_tree(), _progress)
	else:
		wildlife = Wildlife.new()
		wildlife.name = "AmbientFish"
		world_root.add_child(wildlife)
		wildlife.setup(world_root, folder, map_data)
	if pilot == null:
		pilot = Pilot.new()
		pilot.name = "PlayerSubmarine"
		pilot.remember_settings = remember_preferences
		add_child(pilot)
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
	pilot.reset_physics_interpolation()
	pilot.bubbles.configure(Assets._load_texture(folder, "BUBBLE", "BUBBLEM", {}))
	pilot.submarine_audio.setup(pilot, folder)
	if sound_panel != null: sound_panel.free()
	sound_panel = SoundPanel.new()
	sound_panel.name = "Sound"
	developer_tabs.add_child(sound_panel)
	developer_tabs.move_child(sound_panel, 1)
	sound_panel.setup(pilot.submarine_audio, true)
	_select_developer_tab(str(selected_tab))
	pilot.active = true
	if docking != null: docking.free()
	docking = Docking.new()
	add_child(docking)
	docking.setup(pilot, world_root, folder, camera)
	if wildlife != null: wildlife.player = pilot
	docking.docked.connect(_reset_docked_wildlife)
	if docking_prompt == null: _build_docking_prompt()
	pilot_mode = true
	world_loading = false
	export_all_button.disabled = false
	status_label.text = str(world_root.get_meta("scenery_summary", "Piloting ready."))
	loading_canvas.visible = false
	_update_follow_camera(0.0, true)
	particles.material.set_shader_parameter("surface_height", pilot.surface_height)
	particles._rebuild()
	_update_water_environment()
	_save_preferences()

func _progress(message: String) -> void:
	loading_label.text = message

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
	docking_portrait = TextureRect.new()
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_toggle_developer_ui()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not pilot_mode or world_loading: return
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A: docking.request_docking()
		elif event.button_index == JOY_BUTTON_B: docking.decline_docking()
		elif event.button_index == JOY_BUTTON_START: _toggle_developer_ui()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Y:
			docking.request_docking()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_N:
			docking.decline_docking()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R: _reset_submarine()
		elif event.keycode == KEY_ESCAPE:
			if developer_ui_visible: _toggle_developer_ui()
	elif event is InputEventMouseButton and event.pressed:
		if developer_ui_visible and developer_menu.get_global_rect().has_point(get_viewport().get_mouse_position()): return
		var distance := float(pilot.movement.settings.camera_distance)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: tuning_panel.set_camera_distance(distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: tuning_panel.set_camera_distance(distance * 1.1)

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
	if developer_tabs.get_tab_title(index) == "Mods" and not world_loading: mod_panel.open()

func _select_developer_tab(tab_name: String) -> void:
	for index in range(developer_tabs.get_tab_count()):
		if developer_tabs.get_tab_title(index) == tab_name:
			developer_tabs.current_tab = index
			break
	for index in range(developer_tabs.get_tab_count()): developer_tabs.get_tab_control(index).visible = index == developer_tabs.current_tab

# Retained for capture/test scripts; F1 is the only menu keyboard shortcut.
func _toggle_tuning() -> void:
	if not pilot_mode: return
	developer_ui_visible = true
	canvas.visible = true
	_select_developer_tab("Movement")

func _toggle_sound_tuning() -> void:
	if not pilot_mode: return
	developer_ui_visible = true
	canvas.visible = true
	_select_developer_tab("Sound")

func _reset_submarine() -> void:
	if not pilot_mode or world_loading: return
	if docking != null: docking.cancel()
	pilot.reset_at(pilot.spawn)
	_update_follow_camera(0.0, true)

func _physics_process(_delta: float) -> void:
	if pilot == null: return
	var pointer := get_viewport().get_mouse_position()
	var over_ui := developer_ui_visible and controls.get_global_rect().has_point(pointer)
	if developer_ui_visible and tuning_panel.visible:
		over_ui = over_ui or tuning_panel.get_global_rect().has_point(pointer)
	if developer_ui_visible and sound_panel != null and sound_panel.visible:
		over_ui = over_ui or sound_panel.get_global_rect().has_point(pointer)
	pilot.controls_enabled = pilot_mode and not world_loading and not developer_ui_visible and not over_ui and not folder_dialog.visible and not export_all_dialog.visible and not mod_panel.visible and not tuning_panel.export_dialog.visible and (sound_panel == null or not sound_panel.export_dialog.visible) and (docking == null or docking.stage == Docking.Stage.IDLE)

func _process(delta: float) -> void:
	_update_mouse_pointer()
	particles.active = pilot_mode and not world_loading
	if not pilot_mode: return
	if docked_screen != null:
		docked_screen.visible = docking.stage == Docking.Stage.DOCKED
		if docked_screen.visible: docked_label.text = "Docked at %s\n\nPress Y / controller A to undock" % docking.current.get("name", "port")
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
		docking_portrait.texture = docking.portrait_texture()
		docking_portrait.visible = docking_prompt.visible and docking_portrait.texture != null
	if developer_ui_visible:
		var state: RefCounted = pilot.movement
		telemetry.text = "Speed: %.2f · Vertical: %.2f units/s\nPod tilt: %.1f° · Hull pitch: %.1f°\nDocking limit: %.2f units/s" % [state.velocity.length(), state.velocity.y, rad_to_deg(state.tilt), rad_to_deg(asin(clampf(-pilot.global_basis.z.y, -1.0, 1.0))), docking.maximum_docking_speed()]

func _update_follow_camera(delta: float, snap: bool = false) -> void:
	var pose := pilot.global_transform if snap else pilot.get_global_transform_interpolated()
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

func _update_water_environment() -> void:
	water_environment.fog_enabled = fog_button.button_pressed
	water_environment.fog_density = 3.0 / fog_visibility
	fog_label.text = "Fog visibility distance: %.0f units" % fog_visibility

func _build_particle_controls() -> void:
	var enabled := CheckButton.new(); enabled.text = "Floating water particles"
	enabled.button_pressed = true; enabled.focus_mode = Control.FOCUS_NONE
	graphics_controls.add_child(enabled); particle_controls.enabled = enabled
	enabled.toggled.connect(func(on: bool) -> void:
		particles.configure({"enabled": on}); _save_preferences()
	)
	for row in [["count", "Particle count", 0.0, 2000.0, 50.0], ["size", "Particle size", 0.005, 0.08, 0.005], ["drift", "Particle drift speed", 0.0, 0.3, 0.01], ["radius", "Particle viewing radius", 3.0, 30.0, 0.5], ["visibility", "Particle brightness", 0.0, 1.0, 0.05]]:
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

func _desired_mouse_mode() -> int:
	var menus := developer_ui_visible or (folder_dialog != null and folder_dialog.visible) or (mod_panel != null and mod_panel.visible)
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
		for attempt in range(24):
			var point: Vector3 = fish.home + Vector3(random.randf_range(-3, 3), random.randf_range(-0.5, 0.5), random.randf_range(-3, 3))
			if point.y + fish.radius >= pilot.surface_height or not Creatures._clear(world_root, point, fish.radius): continue
			fish.position = point
			fish.rng.seed = random.randi()
			fish._choose_goal()
			fish.reset_physics_interpolation()
			break

func _load_preferences(path: String = "user://opensubculture.cfg") -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	loading_preferences = true
	var value: Variant = config.get_value("view", "fog_visibility", DEFAULT_VISIBILITY)
	if (value is float or value is int) and is_finite(float(value)):
		fog_slider.value = clampf(float(value), MIN_VISIBILITY, MAX_VISIBILITY)
	var enabled: Variant = config.get_value("view", "fog_enabled", true)
	if enabled is bool: fog_button.button_pressed = enabled
	for key in particle_controls:
		var setting: Variant = config.get_value("view", "particles_" + str(key), WaterParticles.DEFAULTS[key])
		if key == "enabled":
			if setting is bool: particle_controls[key].button_pressed = setting
		elif (setting is float or setting is int) and is_finite(float(setting)):
			particle_controls[key].value = clampf(float(setting), particle_controls[key].min_value, particle_controls[key].max_value)
	loading_preferences = false

func _save_preferences(path: String = "user://opensubculture.cfg") -> void:
	if not remember_preferences or loading_preferences: return
	var config := ConfigFile.new()
	config.load(path)
	if not game_folder.is_empty(): config.set_value("game", "folder", game_folder)
	var view := _view_settings()
	for key in view: config.set_value("view", key, view[key])
	if config.save(path) != OK: status_label.text = "Visibility settings could not be saved."

func _view_settings() -> Dictionary:
	var settings := {"fog_visibility": fog_visibility, "fog_enabled": fog_button.button_pressed}
	for key in particle_controls:
		settings["particles_" + str(key)] = particle_controls[key].button_pressed if key == "enabled" else particle_controls[key].value
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
	surface.mesh = plane
	surface.position = Vector3(bounds.get_center().x, float(world_root.get_meta("surface_height")), bounds.get_center().z)
	var material := ShaderMaterial.new()
	material.shader = preload("res://water_surface.gdshader")
	surface.material_override = material
	world_root.add_child(surface)
