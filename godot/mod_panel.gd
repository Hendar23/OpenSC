extends Window

signal applied
const Mods = preload("res://mod_registry.gd")
var persist_preferences := true
var rows: VBoxContainer
var info: Label
var choices := {}
var pending_order: Array[String] = []
var pending_enabled: Array[String] = []
var embedded := false
var content: MarginContainer
var apply_confirmation: ConfirmationDialog

func _ready() -> void:
	# Main-menu gameplay is paused; this window must still receive GUI input.
	process_mode = Node.PROCESS_MODE_ALWAYS
	title = "Mods"
	size = Vector2i(850, 600)
	min_size = Vector2i(650, 450)
	exclusive = true
	close_requested.connect(hide)
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
	hint.text = "Put a mod folder containing mod.json into Mods."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var refresh := Button.new()
	refresh.text = "Refresh installed mods"
	refresh.pressed.connect(func() -> void: Mods.refresh(); open())
	column.add_child(refresh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.y = 70
	column.add_child(info)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(_apply)
	buttons.add_child(apply)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: open() if embedded else hide())
	buttons.add_child(cancel)
	apply_confirmation = ConfirmationDialog.new()
	apply_confirmation.title = "Apply mods?"
	apply_confirmation.dialog_text = "Applying these changes will end the current game.\nAny unsaved progress will be lost."
	apply_confirmation.ok_button_text = "OK"
	apply_confirmation.cancel_button_text = "Cancel"
	apply_confirmation.confirmed.connect(_commit_apply,CONNECT_DEFERRED)
	add_child(apply_confirmation)
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
	Mods.ensure(persist_preferences)
	pending_order = Mods.order.duplicate()
	pending_enabled = Mods.enabled.duplicate()
	_build_rows()
	if not embedded:
		popup_centered()
		if not choices.is_empty(): choices.values()[0].grab_focus()

func _input(event: InputEvent) -> void:
	if not embedded and visible and preload("res://input_bindings.gd").pressed(event,"menu_cancel"):
		hide(); get_viewport().set_input_as_handled()

func _build_rows() -> void:
	for child in rows.get_children(): child.free()
	choices.clear()
	for id in pending_order:
		var pack := {}
		for candidate in Mods.packs:
			if str(candidate.id) == id: pack = candidate; break
		if pack.is_empty(): continue
		var item := VBoxContainer.new()
		rows.add_child(item)
		var line := HBoxContainer.new()
		item.add_child(line)
		var enabled := CheckBox.new()
		enabled.text = "%s · %s" % [pack.name, pack.version]
		enabled.disabled = not pack.valid
		enabled.button_pressed = id in pending_enabled and pack.valid
		enabled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		enabled.toggled.connect(func(on: bool) -> void:
			if on and id not in pending_enabled: pending_enabled.append(id)
			elif not on: pending_enabled.erase(id)
			_update_info()
		)
		line.add_child(enabled)
		choices[id] = enabled
		for direction in [-1, 1]:
			var move := Button.new()
			move.text = "Earlier" if direction == -1 else "Later"
			move.pressed.connect(func() -> void:
				var index := pending_order.find(id)
				var target := clampi(index + direction, 0, pending_order.size() - 1)
				pending_order.remove_at(index)
				pending_order.insert(target, id)
				_build_rows()
			,CONNECT_DEFERRED)
			line.add_child(move)
		var description := Label.new()
		description.text = str(pack.description)
		if not pack.errors.is_empty(): description.text += "\n" + "\n".join(pack.errors)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.add_child(description)
	_update_info()

func _update_info() -> void:
	info.text = "No mods installed." if Mods.packs.is_empty() else ""
	var notes: Array[String] = []
	var sources := {}
	for id in pending_order:
		for pack in Mods.packs:
			if str(pack.id) != id or not pack.valid or id not in pending_enabled: continue
			var keys: Array = pack.assets.keys()
			for key in pack.movement: keys.append("movement." + str(key))
			for key in keys:
				if sources.has(key): notes.append("%s: %s overrides %s" % [key, pack.name, sources[key]])
				sources[key] = pack.name
	notes.append_array(Mods.runtime_warnings)
	if not notes.is_empty(): info.text += "\n" + "\n".join(notes.slice(0, 5))
	if notes.size() > 5: info.text += "\n%d more notes (hover to read)." % (notes.size() - 5)
	info.tooltip_text = "\n".join(notes)

func _apply() -> void:
	if embedded:
		_commit_apply()
	else:
		apply_confirmation.popup_centered(Vector2i(480,160))
		apply_confirmation.get_cancel_button().grab_focus()

func _commit_apply() -> void:
	var result := Mods.apply(pending_enabled, pending_order, persist_preferences)
	if result != OK:
		info.text = "Could not save mod selection: " + error_string(result)
		return
	hide()
	applied.emit()
