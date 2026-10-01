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
var controls: VBoxContainer
var status_label: Label
var telemetry: Label
var tuning_panel: PanelContainer
var sound_panel: PanelContainer
var folder_dialog: FileDialog
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
var loading_preferences := false
var docking: Node
var docking_prompt: Label
var docking_portrait: TextureRect
var mod_panel: Window

func _ready() -> void:
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
	add_child(camera)
	_build_interface()
	_load_preferences()
	_update_water_environment()
	call_deferred("_bootstrap")

func _build_interface() -> void:
	canvas = CanvasLayer.new()
	canvas.visible = developer_ui_visible
	add_child(canvas)
	controls = VBoxContainer.new()
	controls.position = Vector2(18, 18)
	controls.custom_minimum_size.x = 390
	canvas.add_child(controls)
	var title := Label.new()
	title.text = "OpenSubCulture · developer controls\nF1: UI · T: tuning · R: reset · ↑/↓: pitch\nW/S: thrust · A/D: turn · Q/E: pods\nPad: left stick steer/pitch (back = nose up)\nRight stick pods · triggers thrust"
	controls.add_child(title)
	status_label = Label.new()
	controls.add_child(status_label)
	telemetry = Label.new()
	controls.add_child(telemetry)
	var tuning_button := Button.new()
	tuning_button.text = "Movement tuning (T)"
	tuning_button.focus_mode = Control.FOCUS_NONE
	tuning_button.pressed.connect(_toggle_tuning)
	controls.add_child(tuning_button)
	var sound_button := Button.new()
	sound_button.text = "Sound tuning (F6)"
	sound_button.focus_mode = Control.FOCUS_NONE
	sound_button.pressed.connect(_toggle_sound_tuning)
	controls.add_child(sound_button)
	var mods_button := Button.new()
	mods_button.text = "Mods (F8)"
	mods_button.focus_mode = Control.FOCUS_NONE
	mods_button.pressed.connect(func() -> void: if not world_loading: mod_panel.open())
	controls.add_child(mods_button)
	fog_button = CheckButton.new()
	fog_button.text = "Underwater fog"
	fog_button.button_pressed = true
	fog_button.focus_mode = Control.FOCUS_NONE
	controls.add_child(fog_button)
	fog_label = Label.new()
	controls.add_child(fog_label)
	fog_slider = HSlider.new()
	fog_slider.min_value = MIN_VISIBILITY
	fog_slider.max_value = MAX_VISIBILITY
	fog_slider.step = 1.0
	fog_slider.value = DEFAULT_VISIBILITY
	fog_slider.focus_mode = Control.FOCUS_NONE
	controls.add_child(fog_slider)
	var hint := Label.new()
	hint.text = "Shorter distance = denser fog. Saved on release."
	hint.add_theme_font_size_override("font_size", 12)
	controls.add_child(hint)
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
	controls.add_child(presets)
	for preset in [["Original feel", DEFAULT_VISIBILITY], ["Clearer water", 100.0]]:
		var button := Button.new()
		button.text = preset[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			fog_slider.value = float(preset[1])
			_save_preferences()
		)
		presets.add_child(button)
	var reset := Button.new()
	reset.text = "Reset submarine (R)"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_reset_submarine)
	controls.add_child(reset)
	var choose := Button.new()
	choose.text = "Choose Sub Culture folder…"
	choose.focus_mode = Control.FOCUS_NONE
	choose.pressed.connect(func() -> void:
		if not world_loading: folder_dialog.popup_centered(Vector2i(850, 600))
	)
	controls.add_child(choose)
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
	_add_water_surface()
	await get_tree().physics_frame
	await Creatures.populate(world_root, folder, get_tree(), _progress)
	if pilot == null:
		pilot = Pilot.new()
		pilot.name = "PlayerSubmarine"
		pilot.remember_settings = remember_preferences
		add_child(pilot)
	else: pilot.movement.load_settings(remember_preferences)
	if tuning_panel != null: tuning_panel.free()
	tuning_panel = Tuning.new()
	canvas.add_child(tuning_panel)
	tuning_panel.setup(pilot.movement)
	tuning_panel.dismissed.connect(func() -> void: tuning_panel.visible = false)
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
	pilot.bubbles.configure(Assets._load_texture(folder, "BUBBLE", "BUBBLEM", {}))
	pilot.submarine_audio.setup(pilot, folder)
	if sound_panel != null: sound_panel.free()
	sound_panel = SoundPanel.new()
	canvas.add_child(sound_panel)
	sound_panel.setup(pilot.submarine_audio)
	sound_panel.dismissed.connect(func() -> void: sound_panel.visible = false)
	pilot.active = true
	if docking != null: docking.free()
	docking = Docking.new()
	add_child(docking)
	docking.setup(pilot, world_root, folder, camera)
	if docking_prompt == null: _build_docking_prompt()
	pilot_mode = true
	world_loading = false
	status_label.text = str(world_root.get_meta("scenery_summary", "Piloting ready."))
	loading_canvas.visible = false
	_update_follow_camera(0.0, true)
	_update_water_environment()
	_save_preferences()

