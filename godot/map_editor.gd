extends HBoxContainer
const World = preload("res://world_loader.gd")
const Scenery = preload("res://scenery_loader.gd")
const Creatures = preload("res://creature_loader.gd")
const Document = preload("res://map_document.gd")
const Wildlife = preload("res://wildlife_population.gd")
const Mods = preload("res://mod_registry.gd")
const SpeciesPreview = preload("res://species_preview.gd")
var species_preview: SubViewportContainer
var folder := ""
var loaded := false
var loading := false
var dirty := false
var document := {}
var save_path := Document.DEFAULT_PATH
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var selected := ""
var list_keys: Array[String] = []
var entity_list: ItemList
var category: OptionButton
var visibility_filter: OptionButton
var search: LineEdit
var status: Label
var fields := {}
var properties: VBoxContainer
var properties_scroll: ScrollContainer
var view: SubViewportContainer
var viewport: SubViewport
var scene: Node3D
var world: Node3D
var camera: Camera3D
var population: Node3D
var markers: Node3D
var selection_outline: MeshInstance3D
var base_nodes := {}
var base_entities := {}
var simulating := false
var fly := false
var move_drag := false
var drag_before := {}
var drag_plane := Plane()
var fly_speed := 20.0
var yaw := 0.0
var pitch := -0.15
var export_dialog: FileDialog
var models: Array[String] = []
func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 240
	add_child(sidebar)
	search = LineEdit.new(); search.placeholder_text = "Find an entity or species…"
	search.text_changed.connect(func(_value: String) -> void: _refresh_list())
	sidebar.add_child(search)
	category = OptionButton.new()
	for name in ["All entities", "Scenery / plants", "Lights", "Wildlife groups", "Creature types"]: category.add_item(name)
	category.item_selected.connect(func(_index: int) -> void: _refresh_list())
	sidebar.add_child(category)
	entity_list = ItemList.new(); entity_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entity_list.item_selected.connect(func(index: int) -> void: select(list_keys[index]))
	entity_list.item_activated.connect(func(_index: int) -> void: frame_selection())
	sidebar.add_child(entity_list)
	var actions := GridContainer.new(); actions.columns = 2; sidebar.add_child(actions)
	button(actions, "Add model", add_model)
	button(actions, "Add light", add_light)
	button(actions, "Add group", add_group)
	button(actions, "New species", add_species)
	button(actions, "Duplicate", duplicate_selection)
	button(actions, "Delete", delete_selection)
	button(actions, "Undo", undo)
	button(actions, "Redo", redo)
	button(actions, "Save map", save_map)
	button(actions, "Export JSON", func() -> void: export_dialog.popup_centered(Vector2i(850, 600)))
	var main := VBoxContainer.new(); main.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add_child(main)
	var toolbar := HFlowContainer.new(); main.add_child(toolbar)
	button(toolbar, "Frame selection (F)", frame_selection)
	button(toolbar, "Snap to seabed", snap_to_floor)
	var preview := CheckButton.new(); preview.text = "Simulate wildlife"
	preview.toggled.connect(func(on: bool) -> void:
		simulating = on
		if population != null: population.set_simulating(on)
	)
	toolbar.add_child(preview)
	button(toolbar, "Reload map", reload_map)
	visibility_filter = OptionButton.new()
	for caption in ["Show everything", "Hide plants", "Hide scenery", "Hide wildlife", "Terrain only"]: visibility_filter.add_item(caption)
	visibility_filter.item_selected.connect(func(_index: int) -> void: _apply_visibility())
	toolbar.add_child(visibility_filter)
	view = SubViewportContainer.new(); view.stretch = true; view.focus_mode = Control.FOCUS_ALL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL; view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.gui_input.connect(_view_input); main.add_child(view)
	viewport = SubViewport.new(); viewport.own_world_3d = true; viewport.size = Vector2i(800, 600)
	view.add_child(viewport)
	scene = Node3D.new(); viewport.add_child(scene)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.12, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.75, 0.8); env.environment.ambient_light_energy = 0.8
	scene.add_child(env)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-45, -30, 0); scene.add_child(light)
	camera = Camera3D.new(); camera.current = true; camera.near = 0.05; camera.far = 2000; scene.add_child(camera)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; main.add_child(status)
	status.text = "Open Map mode to load the world."
	var help := Label.new()
	help.text = "Right mouse + WASD: fly · Q/E: down/up · Shift: faster\nWheel: flight speed · Click: select · Shift-drag: move horizontally"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 12); main.add_child(help)
	var inspector := VBoxContainer.new(); inspector.custom_minimum_size.x = 280; add_child(inspector)
	var heading := Label.new(); heading.text = "Properties"; heading.add_theme_font_size_override("font_size", 22); inspector.add_child(heading)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	properties_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; inspector.add_child(scroll)
	properties = VBoxContainer.new(); properties.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(properties)
	button(inspector, "Apply properties", apply_properties)
	export_dialog = FileDialog.new(); export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE; export_dialog.current_file = "scen1.json"
	export_dialog.filters = PackedStringArray(["*.json ; Map document"])
	export_dialog.file_selected.connect(func(path: String) -> void: status.text = "Map exported." if Document.save(document, path) == OK else "Could not export map.")
	add_child(export_dialog)
