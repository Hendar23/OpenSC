extends HBoxContainer
const Bindings = preload("res://input_bindings.gd")
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
var gameplay_catalogue := {}
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
var objects: Node3D
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
var drag_vertical := false
var drag_origin := Vector3.ZERO
var drag_mouse := Vector2.ZERO
var drag_units_per_pixel := 0.01
var fly_speed := 20.0
var yaw := 0.0
var pitch := -0.15
var export_dialog: FileDialog
var models: Array[String] = []
func _ready() -> void:
	Bindings.install_editor()
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 240
	add_child(sidebar)
	search = LineEdit.new(); search.placeholder_text = "Find an entity or species…"
	search.text_changed.connect(func(_value: String) -> void: _refresh_list())
	sidebar.add_child(search)
	category = OptionButton.new()
	for name in ["All entities", "Scenery / plants", "Lights", "Wildlife groups", "Creature types", "Object groups", "Object types"]: category.add_item(name)
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
	button(actions, "Add object group", add_object_group)
	button(actions, "New object type", add_object_type)
	button(actions, "Add drop-off point", func() -> void: if loaded: _add_entity("dropoff", ""))
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
	button(toolbar, "Use current view for menu", capture_menu_camera)
	button(toolbar, "View menu camera", view_menu_camera)
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
	help.text = "Right mouse + WASD: fly · Q/E: down/up · Shift: faster\nWheel: flight speed · Click: select · Shift-drag: horizontal move · Ctrl+Shift-drag: vertical move"
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
func capture_menu_camera() -> void:
	if not loaded: return
	var before := document.duplicate(true)
	document.menu_camera = {"transform":Document.encode(camera.transform),"fov":camera.fov}
	_remember(before)
	status.text = "Menu camera captured. Save map to keep this view."
func view_menu_camera() -> void:
	if not loaded: return
	if not document.has("menu_camera"):
		status.text = "No menu camera has been captured."
		return
	camera.transform = Document.decode(document.menu_camera.transform); camera.fov = float(document.menu_camera.fov)
	yaw = camera.rotation.y; pitch = camera.rotation.x
func open(game_folder: String) -> void:
	if loading or loaded: return
	loading = true; folder = game_folder
	gameplay_catalogue = preload("res://original_game_data.gd").load_catalogue(folder)
	world = await World.load_world(folder.path_join("DATA/SCEN1.BSP"), get_tree(), _progress)
	if world == null: loading = false; status.text = "Could not load map."; return
	scene.add_child(world)
	await World.add_collision(world, get_tree(), _progress)
	await get_tree().physics_frame
	await Scenery.populate(world, folder, get_tree(), _progress)
	await get_tree().physics_frame
	await Creatures.populate(world, folder, get_tree(), _progress)
	var baseline := Document.capture(world,gameplay_catalogue)
	base_entities = baseline.entities.duplicate(true)
	for key in base_entities:
		if key != "player_spawn": base_nodes[key] = world.get_node(NodePath(key)).duplicate()
	# Mod-added species belong to their pack, not the editable map document.
	document = Document.load_active(false)
	if document.is_empty():
		document = baseline
		_seed_species()
	else:
		for entry in Mods.candidates("map.scen1"):
			if not Document.load_path(entry.path).is_empty(): save_path = entry.path; break
		# Preserve original entries omitted from an override document for editing.
		for key in base_entities:
			if not document.entities.has(key): document.entities[key] = base_entities[key].duplicate(true)
	preload("res://object_definitions.gd").ensure(document)
	world.get_node("AmbientFish").free()
	for file in DirAccess.get_files_at(folder.path_join("CLUMPS")):
		if file.get_extension().to_lower() == "dff": models.append(file.get_basename())
	for pack in Mods.packs:
		if not pack.valid or str(pack.id) not in Mods.enabled: continue
		for id in pack.assets:
			if id.begins_with("model."):
				var model_id := str(id).trim_prefix("model.")
				if not models.has(model_id): models.append(model_id)
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
		document.species.append({"id": id.to_lower(), "name": id.capitalize(), "model": id, "mobility": "swimming", "group_behaviour": "shoaling", "response": "flee", "speed": 1.3, "attack_range": 8.0, "flee_range": 4.0, "scale_min": 100.0, "scale_max": 100.0})
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
	world = null; markers = null; selection_outline = null; population = null; objects = null
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
	preload("res://original_game_data.gd").apply_city_names(world,gameplay_catalogue)
	for key in document.entities:
		var entity := world.get_node_or_null(NodePath(str(key)))
		if entity != null and entity.has_meta("city_id"):
			document.entities[key].name = str(entity.get_meta("city_name"))
	if population != null: population.free()
	population = Wildlife.new(); population.name = "AmbientFish"; world.add_child(population)
	population.gameplay_catalogue = gameplay_catalogue
	population.simulating = simulating; population.setup(world, folder, document)
	if objects != null: objects.free()
	objects = preload("res://object_population.gd").new(); objects.name = "MapObjects"; world.add_child(objects)
	objects.setup(folder,document,false)
	for child in markers.get_children(): child.free()
	for group in document.get("object_groups",[]): _marker("object_group:" + group.id,Document.vector(group.position),Color(1.0,0.4,0.2))
	for group in document.groups: _marker("group:" + group.id, Document.vector(group.position), Color(0.2, 1.0, 0.8))
	for key in document.entities:
		var entry: Dictionary = document.entities[key]
		if not entry.get("deleted", false) and entry.kind in ["light", "player", "dropoff"]: _marker(key, Document.decode(entry.transform).origin, Color(0.65, 0.8, 1.0))
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
	if objects != null: objects.visible = mode != 4
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
		if category.selected >= 3 and not (category.selected == 5 and entry.kind == "dropoff"): continue
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
	if category.selected in [0,5]:
		for group in document.get("object_groups",[]):
			if not query.is_empty() and not str(group.name).to_lower().contains(query): continue
			list_keys.append("object_group:" + group.id); entity_list.add_item("Object group: " + str(group.name))
	if category.selected == 6:
		for entry in document.get("object_types",[]):
			if not query.is_empty() and not str(entry.name).to_lower().contains(query): continue
			list_keys.append("object_type:" + entry.id); entity_list.add_item(str(entry.name))
	var index := list_keys.find(selected)
	if index >= 0: entity_list.select(index)