func _progress(message: String) -> void:
	loading_label.text = message

func _build_docking_prompt() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 2
	add_child(hud)
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8 and not world_loading:
		mod_panel.open()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		get_window().mode = Window.MODE_WINDOWED if get_window().mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
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
		elif event.keycode == KEY_T: _toggle_tuning()
		elif event.keycode == KEY_F6: _toggle_sound_tuning()
		elif event.keycode == KEY_R: _reset_submarine()
		elif event.keycode == KEY_ESCAPE:
			tuning_panel.visible = false
			sound_panel.stop_preview()
			sound_panel.visible = false
	elif event is InputEventMouseButton and event.pressed:
		var distance := float(pilot.movement.settings.camera_distance)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: tuning_panel.set_camera_distance(distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: tuning_panel.set_camera_distance(distance * 1.1)

func _toggle_developer_ui() -> void:
	developer_ui_visible = not developer_ui_visible
	canvas.visible = developer_ui_visible
	if not developer_ui_visible:
		folder_dialog.hide()
		if tuning_panel != null: tuning_panel.export_dialog.hide()
		if sound_panel != null:
			sound_panel.stop_preview()
			sound_panel.export_dialog.hide()

func _toggle_tuning() -> void:
	if not pilot_mode: return
	sound_panel.stop_preview()
	sound_panel.visible = false
	if not developer_ui_visible:
		developer_ui_visible = true
		canvas.visible = true
		tuning_panel.visible = true
	else: tuning_panel.visible = not tuning_panel.visible

func _toggle_sound_tuning() -> void:
	if not pilot_mode: return
	var opening := not developer_ui_visible or not sound_panel.visible
	developer_ui_visible = true
	canvas.visible = true
	tuning_panel.visible = false
	sound_panel.visible = opening
	if not opening: sound_panel.stop_preview()

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
	pilot.controls_enabled = pilot_mode and not world_loading and not over_ui and not folder_dialog.visible and not mod_panel.visible and not tuning_panel.export_dialog.visible and (sound_panel == null or not sound_panel.export_dialog.visible) and (docking == null or docking.stage == Docking.Stage.IDLE)

func _process(delta: float) -> void:
	if not pilot_mode: return
	if docking != null and docking.camera_frozen():
		camera.global_position = docking.cinematic_camera
		var target := pilot.global_position + Vector3.UP * 0.35
		if camera.global_position.distance_to(target) > 0.01: camera.look_at(target, Vector3.UP)
		camera_was_frozen = true
	else:
		if camera_was_frozen:
			camera_follow.resume(camera.global_position, pilot.global_position + Vector3.UP * 0.35)
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
	var target := pilot.global_position + Vector3.UP * 0.35
	var forward := -pilot.global_basis.z
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

func _load_preferences(path: String = "user://opensubculture.cfg") -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	loading_preferences = true
	var value: Variant = config.get_value("view", "fog_visibility", DEFAULT_VISIBILITY)
	if (value is float or value is int) and is_finite(float(value)):
		fog_slider.value = clampf(float(value), MIN_VISIBILITY, MAX_VISIBILITY)
	var enabled: Variant = config.get_value("view", "fog_enabled", true)
	if enabled is bool: fog_button.button_pressed = enabled
	loading_preferences = false

func _save_preferences(path: String = "user://opensubculture.cfg") -> void:
	if not remember_preferences or loading_preferences: return
	var config := ConfigFile.new()
	config.load(path)
	if not game_folder.is_empty(): config.set_value("game", "folder", game_folder)
	config.set_value("view", "fog_visibility", fog_visibility)
	config.set_value("view", "fog_enabled", fog_button.button_pressed)
	if config.save(path) != OK: status_label.text = "Visibility settings could not be saved."

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