func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new(); control.text = text; control.focus_mode = Control.FOCUS_NONE
	control.pressed.connect(action); parent.add_child(control); return control
func open(game_folder: String) -> void:
	if loading or loaded: return
	loading = true; folder = game_folder
	world = await World.load_world(folder.path_join("DATA/SCEN1.BSP"), get_tree(), _progress)
	if world == null: loading = false; status.text = "Could not load map."; return
	scene.add_child(world)
	await World.add_collision(world, get_tree(), _progress)
	await get_tree().physics_frame
	await Scenery.populate(world, folder, get_tree(), _progress)
	await get_tree().physics_frame
	await Creatures.populate(world, folder, get_tree(), _progress)
	var baseline := Document.capture(world)
	base_entities = baseline.entities.duplicate(true)
	for key in base_entities:
		if key != "player_spawn": base_nodes[key] = world.get_node(NodePath(key)).duplicate()
	document = Document.load_active()
	if document.is_empty():
		document = baseline
		_seed_species()
	else:
		for entry in Mods.candidates("map.scen1"):
			if not Document.load_path(entry.path).is_empty(): save_path = entry.path; break
		# Preserve original entries omitted from an override document for editing.
		for key in base_entities:
			if not document.entities.has(key): document.entities[key] = base_entities[key].duplicate(true)
	world.get_node("AmbientFish").free()
	for file in DirAccess.get_files_at(folder.path_join("CLUMPS")):
		if file.get_extension().to_lower() == "dff": models.append(file.get_basename())
	for pack in Mods.packs:
		if not pack.valid or str(pack.id) not in Mods.enabled: continue
		for id in pack.assets:
			if id.begins_with("model.") and not models.has(id): models.append(id)
	models.sort()
	markers = Node3D.new(); markers.name = "EditorMarkers"; scene.add_child(markers)
	selection_outline = MeshInstance3D.new(); scene.add_child(selection_outline)
	selection_outline.material_override = _marker_material(Color(1.0, 0.75, 0.15))
	_sync()
	var spawn: Vector3 = world.get_meta("player_spawn")
	camera.position = spawn + Vector3(0, 12, 22); camera.look_at(spawn)
	pitch = camera.rotation.x; yaw = camera.rotation.y
	loaded = true; loading = false
	_refresh_list(); select("player_spawn")
	status.text = "Map ready. Changes take effect in the game after Save map and restart/reload."
func _progress(message: String) -> void: status.text = message
func _seed_species() -> void:
	for id in Creatures.SPECIES:
		document.species.append({"id": id.to_lower(), "name": id.capitalize(), "model": id, "mobility": "swimming", "group_behaviour": "shoaling", "response": "flee", "speed": 1.3, "detection": 8.0, "scale_min": 100.0, "scale_max": 100.0})
		document.species[-1].merge(Document.POPULATION_DEFAULTS)
		document.species[-1].random_spawn = true
func _exit_tree() -> void:
	for node in base_nodes.values(): node.free()