func record(key: String = "") -> Dictionary:
	if key.is_empty(): key = selected
	if key.begins_with("object_group:") or key.begins_with("object_type:"):
		for entry in document.get("object_groups" if key.begins_with("object_group:") else "object_types",[]):
			if entry.id == key.get_slice(":",1): return entry
	elif key.begins_with("group:"):
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
	if key.begins_with("object_type:"):
		species_preview = SpeciesPreview.new(); properties.add_child(species_preview)
		species_preview.show_object(entry,folder)
		choice("behavior","Object behavior",["mine","thorium","salvage","clam","pearl"],entry.get("behavior","mine"),["Floating mine","Thorium crystal","Salvage object","Clam","Pearl"])
		if entry.get("behavior","mine") in ["thorium","salvage","pearl"]:
			var compatible := CheckBox.new(); compatible.text = "Magnet compatible"; compatible.button_pressed = bool(entry.get("magnet_compatible",entry.get("behavior","") == "salvage"))
			properties.add_child(compatible); fields.magnet_compatible = compatible
			var grapple_compatible := CheckBox.new(); grapple_compatible.text = "Grapple compatible"; grapple_compatible.button_pressed = bool(entry.get("grapple_compatible",entry.get("behavior","") == "thorium" or entry.get("id","") == "cigarette_end"))
			properties.add_child(grapple_compatible); fields.grapple_compatible = grapple_compatible
			var commodity_ids: Array = [""]; var commodity_names: Array = ["None"]
			for commodity in gameplay_catalogue.get("tables",{}).get("commodity_text",{}).get("records",{}).values():
				commodity_ids.append(str(commodity.id).to_lower()); commodity_names.append(str(commodity.get("Display name",commodity.id)))
			var delivery := Document.ObjectDefinitions.delivery_defaults(entry)
			var commodity_id := str(entry.get("delivery_commodity",delivery.commodity))
			if not commodity_ids.has(commodity_id): commodity_ids.append(commodity_id); commodity_names.append(commodity_id)
			choice("delivery_commodity","Drop-off commodity",commodity_ids,commodity_id,commodity_names)
			number("delivery_quantity","Commodity units per delivered object",entry.get("delivery_quantity",delivery.quantity),0,999999,1)
		choice("appearance","Appearance",["sprite","model"],entry.appearance,["Billboard image","3D model"])
		text_field("texture","Image asset (texture ID / BMP name)",entry.texture)
		text_field("mask","Original transparency mask",entry.mask)
		choice("model","3D model",models,str(entry.model))
		fields.appearance.item_selected.connect(func(_index: int) -> void: _update_object_preview())
		fields.model.item_selected.connect(func(_index: int) -> void: _update_object_preview())
		fields.texture.text_submitted.connect(func(_text: String) -> void: _update_object_preview())
		number("size","Size (maximum diameter)",entry.size,0.01,1000,0.05)
		if entry.get("behavior","mine") in ["mine","thorium"]: number("health","Health",entry.health,0.01,100000,0.1)
		if entry.get("behavior","mine") == "thorium":
			number("mass","Crystal mass",entry.get("mass",2.0),0.01,1000,0.1)
			number("shard_mass","Shard mass",entry.get("shard_mass",1.0),0.01,1000,0.1)
			number("shard_scale_percent","Shard size (% of original model)",entry.get("shard_scale_percent",100.0),0.1,1000,1)
			for index in range(1,4): choice("shard" + str(index),"Shard " + str(index) + " model",models,str(entry.get("shard" + str(index),"SHARD" + str(index))))
			number("radiation_range","Radiation range",entry.get("radiation_range",1.5),0,100,0.1)
			number("radiation_strength","Radiation damage at 1 unit (shield points/second)",entry.get("radiation_strength",5.0),0,1000,0.1)
			number("glow_energy","Yellow light strength (0 disables)",entry.get("glow_energy",1.0),0,100,0.1)
			number("glow_range","Glow light range",entry.get("glow_range",3.0),0,100,0.1)
			number("glow_emission","Model glow strength (0 disables)",entry.get("glow_emission",0.25),0,100,0.05)
			for channel in ["red","green","blue"]: number("glow_" + channel,"Glow " + channel,entry.get("glow_" + channel,Document.ObjectDefinitions.THORIUM["glow_" + channel]),0,1,0.01)
			number("spawn_chance","Random drop chance per minute (%)",entry.get("spawn_chance",0.0),0,100,1)
			number("maximum_population","Maximum crystal/shard population",entry.get("maximum_population",60),0,5000,1)
		elif entry.get("behavior","mine") == "clam":
			text_field("pearl_type","Pearl object type",str(entry.get("pearl_type","pearl")))
			for row in [["close_distance","Close when sub is nearer than",0.01,10,0.01],["regrowth_seconds","Pearl regrowth (seconds)",1,86400,1],["opening_speed","Opening speed (degrees/second)",1,1000,1],["closing_speed","Closing speed (degrees/second)",1,2000,1],["open_angle","Open angle (degrees)",0,180,1],["closed_angle","Closed angle (degrees)",0,180,1],["pearl_height","Pearl height inside clam",0,10,0.01],["release_distance","Pearl release distance",0.01,10,0.01]]:
				number(row[0],row[1],entry.get(row[0],Document.ObjectDefinitions.CLAM[row[0]]),row[2],row[3],row[4])
		elif entry.get("behavior","mine") == "pearl":
			number("mass","Pearl mass",entry.get("mass",1),0.01,1000,0.1)
			text_field("pickup_commodity","Suck-O-Matic commodity",str(entry.get("pickup_commodity","pearls")))
		elif entry.get("behavior","mine") == "salvage":
			number("mass","Object mass",entry.get("mass",2.0),0.01,1000,0.1)
			number("spawn_chance","Random drop chance per minute (%)",entry.get("spawn_chance",100.0),0,100,1)
			number("maximum_population","Maximum population of this type",entry.get("maximum_population",20),0,5000,1)
		else:
			number("damage","Explosion damage",entry.damage,0,100000,0.1)
			number("explosion_radius","Explosion radius",entry.explosion_radius,0,1000,0.1)
			number("blast_force","Blast impulse (N.s)",entry.get("blast_force",300.0),0,100000,10)
			number("trigger_distance","Trigger distance from submarine centre (0 disables)",entry.trigger_distance,0,1000,0.1)
	elif key.begins_with("object_group:"):
		for i in range(3): number("position_" + str(i),"Position " + ["X","Y","Z"][i],entry.position[i],-50000,50000,0.1)
		var ids: Array = document.object_types.map(func(item: Dictionary) -> String: return item.id)
		var names: Array = document.object_types.map(func(item: Dictionary) -> String: return item.name)
		choice("type","Object type",ids,entry.type,names)
		number("count","Number in this group",entry.count,1,100,1)
		number("radius","Group scatter radius",entry.radius,0,1000,0.1)
		var type: Dictionary = document.object_types.filter(func(item: Dictionary) -> bool: return item.id == entry.type)[0]
		if type.get("behavior","") == "clam":
			number("initial_delay","First pearl delay (seconds; 0 = ready)",entry.get("initial_delay",0),0,86400,1)
		for axis in range(3): number("group_rotation_" + str(axis),"Rotation " + ["X","Y","Z"][axis] + " (°)",entry.get("rotation",[0,0,0])[axis],-360,360,1)
		label("One object sits at the group centre; multiple objects scatter within the radius. Positions repeat from the map seed.")
	elif key.begins_with("species:"):
		species_preview = SpeciesPreview.new(); properties.add_child(species_preview)
		species_preview.show_model(str(entry.model),folder)
		species_preview.animation_speed = float(entry.get("animation_speed",1.0))
		choice("model", "3D model", models, str(entry.model))
		fields.model.item_selected.connect(func(_index: int) -> void: _update_species_model())
		number("health", "Health", Document.creature_health(entry,gameplay_catalogue),0.1,100000,0.1)
		fields.health.allow_greater = true
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
		var combat := Document.creature_combat(entry)
		choice("food_role","Wildlife role",Document.FOOD_ROLES,combat.food_role)
		var armed := CheckBox.new(); armed.text = "Has zapper"; armed.button_pressed = combat.has_zapper
		properties.add_child(armed); fields.has_zapper = armed
		number("bite_damage","Bite damage",combat.bite_damage,0,10000,0.5)
		number("attack_interval","Time between bites (s)",combat.attack_interval,0.05,60,0.05)
		number("bite_range","Bite reach beyond body",combat.bite_range,0,100,0.05)
		number("zapper_range","Zapper range",combat.zapper_range,0,200,0.1)
		number("zapper_damage","Zapper damage per second",combat.zapper_damage,0,10000,0.5)
		number("speed", "Movement speed", entry.speed, 0.05, 30, 0.05)
		number("animation_speed","Animation speed (×)",entry.get("animation_speed",1.0),0,10,0.1)
		fields.animation_speed.value_changed.connect(func(value: float) -> void: species_preview.animation_speed = value)
		number("turn_speed", "Maximum turn speed (°/s)", entry.get("turn_speed", 60.0), 1, 180, 1)
		number("pitch_limit", "Maximum swim pitch (°)", entry.get("pitch_limit", 25.0), 0, 60, 1)
		var ranges := Document.creature_ranges(entry)
		number("flee_range", "Flee range", ranges.flee_range, 0.01, 200, 0.01)
		number("attack_range", "Attack detection range", ranges.attack_range, 0.01, 200, 0.01)
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
			elif entry.kind == "player":
				number("facing", "Facing (° clockwise)", fposmod(-rad_to_deg(atan2(pose.basis.z.x,pose.basis.z.z)),360.0), 0, 360, 1)
			elif entry.kind == "dropoff":
				number("radius", "Detection radius", entry.radius, 0.01, 1000, 0.01)
			elif entry.kind == "light":
				for i in range(3): number("rotation_" + str(i), "Rotation " + ["X", "Y", "Z"][i] + " (°)", rad_to_deg(pose.basis.get_euler()[i]), -360, 360, 1)
				choice("light_type", "Light type", ["beacon", "searchlight"], entry.get("light_type", "beacon"), ["Beacon / flare", "Searchlight"])
				for setting in Document.Searchlight.DEFAULTS:
					var caption: String = {"sweep_speed":"Sweep speed (°/s)", "sweep_angle":"Sweep half-angle (°)", "beam_length":"Beam length", "beam_width":"Beam end width", "beam_brightness":"Beam brightness", "beam_softness":"Beam softness", "day_brightness":"Daytime brightness multiplier"}[setting]
					var limits: Array = {"sweep_speed":[0,180,1], "sweep_angle":[0,180,1], "beam_length":[0.1,100,0.1], "beam_width":[0.02,50,0.02], "beam_brightness":[0,4,0.05], "beam_softness":[0.05,1,0.05], "day_brightness":[0,1,0.05]}[setting]
					number(setting, caption, entry.get(setting, Document.Searchlight.DEFAULTS[setting]), limits[0], limits[1], limits[2])
				number("energy", "Light energy", entry.get("energy", 1), 0, 16, 0.1)
				number("range", "Light range", entry.get("range", 5), 0.1, 1000, 0.1)
				choice("light_mode", "Light style", ["steady", "pulsing", "flashing"], Document.PulseLight.mode_from(entry), ["Steady", "Pulsing", "Flashing"])
				number("pulse_period", "Pulse period (seconds)", entry.get("pulse_period", 2.4), 0.1, 60, 0.1)
				number("pulse_minimum", "Minimum brightness (%)", float(entry.get("pulse_minimum", 0.2)) * 100.0, 0, 100, 1)
				number("flash_on_time", "Flash on time (seconds)", entry.get("flash_on_time", 0.5), 0.05, 60, 0.05)
				number("flash_off_time", "Flash off time (seconds)", entry.get("flash_off_time", 1.0), 0.05, 60, 0.05)
				number("flare_size", "Flare size", entry.get("flare_size", 4.0), 0.1, 100, 0.1)
				fields.light_mode.item_selected.connect(func(_index: int) -> void: _update_light_fields())
				fields.light_type.item_selected.connect(func(_index: int) -> void: _update_light_fields())
				_update_light_fields()
	_refresh_list(); _update_outline()
