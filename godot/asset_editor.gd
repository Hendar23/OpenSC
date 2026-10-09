extends Control

const Assets = preload("res://clump_loader.gd")
const Paths = preload("res://asset_paths.gd")
const MorphAnimation = preload("res://morph_animation.gd")
const Catalog = preload("res://asset_catalog.gd")
const Media = preload("res://media_preview.gd")
const Mods = preload("res://mod_registry.gd")
const ModPanel = preload("res://mod_panel.gd")
const Modern = preload("res://modern_model.gd")
const MapEditor = preload("res://map_editor.gd")
const CreatureAnimation = preload("res://creature_animation.gd")
var creature_animation: RefCounted

var game_folder := ""
var asset_names: Array[String] = []
var filtered_names: Array[String] = []
var selected_name := ""
var model: Node3D
var stage: Node3D
var camera: Camera3D
var viewport: SubViewport
var preview: SubViewportContainer
var asset_list: ItemList
var search: LineEdit
var category: OptionButton
var status: Label
var details: Label
var asset_title: Label
var folder_dialog: FileDialog
var auto_rotate: CheckButton
var animation_button: Button
var animation_speed: HSlider
var animation_speed_label: Label
var animation_status: Label
var animated_meshes: Array[MeshInstance3D] = []
var animation_playing := false
var animation_time := 0.0
var yaw := 0.5
var pitch := 0.2
var distance := 3.0
var base_distance := 3.0
var target := Vector3.ZERO
var dragging := false
var remember_preferences := true
var catalog := {}
var folder_filter: OptionButton
var folder_names: Array[String] = [""]
var media: VBoxContainer
var frame_button: Button
var animation_bar: HBoxContainer
var asset_dialog: FileDialog
var mod_panel: Window
var mods_button: Button
var asset_interface: MarginContainer
var map_editor: HBoxContainer
var map_mode := false
var mount_editor: HBoxContainer

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Mods.ensure(remember_preferences)
	get_window().title = "OpenSubCulture Asset Editor"
	get_window().mode = Window.MODE_FULLSCREEN
	get_window().min_size = Vector2i(1050, 650)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	var folder := Paths.find_game_folder(false)
	if not folder.is_empty(): _load_folder(folder)
	else:
		status.text = "Choose your original Sub Culture folder."
		folder_dialog.popup_centered(Vector2i(850, 600))

