extends Window

signal applied
signal download_started
signal download_finished(success: bool)
signal download_progress(message: String, fraction: float)
const Mods = preload("res://mod_registry.gd")
const Official = preload("res://official_mods.gd")
var official: Node
var applying := false
var persist_preferences := true
var rows: VBoxContainer
var info: Label
var choices := {}
var pending_order: Array[String] = []
var pending_enabled: Array[String] = []
var embedded := false
var content: MarginContainer
var scroll: ScrollContainer
var refresh_button: Button
var apply_button: Button
var cancel_button: Button
var description: Label
var selected_id := ""

func _ready() -> void:
	# Main-menu gameplay is paused; this window must still receive GUI input.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if official == null: official = Official.new()
	add_child(official)
	official.progress.connect(func(message: String, fraction: float) -> void: download_progress.emit(message,fraction))
	if persist_preferences: official.load_cached()
	title = "Mods"
	size = Vector2i(850, 600)
	min_size = Vector2i(650, 450)
	exclusive = true
	close_requested.connect(func() -> void: if not applying: hide())
	var margin := MarginContainer.new()
	content = margin
	# Keep these styles on the content so the editor's embedded Mods tab and
	# the game's popup use the same readable controls.
	margin.theme = _control_theme()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "Enable mods · Later entries take priority"
	heading.add_theme_font_size_override("font_size", 20)
	column.add_child(heading)
	var hint := Label.new()
	hint.text = "Put a mod folder containing mod.json into %s." % preload("res://player_storage.gd").mods_path()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var refresh := Button.new()
	refresh_button = refresh
	refresh.text = "Refresh mods"
	refresh.pressed.connect(func() -> void: Mods.refresh(); open())
	column.add_child(refresh)
	scroll = ScrollContainer.new(); scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var details := ScrollContainer.new()
	details.custom_minimum_size.y = 85
	details.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(details)
	description = Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(description)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(info)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var apply := Button.new()
	apply_button = apply
	apply.text = "Apply"
	apply.pressed.connect(_apply)
	buttons.add_child(apply)
	var cancel := Button.new()
	cancel_button = cancel
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: open() if embedded else hide())
	buttons.add_child(cancel)
	visible = false

func _control_theme() -> Theme:
	var result := Theme.new()
	for kind in ["Button","CheckBox"]:
		result.set_color("font_color",kind,Color("edf7f8"))
		result.set_color("font_hover_color",kind,Color.WHITE)
		result.set_color("font_pressed_color",kind,Color.WHITE)
		result.set_color("font_disabled_color",kind,Color("93a8ad"))
	for state in ["normal","hover","pressed","disabled","focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("203c46") if state == "normal" else Color("315a65")
		box.border_color = Color("789fa8") if state == "normal" else Color("79dfdb")
		if state == "disabled": box.bg_color = Color("1c3038"); box.border_color = Color("516b73")
		if state == "focus": box.bg_color = Color.TRANSPARENT
		box.set_border_width_all(2 if state == "focus" else 1)
		box.set_corner_radius_all(4)
		box.content_margin_left = 10; box.content_margin_right = 10
		box.content_margin_top = 5; box.content_margin_bottom = 5
		result.set_stylebox(state,"Button",box)
	for checked in [false,true]:
		for disabled in [false,true]:
			var icon := _checkbox_icon(checked,disabled)
			var key := "checked" if checked else "unchecked"
			if disabled: key += "_disabled"
			result.set_icon(key,"CheckBox",icon)
			result.set_icon(key + "_mirrored","CheckBox",icon)
	result.set_constant("h_separation","CheckBox",10)
	return result

func _checkbox_icon(checked: bool, disabled: bool) -> Texture2D:
	var border := "#879fa6" if disabled else "#d4f3f2"
	var tick := "#879fa6" if disabled else "#79efdb"
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><rect x="2" y="2" width="20" height="20" rx="3" fill="#17323c" stroke="%s" stroke-width="2"/>' % border
	if checked: svg += '<path d="M6 12 L10 16 L18 8" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>' % tick
	svg += '</svg>'
	var image := Image.new(); image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)

