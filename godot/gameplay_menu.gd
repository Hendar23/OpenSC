extends CanvasLayer

const Bindings = preload("res://input_bindings.gd")
const Storage = preload("res://player_storage.gd")
signal closed
signal auto_aim_changed(enabled: bool)
signal wildlife_limit_changed(limit: int)
signal sun_shafts_changed(enabled: bool)
signal replay_changed(enabled: bool)
var replay_button: Button
var replay_enabled := true
var fmvs_enabled := true
var fmv_button: Button
var sun_shafts_enabled := true
var sun_shafts_button: Button
const WILDLIFE_LIMITS := [40,60,80,100,150,200,0]
var wildlife_limit := 80
var wildlife_button: Button
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
		sun_shafts_enabled = bool(config.get_value("gameplay","sun_shafts",true))
		var saved_limit := int(config.get_value("gameplay","wildlife_limit",80))
		if saved_limit in WILDLIFE_LIMITS: wildlife_limit = saved_limit
		replay_enabled = bool(config.get_value("gameplay","photo_replay",true))
		fmvs_enabled = bool(config.get_value("gameplay","play_fmvs",true))
	# Older installations may have selected Classic; enhanced effects now stay on.
	preload("res://mine_explosion.gd").enhanced_enabled = true
	var shade := ColorRect.new(); shade.color = Color.TRANSPARENT
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(shade)
	layout = Control.new(); layout.size = Vector2(640,480); shade.add_child(layout)
	toggle = _button(Vector2(196,150),Vector2(248,28)); toggle.pressed.connect(_toggle)
	wildlife_button = _button(Vector2(196,188),Vector2(248,28)); wildlife_button.pressed.connect(_cycle_wildlife_limit)
	sun_shafts_button = _button(Vector2(196,226),Vector2(248,28)); sun_shafts_button.pressed.connect(_toggle_sun_shafts)
	replay_button = _button(Vector2(196,264),Vector2(248,28)); replay_button.pressed.connect(_toggle_replay)
	fmv_button = _button(Vector2(196,302),Vector2(248,28)); fmv_button.pressed.connect(_toggle_fmvs)
	back = _button(Vector2(216,350),Vector2(208,28)); back.text = "Back"; back.pressed.connect(close_menu)
	status = Label.new(); status.position = Vector2(160,396); status.size = Vector2(320,60)
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
	fmv_button.text = "Play FMVs: %s" % ("On" if fmvs_enabled else "Off")
	replay_button.text = "Photo mode replay: %s" % ("On" if replay_enabled else "Off")
	toggle.text = "Zapper auto aim: %s" % ("On" if zapper_auto_aim else "Off")
	wildlife_button.text = "Active wildlife: %s" % ("Unlimited" if wildlife_limit == 0 else str(wildlife_limit))
	sun_shafts_button.text = "Sun shafts: %s" % ("On" if sun_shafts_enabled else "Off")

func _toggle_replay() -> void:
	replay_enabled = not replay_enabled
	_refresh(); replay_changed.emit(replay_enabled); _save()

func _toggle_fmvs() -> void:
	fmvs_enabled = not fmvs_enabled
	_refresh(); _save()

func _toggle_sun_shafts() -> void:
	sun_shafts_enabled = not sun_shafts_enabled
	_refresh(); sun_shafts_changed.emit(sun_shafts_enabled); _save()

func _toggle() -> void:
	zapper_auto_aim = not zapper_auto_aim
	_refresh(); auto_aim_changed.emit(zapper_auto_aim)
	_save()

func _cycle_wildlife_limit(step: int = 1) -> void:
	wildlife_limit = WILDLIFE_LIMITS[posmod(WILDLIFE_LIMITS.find(wildlife_limit) + step,WILDLIFE_LIMITS.size())]
	_refresh(); wildlife_limit_changed.emit(wildlife_limit); _save()

func _save() -> void:
	status.text = ""
	if not remember_preferences: return
	var config := ConfigFile.new(); var result := config.load(settings_path)
	if result == OK or result == ERR_FILE_NOT_FOUND:
		config.set_value("gameplay","zapper_auto_aim",zapper_auto_aim)
		config.set_value("gameplay","wildlife_limit",wildlife_limit)
		config.set_value("gameplay","sun_shafts",sun_shafts_enabled)
		config.set_value("gameplay","photo_replay",replay_enabled)
		config.set_value("gameplay","play_fmvs",fmvs_enabled)
		if config.has_section_key("gameplay","enhanced_explosions"): config.erase_section_key("gameplay","enhanced_explosions")
		result = Storage.ensure_parent(settings_path)
		if result == OK: result = config.save(settings_path)
	if result != OK: status.text = "Could not save general settings: %s" % error_string(result)

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
		var buttons := [toggle,wildlife_button,sun_shafts_button,replay_button,fmv_button,back]
		var selected := buttons.find(get_viewport().gui_get_focus_owner())
		buttons[posmod(selected + (-1 if Bindings.pressed(event,"menu_up") else 1),buttons.size())].grab_focus()
	elif toggle.has_focus() and (Bindings.pressed(event,"menu_left") or Bindings.pressed(event,"menu_right")): _toggle()
	elif wildlife_button.has_focus() and (Bindings.pressed(event,"menu_left") or Bindings.pressed(event,"menu_right")):
		_cycle_wildlife_limit(-1 if Bindings.pressed(event,"menu_left") else 1)
	elif sun_shafts_button.has_focus() and (Bindings.pressed(event,"menu_left") or Bindings.pressed(event,"menu_right")): _toggle_sun_shafts()
	elif replay_button.has_focus() and (Bindings.pressed(event,"menu_left") or Bindings.pressed(event,"menu_right")): _toggle_replay()
	elif fmv_button.has_focus() and (Bindings.pressed(event,"menu_left") or Bindings.pressed(event,"menu_right")): _toggle_fmvs()
	elif Bindings.pressed(event,"menu_accept"):
		if toggle.has_focus(): _toggle()
		elif wildlife_button.has_focus(): _cycle_wildlife_limit()
		elif sun_shafts_button.has_focus(): _toggle_sun_shafts()
		elif replay_button.has_focus(): _toggle_replay()
		elif fmv_button.has_focus(): _toggle_fmvs()
		elif back.has_focus(): close_menu()
	else: return
	get_viewport().set_input_as_handled()
