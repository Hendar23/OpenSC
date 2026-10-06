extends CanvasLayer
const Bindings = preload("res://input_bindings.gd")
signal action_requested(action: String, payload: Dictionary)
const Mods = preload("res://mod_registry.gd")
const BMP = preload("res://legacy_bmp.gd")
const DEFAULT_PAGES := {
	"home":{"buttons":[{"action":"missions","rect":[18,298,155,42]},{"action":"equipment","rect":[48,421,140,45]},{"action":"save","rect":[474,298,151,42]},{"action":"launch","rect":[466,421,142,45]}],"title":[218,10,202,40],"welcome":[95,94,450,130],"status":[222,304,198,155]},
	"equipment":{"buttons":[{"action":"home","rect":[14,417,163,49]},{"action":"goods","rect":[465,417,163,49]}],"title":[218,10,202,38]},
	"goods":{"buttons":[{"action":"equipment","rect":[15,418,190,48]}]},
	"missions":{"buttons":[{"action":"home","rect":[18,422,230,40]}]},
	"save":{"buttons":[{"action":"home","rect":[23,419,190,42]}],"slots":[204,56,268,44]},
	"load":{"buttons":[{"action":"close","rect":[23,419,190,42]}],"slots":[204,56,268,44]}
}
var folder := ""
var page := "home"
var model: Callable
var layout: Control
var background: TextureRect
var pages := DEFAULT_PAGES.duplicate(true)
var text_colour := Color(1,0.8,0.15)
var custom_colour: Variant = null
var button_nodes: Array[Button] = []
var name_dialog: ConfirmationDialog
var name_field: LineEdit
var overwrite_dialog: ConfirmationDialog
var pending_slot := 0
var pending_name := ""
var status := ""
var loaded_city := ""
var preview: SubViewport
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS; layer = 20
	var backdrop := ColorRect.new(); backdrop.color = Color.BLACK; add_child(backdrop); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout = Control.new(); backdrop.add_child(layout); layout.size = Vector2(640,480)
	name_dialog = ConfirmationDialog.new(); name_dialog.title = "Name saved game"; add_child(name_dialog)
	name_field = LineEdit.new(); name_field.max_length = 64; name_field.custom_minimum_size = Vector2(360,38); name_dialog.add_child(name_field)
	name_dialog.confirmed.connect(_confirm_name)
	name_field.text_submitted.connect(func(_text: String) -> void: name_dialog.hide(); _confirm_name())
	overwrite_dialog = ConfirmationDialog.new(); overwrite_dialog.dialog_text = "Replace the saved game in this slot?"; add_child(overwrite_dialog)
	overwrite_dialog.confirmed.connect(func() -> void: action_requested.emit("save_slot",{"slot":pending_slot,"name":pending_name}))
	get_viewport().size_changed.connect(_resize); _resize(); hide()
func setup(original_folder: String, state: Callable) -> void:
	folder = original_folder; model = state
	pages = DEFAULT_PAGES.duplicate(true)
	custom_colour = null
	for id in ["ui.dock","ui.saves"]:
		for candidate in Mods.candidates(id):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate.path))
			if not data is Dictionary or data.get("schema_version") != 1 or not data.get("pages") is Dictionary: continue
			for key in data.pages:
				if pages.has(key) and data.pages[key] is Dictionary: pages[key].merge(data.pages[key],true)
			var colour: Variant = data.get("text_colour")
			if preload("res://map_document.gd").finite_array(colour,3): custom_colour = Color(float(colour[0]),float(colour[1]),float(colour[2]))
			break
func _resize() -> void:
	var size := get_viewport().get_visible_rect().size
	var factor := minf(size.x / 640,size.y / 480)
	layout.scale = Vector2.ONE * factor; layout.position = (size - Vector2(640,480) * factor) * 0.5
func rect(values: Variant, fallback: Rect2 = Rect2(0,0,100,30)) -> Rect2:
	if not preload("res://map_document.gd").finite_array(values,4): return fallback
	return Rect2(values[0],values[1],maxf(1,values[2]),maxf(1,values[3]))
func texture(id: String, relative: String) -> Texture2D:
	for candidate in Mods.candidates(id):
		var image := preload("res://clump_loader.gd")._replacement_image(candidate.path)
		if image != null: return ImageTexture.create_from_image(image)
	var image := BMP.load_image(folder.path_join(relative))
	return ImageTexture.create_from_image(image) if image != null else null