func reload_map() -> void:
	if loading or folder.is_empty(): return
	if dirty:
		var confirm := ConfirmationDialog.new(); confirm.dialog_text = "Reload the map and discard unsaved changes?"
		confirm.confirmed.connect(func() -> void: _reload(); confirm.queue_free())
		confirm.canceled.connect(confirm.queue_free); add_child(confirm); confirm.popup_centered()
	else: _reload()
func _reload() -> void:
	fly = false; move_drag = false
	if world != null: world.free()
	if markers != null: markers.free()
	if selection_outline != null: selection_outline.free()
	for node in base_nodes.values(): node.free()
	base_nodes.clear(); base_entities.clear(); models.clear(); undo_stack.clear(); redo_stack.clear()
	world = null; markers = null; selection_outline = null; population = null
	loaded = false; dirty = false; selected = ""; document = {}; save_path = Document.DEFAULT_PATH
	entity_list.clear(); fields.clear()
	for child in properties.get_children(): child.free()
	open(folder)
func _marker_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color; material.no_depth_test = true; return material
func _sync() -> void:
	for key in base_nodes:
		if world.get_node_or_null(NodePath(key)) == null:
			var restored: Node3D = base_nodes[key].duplicate()
			var parent := world.get_node_or_null(NodePath(str(key).get_base_dir()))
			if parent != null: parent.add_child(restored)
	if world.has_node("Added"): world.get_node("Added").free()
	Document.apply_entities(world, folder, document)
	if population != null: population.free()
	population = Wildlife.new(); population.name = "AmbientFish"; world.add_child(population)
	population.simulating = simulating; population.setup(world, folder, document)
	for child in markers.get_children(): child.free()
	for group in document.groups: _marker("group:" + group.id, Document.vector(group.position), Color(0.2, 1.0, 0.8))
	for key in document.entities:
		var entry: Dictionary = document.entities[key]
		if not entry.get("deleted", false) and entry.kind in ["light", "player"]: _marker(key, Document.decode(entry.transform).origin, Color(0.65, 0.8, 1.0))
	_update_outline()
func _apply_visibility() -> void:
	if world == null: return
	var mode := visibility_filter.selected
	for key in document.entities:
		var entry: Dictionary = document.entities[key]
		var node := world.get_node_or_null(NodePath(key)) as Node3D
		if node == null: continue
		var plant := str(entry.get("model", "")).to_upper().get_basename().trim_prefix("MODEL.") in ["BUSH1", "BUSH2", "BUSH3", "BUSH4", "REED"]
		node.visible = mode != 4 and not (mode == 1 and plant) and not (mode == 2 and entry.kind == "model")
	if population != null: population.visible = mode not in [3, 4]
	if markers != null:
		for marker in markers.get_children(): marker.visible = mode != 4 and not (mode == 3 and str(marker.get_meta("entity_key")).begins_with("group:"))
func _marker(key: String, point: Vector3, color: Color) -> void:
	var marker := MeshInstance3D.new(); var mesh := SphereMesh.new(); mesh.radius = 0.35; mesh.height = 0.7
	if document.entities.has(key) and document.entities[key].kind == "light": mesh.radius = 0.08; mesh.height = 0.16
	marker.mesh = mesh; marker.material_override = _marker_material(color); marker.position = point
	marker.set_meta("entity_key", key); markers.add_child(marker)
func _refresh_list() -> void:
	if document.is_empty(): return
	entity_list.clear(); list_keys.clear()
	var query := search.text.to_lower()
	for key in document.entities:
		var entry: Dictionary = document.entities[key]
		if entry.get("deleted", false): continue
		if category.selected == 1 and entry.kind != "model": continue
		if category.selected == 2 and entry.kind != "light": continue
		if category.selected >= 3: continue
		if not query.is_empty() and not (str(entry.name) + " " + str(key) + " " + str(entry.get("model", ""))).to_lower().contains(query): continue
		list_keys.append(key)
		entity_list.add_item((str(entry.model) + " · " if str(entry.name).begins_with("Plant_") else "") + str(entry.name))
		entity_list.set_item_tooltip(entity_list.item_count - 1, key)
	if category.selected in [0, 3]:
		for group in document.groups:
			if not query.is_empty() and not str(group.name).to_lower().contains(query): continue
			list_keys.append("group:" + group.id); entity_list.add_item("◇ " + str(group.name))
	if category.selected == 4:
		for species in document.species:
			if not query.is_empty() and not str(species.name).to_lower().contains(query): continue
			list_keys.append("species:" + species.id); entity_list.add_item(str(species.name))
	var index := list_keys.find(selected)
	if index >= 0: entity_list.select(index)
