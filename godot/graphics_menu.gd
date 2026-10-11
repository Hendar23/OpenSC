extends CanvasLayer

const Bindings = preload("res://input_bindings.gd")
signal closed
var graphics: Node
var layout: Control
var controls := {}
var labels := {}
var order: Array[Control] = []
var status: Label
var back: Button
var normal: StyleBoxFlat
var hover: StyleBoxFlat

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS; layer = 12
	var shade := ColorRect.new(); shade.color = Color.TRANSPARENT
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(shade)
	layout = Control.new(); layout.size = Vector2(640,480); shade.add_child(layout)
	normal = StyleBoxFlat.new(); normal.bg_color = Color(0.01,0.05,0.07,0.82)
	normal.border_color = Color(0.24,0.55,0.6,0.7); normal.set_border_width_all(1); normal.set_corner_radius_all(5)
	hover = normal.duplicate(); hover.bg_color = Color(0.04,0.23,0.28,0.95)
	for entry in [["display_mode","Display mode"],["resolution","Resolution"],["vsync","VSync"],["frame_limit","Frame-rate limit"],["anti_aliasing","Anti-aliasing"],["shadows","Shadow quality"],["brightness","Brightness"]]:
		_add_row(entry[0],entry[1])
	status = Label.new(); status.position = Vector2(120,449); status.size = Vector2(400,28)
	status.add_theme_font_size_override("font_size",12); layout.add_child(status)
	back = _button("Back"); back.position = Vector2(216,389); back.size = Vector2(208,28)
	layout.add_child(back); back.pressed.connect(close_menu); order.append(back)
	get_viewport().size_changed.connect(_layout); _layout(); hide()

func _button(text: String) -> Button:
	var button := Button.new(); button.text = text; button.add_theme_font_size_override("font_size",14)
	button.add_theme_stylebox_override("normal",normal)
	for state in ["hover","pressed","focus"]: button.add_theme_stylebox_override(state,hover)
	return button

func _add_row(key: String,title: String) -> void:
	var y := 174 + controls.size() * 30
	var panel := Panel.new(); panel.position = Vector2(120,y); panel.size = Vector2(400,28)
	panel.add_theme_stylebox_override("panel",normal); panel.mouse_filter = Control.MOUSE_FILTER_IGNORE; layout.add_child(panel)
	var label := Label.new(); label.position = Vector2(130,y); label.size = Vector2(178,28)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; label.text = title
	label.add_theme_font_size_override("font_size",14); layout.add_child(label); labels[key] = label
	var control: Control
	if key == "brightness":
		var slider := HSlider.new(); slider.min_value = 50; slider.max_value = 150
		slider.step = 1; slider.scrollable = false
		slider.value_changed.connect(func(value: float) -> void: _change(key,value))
		control = slider
	else:
		var button := _button(""); button.pressed.connect(func() -> void: _cycle(key,1)); control = button
	control.position = Vector2(312,y + 2); control.size = Vector2(198,24)
	layout.add_child(control); controls[key] = control; order.append(control)

func _choices(key: String) -> Array:
	match key:
		"display_mode": return [0,1,2]
		"resolution": return graphics.resolutions()
		"vsync": return [true,false]
		"frame_limit": return graphics.FRAME_LIMITS
		"anti_aliasing", "shadows": return [0,1,2,3]
	return []

func _cycle(key: String,direction: int) -> void:
	var values := _choices(key)
	_change(key,values[posmod(values.find(graphics.settings[key]) + direction,values.size())])

func _change(key: String,value: Variant) -> void:
	var result: Error = graphics.set_value(key,value)
	status.text = "" if result == OK else "Could not save graphics settings: %s" % error_string(result)
	_refresh()

func _refresh() -> void:
	for key in controls:
		var value: Variant = graphics.settings[key]
		if controls[key] is HSlider:
			controls[key].set_value_no_signal(value)
			labels[key].text = "Brightness: %d%%" % roundi(value)
		else:
			var text := ""
			match key:
				"display_mode": text = ["Fullscreen","Borderless","Windowed"][int(value)]
				"resolution": text = "%d × %d" % [value.x,value.y]
				"vsync": text = "On" if value else "Off"
				"frame_limit": text = "Unlimited" if int(value) == 0 else "%d FPS" % value
				"anti_aliasing": text = ["Off","MSAA 2×","MSAA 4×","MSAA 8×"][int(value)]
				"shadows": text = ["Off","Low","Medium","High"][int(value)]
			controls[key].text = "‹  %s  ›" % text

func open_menu() -> void:
	_refresh(); status.text = ""; show(); order[0].grab_focus()

func close_menu() -> void:
	if not visible: return
	hide(); closed.emit()

func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var factor := minf(viewport.x / 640.0,viewport.y / 480.0)
	layout.scale = Vector2.ONE * factor
	layout.position = (viewport - Vector2(640,480) * factor) * 0.5

func _input(event: InputEvent) -> void:
	if not visible: return
	var focused := get_viewport().gui_get_focus_owner()
	if Bindings.pressed(event,"menu_cancel"):
		close_menu()
	elif Bindings.pressed(event,"menu_up") or Bindings.pressed(event,"menu_down"):
		var step := 1 if Bindings.pressed(event,"menu_down") else -1
		order[posmod(order.find(focused) + step,order.size())].grab_focus()
	elif Bindings.pressed(event,"menu_left") or Bindings.pressed(event,"menu_right"):
		var step := 1 if Bindings.pressed(event,"menu_right") else -1
		if focused is HSlider: focused.value += step
		else:
			for key in controls:
				if controls[key] == focused: _cycle(key,step); break
	elif Bindings.pressed(event,"menu_accept"):
		if focused is Button: focused.pressed.emit()
	else: return
	get_viewport().set_input_as_handled()
