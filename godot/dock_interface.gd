extends CanvasLayer
const Bindings = preload("res://input_bindings.gd")
signal action_requested(action: String, payload: Dictionary)
const Mods = preload("res://mod_registry.gd")
const BMP = preload("res://legacy_bmp.gd")
const DEFAULT_PAGES := {
	"home":{"buttons":[{"action":"missions","rect":[18,298,163,120]},{"action":"equipment","rect":[30,350,151,116]},{"action":"save","rect":[472,298,153,120]},{"action":"launch","rect":[458,350,150,116]}],"title":[218,10,202,40],"welcome":[95,94,450,130],"status":[222,304,198,155]},
	"equipment":{"buttons":[{"action":"home","rect":[14,417,163,49]},{"action":"goods","rect":[465,417,163,49]}],"title":[218,10,202,38],"sale":[22,54,145,267],"hold":[478,54,143,267],"buy":[100,361,66,26],"sale_info":[27,361,66,26],"hold_info":[477,361,66,26],"sell":[550,361,66,26],"cost":[24,339,145,22],"sell_price":[478,339,143,22],"preview":[210,58,230,126],"status":[235,332,172,130],"message":[210,203,230,67]},
	"goods":{"buttons":[{"action":"equipment","rect":[15,418,160,48]}],"list":[22,49,198,304],"buy":[248,364,65,27],"sell":[356,364,65,27],"info":[86,364,65,27]},
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
var selected_hold := ""
var selected_hold_copy := 0
var selected_sale := ""
var selected_commodity := ""
var sale_list: ItemList
var hold_list: ItemList
var shop_offer_id := "shield"
var slot_buttons: Array[Button] = []
var selection_dot: Texture2D
var empty_dot: Texture2D
var mount_dot: Control
var info_dialog: AcceptDialog
const DockButton = preload("res://dock_button.gd")
const MENU_SOUNDS := {"over":"OVERBUTT","off":"OFFBUTT","activate":"ACTIVATE","equipment_trade":"SUBCYCLE","commodity_trade":"SELECT","install":"LOAD","repair":"SHIELD","error":"ERROR"}
signal menu_sound_played(role: String)
var sound_players := {}
var audio_tuning := preload("res://sound_tuning.gd").new()
var active_button: Button
var controller_button: Button
var rebuilding := false
var dock_race := 1
var art_cache := {}

class DialogInput extends Node:
	var handler: Callable
	func _input(event: InputEvent) -> void: handler.call(event)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS; layer = 20
	var backdrop := ColorRect.new(); backdrop.color = Color.BLACK; add_child(backdrop); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout = Control.new(); backdrop.add_child(layout); layout.size = Vector2(640,480)
	name_dialog = ConfirmationDialog.new(); name_dialog.title = "Name saved game"; add_child(name_dialog)
	name_field = LineEdit.new(); name_field.max_length = 64; name_field.custom_minimum_size = Vector2(360,38); name_dialog.add_child(name_field)
	name_dialog.confirmed.connect(_confirm_name)
	var naming_input := DialogInput.new(); naming_input.handler = func(event: InputEvent) -> void: _dialog_input(name_dialog,event)
	name_dialog.add_child(naming_input)
	name_field.text_submitted.connect(func(_text: String) -> void: name_dialog.hide(); _confirm_name())
	overwrite_dialog = ConfirmationDialog.new(); overwrite_dialog.dialog_text = "Replace the saved game in this slot?"; add_child(overwrite_dialog)
	overwrite_dialog.confirmed.connect(func() -> void: action_requested.emit("save_slot",{"slot":pending_slot,"name":pending_name}))
	info_dialog = AcceptDialog.new(); info_dialog.title = "Shield Repair"; add_child(info_dialog)
	var overwrite_input := DialogInput.new(); overwrite_input.handler = func(event: InputEvent) -> void: _dialog_input(overwrite_dialog,event)
	overwrite_dialog.add_child(overwrite_input)
	name_dialog.canceled.connect(_restore_slot_focus); overwrite_dialog.canceled.connect(_restore_slot_focus)
	get_viewport().size_changed.connect(_resize); _resize(); hide()
func setup(original_folder: String, state: Callable) -> void:
	folder = original_folder; model = state
	art_cache.clear()
	_load_menu_audio()
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
	var node := DockButton.new(); node.position = area.position; node.size = area.size; node.text = text
	node.name = action + "_" + str(payload.slot) if action == "choose_slot" else action
	node.add_theme_font_size_override("font_size",12); node.add_theme_color_override("font_color",text_colour)
	node.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new(); focus.bg_color = Color(1,1,1,0.1); focus.border_color = text_colour; focus.set_border_width_all(1)
	for state in ["hover","focus","pressed"]: node.add_theme_stylebox_override(state,focus)
	_skin_button(node,action,payload)
	node.mouse_entered.connect(func() -> void: _enter_button(node))
	node.focus_entered.connect(func() -> void: _enter_button(node))
	node.mouse_exited.connect(func() -> void: _leave_button(node))
	node.focus_exited.connect(func() -> void: _leave_button(node))
	node.button_down.connect(func() -> void:
		node.held = true; node.set_meta("sounded_down",true); node.queue_redraw(); _play_menu_sound("activate"))
	node.button_up.connect(func() -> void: node.held = false; node.queue_redraw())
	layout.add_child(node); button_nodes.append(node)
	node.pressed.connect(func() -> void:
		if not node.get_meta("sounded_down",false): _play_menu_sound("activate")
		node.set_meta("sounded_down",false)
		if action in pages: open(action)
		elif action == "choose_slot": _choose_slot(int(payload.slot))
		elif action == "repair_info": shop_offer_id = selected_hold if payload.get("side","") == "hold" else selected_sale; _repair_info()
		elif action in ["buy_equipment","sell_equipment"]: action_requested.emit(action,{"item":selected_sale if action == "buy_equipment" else selected_hold})
		elif action in ["buy_commodity","sell_commodity"]: action_requested.emit(action,{"item":selected_commodity})
		elif action == "commodity_info": _commodity_info()
		elif action == "equipment_slot": action_requested.emit(action,{"slot":payload.slot,"item":selected_hold})
		elif action == "use_repair": action_requested.emit(action,{"item":selected_hold})
		else: action_requested.emit(action,payload))
	return node
func _button_texture(relative: String) -> Texture2D:
	if not art_cache.has(relative): art_cache[relative] = texture("texture.ui_dock_button_" + relative.get_file().get_basename().to_lower(),"INTROTEX/" + relative + ".BMP")
	return art_cache[relative]

func _piece(node: Button, target: Array, relative: String, position: Vector2) -> void:
	var image := _button_texture(relative)
	if image != null: target.append({"texture":image,"rect":Rect2(position - node.position,image.get_size())})

func _skin_button(node: DockButton, action: String, payload: Dictionary) -> void:
	var procha := dock_race == 2
	var prefix := "P" if procha else "B"
	var trade := "TP" if procha else "TB"
	if page == "home" and action in ["missions","equipment","save","launch"]:
		var entries := {
			"missions":["MISS",Vector2(27,307),Vector2(23,345),[Vector2(18,298),Vector2(181,298),Vector2(18,418)]],
			"equipment":["TRAD",Vector2(70,435),Vector2(111,360),[Vector2(181,350),Vector2(181,466),Vector2(30,466)]],
			"save":["SAVE",Vector2(490,307),Vector2(542,344),[Vector2(472,298),Vector2(625,298),Vector2(625,418)]],
			"launch":["LAUN",Vector2(464,435),Vector2(460,360),[Vector2(458,350),Vector2(608,466),Vector2(458,466)]]}
		var entry: Array = entries[action]
		_piece(node,node.highlight_art,"ENGLISH/" + prefix + "D" + entry[0] + "T",entry[1])
		_piece(node,node.held_art,prefix + "D" + entry[0] + "B",entry[2])
		for point in entry[3]: node.hit_polygon.append(point - node.position)
	elif action in ["buy_equipment","sell_equipment","repair_info","buy_commodity","sell_commodity","commodity_info"]:
		var letter := "B" if action.begins_with("buy") else "S" if action.begins_with("sell") else "I"
		_piece(node,node.highlight_art,"ENGLISH/" + trade + "-" + letter + "1",node.position)
		_piece(node,node.held_art,"ENGLISH/" + trade + "-" + letter + "2",node.position)
	elif page == "equipment" and action in ["home","goods"]:
		if action == "home":
			_piece(node,node.highlight_art,"ENGLISH/" + trade + "-DN1",Vector2(82,434))
			_piece(node,node.held_art,trade + "-BUT1",Vector2(22,418))
		else:
			_piece(node,node.highlight_art,"ENGLISH/" + prefix + "GOOD",Vector2(473,435))
			_piece(node,node.held_art,prefix + "GBUT",Vector2(563,416))
	elif page == "missions" and action == "home":
		_piece(node,node.highlight_art,"ENGLISH/M" + prefix + "-BDL",Vector2(93,437))
		_piece(node,node.held_art,"M" + prefix + "-B1",Vector2(27,421))
	elif action in ["home","equipment"] and page in ["goods","save","load"]:
		_piece(node,node.highlight_art,"ENGLISH/" + prefix + "DONG",Vector2(82,434))
		_piece(node,node.held_art,trade + "-BUT1",Vector2(22,418))
	# Keep original overlays attached when a mod moves a navigation button.
	for entry in DEFAULT_PAGES.get(page,{}).get("buttons",[]):
		if entry.action != action: continue
		var offset := node.position - rect(entry.rect).position
		for piece in node.highlight_art + node.held_art: piece.rect.position += offset
		for index in range(node.hit_polygon.size()): node.hit_polygon[index] += offset
		break
	if not node.highlight_art.is_empty():
		for state in ["hover","focus","pressed"]: node.add_theme_stylebox_override(state,StyleBoxEmpty.new())

func _load_menu_audio() -> void:
	audio_tuning.load_settings()
	for role in MENU_SOUNDS:
		var player: AudioStreamPlayer = sound_players.get(role)
		if player == null:
			player = AudioStreamPlayer.new(); add_child(player); sound_players[role] = player
		var path := folder.path_join("WAVES/" + str(MENU_SOUNDS[role]) + ".RAW")
		for replacement in Mods.candidates("audio.menu." + role):
			if preload("res://legacy_audio.gd").load_file(replacement.path) != null: path = replacement.path; break
		player.stream = preload("res://legacy_audio.gd").load_file(path)

func _play_menu_sound(role: String) -> void:
	if rebuilding or not visible: return
	var player: AudioStreamPlayer = sound_players.get(role)
	if player == null or not player.is_inside_tree() or player.stream == null: return
	var gain := float(audio_tuning.settings.master_volume)
	player.volume_db = -80.0 if gain <= -60 else gain
	player.play(); menu_sound_played.emit(role)

func transaction_feedback(message: String, success_sound: String, changed: bool = true) -> void:
	# Empty reports mean success, but some inventory actions intentionally do
	# nothing. Those must not sound like a completed repair or installation.
	if not message.is_empty(): _play_menu_sound("error")
	elif changed: _play_menu_sound(success_sound)
	report(message)

func _enter_button(node: Button) -> void:
	if node.disabled or active_button == node: return
	if is_instance_valid(active_button):
		active_button.highlighted = false; active_button.queue_redraw(); _play_menu_sound("off")
	active_button = node; node.highlighted = true; node.queue_redraw(); _play_menu_sound("over")

func _leave_button(node: Button) -> void:
	if active_button != node: return
	active_button = null; node.highlighted = false; node.queue_redraw(); _play_menu_sound("off")

func open(next_page: String = "home") -> void:
	page = next_page if pages.has(next_page) else "home"
	status = ""; show(); rebuild(true); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
func rebuild(new_page: bool = false) -> void:
	rebuilding = true; active_button = null
	var focused := get_viewport().gui_get_focus_owner()
	var focus_name := str(focused.name) if not new_page and focused != null and layout.is_ancestor_of(focused) else ""
	# A button may still be emitting pressed while its page changes.
	for child in layout.get_children(): layout.remove_child(child); child.queue_free()
	button_nodes.clear()
	var data: Dictionary = model.call() if model.is_valid() else {}
	loaded_city = str(data.get("city","Dock"))
	var race := int(data.get("race",1)); dock_race = race; var prefix := "P" if race == 2 else "R" if race == 4 else "B"
	text_colour = Color(0.2,0.95,1) if race == 2 else Color(1,0.8,0.15)
	if custom_colour is Color: text_colour = custom_colour
	var artwork := "TRAD1" if race != 2 else "TECH1"
	match page:
		"equipment": artwork = "TP-1" if race == 2 else "TB-1"
		"goods": artwork = prefix + "GOODSCR"
		"missions": artwork = "MIS" + prefix + "1"
		"save","load": artwork = "SAVESCR" if page == "load" else "PSAVE" if race == 2 else "BSAVE"
	background = TextureRect.new(); background.size = Vector2(640,480); background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture = texture(str(pages[page].get("background","texture.ui_dock_" + page)),"INTROTEX/ENGLISH/" + artwork + ".BMP")
	layout.add_child(background)
	if pages[page].has("title"):
		var title_texture: Texture2D = null
		if not str(data.get("title_bitmap","")).is_empty(): title_texture = texture("texture.ui_dock_title_" + str(data.get("city_id","")),data.title_bitmap)
		if title_texture != null:
			var title := TextureRect.new(); title.texture = title_texture
			title.name = "CityTitle"; title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			title.mouse_filter = Control.MOUSE_FILTER_IGNORE; layout.add_child(title)
			var area := rect(pages[page].title); title.position = area.position; title.size = area.size
		else: label(loaded_city.to_upper(),rect(pages[page].title),18,true)
	for entry in pages[page].get("buttons",[]):
		if entry is Dictionary and entry.get("action") is String: button(entry.action,rect(entry.get("rect")),str(entry.get("text","")))
	match page:
		"home":
			var welcome := str(data.get("welcome",""))
			_welcome(welcome if not welcome.is_empty() else "Welcome to %s." % loaded_city,rect(pages.home.welcome))
			_status(data,rect(pages.home.status))
		"equipment":
			_equipment_shop(data)

		"goods": _commodity_shop(data)
		"missions":
			label("Available missions\n\nNo missions available yet.",Rect2(24,24,325,160),16)
			label("Current mission\n\nNone",Rect2(392,24,224,160),16)
			label("Mission selection and rewards are not implemented yet.",Rect2(26,239,588,138),16)
		"save","load":
			var area := rect(pages[page].get("slots"))
			var slots: Array = data.get("slots",[])
			for slot in slots:
				var text := "%d  %s" % [int(slot.slot) + 1,slot.name]
				if slot.valid and not str(slot.saved_at).is_empty(): text += " — " + str(slot.saved_at).replace("T"," ")
				if slot.exists and not slot.valid: text = "%d  Unreadable save" % [int(slot.slot) + 1]
				var node := button("choose_slot",Rect2(area.position + Vector2(0,int(slot.slot) * area.size.y),Vector2(area.size.x,25)),text,{"slot":slot.slot})
				node.tooltip_text = "%s — %s" % [slot.city,slot.saved_at]
				node.disabled = page == "load" and not slot.valid
			label(status,Rect2(190,350,310,56),12,true)
	var slot_controls: Array[Button] = []
	if page in ["save","load"]: slot_controls = _wire_slot_focus()
	var restored := layout.get_node_or_null(NodePath(focus_name)) as Control if not focus_name.is_empty() else null
	if restored != null: restored.grab_focus()
	elif page in ["save","load"]:
		(slot_controls[0] if not slot_controls.is_empty() else button_nodes[0]).grab_focus()
	elif page in ["equipment","goods"] and sale_list != null: sale_list.grab_focus()
	elif not button_nodes.is_empty(): button_nodes[0].grab_focus()
	rebuilding = false

func _welcome(text: String, area: Rect2) -> void:
	var scroll := ScrollContainer.new(); scroll.name = "CityWelcome"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = area.position; scroll.size = area.size; layout.add_child(scroll)
	var body := Label.new(); body.text = text; body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size",13); body.add_theme_color_override("font_color",text_colour)
	scroll.add_child(body)


func _equipment_shop(data: Dictionary) -> void:
	var offers: Dictionary = data.get("offers",{"shield":data.get("repair_offer",{})})
	var settings: Dictionary = pages.equipment
	if int(data.get("hold",{}).get(selected_hold,0)) == 0: selected_hold = ""
	sale_list = _item_list("ForSale",rect(settings.sale))
	for id in offers:
		if not offers[id].get("available",false): continue
		sale_list.add_item(str(offers[id].name)); sale_list.set_item_metadata(sale_list.item_count - 1,id)
		if id == selected_sale: sale_list.select(sale_list.item_count - 1)
	sale_list.item_selected.connect(func(index: int) -> void: selected_sale = str(sale_list.get_item_metadata(index)); _update_shop_selection(data))
	var cost := label("",rect(settings.cost),12,true); cost.name = "PurchasePrice"
	var buy := button("buy_equipment",rect(settings.buy)); buy.name = "BuyShieldRepair"
	var sale_info := button("repair_info",rect(settings.sale_info),"",{"side":"sale"}); sale_info.name = "SaleInfo"
	hold_list = _item_list("Hold",rect(settings.hold))
	for id in data.get("hold",{}):
		var count := int(data.hold[id])
		if count <= 0: continue
		for copy in range(count if id == "shield" else 1):
			hold_list.add_item(str(offers.get(id,{}).get("name",id)) + (" ×%d" % count if count > 1 and id != "shield" else ""))
			hold_list.set_item_metadata(hold_list.item_count - 1,id)
			if id == selected_hold and copy == mini(selected_hold_copy,count - 1): hold_list.select(hold_list.item_count - 1)
	hold_list.item_selected.connect(func(index: int) -> void:
		selected_hold = str(hold_list.get_item_metadata(index)); selected_hold_copy = 0
		for previous in range(index):
			if hold_list.get_item_metadata(previous) == selected_hold: selected_hold_copy += 1
		_update_shop_selection(data))
	var price := label("",rect(settings.sell_price),12,true); price.name = "ResalePrice"
	var info := button("repair_info",rect(settings.hold_info),"",{"side":"hold"}); info.name = "HoldInfo"
	var sell := button("sell_equipment",rect(settings.sell)); sell.name = "SellShieldRepair"
	_status(data,rect(settings.status),true)
	label(status,Rect2(210,184,230,13),10,true)
	# The original two-view submarine illustration shares the slot highlight.
	var picture := TextureRect.new(); picture.texture = texture("texture.ui_equipment_sub","INTROTEX/2SUB.BMP")
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var area := rect(settings.preview); picture.position = area.position; picture.size = area.size; layout.add_child(picture)
	mount_dot = Panel.new(); mount_dot.name = "MountPosition"
	var dot := StyleBoxFlat.new(); dot.bg_color = Color.YELLOW; dot.set_corner_radius_all(4)
	mount_dot.add_theme_stylebox_override("panel",dot); mount_dot.size = Vector2(7,7); mount_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE; layout.add_child(mount_dot)
	var use := button("use_repair",area); use.name = "UseShieldRepair"
	slot_buttons.clear()
	var installed: Dictionary = data.get("installed",{})
	# Original grid: weapon, lights and underside tool positions.
	for index in range(10):
		var slot: int = {0:9,1:5,7:3}.get(index,0)
		var id: String = installed.get(slot,"") if slot != 0 else ""
		var square := Rect2(210 + (index % 5) * 47,197 + (index / 5) * 39,46,38)
		var slot_button := button("equipment_slot",square,"EMPTY" if id.is_empty() else "",{"slot":slot})
		slot_button.name = "EquipmentSlot%d" % index; slot_button.set_meta("slot",slot)
		slot_button.tooltip_text = str(offers.get(id,{}).get("name","Empty"))
		if not id.is_empty():
			var icon := TextureRect.new(); icon.texture = texture("texture.ui_equipment_square_" + id,str(offers[id].square_bitmap))
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot_button.add_child(icon); icon.offset_left = 2; icon.offset_top = 2; icon.offset_right = -2; icon.offset_bottom = -2
		elif slot != 0: slot_button.text = "EMPTY"
		slot_buttons.append(slot_button)
		slot_button.focus_entered.connect(func() -> void: _mount_highlight(slot))
		slot_button.mouse_entered.connect(func() -> void: _mount_highlight(slot))
		var blank := StyleBoxFlat.new(); blank.bg_color = Color(0.07,0.025,0.015) if id.is_empty() else Color(0.1,0.55,0.58)
		blank.set_corner_radius_all(4); slot_button.add_theme_stylebox_override("normal",blank)
	for index in range(10):
		var node := slot_buttons[index]
		node.focus_neighbor_left = node.get_path_to(slot_buttons[index - 1] if index % 5 else sale_list)
		node.focus_neighbor_right = node.get_path_to(slot_buttons[index + 1] if index % 5 < 4 else hold_list)
		node.focus_neighbor_top = node.get_path_to(slot_buttons[index - 5] if index >= 5 else node)
		node.focus_neighbor_bottom = node.get_path_to(slot_buttons[index + 5] if index < 5 else button_nodes[0])
	sale_list.focus_neighbor_bottom = sale_list.get_path_to(buy); hold_list.focus_neighbor_bottom = hold_list.get_path_to(sell)
	sale_list.focus_neighbor_right = sale_list.get_path_to(slot_buttons[0]); hold_list.focus_neighbor_left = hold_list.get_path_to(slot_buttons[4])
	_update_shop_selection(data)

func _commodity_shop(data: Dictionary) -> void:
	var offers: Dictionary = data.get("commodity_offers",{})
	var settings: Dictionary = pages.goods
	sale_list = _item_list("Commodities",rect(settings.list))
	sale_list.add_theme_constant_override("v_separation",0)
	sale_list.fixed_icon_size = Vector2i(1,16)
	var spacer_image := Image.create(1,16,false,Image.FORMAT_RGBA8)
	spacer_image.fill(Color.TRANSPARENT)
	var spacer := ImageTexture.create_from_image(spacer_image)
	var index := 0
	for id in offers:
		var offer: Dictionary = offers[id]
		sale_list.add_item(str(offer.name),spacer); sale_list.set_item_metadata(index,id)
		if id == selected_commodity: sale_list.select(index)
		for column in range(3):
			var value := str(offer.buy_price) if column == 0 else str(offer.sell_price) if column == 1 else str(data.get("cargo",{}).get(id,0))
			if column < 2 and value == "0": value = "—"
			var amount := label(value,Rect2([242,350,495][column],49 + index * 16,82,16),11,true)
			amount.name = "Quote_%s_%d" % [id,column]
			amount.tooltip_text = "City stock: %d" % int(offer.stock)
		index += 1
	sale_list.item_selected.connect(func(row: int) -> void: selected_commodity = str(sale_list.get_item_metadata(row)); _update_commodity_selection(model.call()))
	if sale_list.item_count > 0 and sale_list.get_selected_items().is_empty():
		sale_list.select(0); selected_commodity = str(sale_list.get_item_metadata(0))
	var buy := button("buy_commodity",rect(settings.buy)); buy.name = "BuyCommodity"
	var sell := button("sell_commodity",rect(settings.sell)); sell.name = "SellCommodity"
	var info := button("commodity_info",rect(settings.info)); info.name = "CommodityInfo"
	var credits := label("Credits: %d" % int(data.get("status",{}).get("credits",0)),Rect2(495,428,100,32),11,true)
	credits.name = "CommodityCredits"
	credits.autowrap_mode = TextServer.AUTOWRAP_OFF
	credits.size = Vector2(100,32)
	credits.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label(status if not offers.is_empty() else "No commodity market at this station.",Rect2(180,420,280,44),11,true)
	sale_list.focus_neighbor_bottom = sale_list.get_path_to(info)
	sale_list.focus_neighbor_right = sale_list.get_path_to(buy)
	var controls: Array[Control] = [button_nodes[0],info,buy,sell]
	for i in range(controls.size()):
		var control := controls[i]
		control.focus_neighbor_top = control.get_path_to(sale_list)
		control.focus_neighbor_left = control.get_path_to(controls[(i - 1 + controls.size()) % controls.size()])
		control.focus_neighbor_right = control.get_path_to(controls[(i + 1) % controls.size()])
	_update_commodity_selection(data)

func refresh_market() -> void:
	if page != "goods" or not visible: return
	var data: Dictionary = model.call()
	for id in data.get("commodity_offers",{}):
		var offer: Dictionary = data.commodity_offers[id]
		for column in range(3):
			var amount := layout.get_node_or_null("Quote_%s_%d" % [id,column]) as Label
			if amount == null: continue
			var value := int(offer.buy_price) if column == 0 else int(offer.sell_price) if column == 1 else int(data.get("cargo",{}).get(id,0))
			amount.text = "—" if column < 2 and value == 0 else str(value)
			amount.tooltip_text = "City stock: %d" % int(offer.stock)
	_update_commodity_selection(data)

func _update_commodity_selection(data: Dictionary) -> void:
	var offer: Dictionary = data.get("commodity_offers",{}).get(selected_commodity,{})
	(layout.get_node("BuyCommodity") as Button).disabled = int(offer.get("buy_price",0)) <= 0 or int(offer.get("stock",0)) <= 0 or int(data.get("status",{}).get("credits",0)) < int(offer.get("buy_price",0))
	(layout.get_node("SellCommodity") as Button).disabled = int(offer.get("sell_price",0)) <= 0 or int(data.get("cargo",{}).get(selected_commodity,0)) <= 0
	(layout.get_node("CommodityInfo") as Button).disabled = offer.is_empty()

func _mount_highlight(slot: int) -> void:
	if mount_dot == null: return
	mount_dot.visible = slot in [3,5,9]
	var area := rect(pages.equipment.preview)
	var points := {9:Vector2(0.82,0.4),5:Vector2(0.77,0.25),3:Vector2(0.83,0.74)}
	mount_dot.position = area.position + area.size * points.get(slot,Vector2.ZERO) - Vector2(3.5,3.5)

func _item_list(node_name: String, area: Rect2) -> ItemList:
	var list := ItemList.new(); list.name = node_name; list.position = area.position; list.size = area.size
	list.allow_reselect = true; list.fixed_icon_size = Vector2i(8,8); list.add_theme_font_size_override("font_size",11)
	list.add_theme_constant_override("v_separation",4)
	list.add_theme_color_override("font_color",text_colour); list.add_theme_color_override("font_selected_color",Color.WHITE)
	list.add_theme_stylebox_override("panel",StyleBoxEmpty.new()); list.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	var selected := StyleBoxFlat.new(); selected.bg_color = Color.TRANSPARENT
	list.add_theme_stylebox_override("selected",selected); list.add_theme_stylebox_override("selected_focus",selected)
	layout.add_child(list); return list


func _update_shop_selection(data: Dictionary) -> void:
	var offers: Dictionary = data.get("offers",{"shield":data.get("repair_offer",{})})
	var sale: Dictionary = offers.get(selected_sale,{})
	var held: Dictionary = offers.get(selected_hold,{})
	var count := int(data.get("hold",{}).get(selected_sale,0)) + int(selected_sale in data.get("installed",{}).values())
	layout.get_node("BuyShieldRepair").disabled = sale.is_empty() or not sale.get("available",false) or int(data.status.credits) < int(sale.get("price",0)) or (selected_sale != "shield" and count >= int(sale.get("maximum",1)))
	if not preload("res://equipment_shop.gd").upgrade_available(data,selected_sale): layout.get_node("BuyShieldRepair").disabled = true
	layout.get_node("SaleInfo").disabled = sale.is_empty()
	layout.get_node("HoldInfo").disabled = held.is_empty()
	layout.get_node("SellShieldRepair").disabled = held.is_empty() or int(held.get("sell_price",0)) <= 0
	layout.get_node("UseShieldRepair").disabled = selected_hold not in ["shield","hullstr","radoff"] or not preload("res://equipment_shop.gd").upgrade_available(data,selected_hold)
	layout.get_node("PurchasePrice").text = "Cost %d" % int(sale.price) if not sale.is_empty() else ""
	layout.get_node("ResalePrice").text = "SellPrice %d" % int(held.sell_price) if not held.is_empty() else ""
	if selection_dot == null:
		var image := Image.create(8,8,false,Image.FORMAT_RGBA8); image.fill(Color.TRANSPARENT)
		empty_dot = ImageTexture.create_from_image(image)
		for y in range(8):
			for x in range(8):
				if Vector2(x - 3.5,y - 3.5).length() <= 3.5: image.set_pixel(x,y,Color.YELLOW)
		selection_dot = ImageTexture.create_from_image(image)
	for list in [sale_list,hold_list]:
		for index in range(list.item_count):
			var id := str(list.get_item_metadata(index))
			var offer: Dictionary = offers.get(id,{})
			var number := int(data.get("hold",{}).get(id,0))
			var chosen: bool = selected_sale == id if list == sale_list else list.get_selected_items().has(index)
			list.set_item_icon(index,selection_dot if chosen else empty_dot)
			list.set_item_text(index,str(offer.get("name",id)) + (" ×%d" % number if list == hold_list and number > 1 and id != "shield" else ""))
	var slot: int = held.get("slot",0)
	for node in slot_buttons:
		var normal: StyleBoxFlat = node.get_theme_stylebox("normal")
		normal.border_color = Color.YELLOW; normal.set_border_width_all(2 if slot != 0 and node.get_meta("slot") == slot else 0)
	_mount_highlight(slot)

func _repair_info() -> void:
	var data: Dictionary = model.call() if model.is_valid() else {}
	var offer: Dictionary = data.get("offers",{}).get(shop_offer_id,data.get("repair_offer",{}))
	_show_item_info(offer,shop_offer_id)

func _commodity_info() -> void:
	var data: Dictionary = model.call() if model.is_valid() else {}
	var offer: Dictionary = data.get("commodity_offers",{}).get(selected_commodity,{})
	if not offer.is_empty(): _show_item_info(offer,selected_commodity)

func _show_item_info(offer: Dictionary, item_id: String) -> void:
	info_dialog.title = str(offer.get("name","Shield Repair"))
	info_dialog.dialog_text = ""
	for child in info_dialog.get_children():
		if child.name == "RepairInfo": info_dialog.remove_child(child); child.queue_free()
	var content := VBoxContainer.new(); content.name = "RepairInfo"; content.custom_minimum_size = Vector2(400,200); info_dialog.add_child(content)
	var artwork := texture("texture.ui_equipment_info_" + item_id,str(offer.get("info_bitmap","INTROTEX/WSHIELDS.BMP")))
	if artwork != null:
		var image := TextureRect.new(); image.texture = artwork; image.custom_minimum_size.y = 120
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; content.add_child(image)
	var description := Label.new(); description.text = str(offer.get("description","Restores shields to full strength."))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; content.add_child(description)
	info_dialog.popup_centered(Vector2i(450,270))

func _status(data: Dictionary, area: Rect2, compact: bool = false) -> void:
	var values: Dictionary = data.get("status",{})
	var faction: String = {1:"Bohine",2:"Procha",4:"Brotherhood"}.get(int(data.get("race",1)),"")
	var lines := ["Standing with %s:" % faction,str(data.get("standing","Neutral")),"Current mission:",str(data.get("mission","None")),""]
	if compact: lines = ["Current mission:",str(data.get("mission","None")),""]
	var ratings := [["Hull Strength","hull_strength"],["Top Speed","top_speed"],["Shields","shields"],["Radiation Shield","radiation_shield"],["Credits","credits"]]
	var panel := Control.new(); panel.name = "SubStatus"; panel.position = area.position; panel.size = area.size; panel.clip_contents = true; layout.add_child(panel)
	var row_height := minf(15.0,area.size.y / float(lines.size() + ratings.size()))
	for index in range(lines.size() + ratings.size()):
		var left: String = str(lines[index]) if index < lines.size() else str(ratings[index - lines.size()][0])
		var right := "" if index < lines.size() else str(values.get(ratings[index - lines.size()][1],0))
		# Standing and mission values occupy their own right-aligned rows.
		if index == 1 or (not compact and index == 3): right = left; left = ""
		for side in range(2):
			var node := Label.new(); node.text = left if side == 0 else right
			node.position = Vector2(0,index * row_height); node.size = Vector2(area.size.x,row_height)
			node.add_theme_font_size_override("font_size",12); node.add_theme_color_override("font_color",text_colour)
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if side == 1: node.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			panel.add_child(node)
func _choose_slot(slot: int) -> void:
	if page == "load": action_requested.emit("load_slot",{"slot":slot}); return
	pending_slot = slot
	var data: Dictionary = model.call(); var record: Dictionary = data.slots[slot]
	name_field.text = record.name if record.valid else (loaded_city if not loaded_city.is_empty() else "Saved game")
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
	if is_instance_valid(controller_button) and event.is_action_released("menu_accept"):
		var held_button := controller_button
		controller_button = null
		held_button.button_up.emit()
		if visible and not held_button.disabled: held_button.pressed.emit()
		get_viewport().set_input_as_handled(); return
	if not visible or name_dialog.visible or overwrite_dialog.visible or info_dialog.visible: return
	var item_list := get_viewport().gui_get_focus_owner() as ItemList
	if item_list != null and not Bindings.pressed(event,"menu_cancel"):
		for direction in [["menu_left",SIDE_LEFT],["menu_right",SIDE_RIGHT]]:
			if Bindings.pressed(event,direction[0]):
				var next := item_list.find_valid_focus_neighbor(direction[1])
				if next != null: next.grab_focus()
				get_viewport().set_input_as_handled(); return
		for direction in [["menu_up",-1],["menu_down",1]]:
			if not Bindings.pressed(event,direction[0]): continue
			var chosen := item_list.get_selected_items()
			var index: int = chosen[0] + int(direction[1]) if not chosen.is_empty() else 0
			if index >= 0 and index < item_list.item_count:
				item_list.select(index); item_list.ensure_current_is_visible(); item_list.item_selected.emit(index)
			else:
				var next := item_list.find_valid_focus_neighbor(SIDE_TOP if direction[1] < 0 else SIDE_BOTTOM)
				if next != null: next.grab_focus()
			get_viewport().set_input_as_handled(); return
		return
	if Bindings.pressed(event,"menu_cancel"):
		if page == "load": action_requested.emit("close",{})
		elif page != "home": open("home")
		get_viewport().set_input_as_handled()
	elif Bindings.pressed(event,"menu_accept"):
		var focused := get_viewport().gui_get_focus_owner() as Button
		if focused != null and not focused.disabled and not is_instance_valid(controller_button):
			controller_button = focused; focused.button_down.emit(); get_viewport().set_input_as_handled()
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
	if is_instance_valid(controller_button): controller_button.button_up.emit()
	controller_button = null
	active_button = null
	name_dialog.hide(); overwrite_dialog.hide(); info_dialog.hide(); hide()

func _wire_slot_focus() -> Array[Button]:
	var slots: Array[Button] = []
	for node in button_nodes:
		if node.name.begins_with("choose_slot") and not node.disabled: slots.append(node)
	var done: Button = button_nodes[0]
	for index in range(slots.size()):
		slots[index].focus_neighbor_top = slots[index].get_path_to(slots[index - 1] if index > 0 else done)
		slots[index].focus_neighbor_bottom = slots[index].get_path_to(slots[index + 1] if index + 1 < slots.size() else done)
	if not slots.is_empty():
		done.focus_neighbor_bottom = done.get_path_to(slots[0]); done.focus_neighbor_top = done.get_path_to(slots[-1])
	return slots

func _restore_slot_focus() -> void:
	for node in button_nodes:
		if node.name == "choose_slot_" + str(pending_slot) and not node.disabled:
			node.grab_focus(); return
	for node in button_nodes:
		if node.name.begins_with("choose_slot") and not node.disabled:
			node.grab_focus(); return

func _dialog_input(dialog: ConfirmationDialog, event: InputEvent) -> void:
	if not dialog.visible: return
	if Bindings.pressed(event,"menu_cancel"):
		dialog.hide(); _restore_slot_focus(); dialog.get_viewport().set_input_as_handled()
	elif Bindings.pressed(event,"menu_accept"):
		var focus := dialog.get_viewport().gui_get_focus_owner()
		if focus == dialog.get_cancel_button(): dialog.hide(); _restore_slot_focus()
		else: dialog.hide(); dialog.confirmed.emit()
		dialog.get_viewport().set_input_as_handled()
	else:
		for direction in [["menu_left",SIDE_LEFT],["menu_right",SIDE_RIGHT],["menu_up",SIDE_TOP],["menu_down",SIDE_BOTTOM]]:
			if not Bindings.pressed(event,direction[0]): continue
			var focus := dialog.get_viewport().gui_get_focus_owner()
			var next: Control = focus.find_valid_focus_neighbor(direction[1]) if focus != null else dialog.get_ok_button()
			if next != null: next.grab_focus()
			dialog.get_viewport().set_input_as_handled(); break