func embed(parent: Control) -> void:
	embedded = true
	content.reparent(parent)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	open()

func open() -> void:
	if applying: return
	Mods.ensure(persist_preferences)
	pending_order = Mods.order.duplicate()
	pending_enabled = Mods.enabled.duplicate()
	_add_catalogue_order()
	_build_rows()
	if not embedded:
		popup_centered()
		if not choices.is_empty(): choices.values()[0].grab_focus()
	if persist_preferences: _refresh_catalogue()

func _listed_packs() -> Array[Dictionary]:
	var listed: Array[Dictionary] = []
	for pack in Mods.packs:
		var item: Dictionary = pack.duplicate()
		var update: Dictionary = official.update_for(pack)
		if not update.is_empty(): item["update"] = update
		listed.append(item)
	for entry in official.entries:
		if listed.any(func(pack: Dictionary) -> bool: return pack.id == entry.id): continue
		listed.append({"id":entry.id,"name":entry.name,"version":entry.version,"description":entry.description,"valid":Official.compatible(entry.min_game_version),"errors":[] if Official.compatible(entry.min_game_version) else ["Requires OpenSC " + entry.min_game_version + "."],"installed":false,"size":entry.size})
	return listed

func _add_catalogue_order() -> void:
	for pack in _listed_packs():
		if str(pack.id) not in pending_order: pending_order.append(str(pack.id))

func _refresh_catalogue() -> void:
	if official.fetching or applying: return
	refresh_button.disabled = true
	await official.refresh_catalogue()
	refresh_button.disabled = false
	if applying: return
	_add_catalogue_order()
	_build_rows()

func _input(event: InputEvent) -> void:
	if embedded or not visible or applying: return
	var bindings = preload("res://input_bindings.gd")
	if bindings.pressed(event,"menu_cancel"):
		hide(); get_viewport().set_input_as_handled(); return
	for direction in [["menu_up",SIDE_TOP],["menu_down",SIDE_BOTTOM],["menu_left",SIDE_LEFT],["menu_right",SIDE_RIGHT]]:
		if not bindings.pressed(event,direction[0]): continue
		var focused := get_viewport().gui_get_focus_owner() as Control
		if focused != null:
			var next := focused.find_valid_focus_neighbor(direction[1])
			if next != null: next.grab_focus()
		get_viewport().set_input_as_handled(); return

func _build_rows() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var focused_id: String = str(focused.get_meta("mod_id","")) if focused != null else ""
	var focused_column: int = int(focused.get_meta("mod_column",0)) if focused != null else 0
	var lines: Array[Array] = []
	for child in rows.get_children(): child.free()
	choices.clear()
	for id in pending_order:
		var pack := {}
		for candidate in _listed_packs():
			if str(candidate.id) == id: pack = candidate; break
		if pack.is_empty(): continue
		var item := VBoxContainer.new()
		rows.add_child(item)
		var line := HBoxContainer.new()
		item.add_child(line)
		var enabled := CheckBox.new()
		enabled.text = "%s · %s" % [pack.name, pack.version]
		if pack.get("installed",true): enabled.text += " · Installed"
		else: enabled.text += " · Not installed · " + String.humanize_size(int(pack.size))
		if pack.has("update"):
			if Official.compatible(pack.update.min_game_version): enabled.text += "\nUpdate available: " + str(pack.update.version) + " · " + String.humanize_size(int(pack.update.size))
			else: enabled.text += "\nUpdate requires OpenSC " + str(pack.update.min_game_version)
		enabled.disabled = not pack.valid
		enabled.button_pressed = id in pending_enabled and pack.valid
		enabled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		enabled.toggled.connect(func(on: bool) -> void:
			if on and id not in pending_enabled: pending_enabled.append(id)
			elif not on: pending_enabled.erase(id)
			_show_description(id)
			_update_info()
		)
		line.add_child(enabled)
		choices[id] = enabled
		var controls: Array = [enabled]
		for direction in [-1, 1]:
			var move := Button.new()
			move.text = "Earlier" if direction == -1 else "Later"
			move.pressed.connect(func() -> void:
				_show_description(id)
				var index := pending_order.find(id)
				var target := clampi(index + direction, 0, pending_order.size() - 1)
				pending_order.remove_at(index)
				pending_order.insert(target, id)
				_build_rows()
			,CONNECT_DEFERRED)
			line.add_child(move)
			controls.append(move)
		for index in range(controls.size()):
			var control: Control = controls[index]
			control.set_meta("mod_id",id); control.set_meta("mod_column",index)
			control.focus_entered.connect(func() -> void: _show_description(id); scroll.ensure_control_visible(control))
			control.mouse_entered.connect(func() -> void: _show_description(id))
			if str(id) == focused_id and index == focused_column: control.grab_focus()
		lines.append(controls)
	_wire_focus(lines)
	_show_description(selected_id if selected_id in choices else "")
	_update_info()