func record(key: String = "") -> Dictionary:
	if key.is_empty(): key = selected
	if key.begins_with("group:"):
		for group in document.groups:
			if group.id == key.trim_prefix("group:"): return group
	elif key.begins_with("species:"):
		for species in document.species:
			if species.id == key.trim_prefix("species:"): return species
	else: return document.entities.get(key, {})
	return {}
func select(key: String) -> void:
	selected = key; fields.clear()
	properties_scroll.scroll_vertical = 0
	species_preview = null
	for child in properties.get_children(): child.free()
	var entry := record()
	if entry.is_empty(): return
	text_field("name", "Name", str(entry.name))
	if key.begins_with("species:"):
		species_preview = SpeciesPreview.new(); properties.add_child(species_preview)
		species_preview.show_model(str(entry.model),folder)
		choice("model", "3D model", models, str(entry.model))
		fields.model.item_selected.connect(func(_index: int) -> void: species_preview.show_model(str(_value("model")),folder))
		var random_spawn := CheckBox.new(); random_spawn.text = "Spawn randomly across the map"
		random_spawn.button_pressed = entry.get("random_spawn",false); properties.add_child(random_spawn); fields.random_spawn = random_spawn
		number("groups_min","Minimum groups",entry.get("groups_min",3),0,100,1)
		number("groups_max","Maximum groups",entry.get("groups_max",8),0,100,1)
		number("count_min","Minimum creatures per group",entry.get("count_min",1),1,100,1)
		number("count_max","Maximum creatures per group",entry.get("count_max",10),1,100,1)
		number("spawn_chance","Group spawn chance (%)",entry.get("spawn_chance",100.0),0,100,1)
		number("roam_radius","Group roaming radius",entry.get("roam_radius",10.0),0.5,1000,0.5)
		choice("mobility", "Mobility", ["swimming", "crawling"], entry.mobility)
		choice("group_behaviour", "Group movement", Document.GROUP_BEHAVIOURS, entry.group_behaviour)
		choice("response", "Response to submarine", Document.RESPONSES, entry.response)
		number("speed", "Movement speed", entry.speed, 0.05, 30, 0.05)
		number("turn_speed", "Maximum turn speed (°/s)", entry.get("turn_speed", 60.0), 1, 180, 1)
		number("pitch_limit", "Maximum swim pitch (°)", entry.get("pitch_limit", 25.0), 0, 60, 1)
		number("detection", "Detection distance", entry.detection, 0.1, 200, 0.1)
		number("startle_duration", "Flee startle duration (s; 0 disables)", entry.get("startle_duration", 0.3), 0, 1, 0.05)
		number("startle_speed_multiplier", "Flee burst speed multiplier", entry.get("startle_speed_multiplier", 2.8), 1.6, 6, 0.1)
		number("startle_turn_speed", "Flee startle turn speed (°/s)", entry.get("startle_turn_speed", 720.0), 180, 1440, 30)
		number("scale_min", "Minimum scale (%)", entry.scale_min, 1, 500, 1)
		number("scale_max", "Maximum scale (%)", entry.scale_max, 1, 500, 1)
	else:
		var pose := Transform3D(Basis.IDENTITY, Document.vector(entry.position)) if key.begins_with("group:") else Document.decode(entry.transform)
		for i in range(3): number("position_" + str(i), "Position " + ["X", "Y", "Z"][i], pose.origin[i], -50000, 50000, 0.1)
		if key.begins_with("group:"):
			var ids: Array = document.species.map(func(species: Dictionary) -> String: return species.id)
			var names: Array = document.species.map(func(species: Dictionary) -> String: return species.name)
			choice("species", "Creature type", ids, entry.species, names)
			number("chance", "Spawn chance (%)", entry.chance, 0, 100, 1)
			number("count_min", "Minimum population", entry.count_min, 1, 100, 1)
			number("count_max", "Maximum population", entry.count_max, 1, 100, 1)
			number("radius", "Roaming radius", entry.radius, 0.5, 1000, 0.5)
			var override := CheckBox.new(); override.text = "Override creature size / behaviour"
			override.button_pressed = entry.has("overrides"); properties.add_child(override); fields.overrides_enabled = override
			var species: Dictionary = document.species.filter(func(item: Dictionary) -> bool: return item.id == entry.species)[0].duplicate(true)
			species.merge(entry.get("overrides", {}), true)
			number("scale_min", "Minimum scale (%)", species.scale_min, 1, 500, 1)
			number("scale_max", "Maximum scale (%)", species.scale_max, 1, 500, 1)
			choice("group_behaviour", "Group movement", Document.GROUP_BEHAVIOURS, species.group_behaviour)
			choice("response", "Response to submarine", Document.RESPONSES, species.response)
		else:
			if entry.kind == "model":
				var original: Node3D = base_nodes.get(key)
				if entry.has("dock") or (original != null and original.has_meta("city_id")): label("Dock model: " + str(entry.model))
				else: choice("model", "3D model", models, str(entry.model))
				for i in range(3): number("rotation_" + str(i), "Rotation " + ["X", "Y", "Z"][i] + " (°)", rad_to_deg(pose.basis.get_euler()[i]), -360, 360, 1)
				for i in range(3): number("scale_" + str(i), "Scale " + ["X", "Y", "Z"][i], pose.basis.get_scale()[i], 0.01, 100, 0.01)
			elif entry.kind == "light":
				number("energy", "Light energy", entry.get("energy", 1), 0, 16, 0.1)
				number("range", "Light range", entry.get("range", 5), 0.1, 1000, 0.1)
				choice("light_mode", "Light style", ["steady", "pulsing", "flashing"], Document.PulseLight.mode_from(entry), ["Steady", "Pulsing", "Flashing"])
				number("pulse_period", "Pulse period (seconds)", entry.get("pulse_period", 2.4), 0.1, 60, 0.1)
				number("pulse_minimum", "Minimum brightness (%)", float(entry.get("pulse_minimum", 0.2)) * 100.0, 0, 100, 1)
				number("flash_on_time", "Flash on time (seconds)", entry.get("flash_on_time", 0.5), 0.05, 60, 0.05)
				number("flash_off_time", "Flash off time (seconds)", entry.get("flash_off_time", 1.0), 0.05, 60, 0.05)
				number("flare_size", "Flare size", entry.get("flare_size", 4.0), 0.1, 100, 0.1)
				fields.light_mode.item_selected.connect(func(_index: int) -> void: _update_light_fields())
				_update_light_fields()
	_refresh_list(); _update_outline()
