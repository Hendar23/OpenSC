extends CanvasLayer
const Bindings = preload("res://input_bindings.gd")
const Mods = preload("res://mod_registry.gd")
signal closed
var layout: Control
var rows: VBoxContainer
var scroll: ScrollContainer
var status: Label
var back: Button
var reset: Button
var cancel: Button
var binding_buttons := {}
var navigation_rows: Array = []
var config := {}
var capture_action := ""
var capture_slot := 0
var pending: InputEvent
var settings_path := Bindings.CONFIG_PATH

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS; layer = 12
	Bindings.install()
	config = JSON.parse_string(FileAccess.get_file_as_string("res://game_assets/ui/controls.json"))
	for replacement in Mods.candidates("ui.controls"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(replacement.path))
		if data is Dictionary and data.get("schema_version") == 1: config.merge(data,true); break
	var shade := ColorRect.new(); shade.color = Color(0.005,0.025,0.04,0.97); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(shade)
	layout = Control.new(); layout.size = Vector2(960,640); shade.add_child(layout)
	var title := Label.new(); title.text = str(config.title); title.position = Vector2(32,20); title.add_theme_font_size_override("font_size",30); layout.add_child(title)
	for column in [["Action",32],["Binding 1",275],["Binding 2",591]]:
		var header := Label.new(); header.text = column[0]; header.position = Vector2(column[1],76); layout.add_child(header)
	scroll = ScrollContainer.new(); scroll.position = Vector2(32,106); scroll.size = Vector2(896,409); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; layout.add_child(scroll)
	scroll.follow_focus = true
	rows = VBoxContainer.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rows.add_theme_constant_override("separation",6); scroll.add_child(rows)
	var shown := {}
	for group in config.groups:
		if not config.groups[group].any(func(action: String) -> bool: return Bindings.bindings.has(action)): continue
		var heading := Label.new(); heading.text = str(group); heading.add_theme_color_override("font_color",Color(0.4,0.85,0.9)); heading.add_theme_font_size_override("font_size",20); rows.add_child(heading)
		for action in config.groups[group]:
			if Bindings.bindings.has(action) and not shown.has(action): _add_row(action); shown[action] = true
	for action in Bindings.bindings:
		if not shown.has(action): _add_row(action)
	status = Label.new(); status.position = Vector2(32,528); status.size = Vector2(896,45); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.add_theme_font_size_override("font_size",16); layout.add_child(status)
	back = _footer("Back",Vector2(748,590)); back.pressed.connect(close_menu)
	reset = _footer("Restore defaults",Vector2(32,590)); reset.pressed.connect(func() -> void: Bindings.reset_defaults(); _persist(); refresh())
	cancel = _footer("Cancel binding",Vector2(350,590)); cancel.pressed.connect(cancel_capture); cancel.hide()
	get_viewport().size_changed.connect(_layout); _layout(); hide()

func _footer(text: String, point: Vector2) -> Button:
	var button := Button.new(); button.text = text; button.position = point; button.size = Vector2(180,34); layout.add_child(button); return button

func _add_row(action: String) -> void:
	var row := HBoxContainer.new(); rows.add_child(row)
	var navigation: Array = []; navigation_rows.append(navigation)
	var caption := Label.new(); caption.text = str(config.labels.get(action,action.replace("_"," ").capitalize())); caption.custom_minimum_size.x = 235; row.add_child(caption)
	binding_buttons[action] = []
	for slot in range(2):
		var button := Button.new(); button.text = Bindings.describe(Bindings.bindings[action][slot]); button.custom_minimum_size = Vector2(265,32); button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",16); row.add_child(button); binding_buttons[action].append(button)
		navigation.append(button)
		button.pressed.connect(begin_capture.bind(action,slot))
		var clear := Button.new(); clear.text = "X"; clear.tooltip_text = "Clear this binding"; clear.custom_minimum_size.x = 30; row.add_child(clear)
		navigation.append(clear)
		clear.pressed.connect(func() -> void: Bindings.set_binding(action,slot,null); _persist(); refresh())

func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var scale_factor := minf(viewport.x / 960.0,viewport.y / 640.0)
	layout.scale = Vector2.ONE * scale_factor; layout.position = (viewport - Vector2(960,640) * scale_factor) * 0.5

func open_menu() -> void:
	cancel_capture(); refresh(); show(); back.grab_focus()
	status.text = "Changes save automatically. Either slot can use keyboard, mouse or controller."

func close_menu() -> void:
	var was_visible := visible
	cancel_capture(); hide()
	if was_visible: closed.emit()

func refresh() -> void:
	for action in binding_buttons:
		for slot in range(2): binding_buttons[action][slot].text = Bindings.describe(Bindings.bindings[action][slot])