func _build_interface() -> void:
	var exit_button := Button.new()
	exit_button.text = "Exit"
	exit_button.focus_mode = Control.FOCUS_NONE
	exit_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	exit_button.offset_left = -96; exit_button.offset_right = -16
	exit_button.offset_top = 5; exit_button.offset_bottom = 37
	exit_button.pressed.connect(func() -> void: get_tree().quit())
	add_child(exit_button)
	var modes := HBoxContainer.new()
	modes.position = Vector2(16, 5)
	add_child(modes)
	for caption in ["Assets", "Map"]:
		var mode_button := Button.new(); mode_button.text = caption; mode_button.focus_mode = Control.FOCUS_NONE
		mode_button.pressed.connect(func() -> void: _set_mode(caption == "Map"))
		modes.add_child(mode_button)
	var mounts_button := Button.new(); mounts_button.text = "Mounts"; mounts_button.focus_mode = Control.FOCUS_NONE
	mounts_button.pressed.connect(_show_mounts); modes.add_child(mounts_button)
	mods_button = Button.new()
	mods_button.text = "Mods"
	mods_button.focus_mode = Control.FOCUS_NONE
	mods_button.pressed.connect(func() -> void: mod_panel.open())
	modes.add_child(mods_button)
	var margin := MarginContainer.new()
	asset_interface = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_top = 42
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 300
	layout.add_child(sidebar)
	var heading := Label.new()
	heading.text = "OpenSubCulture Editor"
	heading.add_theme_font_size_override("font_size", 22)
	sidebar.add_child(heading)
	var caption := Label.new()
	caption.text = "Asset library"
	sidebar.add_child(caption)
	var choose := Button.new()
	choose.text = "Choose game folder…"
	choose.focus_mode = Control.FOCUS_NONE
	choose.pressed.connect(func() -> void: folder_dialog.popup_centered(Vector2i(850, 600)))
	sidebar.add_child(choose)
	var open_file := Button.new()
	open_file.text = "Open asset file…"
	open_file.focus_mode = Control.FOCUS_NONE
	open_file.pressed.connect(func() -> void: asset_dialog.popup_centered(Vector2i(850, 600)))
	sidebar.add_child(open_file)
	search = LineEdit.new()
	search.placeholder_text = "Search assets…"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_query: String) -> void: _filter_assets())
	sidebar.add_child(search)
	category = OptionButton.new()
	category.add_item("All 3D assets")
	category.add_item("Plants")
	category.add_item("All assets")
	category.add_item("Images / BMP")
	category.add_item("Audio / WAV / RAW / music")
	category.add_item("Text / configuration")
	category.add_item("Cutscenes / video")
	category.focus_mode = Control.FOCUS_NONE
	category.item_selected.connect(func(_index: int) -> void: _filter_assets())
	sidebar.add_child(category)
	folder_filter = OptionButton.new()
	folder_filter.focus_mode = Control.FOCUS_NONE
	folder_filter.item_selected.connect(func(_index: int) -> void: _filter_assets())
	sidebar.add_child(folder_filter)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 36
	sidebar.add_child(status)
	asset_list = ItemList.new()
	asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	asset_list.item_selected.connect(_select_asset)
	asset_list.item_activated.connect(_activate_asset)
	sidebar.add_child(asset_list)
	var footer := Label.new()
	footer.text = "Double-click audio or video to play it\nOriginal game files are read directly."
	footer.add_theme_font_size_override("font_size", 12)
	sidebar.add_child(footer)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(main)
	var toolbar := HBoxContainer.new()
	main.add_child(toolbar)
	asset_title = Label.new()
	asset_title.text = "Select an asset"
	asset_title.add_theme_font_size_override("font_size", 22)
	asset_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(asset_title)
	var frame := Button.new()
	frame_button = frame
	frame.text = "Frame asset"
	frame.focus_mode = Control.FOCUS_NONE
	frame.pressed.connect(_frame_model)
	toolbar.add_child(frame)
	auto_rotate = CheckButton.new()
	auto_rotate.text = "Auto orbit"
	auto_rotate.focus_mode = Control.FOCUS_NONE
	toolbar.add_child(auto_rotate)
	preview = SubViewportContainer.new()
	preview.stretch = true
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.mouse_filter = Control.MOUSE_FILTER_STOP
	preview.gui_input.connect(_preview_input)
	main.add_child(preview)
	media = Media.new()
	media.remember_preferences = remember_preferences
	main.add_child(media)
	media.visible = false
	media.summary_changed.connect(func() -> void:
		if details != null and catalog.has(selected_name): details.text = "%s\n%s" % [catalog[selected_name].relative, media.summary]
	)
	viewport = SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.065, 0.085)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.73, 0.77)
	environment.ambient_light_energy = 0.9
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.5
	stage.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, 130, 0)
	fill.light_energy = 0.5
	stage.add_child(fill)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 45.0
	stage.add_child(camera)
	animation_bar = HBoxContainer.new()
	main.add_child(animation_bar)
	animation_button = Button.new()
	animation_button.focus_mode = Control.FOCUS_NONE
	animation_button.pressed.connect(_toggle_animation)
	animation_bar.add_child(animation_button)
	var restart := Button.new()
	restart.text = "Restart"
	restart.focus_mode = Control.FOCUS_NONE
	restart.pressed.connect(func() -> void: animation_time = 0.0; _apply_animation())
	animation_bar.add_child(restart)
	animation_speed_label = Label.new()
	animation_speed_label.custom_minimum_size.x = 105
	animation_bar.add_child(animation_speed_label)
	animation_speed = HSlider.new(); animation_speed.scrollable = false
	animation_speed.min_value = 0.1
	animation_speed.max_value = 3.0
	animation_speed.step = 0.1
	animation_speed.value = 0.5
	animation_speed.custom_minimum_size.x = 140
	animation_speed.value_changed.connect(func(value: float) -> void: animation_speed_label.text = "Speed: %.1f×" % value)
	animation_bar.add_child(animation_speed)
	animation_speed_label.text = "Speed: 0.5×"
	animation_status = Label.new()
	animation_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	animation_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	animation_bar.add_child(animation_status)
	_update_animation_controls()
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.text = "Drag to orbit · Mouse wheel to zoom · Frame asset to reset"
	main.add_child(details)
	folder_dialog = FileDialog.new()
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.title = "Choose your Sub Culture game folder"
	folder_dialog.dir_selected.connect(_load_folder)
	add_child(folder_dialog)
	asset_dialog = FileDialog.new()
	asset_dialog.access = FileDialog.ACCESS_FILESYSTEM
	asset_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	asset_dialog.title = "Open an asset for preview"
	asset_dialog.filters = PackedStringArray(["*.bmp,*.ras,*.png,*.jpg,*.jpeg,*.webp ; Images", "*.wav,*.raw,*.mp3,*.ogg ; Audio", "*.dff,*.glb ; 3D assets", "*.txt,*.csv,*.cfg,*.conf ; Text", "*.smk,*.ogv ; Cutscenes"])
	asset_dialog.file_selected.connect(_open_asset_file)
	add_child(asset_dialog)
	mod_panel = ModPanel.new()
	mod_panel.persist_preferences = remember_preferences
	mod_panel.applied.connect(func() -> void: if not game_folder.is_empty(): _load_folder(game_folder))
	add_child(mod_panel)
	map_editor = MapEditor.new()
	map_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_editor.offset_left = 16; map_editor.offset_right = -16; map_editor.offset_top = 46; map_editor.offset_bottom = -16
	add_child(map_editor); map_editor.visible = false
	mount_editor = preload("res://mount_editor.gd").new()
	mount_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mount_editor.offset_left = 16; mount_editor.offset_right = -16; mount_editor.offset_top = 46; mount_editor.offset_bottom = -16
	add_child(mount_editor); mount_editor.hide()

