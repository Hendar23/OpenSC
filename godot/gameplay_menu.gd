extends CanvasLayer

const Bindings = preload("res://input_bindings.gd")
const Storage = preload("res://player_storage.gd")
signal closed
signal auto_aim_changed(enabled: bool)
var remember_preferences := true
var settings_path := ""
var zapper_auto_aim := false
var layout: Control
var toggle: Button
var back: Button
var status: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS; layer = 12
	if settings_path.is_empty(): settings_path = Storage.preferences_path()
	var config := ConfigFile.new()
	if remember_preferences and config.load(settings_path) == OK:
		zapper_auto_aim = bool(config.get_value("gameplay","zapper_auto_aim",false))
	var shade := ColorRect.new(); shade.color = Color.TRANSPARENT
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(shade)
	layout = Control.new(); layout.size = Vector2(640,480); shade.add_child(layout)
	toggle = _button(Vector2(196,174),Vector2(248,28)); toggle.pressed.connect(_toggle)
	back = _button(Vector2(216,219),Vector2(208,28)); back.text = "Back"; back.pressed.connect(close_menu)
	status = Label.new(); status.position = Vector2(160,265); status.size = Vector2(320,60)
	status.add_theme_font_size_override("font_size",14); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; layout.add_child(status)
	get_viewport().size_changed.connect(_layout); _layout(); _refresh(); hide()

func _button(point: Vector2,dimensions: Vector2) -> Button:
	var button := Button.new(); button.position = point; button.size = dimensions
	button.add_theme_font_size_override("font_size",14)
	var normal := StyleBoxFlat.new(); normal.bg_color = Color(0.01,0.05,0.07,0.82)
	normal.border_color = Color(0.24,0.55,0.6,0.7); normal.set_border_width_all(1); normal.set_corner_radius_all(5)
	var hover := normal.duplicate() as StyleBoxFlat; hover.bg_color = Color(0.04,0.23,0.28,0.95)
	button.add_theme_stylebox_override("normal",normal)
	for state in ["hover","pressed","focus"]: button.add_theme_stylebox_override(state,hover)
	layout.add_child(button); return button

func _refresh() -> void:
	toggle.text = "Zapper auto aim: %s" % ("On" if zapper_auto_aim else "Off")

func _toggle() -> void:
	zapper_auto_aim = not zapper_auto_aim
	_refresh(); auto_aim_changed.emit(zapper_auto_aim)
	status.text = ""
	if not remember_preferences: return
	var config := ConfigFile.new(); var result := config.load(settings_path)
	if result == OK or result == ERR_FILE_NOT_FOUND:
		config.set_value("gameplay","zapper_auto_aim",zapper_auto_aim)
		result = Storage.ensure_parent(settings_path)
		if result == OK: result = config.save(settings_path)
	if result != OK: status.text = "Could not save gameplay settings: %s" % error_string(result)

func open_menu() -> void:
	_refresh(); status.text = ""; show(); toggle.grab_focus()

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
	if Bindings.pressed(event,"menu_cancel"): close_menu()
	elif Bindings.pressed(event,"menu_up") or Bindings.pressed(event,"menu_down"):
		if toggle.has_focus(): back.grab_focus()
		else: toggle.grab_focus()
	elif toggle.has_focus() and (Bindings.pressed(event,"menu_left") or Bindings.pressed(event,"menu_right")): _toggle()
	elif Bindings.pressed(event,"menu_accept"):
		if toggle.has_focus(): _toggle()
		elif back.has_focus(): close_menu()
	else: return
	get_viewport().set_input_as_handled()