func _update_light_fields() -> void:
	var mode: String = _value("light_mode")
	for key in ["pulse_period", "pulse_minimum", "flash_on_time", "flash_off_time"]:
		var control: Control = fields[key]
		var shown := mode == ("pulsing" if key.begins_with("pulse_") else "flashing")
		control.visible = shown
		properties.get_child(control.get_index() - 1).visible = shown
func label(text: String) -> void:
	var control := Label.new(); control.text = text; control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; properties.add_child(control)
func text_field(key: String, caption: String, value: String) -> void:
	label(caption); var control := LineEdit.new(); control.text = value; properties.add_child(control); fields[key] = control
func number(key: String, caption: String, value: float, low: float, high: float, step: float) -> void:
	label(caption); var control := SpinBox.new(); control.min_value = low; control.max_value = high; control.step = step; control.value = value
	control.set_meta("original_value", value); control.set_meta("initial_value", control.value)
	properties.add_child(control); fields[key] = control
func choice(key: String, caption: String, options: Array, value: String, display_names: Array = []) -> void:
	label(caption); var control := OptionButton.new(); control.fit_to_longest_item = false
	for index in range(options.size()):
		control.add_item(str(display_names[index]) if index < display_names.size() else str(options[index]))
		control.set_item_metadata(index, str(options[index]))
	control.select(maxi(0, options.find(value))); properties.add_child(control); fields[key] = control
