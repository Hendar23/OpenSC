extends CanvasLayer

const Bindings = preload("res://input_bindings.gd")
const Storage = preload("res://player_storage.gd")
signal closed
signal auto_aim_changed(enabled: bool)
signal wildlife_limit_changed(limit: int)
signal sun_shafts_changed(enabled: bool)
signal replay_changed(enabled: bool)
signal classic_sub_physics_changed(enabled: bool)
var classic_sub_physics := false
var classic_sub_physics_button: Button
var classic_explosions := false
signal random_pirates_changed(disabled: bool)
var disable_random_pirates := false
signal pirate_weapons_changed(enabled: bool)
var random_pirate_weapons := true
var crosshair_enabled := true
var crosshair_button: Button
signal cockpit_3d_changed(enabled: bool)
var cockpit_3d_enabled := true
var cockpit_3d_button: Button
var replay_button: Button
var replay_enabled := true
var fmvs_enabled := true
var sun_shafts_enabled := true
var lens_flares_enabled := true
const WILDLIFE_LIMITS := [40,60,80,100,150,200,0]
const BUBBLE_LIMITS := [0,50,100,200,500,1000,2000,4000,-1]
var bubble_limit := 200
var wildlife_limit := 80
var remember_preferences := true
var settings_path := ""
var zapper_auto_aim := false
var layout: Control
var scroll: ScrollContainer
var option_rows: VBoxContainer
var back: Button
var status: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS; layer = 12
	if settings_path.is_empty(): settings_path = Storage.preferences_path()
	_load_preferences()
	_build_menu()

func _load_preferences() -> void:
	var config := ConfigFile.new()
	if remember_preferences:
		config = preload("res://option_defaults.gd").load_preferences(settings_path)
		disable_random_pirates = bool(config.get_value("gameplay","disable_random_pirates",false))
		random_pirate_weapons = bool(config.get_value("gameplay","random_pirate_weapons",true))
		crosshair_enabled = bool(config.get_value("gameplay","first_person_crosshair",true))
		cockpit_3d_enabled = bool(config.get_value("gameplay","cockpit_3d",true))
		classic_sub_physics = bool(config.get_value("gameplay","classic_sub_physics",false))
		classic_explosions = bool(config.get_value("gameplay","classic_explosions",false))
		zapper_auto_aim = bool(config.get_value("gameplay","zapper_auto_aim",false))
		sun_shafts_enabled = bool(config.get_value("gameplay","sun_shafts",true))
		lens_flares_enabled = bool(config.get_value("gameplay","lens_flares",true))
		var saved_limit := int(config.get_value("gameplay","wildlife_limit",80))
		wildlife_limit = saved_limit if saved_limit in WILDLIFE_LIMITS else 80
		replay_enabled = bool(config.get_value("gameplay","photo_replay",true))
		fmvs_enabled = bool(config.get_value("gameplay","play_fmvs",true))
		var saved_bubbles := int(config.get_value("gameplay","bubble_limit",config.get_value("graphics","bubble_limit",200)))
		bubble_limit = saved_bubbles if saved_bubbles in BUBBLE_LIMITS else 200
	preload("res://propeller_bubbles.gd").set_limit(bubble_limit)
	preload("res://lens_flare.gd").set_enabled(lens_flares_enabled)
	preload("res://mine_explosion.gd").classic_enabled = classic_explosions
func reload_preferences() -> void:
	var live_options := {
		"zapper_auto_aim": auto_aim_changed, "classic_sub_physics": classic_sub_physics_changed,
		"disable_random_pirates": random_pirates_changed, "random_pirate_weapons": pirate_weapons_changed,
		"wildlife_limit": wildlife_limit_changed, "sun_shafts_enabled": sun_shafts_changed,
		"replay_enabled": replay_changed, "cockpit_3d_enabled": cockpit_3d_changed,
	}
	var previous := {}
	for key in live_options: previous[key] = get(key)
	_load_preferences()
	for key in live_options:
		var value: Variant = get(key)
		if value != previous[key]: live_options[key].emit(value)
	_refresh()