func _set_mode(on: bool) -> void:
	if mount_editor != null: mount_editor.hide()
	map_mode = on
	asset_interface.visible = not on
	map_editor.visible = on
	if on:
		media._stop_audio()
		if not game_folder.is_empty(): map_editor.open(game_folder)
		else: map_editor.status.text = "Choose the game folder in Assets first."
		if map_editor.population != null: map_editor.population.set_simulating(map_editor.simulating)
	else:
		map_editor.fly = false
		if map_editor.population != null: map_editor.population.set_simulating(false)

func _show_mounts() -> void:
	_set_mode(false); asset_interface.hide(); media._stop_audio(); mount_editor.show()
	if not game_folder.is_empty(): mount_editor.open(game_folder)
	else: mount_editor.status.text = "Choose the game folder in Assets first."

func _open_asset_file(path: String) -> void:
	var extension := path.get_extension().to_lower()
	var kind := "model" if extension in ["dff", "glb"] else "image" if extension in Catalog.IMAGE_EXTENSIONS else "audio" if extension in Catalog.AUDIO_EXTENSIONS else "text" if extension in Catalog.TEXT_EXTENSIONS else "video" if extension in Catalog.VIDEO_EXTENSIONS else ""
	if kind.is_empty(): status.text = "That file format is not supported for preview."; return
	var key := path
	catalog[key] = {"path": path, "relative": path, "folder": "Opened files", "kind": kind}
	if not asset_names.has(key): asset_names.append(key); asset_names.sort()
	if not folder_names.has("Opened files"):
		folder_names.append("Opened files")
		folder_filter.add_item("Opened files")
	selected_name = key
	search.text = ""
	folder_filter.select(0)
	category.select(0 if kind == "model" else 3 if kind == "image" else 4 if kind == "audio" else 6 if kind == "video" else 5)
	_filter_assets()