func label(text: String, area: Rect2, font_size: int = 13, centre: bool = false) -> Label:
	var node := Label.new(); node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; node.text = text
	node.add_theme_font_size_override("font_size",font_size); node.add_theme_color_override("font_color",text_colour)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if centre: node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(node); node.position = area.position; node.size = area.size; node.clip_text = true; return node
func button(action: String, area: Rect2, text: String = "", payload: Dictionary = {}) -> Button:
	var node := Button.new(); node.position = area.position; node.size = area.size; node.text = text
	node.add_theme_font_size_override("font_size",12); node.add_theme_color_override("font_color",text_colour)
	node.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new(); focus.bg_color = Color(1,1,1,0.1); focus.border_color = text_colour; focus.set_border_width_all(1)
	for state in ["hover","focus","pressed"]: node.add_theme_stylebox_override(state,focus)
	layout.add_child(node); button_nodes.append(node)
	node.pressed.connect(func() -> void:
		if action in pages: open(action)
		elif action == "choose_slot": _choose_slot(int(payload.slot))
		else: action_requested.emit(action,payload))
	return node
func open(next_page: String = "home") -> void:
	page = next_page if pages.has(next_page) else "home"
	status = ""; show(); rebuild(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
func rebuild() -> void:
	# A button may still be emitting pressed while its page changes.
	for child in layout.get_children(): layout.remove_child(child); child.queue_free()
	button_nodes.clear()
	var data: Dictionary = model.call() if model.is_valid() else {}
	loaded_city = str(data.get("city","Dock"))
	var race := int(data.get("race",1)); var prefix := "P" if race == 2 else "R" if race == 4 else "B"
	text_colour = Color(0.2,0.95,1) if race == 2 else Color(1,0.8,0.15)
	if custom_colour is Color: text_colour = custom_colour
	var artwork := "TRAD1" if race != 2 else "TECH1"
	match page:
		"equipment": artwork = "TRADE"
		"goods": artwork = prefix + "GOODSCR"
		"missions": artwork = "MIS" + prefix + "1"
		"save","load": artwork = "SAVESCR" if page == "load" else "PSAVE" if race == 2 else "BSAVE"
	background = TextureRect.new(); background.size = Vector2(640,480); background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture = texture(str(pages[page].get("background","texture.ui_dock_" + page)),"INTROTEX/ENGLISH/" + artwork + ".BMP")
	layout.add_child(background)
	if pages[page].has("title"): label(loaded_city.to_upper(),rect(pages[page].title),18,true)
	for entry in pages[page].get("buttons",[]):
		if entry is Dictionary and entry.get("action") is String: button(entry.action,rect(entry.get("rect")),str(entry.get("text","")))
	match page:
		"home":
			label("Welcome to %s.\n\nSave your game, inspect your equipment, or browse the dock services. Trading and missions are coming later." % loaded_city,rect(pages.home.welcome),14)
			label("Mounted equipment: %d\nWeapons: %d\n\nHull and shield systems:\nNot implemented yet\n\nCurrent mission: None" % [data.get("equipment",[]).size(),data.get("weapons",[]).size()],rect(pages.home.status),12)
		"equipment":
			label("Shop preview\nPurchases coming later",Rect2(22,53,157,49),12)
			label("\n".join(PackedStringArray(data.get("shop_items",[]).slice(0,12))),Rect2(24,106,150,230),11)
			label("Mounted\n\n" + "\n".join(PackedStringArray(data.get("equipment",[]) + data.get("weapons",[]))),Rect2(476,57,147,263),12)
			label("Equipment mounting and upgrades\nNot available yet",Rect2(216,325,216,135),13,true)
			_sub_preview(data.get("submarine"))
		"goods":
			label("\n".join(PackedStringArray(data.get("commodities",[]).slice(0,16))),Rect2(25,58,190,310),12)
			label("Trade preview\n\nBuying and selling\nnot available yet",Rect2(251,98,188,195),13,true)
			label("Cargo hold\n\nEmpty",Rect2(509,56,104,322),13)
		"missions":
			label("Available missions\n\nNo missions available yet.",Rect2(24,24,325,160),16)
			label("Current mission\n\nNone",Rect2(392,24,224,160),16)
			label("Mission selection and rewards are not implemented yet.",Rect2(26,239,588,138),16)
		"save","load":
			var area := rect(pages[page].get("slots"))
			var slots: Array = data.get("slots",[])
			for slot in slots:
				var text := "%d  %s" % [int(slot.slot) + 1,slot.name]
				if slot.exists and not slot.valid: text = "%d  Unreadable save" % [int(slot.slot) + 1]
				var node := button("choose_slot",Rect2(area.position + Vector2(0,int(slot.slot) * area.size.y),Vector2(area.size.x,25)),text,{"slot":slot.slot})
				node.tooltip_text = "%s — %s" % [slot.city,slot.saved_at]
				node.disabled = page == "load" and not slot.valid
			label(status,Rect2(190,350,310,56),12,true)
	if not button_nodes.is_empty(): button_nodes[0].grab_focus()
func _sub_preview(source: Node3D) -> void:
	if source == null: return
	preview = SubViewport.new(); preview.own_world_3d = true; preview.size = Vector2i(440,240); preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS; layout.add_child(preview)
	var bounds := AABB(); var first := true
	for mesh in source.find_children("*","MeshInstance3D",true,false):
		var copy := MeshInstance3D.new(); copy.mesh = mesh.mesh; copy.transform = source.global_transform.affine_inverse() * mesh.global_transform
		for index in range(mesh.mesh.get_surface_count()): copy.set_surface_override_material(index,preload("res://hud_map.gd")._map_material(mesh.get_active_material(index)))
		preview.add_child(copy)
		var box: AABB = copy.transform * copy.mesh.get_aabb()
		bounds = box if first else bounds.merge(box); first = false
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color.WHITE; environment.environment.ambient_light_energy = 0.7; preview.add_child(environment)
	environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color.BLACK
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40,-30,0); preview.add_child(sun)
	var camera := Camera3D.new(); preview.add_child(camera); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size.length() * 1.05,0.1); camera.position = bounds.get_center() + Vector3(1,0.65,1).normalized() * maxf(bounds.size.length() * 3,1)
	camera.look_at(bounds.get_center()); camera.current = true
	var image := TextureRect.new(); image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.texture = preview.get_texture(); image.position = Vector2(210,58); image.size = Vector2(230,126); image.mouse_filter = Control.MOUSE_FILTER_IGNORE; layout.add_child(image)