func _value(key: String) -> Variant:
	var control: Control = fields[key]
	if control is CheckBox: return control.button_pressed
	if control is LineEdit: return control.text
	if control is OptionButton: return control.get_item_metadata(control.selected)
	if is_equal_approx(control.value, control.get_meta("initial_value")): return control.get_meta("original_value")
	return control.value
func _remember(before: Dictionary) -> void:
	undo_stack.append(before); if undo_stack.size() > 100: undo_stack.pop_front()
	redo_stack.clear(); dirty = true
func apply_properties() -> void:
	if not loaded or record().is_empty(): return
	var before := document.duplicate(true); var entry := record()
	entry.name = _value("name")
	if selected.begins_with("species:"):
		for key in Document.POPULATION_DEFAULTS: entry[key] = _value(key)
		for key in ["model", "mobility", "group_behaviour", "response", "speed", "turn_speed", "pitch_limit", "detection", "startle_duration", "startle_speed_multiplier", "startle_turn_speed", "scale_min", "scale_max"]: entry[key] = _value(key)
	else:
		var point := Vector3(float(_value("position_0")), float(_value("position_1")), float(_value("position_2")))
		if selected.begins_with("group:"):
			entry.position = Document.array(point)
			for key in ["species", "chance", "count_min", "count_max", "radius"]: entry[key] = _value(key)
			if fields.overrides_enabled.button_pressed:
				entry.overrides = {}
				for key in ["scale_min", "scale_max", "group_behaviour", "response"]: entry.overrides[key] = _value(key)
			else: entry.erase("overrides")
		else:
			var pose := Document.decode(entry.transform); pose.origin = point
			if entry.kind == "model":
				if fields.has("model"): entry.model = _value("model")
				var euler := Vector3(deg_to_rad(_value("rotation_0")), deg_to_rad(_value("rotation_1")), deg_to_rad(_value("rotation_2")))
				var scale_value := Vector3(_value("scale_0"), _value("scale_1"), _value("scale_2"))
				var changed := false
				for key in ["rotation_0", "rotation_1", "rotation_2", "scale_0", "scale_1", "scale_2"]:
					if not is_equal_approx(fields[key].value, fields[key].get_meta("initial_value")): changed = true
				if changed: pose.basis = Basis.from_euler(euler) * Basis.from_scale(scale_value)
			if entry.kind == "light":
				for key in ["energy", "range", "light_mode", "pulse_period", "flare_size", "flash_on_time", "flash_off_time"]: entry[key] = _value(key)
				entry.pulse_minimum = float(_value("pulse_minimum")) / 100.0
				entry.erase("pulse_enabled")
			entry.transform = Document.encode(pose)
	if not Document.valid(document): document = before; status.text = "Invalid properties: check minimum / maximum values."; return
	_remember(before); _sync(); select(selected); status.text = "Properties applied. Save map to keep changes."
func undo() -> void:
	if undo_stack.is_empty(): return
	redo_stack.append(document.duplicate(true)); document = undo_stack.pop_back(); dirty = true; _sync(); _refresh_list(); select(selected)
func redo() -> void:
	if redo_stack.is_empty(): return
	undo_stack.append(document.duplicate(true)); document = redo_stack.pop_back(); dirty = true; _sync(); _refresh_list(); select(selected)
func _new_id() -> String: return "entity_" + str(Time.get_ticks_usec())
func _new_position() -> Vector3: return camera.position - camera.basis.z * 8.0
func add_species() -> void:
	if not loaded: return
	var before := document.duplicate(true); var id := _new_id()
	document.species.append({"id": id, "name": "New creature", "model": "ANGEL", "mobility": "swimming", "group_behaviour": "shoaling", "response": "flee", "speed": 1.3, "detection": 8.0, "scale_min": 100.0, "scale_max": 100.0})
	document.species[-1].merge(Document.POPULATION_DEFAULTS)
	document.species[-1].random_spawn = true
	_remember(before); category.select(4); select("species:" + id)