func _build_menu() -> void:
	var shade := ColorRect.new(); shade.color = Color.TRANSPARENT
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(shade)
	layout = Control.new(); layout.size = Vector2(640,480); shade.add_child(layout)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	scroll.follow_focus = true
	scroll.add_theme_constant_override("scrollbar_h_separation", 5)
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	layout.add_child(scroll)
	option_rows = VBoxContainer.new()
	option_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(option_rows)
	classic_sub_physics_button = _button(option_rows, _toggle_classic_sub_physics)
	cockpit_3d_button = _button(option_rows, _toggle_cockpit_3d)
	crosshair_button = _button(option_rows, _toggle_crosshair)
	replay_button = _button(option_rows, _toggle_replay)
	back = _button(layout, close_menu, 208.0)
	back.text = "Back"
	status = Label.new(); status.size = Vector2(320,32)
	status.add_theme_font_size_override("font_size",14); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; layout.add_child(status)
	option_rows.minimum_size_changed.connect(_layout)
	get_viewport().size_changed.connect(_layout); _refresh(); _layout(); hide()

func _button(parent: Control, activate: Callable, width := 248.0) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(width,28)
	button.add_theme_font_size_override("font_size",14)
	var normal := StyleBoxFlat.new(); normal.bg_color = Color(0.01,0.05,0.07,0.82)
	normal.border_color = Color(0.24,0.55,0.6,0.7); normal.set_border_width_all(1); normal.set_corner_radius_all(5)
	normal.content_margin_left = 8.0; normal.content_margin_right = 8.0
	var hover := normal.duplicate() as StyleBoxFlat; hover.bg_color = Color(0.04,0.23,0.28,0.95)
	button.add_theme_stylebox_override("normal",normal)
	for state in ["hover","pressed","focus"]: button.add_theme_stylebox_override(state,hover)
	button.pressed.connect(activate)
	parent.add_child(button)
	return button

func _refresh() -> void:
	crosshair_button.text = tr("First-person crosshair: %s") % (tr("On") if crosshair_enabled else tr("Off"))
	cockpit_3d_button.text = tr("3D cockpit: %s") % (tr("On") if cockpit_3d_enabled else tr("Off"))
	classic_sub_physics_button.text = tr("Classic Sub physics: %s") % (tr("On") if classic_sub_physics else tr("Off"))
	replay_button.text = tr("Photo mode replay: %s") % (tr("On") if replay_enabled else tr("Off"))

func _toggle_cockpit_3d() -> void:
	cockpit_3d_enabled = not cockpit_3d_enabled
	cockpit_3d_changed.emit(cockpit_3d_enabled)
	_refresh()
	_save()

func _toggle_crosshair() -> void:
	crosshair_enabled = not crosshair_enabled
	_refresh(); _save()

func _toggle_classic_sub_physics() -> void:
	classic_sub_physics = not classic_sub_physics
	_refresh(); classic_sub_physics_changed.emit(classic_sub_physics); _save()

func _toggle_classic_explosions() -> Error:
	classic_explosions = not classic_explosions
	preload("res://mine_explosion.gd").classic_enabled = classic_explosions
	return _save()

func _toggle_random_pirates() -> Error:
	disable_random_pirates = not disable_random_pirates
	random_pirates_changed.emit(disable_random_pirates)
	return _save()

func _toggle_pirate_weapons() -> Error:
	random_pirate_weapons = not random_pirate_weapons
	pirate_weapons_changed.emit(random_pirate_weapons)
	return _save()

func _toggle_replay() -> void:
	replay_enabled = not replay_enabled
	_refresh(); replay_changed.emit(replay_enabled); _save()

func _toggle_fmvs() -> Error:
	fmvs_enabled = not fmvs_enabled
	return _save()

func _toggle_sun_shafts() -> Error:
	sun_shafts_enabled = not sun_shafts_enabled
	sun_shafts_changed.emit(sun_shafts_enabled)
	return _save()

func _toggle_lens_flares() -> Error:
	lens_flares_enabled = not lens_flares_enabled
	preload("res://lens_flare.gd").set_enabled(lens_flares_enabled)
	return _save()

func _toggle() -> Error:
	zapper_auto_aim = not zapper_auto_aim
	auto_aim_changed.emit(zapper_auto_aim)
	return _save()

func _cycle_wildlife_limit(step: int = 1) -> Error:
	wildlife_limit = WILDLIFE_LIMITS[posmod(WILDLIFE_LIMITS.find(wildlife_limit) + step,WILDLIFE_LIMITS.size())]
	wildlife_limit_changed.emit(wildlife_limit)
	return _save()

func _cycle_bubble_limit(step: int = 1) -> Error:
	return _set_bubble_limit(BUBBLE_LIMITS[posmod(BUBBLE_LIMITS.find(bubble_limit)+step,BUBBLE_LIMITS.size())])