func _update_light_fields() -> void:
	var mode: String = _value("light_mode")
	var searchlight: bool = _value("light_type") == "searchlight"
	var keys: Array = Document.Searchlight.DEFAULTS.keys() + ["energy", "range", "light_mode", "pulse_period", "pulse_minimum", "flare_size", "flash_on_time", "flash_off_time"]
	for key in keys:
		var control: Control = fields[key]
		var shown: bool = searchlight if key in Document.Searchlight.DEFAULTS else not searchlight
		if key in ["pulse_period", "pulse_minimum", "flash_on_time", "flash_off_time"]: shown = shown and mode == ("pulsing" if key.begins_with("pulse_") else "flashing")
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
func _update_object_preview() -> void:
	var entry := record().duplicate(true)
	for key in ["appearance","texture","mask","model","size"]: entry[key] = _value(key)
	species_preview.show_object(entry,folder)
func _update_species_model() -> void:
	species_preview.show_model(str(_value("model")),folder)
	if not record().has("health") and is_equal_approx(fields.health.value,fields.health.get_meta("initial_value")):
		var value := Document.creature_health({"model":str(_value("model"))},gameplay_catalogue)
		fields.health.value = value
		fields.health.set_meta("original_value",value); fields.health.set_meta("initial_value",fields.health.value)