func _show_description(id: String) -> void:
	selected_id = id
	description.text = ""
	for pack in _listed_packs():
		if str(pack.id) != id: continue
		description.text = str(pack.description)
		if not pack.errors.is_empty(): description.text += "\n" + "\n".join(pack.errors)
		if pack.has("update") and not Official.compatible(pack.update.min_game_version): description.text += "\nRequires OpenSC " + str(pack.update.min_game_version) + "."
		break
	if description.get_parent() is ScrollContainer: description.get_parent().scroll_vertical = 0

func _wire_focus(lines: Array[Array]) -> void:
	for column in range(3):
		var chain: Array[Control] = [refresh_button]
		for line in lines:
			var control: BaseButton = line[column]
			if not control.disabled: chain.append(control)
		chain.append(apply_button if column < 2 else cancel_button)
		for index in range(1,chain.size() - 1):
			chain[index].focus_neighbor_top = chain[index].get_path_to(chain[index - 1])
			chain[index].focus_neighbor_bottom = chain[index].get_path_to(chain[index + 1])
		if column == 0:
			refresh_button.focus_neighbor_bottom = refresh_button.get_path_to(chain[1])
			apply_button.focus_neighbor_top = apply_button.get_path_to(chain[-2])
		if column == 2: cancel_button.focus_neighbor_top = cancel_button.get_path_to(chain[-2])
	for line in lines:
		for column in range(3):
			var control: Control = line[column]
			control.focus_neighbor_left = control.get_path_to(line[maxi(0,column - 1)])
			control.focus_neighbor_right = control.get_path_to(line[mini(2,column + 1)])

func _update_info() -> void:
	info.text = "No mods installed." if _listed_packs().is_empty() else ""
	if not official.last_error.is_empty(): info.text += "\n" + official.last_error
	var notes: Array[String] = Mods.runtime_warnings.duplicate()
	if not notes.is_empty(): info.text += "\n" + "\n".join(notes.slice(0, 5))
	if notes.size() > 5: info.text += "\n%d more notes (hover to read)." % (notes.size() - 5)
	info.tooltip_text = "\n".join(notes)
	info.visible = not info.text.strip_edges().is_empty()

func _apply() -> void:
	_commit_apply()

func _commit_apply() -> void:
	if applying: return
	var updates: Array[String] = []
	for pack in Mods.packs:
		if str(pack.id) not in pending_enabled: continue
		var update: Dictionary = official.update_for(pack)
		if not update.is_empty() and Official.compatible(update.min_game_version): updates.append(str(pack.id))
	var downloading: bool = not official.missing(pending_enabled).is_empty() or not updates.is_empty()
	if downloading:
		applying = true
		hide()
		download_started.emit()
		await get_tree().process_frame
		if not await official.install(pending_enabled,updates):
			applying = false
			download_finished.emit(false)
			if not embedded: popup_centered()
			info.text = official.last_error; info.show()
			return
	var result := Mods.apply(pending_enabled, pending_order, persist_preferences)
	applying = false
	if downloading: download_finished.emit(result == OK)
	if result != OK:
		if not embedded: popup_centered()
		info.text = "Could not save mod selection: " + error_string(result)
		info.show()
		return
	hide()
	applied.emit()