func _load_folder(folder: String) -> void:
	if not Paths.valid_game_folder(folder, false):
		status.text = "Could not find CLUMPS/SUB.DFF in that folder."
		return
	game_folder = folder
	if map_editor != null and map_editor.loaded:
		map_editor.folder = folder
		map_editor.status.text = "Folder or mods refreshed. Use Reload map to refresh this map view."
	asset_names.clear()
	catalog = Catalog.index(folder)
	var folders := {}
	for name in catalog:
		asset_names.append(name)
		folders[catalog[name].folder] = true
	asset_names.sort()
	folder_filter.clear()
	folder_filter.add_item("All folders")
	folder_names = [""]
	var sorted_folders: Array = folders.keys()
	sorted_folders.sort()
	for name in sorted_folders:
		folder_names.append(name)
		folder_filter.add_item("Root files" if str(name).is_empty() else str(name))
	folder_filter.select(0)
	_filter_assets()
	if remember_preferences:
		var preferences := preload("res://player_storage.gd").preferences_path()
		preload("res://player_storage.gd").ensure_parent(preferences)
		var config := ConfigFile.new()
		config.load(preferences)
		config.set_value("game", "folder", folder)
		config.save(preferences)

func _filter_assets() -> void:
	asset_list.clear()
	filtered_names.clear()
	var query := search.text.strip_edges().to_upper()
	for name in asset_names:
		var entry: Dictionary = catalog[name]
		if not query.is_empty() and not str(entry.relative).to_upper().contains(query): continue
		if category.selected == 0 and entry.kind != "model": continue
		if category.selected == 1 and (entry.kind != "model" or not is_plant(name)): continue
		if category.selected >= 3 and entry.kind != ["image", "audio", "text", "video"][category.selected - 3]: continue
		if folder_filter.selected > 0 and entry.folder != folder_names[folder_filter.selected]: continue
		filtered_names.append(name)
		asset_list.add_item(name)
		asset_list.set_item_tooltip(asset_list.item_count - 1, entry.relative)
	status.text = "%d of %d assets" % [filtered_names.size(), asset_names.size()]
	if filtered_names.is_empty():
		_clear_selection()
		asset_title.text = "No matching assets"
		details.text = "Change the search or filters to browse the library."
		return
	var index := filtered_names.find(selected_name)
	if index < 0: index = 0
	asset_list.select(index)
	_select_asset(index)

static func is_plant(name: String) -> bool:
	return name.get_basename().to_upper() in ["REED", "BUSH1", "BUSH2", "BUSH3", "BUSH4"]

func _activate_asset(index: int) -> void:
	if index < 0 or index >= filtered_names.size(): return
	var name: String = filtered_names[index]
	if catalog[name].kind == "video":
		if selected_name != name: _select_asset(index)
		media.video_preview.toggle_playback()
		return
	if catalog[name].kind != "audio": return
	if selected_name != name: _select_asset(index)
	media._stop_audio()
	media._toggle_audio()

func _select_asset(index: int) -> void:
	if index < 0 or index >= filtered_names.size(): return
	asset_list.select(index)
	asset_list.ensure_current_is_visible()
	selected_name = filtered_names[index]
	_clear_selection()
	var entry: Dictionary = catalog[selected_name]
	asset_title.text = selected_name
	if entry.kind != "model":
		media.visible = true
		media.show_asset(entry.path, entry.kind)
		details.text = "%s\n%s" % [entry.relative, media.summary]
		return
	preview.visible = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	frame_button.visible = true
	auto_rotate.visible = true
	animation_bar.visible = true
	var loaded: Node3D = Modern.load_model(entry.path, entry.get("descriptor", {})) if str(entry.path).get_extension().to_lower() == "glb" else Assets.load_clump(entry.path, PackedStringArray(), true)
	if loaded == null:
		_update_animation_controls()
		details.text = "This asset could not be decoded. See the Godot output for details."
		return
	model = loaded
	stage.add_child(model)
	_collect_animated_meshes(model)
	animation_playing = creature_animation.has_animation()
	_update_animation_controls()
	_frame_model()
	var stats := {"meshes": 0, "triangles": 0}
	_mesh_stats(model, stats)
	details.text = "%s · Parts: %d · Triangles: %d\nDrag to orbit · Mouse wheel to zoom · Frame asset to reset" % [entry.relative, stats.meshes, stats.triangles]
	if model.has_meta("asset_mod"): details.text += "\nReplacement from: " + str(model.get_meta("asset_mod"))