func choice(key: String, caption: String, options: Array, value: String, display_names: Array = []) -> void:
	label(caption); var control := OptionButton.new(); control.fit_to_longest_item = false
	for index in range(options.size()):
		control.add_item(str(display_names[index]) if index < display_names.size() else str(options[index]))
		control.set_item_metadata(index, str(options[index]))
	var selected_index := options.find(value)
	if selected_index < 0:
		# Preserve identifiers missing from the current list, including assets
		# supplied by an inactive mod, instead of silently choosing another asset.
		selected_index = control.item_count
		control.add_item(value); control.set_item_metadata(selected_index,value)
	control.select(selected_index); properties.add_child(control); fields[key] = control
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
	if selected.begins_with("object_type:"):
		for key in ["delivery_commodity","delivery_quantity","pearl_type","pearl_height","close_distance","open_angle","closed_angle","opening_speed","closing_speed","regrowth_seconds","release_distance","pickup_commodity"]:
			if fields.has(key): entry[key] = _value(key)
		for key in ["behavior","magnet_compatible","grapple_compatible","appearance","texture","mask","model","size","health","damage","explosion_radius","trigger_distance","blast_force","mass","shard_mass","shard_scale_percent","shard1","shard2","shard3","radiation_range","radiation_strength","glow_energy","glow_range","glow_emission","glow_red","glow_green","glow_blue","spawn_chance","maximum_population"]:
			if fields.has(key): entry[key] = _value(key)
		if entry.behavior == "thorium":
			for key in Document.ObjectDefinitions.THORIUM:
				if not entry.has(key): entry[key] = Document.ObjectDefinitions.THORIUM[key]
		if entry.behavior == "salvage":
			for key in Document.ObjectDefinitions.SALVAGE:
				if not entry.has(key): entry[key] = Document.ObjectDefinitions.SALVAGE[key]
		for defaults in [Document.ObjectDefinitions.CLAM,Document.ObjectDefinitions.PEARL]:
			if entry.behavior == defaults.behavior:
				for key in defaults:
					if not entry.has(key): entry[key] = defaults[key]
	elif selected.begins_with("object_group:"):
		entry.position = [_value("position_0"),_value("position_1"),_value("position_2")]
		for key in ["type","count","radius"]: entry[key] = _value(key)
		if fields.has("initial_delay"): entry.initial_delay = _value("initial_delay")
		var changed_rotation := false
		for axis in range(3):
			var field: Range = fields["group_rotation_" + str(axis)]
			if not is_equal_approx(field.value,field.get_meta("initial_value")): changed_rotation = true
		if changed_rotation: entry.rotation = [_value("group_rotation_0"),_value("group_rotation_1"),_value("group_rotation_2")]
	elif selected.begins_with("species:"):
		# Viewing/applying other properties should preserve the imported default.
		if entry.has("health") or not is_equal_approx(fields.health.value,fields.health.get_meta("initial_value")): entry.health = _value("health")
		entry.erase("detection")
		for key in Document.POPULATION_DEFAULTS: entry[key] = _value(key)
		entry.food_role = _value("food_role"); entry.has_zapper = fields.has_zapper.button_pressed
		for combat_key in Document.COMBAT_DEFAULTS: entry[combat_key] = _value(combat_key)
		for key in ["model", "mobility", "group_behaviour", "response", "speed", "animation_speed", "turn_speed", "pitch_limit", "flee_range", "attack_range", "startle_duration", "startle_speed_multiplier", "startle_turn_speed", "scale_min", "scale_max"]: entry[key] = _value(key)
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
			if entry.kind == "player" and not is_equal_approx(fields.facing.value,fields.facing.get_meta("initial_value")):
				pose.basis = Basis(Vector3.UP,-deg_to_rad(float(_value("facing"))))
			if entry.kind == "dropoff": entry.radius = _value("radius")
			if entry.kind == "light":
				entry.light_type = _value("light_type")
				var changed := false
				for i in range(3):
					var control: SpinBox = fields["rotation_" + str(i)]
					if not is_equal_approx(control.value, control.get_meta("initial_value")): changed = true
				if changed: pose.basis = Basis.from_euler(Vector3(deg_to_rad(_value("rotation_0")), deg_to_rad(_value("rotation_1")), deg_to_rad(_value("rotation_2")))) * Basis.from_scale(pose.basis.get_scale())
				if entry.light_type == "searchlight":
					for key in Document.Searchlight.DEFAULTS: entry[key] = _value(key)
				else:
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
	document.species.append({"id": id, "name": "New creature", "model": "ANGEL", "mobility": "swimming", "group_behaviour": "shoaling", "response": "flee", "speed": 1.3, "attack_range": 8.0, "flee_range": 4.0, "scale_min": 100.0, "scale_max": 100.0})
	document.species[-1].merge(Document.POPULATION_DEFAULTS)
	document.species[-1].random_spawn = true
	_remember(before); category.select(4); select("species:" + id)