func _set_bubble_limit(value: int) -> Error:
	bubble_limit = value if value in BUBBLE_LIMITS else 200
	preload("res://propeller_bubbles.gd").set_limit(bubble_limit)
	return _save()

func _save() -> Error:
	status.text = ""
	if not remember_preferences: return OK
	var config := ConfigFile.new(); var result := config.load(settings_path)
	if result == OK or result == ERR_FILE_NOT_FOUND:
		config.set_value("gameplay","disable_random_pirates",disable_random_pirates)
		config.set_value("gameplay","random_pirate_weapons",random_pirate_weapons)
		config.set_value("gameplay","zapper_auto_aim",zapper_auto_aim)
		config.set_value("gameplay","wildlife_limit",wildlife_limit)
		config.set_value("gameplay","bubble_limit",bubble_limit)
		if config.has_section_key("graphics","bubble_limit"): config.erase_section_key("graphics","bubble_limit")
		config.set_value("gameplay","sun_shafts",sun_shafts_enabled)
		config.set_value("gameplay","lens_flares",lens_flares_enabled)
		config.set_value("gameplay","photo_replay",replay_enabled)
		config.set_value("gameplay","play_fmvs",fmvs_enabled)
		config.set_value("gameplay","first_person_crosshair",crosshair_enabled)
		config.set_value("gameplay","cockpit_3d",cockpit_3d_enabled)
		config.set_value("gameplay","classic_sub_physics",classic_sub_physics)
		config.set_value("gameplay","classic_explosions",classic_explosions)
		if config.has_section_key("gameplay","enhanced_explosions"): config.erase_section_key("gameplay","enhanced_explosions")
		result = Storage.ensure_parent(settings_path)
		if result == OK: result = config.save(settings_path)
	if result != OK: status.text = tr("Could not save settings: %s") % error_string(result)
	return result

func open_menu() -> void:
	_refresh()
	status.text = ""
	show()
	classic_sub_physics_button.grab_focus()
	scroll.scroll_vertical = 0

func close_menu() -> void:
	if not visible: return
	hide(); closed.emit()

func _layout() -> void:
	var viewport := get_viewport()
	var available := viewport.get_visible_rect().size
	if available.x <= 0.0 or available.y <= 0.0: return
	# Account for the project canvas stretch when keeping short windows readable.
	var pixels_per_unit := maxf(viewport.get_stretch_transform().get_scale().y, 0.001)
	var list_size := option_rows.get_combined_minimum_size()
	var full_height := list_size.y + 78.0
	var factor := minf(available.x / 640.0, maxf(available.y / full_height, 1.0 / pixels_per_unit))
	layout.size = Vector2(640.0, minf(full_height, available.y / factor))
	layout.scale = Vector2.ONE * factor
	layout.position = (available - layout.size * factor) * 0.5
	var scrollbar_gutter := scroll.get_v_scroll_bar().get_combined_minimum_size().x + scroll.get_theme_constant("scrollbar_h_separation")
	var list_height := minf(list_size.y, maxf(28.0, layout.size.y - 78.0))
	scroll.size = Vector2(list_size.x + scrollbar_gutter, list_height)
	scroll.position = Vector2((layout.size.x - list_size.x) * 0.5, 12.0)
	back.position = Vector2(216.0, scroll.position.y + scroll.size.y + 5.0)
	status.position = Vector2(160.0, back.position.y + back.size.y + 5.0)

func _input(event: InputEvent) -> void:
	if not visible: return
	if Bindings.pressed(event,"menu_cancel"): close_menu()
	elif Bindings.pressed(event,"menu_up") or Bindings.pressed(event,"menu_down"):
		var buttons := option_rows.get_children()
		buttons.append(back)
		var selected := buttons.find(get_viewport().gui_get_focus_owner())
		buttons[posmod(selected + (-1 if Bindings.pressed(event,"menu_up") else 1),buttons.size())].grab_focus()
	else:
		var focused := get_viewport().gui_get_focus_owner() as Button
		var accept := Bindings.pressed(event,"menu_accept")
		var adjust := Bindings.pressed(event,"menu_left") or Bindings.pressed(event,"menu_right")
		if focused == back and accept: close_menu()
		elif focused != null and focused.get_parent() == option_rows and (accept or adjust): focused.pressed.emit()
		else: return
	get_viewport().set_input_as_handled()