func add_group() -> void:
	if not loaded or document.species.is_empty(): return
	var before := document.duplicate(true); var id := _new_id()
	var species_id: String = selected.trim_prefix("species:") if selected.begins_with("species:") else str(document.species[0].id)
	document.groups.append({"id": id, "name": "New wildlife group", "species": species_id, "position": Document.array(_new_position()), "count_min": 1, "count_max": 10, "radius": 10.0, "chance": 100.0})
	_remember(before); category.select(3); _sync(); select("group:" + id)
func add_model() -> void:
	if not loaded: return
	# Select a model in the list below, then add it; plants are convenient defaults.
	var dialog := AcceptDialog.new(); dialog.title = "Add a model"
	var option := OptionButton.new()
	for id in models: option.add_item(id)
	option.select(maxi(0, models.find("BUSH1"))); dialog.add_child(option)
	dialog.confirmed.connect(func() -> void: _add_entity("model", option.get_item_text(option.selected)); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); add_child(dialog); dialog.popup_centered(Vector2i(360, 140))
func add_light() -> void: if loaded: _add_entity("light", "")
func _add_entity(kind: String, model_id: String) -> void:
	var pose := Transform3D(Basis.IDENTITY, _new_position())
	if kind == "model":
		var template := Document.load_model(model_id, folder)
		if template == null: status.text = "Could not load that model."; return
		pose.basis = template.basis; template.free()
	var before := document.duplicate(true); var key := "Added/" + _new_id()
	document.entities[key] = {"name": "New light" if kind == "light" else model_id, "kind": kind, "model": model_id, "transform": Document.encode(pose), "solid": kind == "model", "deleted": false, "energy": 1.0, "range": 8.0}
	_remember(before); category.select(0); _sync(); select(key)
func duplicate_selection() -> void:
	if not loaded or record().is_empty(): return
	var before := document.duplicate(true); var entry := record().duplicate(true); var id := _new_id(); entry.name += " copy"
	if selected.begins_with("species:"): entry.id = id; document.species.append(entry); selected = "species:" + id
	elif selected.begins_with("group:"): entry.id = id; entry.position[0] += 2.0; document.groups.append(entry); selected = "group:" + id
	elif entry.kind == "player": status.text = "The map has one player spawn."; return
	else:
		if entry.has("dock"): entry.dock.city_id = Time.get_ticks_usec()
		selected = "Added/" + id; entry.transform[9] += 2.0; document.entities[selected] = entry
	_remember(before); _sync(); select(selected)
func delete_selection() -> void:
	if not loaded or record().is_empty(): return
	if selected == "player_spawn": status.text = "Move the player spawn instead of deleting it."; return
	var before := document.duplicate(true)
	if selected.begins_with("species:"):
		if document.groups.any(func(group: Dictionary) -> bool: return group.species == record().id): status.text = "Remove or reassign this creature's groups first."; return
		document.species.erase(record())
	elif selected.begins_with("group:"): document.groups.erase(record())
	else: record().deleted = true
	_remember(before); selected = ""; _sync(); select(""); _refresh_list()
func save_map() -> void:
	if not loaded: return
	var result := Document.save(document, save_path)
	status.text = "Saved %s. Restart/reload the game to use it." % ProjectSettings.globalize_path(save_path) if result == OK else "Could not save: " + error_string(result)
	if result == OK: dirty = false
func randomise() -> void:
	if not loaded: return
	_remember(document.duplicate(true)); document.seed = int(document.seed) + 1; _sync(); status.text = "New seed previewed. Save map to keep it."
func point(key: String = "") -> Vector3:
	if key.is_empty(): key = selected
	var entry := record(key)
	if entry.is_empty() or key.begins_with("species:"): return Vector3(INF, INF, INF)
	return Document.vector(entry.position) if key.begins_with("group:") else Document.decode(entry.transform).origin
func _move(point_value: Vector3) -> void:
	var entry := record()
	if selected.begins_with("group:"): entry.position = Document.array(point_value)
	else: var pose := Document.decode(entry.transform); pose.origin = point_value; entry.transform = Document.encode(pose)