func add_group() -> void:
	if not loaded or document.species.is_empty(): return
	var before := document.duplicate(true); var id := _new_id()
	var species_id: String = selected.trim_prefix("species:") if selected.begins_with("species:") else str(document.species[0].id)
	document.groups.append({"id": id, "name": "New wildlife group", "species": species_id, "position": Document.array(_new_position()), "count_min": 1, "count_max": 10, "radius": 10.0, "chance": 100.0})
	_remember(before); category.select(3); _sync(); select("group:" + id)
func add_object_type() -> void:
	if not loaded: return
	var before := document.duplicate(true); var entry := preload("res://object_definitions.gd").FLOATING_MINE.duplicate(true)
	entry.id = _new_id(); entry.name = "New floating mine type"; document.object_types.append(entry)
	_remember(before); category.select(6); select("object_type:" + entry.id)
func add_object_group() -> void:
	if not loaded or document.object_types.is_empty(): return
	var before := document.duplicate(true); var id := _new_id()
	var type_id: String = selected.trim_prefix("object_type:") if selected.begins_with("object_type:") else str(document.object_types[0].id)
	if selected.begins_with("object_group:"): type_id = record().type
	var type_name := "object"
	for entry in document.object_types:
		if entry.id == type_id: type_name = str(entry.name).to_lower(); break
	document.object_groups.append({"id":id,"name":"New %s group" % type_name,"type":type_id,"position":Document.array(_new_position()),"count":1,"radius":5.0})
	_remember(before); category.select(5); _sync(); select("object_group:" + id)
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
	if kind == "dropoff": document.entities[key].merge({"name":"New drop-off point","radius":0.5,"city_id":0})
	_remember(before); category.select(5 if kind == "dropoff" else 0); _sync(); select(key)
