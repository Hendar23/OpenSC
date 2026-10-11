extends CanvasLayer

const Bindings = preload("res://input_bindings.gd")
signal closed
var effects: Node
var layout: Control
var slider: HSlider
var caption: Label
var status: Label
var back: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS; layer = 12
	# Keep the main menu's live backdrop and title visible; only replace its controls.
	var shade := ColorRect.new(); shade.color = Color.TRANSPARENT
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(shade)
	layout = Control.new(); layout.size = Vector2(640,480); shade.add_child(layout)
	var normal := StyleBoxFlat.new(); normal.bg_color = Color(0.01,0.05,0.07,0.82)
	normal.border_color = Color(0.24,0.55,0.6,0.7); normal.set_border_width_all(1); normal.set_corner_radius_all(5)
	var volume_panel := Panel.new(); volume_panel.position = Vector2(216,174); volume_panel.size = Vector2(208,62)
	volume_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	volume_panel.add_theme_stylebox_override("panel",normal); layout.add_child(volume_panel)
	caption = Label.new(); caption.position = Vector2(216,174); caption.size = Vector2(208,28)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",14); layout.add_child(caption)
	slider = HSlider.new(); slider.position = Vector2(228,205); slider.size = Vector2(184,28)
	slider.min_value = 0; slider.max_value = effects.MAX_VOLUME; slider.step = 1; slider.scrollable = false
	layout.add_child(slider); slider.value_changed.connect(_changed)
	status = Label.new(); status.position = Vector2(160,292); status.size = Vector2(320,60)
	status.add_theme_font_size_override("font_size",14)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; layout.add_child(status)
	back = Button.new(); back.text = "Back"; back.position = Vector2(216,248); back.size = Vector2(208,28)
	back.add_theme_font_size_override("font_size",14)
	var hover := normal.duplicate() as StyleBoxFlat; hover.bg_color = Color(0.04,0.23,0.28,0.95)
	back.add_theme_stylebox_override("normal",normal)
	for state in ["hover","pressed","focus"]: back.add_theme_stylebox_override(state,hover)
	layout.add_child(back); back.pressed.connect(close_menu)
	get_viewport().size_changed.connect(_layout); _layout(); hide()

func open_menu() -> void:
	slider.set_value_no_signal(effects.volume)
	_update_caption(); status.text = ""; show(); slider.grab_focus()

func close_menu() -> void:
	if not visible: return
	hide(); closed.emit()

func _changed(value: float) -> void:
	var result: Error = effects.set_volume(value)
	status.text = "" if result == OK else "Could not automatically save audio settings: %s" % error_string(result)
	_update_caption()

func _update_caption() -> void:
	caption.text = "Effects volume: %d%%" % roundi(slider.value)

func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var factor := minf(viewport.x / 640.0,viewport.y / 480.0)
	layout.scale = Vector2.ONE * factor
	layout.position = (viewport - Vector2(640,480) * factor) * 0.5

func _input(event: InputEvent) -> void:
	if not visible: return
	if Bindings.pressed(event,"menu_cancel"):
		close_menu()
	elif Bindings.pressed(event,"menu_up") or Bindings.pressed(event,"menu_down"):
		if slider.has_focus(): back.grab_focus()
		else: slider.grab_focus()
	elif slider.has_focus() and (Bindings.pressed(event,"menu_left") or Bindings.pressed(event,"menu_right")):
		slider.value += 1 if Bindings.pressed(event,"menu_right") else -1
	elif Bindings.pressed(event,"menu_accept"):
		if back.has_focus(): close_menu()
		else: back.grab_focus()
	else: return
	get_viewport().set_input_as_handled()
