extends PanelContainer

signal dismissed
const Movement = preload("res://movement_model.gd")
const FollowCamera = preload("res://follow_camera.gd")
const ROWS := [
	["main_forward", "Main forward thrust", 0.0, 2000.0, 10.0, "N"],
	["main_reverse", "Main reverse thrust", 0.0, 2000.0, 10.0, "N"],
	["side_thrust", "Each side propeller thrust", 0.0, 1500.0, 10.0, "N"],
	["forward_speed", "Maximum forward speed", 0.0, 40.0, 0.1, "units/s"],
	["reverse_speed", "Maximum reverse speed", 0.0, 20.0, 0.1, "units/s"],
	["vertical_speed", "Maximum ascent/descent speed", 0.0, 20.0, 0.1, "units/s"],
	["forward_drag", "Forward drag", 0.0, 4.0, 0.05, "/s"],
	["lateral_drag", "Sideways drag", 0.0, 6.0, 0.05, "/s"],
	["vertical_drag", "Vertical drag", 0.0, 6.0, 0.05, "/s"],
	["turn_acceleration", "Turning acceleration", 0.0, 360.0, 1.0, "°/s²"],
	["turn_speed", "Maximum turning speed", 0.0, 180.0, 1.0, "°/s"],
	["turn_drag", "Turning drag", 0.0, 8.0, 0.05, "/s"],
	["tilt_speed", "Pod tilt speed", 5.0, 360.0, 1.0, "°/s"],
	["mass", "Submarine mass", 1.0, 1000.0, 1.0, "kg"],
	["water_resistance", "Water resistance", 0.0, 1.0, 0.01, ""],
	["pitch_acceleration", "Pitch acceleration", 0.0, 360.0, 1.0, "°/s²"],
	["pitch_speed", "Maximum pitch speed", 0.0, 180.0, 1.0, "°/s"],
	["upright_strength", "Ballast restoring strength", 0.0, 12.0, 0.1, ""],
	["upright_damping", "Ballast damping", 0.0, 12.0, 0.1, ""],
	["camera_distance", "Camera distance", FollowCamera.MIN_DISTANCE, FollowCamera.MAX_DISTANCE, 0.05, "units"],
	["propeller_spin_down", "Propeller spin-down time", 0.0, 3.0, 0.05, "s"],
	["impact_damage_threshold", "Impact damage minimum speed", 0.0, 10.0, 0.05, "units/s"],
	["impact_damage_scale", "Impact damage multiplier", 0.0, 20.0, 0.1, ""],
	["bubble_rate", "Bubbles per propeller at full speed", 0.0, 80.0, 1.0, "/s"]
]
var movement: RefCounted
var sliders := {}
var labels := {}
var message: Label
var export_dialog: FileDialog
var embedded := false

func setup(state: RefCounted, in_tabs: bool = false, graphics_rows: VBoxContainer = null) -> void:
	embedded = in_tabs
	movement = state
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -390
	offset_right = -18
	offset_top = 18
	offset_bottom = 630
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := Label.new()
	title.text = "Movement tuning"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := Button.new()
	close.text = "Close (T)"
	close.pressed.connect(func() -> void: dismissed.emit())
	heading.add_child(close)
	heading.visible = not embedded
	var hint := Label.new()
	hint.text = "Changes apply live. Lower drag = longer coasting.\nW/S: thrust · A/D: turn · Q/E: pods · ↑/↓: pitch\nPad: pull back = nose up · right stick pods · triggers thrust"
	hint.add_theme_font_size_override("font_size", 12)
	column.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for row in ROWS:
		var key := str(row[0])
		var row_parent := graphics_rows if key == "bubble_rate" and graphics_rows != null else rows
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		row_parent.add_child(label)
		labels[key] = label
		var slider := HSlider.new()
		slider.min_value = float(row[2])
		slider.max_value = float(row[3])
		slider.step = float(row[4])
		slider.value = float(movement.settings[key])
		slider.focus_mode = Control.FOCUS_NONE
		row_parent.add_child(slider)
		sliders[key] = slider
		_update_label(row, slider.value)
		slider.value_changed.connect(func(value: float) -> void:
			movement.settings[key] = value
			_update_label(row, value)
		)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	for caption in ["Save settings", "Reset defaults", "Export settings"]:
		var button := Button.new()
		button.text = caption
		button.focus_mode = Control.FOCUS_NONE
		buttons.add_child(button)
		if caption == "Save settings": button.pressed.connect(_save)
		elif caption == "Reset defaults": button.pressed.connect(_reset)
		else: button.pressed.connect(func() -> void: export_dialog.popup_centered(Vector2i(800, 550)))
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 36
	message.add_theme_font_size_override("font_size", 12)
	message.text = "Save remembers settings next launch. Export lets you share the values."
	column.add_child(message)
	export_dialog = FileDialog.new()
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.filters = PackedStringArray(["*.cfg ; Movement settings"])
	export_dialog.current_file = "submarine_tuning.cfg"
	export_dialog.file_selected.connect(func(path: String) -> void:
		var result: Error = movement.save_settings(path)
		message.text = "Settings exported." if result == OK else "Could not export settings: " + error_string(result)
	)
	add_child(export_dialog)
	get_viewport().size_changed.connect(_resize)
	_resize()
	visible = embedded

func _resize() -> void:
	if embedded:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	offset_bottom = minf(710.0, get_viewport_rect().size.y - 18.0)

func _update_label(row: Array, value: float) -> void:
	var label: Label = labels[str(row[0])]
	label.text = "%s: %.2f %s" % [row[1], value, row[5]]

func _save() -> void:
	var result: Error = movement.save_settings()
	message.text = "Settings saved for next launch." if result == OK else "Could not save: " + error_string(result)

func set_camera_distance(value: float) -> void:
	var distance := clampf(value, FollowCamera.MIN_DISTANCE, FollowCamera.MAX_DISTANCE)
	movement.settings.camera_distance = distance
	sliders.camera_distance.set_value_no_signal(distance)
	for row in ROWS:
		if row[0] == "camera_distance": _update_label(row, distance); break

func _reset() -> void:
	movement.settings = movement.defaults.duplicate()
	for row in ROWS:
		var slider: HSlider = sliders[str(row[0])]
		slider.value = float(movement.settings[str(row[0])])
	message.text = "Defaults restored. Save to keep them."