func duplicate_selection() -> void:
	if not loaded or record().is_empty(): return
	var before := document.duplicate(true); var entry := record().duplicate(true); var id := _new_id(); entry.name += " copy"
	if selected.begins_with("object_type:"): entry.id = id; document.object_types.append(entry); selected = "object_type:" + id
	elif selected.begins_with("object_group:"): entry.id = id; entry.position[0] += 2.0; document.object_groups.append(entry); selected = "object_group:" + id
	elif selected.begins_with("species:"): entry.id = id; document.species.append(entry); selected = "species:" + id
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
	if selected.begins_with("object_type:"):
		if document.object_groups.any(func(group: Dictionary) -> bool: return group.type == record().id): status.text = "Remove or reassign this object type's groups first."; return
		document.object_types.erase(record())
	elif selected.begins_with("object_group:"): document.object_groups.erase(record())
	elif selected.begins_with("species:"):
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
	if entry.is_empty() or key.begins_with("species:") or key.begins_with("object_type:"): return Vector3(INF, INF, INF)
	return Document.vector(entry.position) if key.begins_with("group:") or key.begins_with("object_group:") else Document.decode(entry.transform).origin
func _move(point_value: Vector3) -> void:
	var entry := record()
	if selected.begins_with("group:") or selected.begins_with("object_group:"): entry.position = Document.array(point_value)
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
				if event.shift_pressed and point().is_finite():
					move_drag = true; drag_before = document.duplicate(true); drag_origin = point(); drag_vertical = event.ctrl_pressed; drag_mouse = event.position
					drag_units_per_pixel = 2.0 * camera.global_position.distance_to(drag_origin) * tan(deg_to_rad(camera.fov) * 0.5) / maxf(1.0,viewport.size.y)
					drag_plane = Plane(Vector3.UP,drag_origin.y)
			elif move_drag: move_drag = false; _remember(drag_before); _sync(); select(selected)
	elif event is InputEventMouseMotion:
		if fly:
			yaw -= event.relative.x * 0.004; pitch = clampf(pitch - event.relative.y * 0.004, -1.5, 1.5); camera.rotation = Vector3(pitch, yaw, 0)
		elif move_drag:
			var intersection: Variant = drag_origin + Vector3.UP * (drag_mouse.y - event.position.y) * drag_units_per_pixel if drag_vertical else drag_plane.intersects_ray(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position))
			if intersection != null:
				var location: Vector3 = Vector3(drag_origin.x,intersection.y,drag_origin.z) if drag_vertical else Vector3(intersection.x,drag_origin.y,intersection.z)
				_move(location); _update_outline()
				var node := world.get_node_or_null(NodePath(selected)) as Node3D
				if node != null: node.global_position = location
func _pick(mouse: Vector2) -> void:
	var closest := ""; var score := 36.0
	var keys: Array = document.entities.keys()
	for group in document.groups: keys.append("group:" + group.id)
	for group in document.get("object_groups",[]): keys.append("object_group:" + group.id)
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
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not loaded or not event.is_pressed(): return
	if Bindings.pressed(event,"editor_frame"): frame_selection()
	elif Bindings.pressed(event,"editor_undo"): undo()
	elif Bindings.pressed(event,"editor_redo"): redo()
	elif Bindings.pressed(event,"editor_save"): save_map()
func _process(delta: float) -> void:
	if not is_visible_in_tree() or not loaded or not fly: return
	var input := Vector3(Bindings.strength("turn_right") - Bindings.strength("turn_left"), Bindings.strength("thrust_up") - Bindings.strength("thrust_down"), Bindings.strength("thrust_reverse") - Bindings.strength("thrust_forward"))
	camera.position += camera.basis * input.normalized() * fly_speed * (3.0 if Bindings.strength("editor_fast") > 0.5 else 1.0) * delta