func _clear_selection() -> void:
	creature_animation = null
	animated_meshes.clear()
	animation_time = 0.0
	animation_playing = false
	if model != null:
		model.free()
		model = null
	media.clear()
	media.visible = false
	preview.visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	frame_button.visible = false
	auto_rotate.visible = false
	animation_bar.visible = false
	dragging = false
	_update_animation_controls()

func _frame_model() -> void:
	if model == null: return
	var boxes: Array[AABB] = []
	_bounds(model, Transform3D.IDENTITY, boxes)
	if boxes.is_empty(): return
	var bounds := boxes[0]
	for index in range(1, boxes.size()): bounds = bounds.merge(boxes[index])
	target = bounds.get_center()
	var radius := maxf(0.03, bounds.size.length() * 0.5)
	base_distance = radius / sin(deg_to_rad(camera.fov * 0.5)) * 1.15
	distance = base_distance
	yaw = 0.5
	pitch = 0.2
	camera.near = maxf(0.0001, radius * 0.001)
	camera.far = maxf(100.0, radius * 100.0)
	_update_camera()

static func _bounds(node: Node3D, pose: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D: boxes.append(pose * node.mesh.get_aabb())
	for child in node.get_children():
		if child is Node3D: _bounds(child, pose * child.transform, boxes)

static func _mesh_stats(node: Node, stats: Dictionary) -> void:
	if node is MeshInstance3D:
		stats.meshes += 1
		stats.triangles += node.mesh.get_faces().size() / 3
	for child in node.get_children(): _mesh_stats(child, stats)

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(base_distance * 0.1, distance * 0.9)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(base_distance * 10.0, distance * 1.1)
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.008
		pitch = clampf(pitch + event.relative.y * 0.008, -1.4, 1.4)
	_update_camera()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed: dragging = false

func _process(delta: float) -> void:
	if map_mode or (mount_editor != null and mount_editor.visible): return
	if animation_playing:
		animation_time += delta * animation_speed.value
		_apply_animation()
	if model != null and auto_rotate != null and auto_rotate.button_pressed:
		yaw += delta * 0.35
		_update_camera()

func _collect_animated_meshes(node: Node) -> void:
	creature_animation = CreatureAnimation.new(node as Node3D)
	animated_meshes = creature_animation.meshes

func _toggle_animation() -> void:
	if creature_animation == null or not creature_animation.has_animation(): return
	animation_playing = not animation_playing
	_update_animation_controls()

func _update_animation_controls() -> void:
	var available: bool = creature_animation != null and creature_animation.has_animation()
	animation_button.disabled = not available
	animation_button.text = "Pause" if animation_playing else "Play"
	animation_speed.editable = available
	if not available:
		animation_status.text = "No animation in this asset"
	elif not creature_animation.parts.is_empty():
		animation_status.text = "Procedural turtle swim · %d moving parts" % creature_animation.parts.size()
	else:
		var count := 0
		for instance in animated_meshes: count = maxi(count, instance.mesh.get_blend_shape_count() + 1)
		animation_status.text = "%d poses · Preview timing" % count
		animation_status.tooltip_text = "Loops the stored poses in file order. Original timing and sequence are not yet decoded."

func _apply_animation() -> void:
	if creature_animation != null: creature_animation.apply(animation_time)

func _update_camera() -> void:
	if camera == null: return
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target, Vector3.UP)