func _choose_slot(slot: int) -> void:
	if page == "load": action_requested.emit("load_slot",{"slot":slot}); return
	pending_slot = slot
	var data: Dictionary = model.call(); var record: Dictionary = data.slots[slot]
	name_field.text = record.name if record.valid else loaded_city
	name_dialog.popup_centered(Vector2i(390,120)); name_field.grab_focus(); name_field.select_all()
func _confirm_name() -> void:
	pending_name = name_field.text.strip_edges().left(64)
	if pending_name.is_empty(): pending_name = loaded_city
	var data: Dictionary = model.call()
	if data.slots[pending_slot].exists: overwrite_dialog.popup_centered()
	else: action_requested.emit("save_slot",{"slot":pending_slot,"name":pending_name})
func report(message: String) -> void:
	status = message; rebuild()
func _input(event: InputEvent) -> void:
	if not visible or name_dialog.visible or overwrite_dialog.visible: return
	if Bindings.pressed(event,"menu_cancel"):
		if page == "load": action_requested.emit("close",{})
		elif page != "home": open("home")
		get_viewport().set_input_as_handled()
	elif Bindings.pressed(event,"menu_accept"):
		var focused := get_viewport().gui_get_focus_owner() as Button
		if focused != null and not focused.disabled: focused.pressed.emit(); get_viewport().set_input_as_handled()
	else:
		for direction in [["menu_left",SIDE_LEFT],["menu_right",SIDE_RIGHT],["menu_up",SIDE_TOP],["menu_down",SIDE_BOTTOM]]:
			if not Bindings.pressed(event,direction[0]): continue
			var focused := get_viewport().gui_get_focus_owner() as Button
			if focused == null:
				if not button_nodes.is_empty(): button_nodes[0].grab_focus()
			else:
				var next := focused.find_valid_focus_neighbor(direction[1])
				if next != null: next.grab_focus()
			get_viewport().set_input_as_handled(); break

func dismiss() -> void:
	name_dialog.hide(); overwrite_dialog.hide(); hide()