func begin_capture(action: String, slot: int) -> void:
	capture_action = action; capture_slot = slot; pending = null; Bindings.capture_active = true
	cancel.show(); back.disabled = true; reset.disabled = true
	status.text = "Listening for %s, binding %d... Press and release one button, or hold it and press another. Click Cancel binding to stop." % [str(config.labels.get(action,action.replace("_"," ").capitalize())),slot + 1]

func cancel_capture() -> void:
	capture_action = ""; pending = null; Bindings.capture_active = false
	if cancel != null: cancel.hide(); back.disabled = false; reset.disabled = false
	if status != null: status.text = "Changes save automatically. Either slot can use keyboard, mouse or controller."

func _persist() -> void:
	status.text = "Bindings saved." if Bindings.save_settings(settings_path) == OK else "Bindings changed for this session, but the settings file could not be saved."

func _finish(value: Dictionary) -> void:
	var action := capture_action; var slot := capture_slot
	if not Bindings.set_binding(action,slot,value):
		status.text = "F1 is reserved for the developer menu. Choose another control."
		return
	cancel_capture(); refresh(); _persist()
	binding_buttons[action][slot].grab_focus()

func capture_event(event: InputEvent) -> void:
	if event.is_echo(): return
	if event is InputEventKey:
		var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
		if code in [KEY_SHIFT,KEY_CTRL,KEY_ALT,KEY_META] and event.pressed: pending = event.duplicate(); return
		if not event.pressed and (pending == null or not pending is InputEventKey or code != (pending.keycode if pending.keycode != 0 else pending.physical_keycode)): return
		if event.pressed or pending != null:
			_finish({"kind":"key","code":event.physical_keycode if event.physical_keycode != 0 else code,"physical":event.physical_keycode != 0,"ctrl":event.ctrl_pressed and code != KEY_CTRL,"alt":event.alt_pressed and code != KEY_ALT,"shift":event.shift_pressed and code != KEY_SHIFT,"meta":event.meta_pressed and code != KEY_META})
	elif event is InputEventMouseButton and event.pressed:
		_finish({"kind":"mouse","button":event.button_index})
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.65:
		_finish({"kind":"axis","axis":event.axis,"sign":1 if event.axis_value > 0 else -1})
	elif event is InputEventJoypadButton:
		if event.pressed:
			if pending is InputEventJoypadButton and pending.device == event.device and pending.button_index != event.button_index:
				_finish({"kind":"button","button":event.button_index,"modifier":pending.button_index})
			else: pending = event.duplicate()
		elif pending is InputEventJoypadButton and pending.device == event.device and pending.button_index == event.button_index:
			_finish({"kind":"button","button":event.button_index,"modifier":-1})

func _move_focus(direction: int) -> void:
	var selected := get_viewport().gui_get_focus_owner()
	for row in range(navigation_rows.size()):
		var column: int = navigation_rows[row].find(selected)
		if column < 0: continue
		match direction:
			SIDE_TOP:
				if row > 0: navigation_rows[row - 1][column].grab_focus()
			SIDE_BOTTOM:
				if row + 1 < navigation_rows.size(): navigation_rows[row + 1][column].grab_focus()
				else: (reset if column < 2 else back).grab_focus()
			SIDE_LEFT:
				if column > 0: navigation_rows[row][column - 1].grab_focus()
			SIDE_RIGHT:
				if column < 3: navigation_rows[row][column + 1].grab_focus()
		return
	if direction == SIDE_TOP and not navigation_rows.is_empty():
		navigation_rows.back()[0 if selected == reset else 2].grab_focus()
	elif direction == SIDE_LEFT: reset.grab_focus()
	elif direction == SIDE_RIGHT: back.grab_focus()

func _input(event: InputEvent) -> void:
	if not visible: return
	if not capture_action.is_empty():
		# Mouse clicks on Cancel are handled by the button, not captured as a binding.
		if event is InputEventMouseButton and cancel.get_global_rect().has_point(event.position): return
		capture_event(event); get_viewport().set_input_as_handled(); return
	if Bindings.pressed(event,"menu_cancel"): close_menu(); get_viewport().set_input_as_handled(); return
	var selected := get_viewport().gui_get_focus_owner()
	if Bindings.pressed(event,"menu_accept") and selected is Button:
		selected.pressed.emit(); get_viewport().set_input_as_handled()
	else:
		for direction in [["menu_up",SIDE_TOP],["menu_down",SIDE_BOTTOM],["menu_left",SIDE_LEFT],["menu_right",SIDE_RIGHT]]:
			if Bindings.pressed(event,direction[0]):
				_move_focus(direction[1]); get_viewport().set_input_as_handled(); return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