func snap_to_floor() -> void:
	if not loaded or not point().is_finite(): return
	var query := PhysicsRayQueryParameters3D.create(Vector3(point().x, world.get_meta("surface_height") - 0.1, point().z), Vector3(point().x, world.get_meta("bounds").position.y - 1.0, point().z), 1)
	var exclusions: Array[RID] = []
	for body in world.find_children("SceneryCollision", "StaticBody3D", true, false): exclusions.append(body.get_rid())
	query.exclude = exclusions
	query.hit_back_faces = true
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): status.text = "No seabed beneath this entity."; return
	_remember(document.duplicate(true)); _move(hit.position); _sync(); select(selected)
func frame_selection() -> void:
	if not point().is_finite(): return
	var distance := maxf(8.0, float(record().get("radius", 0.0)) * 2.0)
	camera.position = point() + Vector3(0, distance * 0.5, distance); camera.look_at(point()); yaw = camera.rotation.y; pitch = camera.rotation.x
func _update_outline() -> void:
	if selection_outline == null: return
	selection_outline.visible = point().is_finite()
	_apply_visibility()
	if not selection_outline.visible: return
	var radius := float(record().get("radius", 1.0))
	var mesh := ImmediateMesh.new(); mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for plane_index in range(3):
		for step in range(48):
			for angle in [step * TAU / 48.0, (step + 1) * TAU / 48.0]:
				var vertex := Vector3.ZERO; vertex[plane_index] = cos(angle) * radius; vertex[(plane_index + 1) % 3] = sin(angle) * radius; mesh.surface_add_vertex(vertex)
	mesh.surface_end(); selection_outline.mesh = mesh; selection_outline.position = point()
func _view_input(event: InputEvent) -> void:
	if not loaded: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: fly = event.pressed; view.grab_focus()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: fly_speed = minf(200, fly_speed * 1.2)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: fly_speed = maxf(1, fly_speed / 1.2)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pick(event.position)
				if event.shift_pressed and point().is_finite(): move_drag = true; drag_before = document.duplicate(true); drag_plane = Plane(Vector3.UP, point().y)
			elif move_drag: move_drag = false; _remember(drag_before); _sync(); select(selected)
	elif event is InputEventMouseMotion:
		if fly:
			yaw -= event.relative.x * 0.004; pitch = clampf(pitch - event.relative.y * 0.004, -1.5, 1.5); camera.rotation = Vector3(pitch, yaw, 0)
		elif move_drag:
			var intersection: Variant = drag_plane.intersects_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
			if intersection != null:
				_move(intersection); _update_outline()
				var node := world.get_node_or_null(NodePath(selected)) as Node3D
				if node != null: node.global_position = intersection
func _pick(mouse: Vector2) -> void:
	var closest := ""; var score := 36.0
	var keys: Array = document.entities.keys()
	for group in document.groups: keys.append("group:" + group.id)
	for key in keys:
		var entry := record(key)
		if entry.get("deleted", false): continue
		var location := point(key)
		if not location.is_finite() or camera.is_position_behind(location): continue
		var distance := camera.unproject_position(location).distance_to(mouse)
		if distance < score: score = distance; closest = key
	if not closest.is_empty(): select(closest)
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT: fly = false
		if event.button_index == MOUSE_BUTTON_LEFT and move_drag: move_drag = false; _remember(drag_before); _sync(); select(selected)
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not loaded or not event.pressed: return
	if event.is_action_pressed("editor_frame"): frame_selection()
	elif event.is_action_pressed("editor_undo"): undo()
	elif event.is_action_pressed("editor_redo"): redo()
	elif event.is_action_pressed("editor_save"): save_map()
func _process(delta: float) -> void:
	if not is_visible_in_tree() or not loaded or not fly: return
	var input := Vector3(float(Input.is_action_pressed("turn_right")) - float(Input.is_action_pressed("turn_left")), float(Input.is_action_pressed("thrust_up")) - float(Input.is_action_pressed("thrust_down")), float(Input.is_action_pressed("thrust_reverse")) - float(Input.is_action_pressed("thrust_forward")))
	camera.position += camera.basis * input.normalized() * fly_speed * (3.0 if Input.is_action_pressed("editor_fast") else 1.0) * delta
