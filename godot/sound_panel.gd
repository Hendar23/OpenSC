extends PanelContainer
signal dismissed
var audio: Node
var sliders := {}
var labels := {}
var message: Label
var export_dialog: FileDialog
var preview_button: CheckButton
var all_button: CheckBox
const ROWS := [
	["master_volume", "Master volume", -60.0, 6.0, 1.0, "dB"],
	["volume_response", "Volume response time", 0.01, 2.0, 0.01, "s"],
	["pitch_response", "Pitch response time", 0.01, 2.0, 0.01, "s"],
	["loop_blend_ms", "Loop join smoothing", 0.0, 50.0, 1.0, "ms"]
]
func setup(sound: Node) -> void:
	audio = sound
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -450
	offset_right = -18
	offset_top = 18
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := Label.new()
	title.text = "Submarine sound tuning"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := Button.new()
	close.text = "Close (F6)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: stop_preview(); dismissed.emit())
	heading.add_child(close)
	var hint := Label.new()
	hint.text = "Live controls · pitch 1.0 = original sample rate.\n-60 dB mutes a layer. Lower response = faster changes."
	hint.add_theme_font_size_override("font_size", 12)
	column.add_child(hint)
	preview_button = CheckButton.new()
	preview_button.text = "Stationary audio preview"
	preview_button.focus_mode = Control.FOCUS_NONE
	preview_button.toggled.connect(func(on: bool) -> void: audio.preview = on)
	column.add_child(preview_button)
	var load_label := Label.new()
	load_label.text = "Preview load / simulated speed"
	column.add_child(load_label)
	var load_slider := HSlider.new()
	load_slider.min_value = 0.0
	load_slider.max_value = 1.0
	load_slider.step = 0.01
	load_slider.value = audio.preview_load
	load_slider.focus_mode = Control.FOCUS_NONE
	load_slider.value_changed.connect(func(value: float) -> void: audio.preview_load = value)
	column.add_child(load_slider)
	var solos := HBoxContainer.new()
	column.add_child(solos)
	var group := ButtonGroup.new()
	for item in [["", "All"], ["main_propeller", "Main"], ["side_pods", "Pods"], ["pod_rotation", "Rotation"]]:
		var button := CheckBox.new()
		button.text = item[1]
		button.button_group = group
		button.button_pressed = item[0] == ""
		if item[0] == "": all_button = button
		button.focus_mode = Control.FOCUS_NONE
		var role := str(item[0])
		button.toggled.connect(func(on: bool) -> void: if on: audio.solo_role = role)
		solos.add_child(button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for row in ROWS: _row(rows, row)
	for item in [["main_propeller", "Main propeller · PROP3"], ["side_pods", "Side pods · PROP4"], ["pod_rotation", "Pod rotation · PROP1"]]:
		var section := Label.new()
		section.text = item[1]
		section.add_theme_font_size_override("font_size", 17)
		rows.add_child(section)
		var role := str(item[0])
		_row(rows, [role + "_volume", "Volume", -60.0, 6.0, 1.0, "dB"])
		_row(rows, [role + "_pitch_min", "Pitch at low load", 0.25, 4.0, 0.01, "×"])
		_row(rows, [role + "_pitch_max", "Pitch at full load", 0.25, 4.0, 0.01, "×"])
		_row(rows, [role + "_speed_pitch", "Extra pitch as speed rises", 0.0, 2.0, 0.01, "×"])
	var impact_heading := Label.new()
	impact_heading.text = "Hull impacts · HIT1 / HIT3 / CREAKING"
	impact_heading.add_theme_font_size_override("font_size", 17)
	rows.add_child(impact_heading)
	_row(rows, ["impact_volume", "Impact volume", -60.0, 6.0, 1.0, "dB"])
	_row(rows, ["creaking_volume", "Creaking volume", -60.0, 6.0, 1.0, "dB"])
	_row(rows, ["impact_pitch_variation", "Random pitch ± (0.05 = 5%)", 0.0, 0.25, 0.01, "×"])
	_row(rows, ["impact_creak_chance", "Creak chance (0.20 = 20%)", 0.0, 1.0, 0.01, ""])
	_row(rows, ["impact_min_speed", "Minimum impact speed", 0.0, 5.0, 0.1, "m/s"])
	_row(rows, ["impact_cooldown", "Impact cooldown", 0.05, 2.0, 0.05, "s"])
	_row(rows, ["impact_rumble_strength", "Controller impact rumble (0 = off)", 0.0, 1.0, 0.05, ""])
	var test_hit := Button.new()
	test_hit.text = "Preview hull impact"
	test_hit.focus_mode = Control.FOCUS_NONE
	test_hit.pressed.connect(func() -> void: audio.impact(float(audio.pilot.movement.settings.forward_speed)))
	rows.add_child(test_hit)
	var docking_heading := Label.new()
	docking_heading.text = "Docking · DOCKING / DOCK / DOCKSHUT"
	docking_heading.add_theme_font_size_override("font_size", 17)
	rows.add_child(docking_heading)
	_row(rows, ["docking_volume", "Docking sequence volume", -60.0, 6.0, 1.0, "dB"])
	_row(rows, ["dock_doors_volume", "Moving doors volume", -60.0, 6.0, 1.0, "dB"])
	_row(rows, ["dock_shut_volume", "Door finish volume", -60.0, 6.0, 1.0, "dB"])
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	for caption in ["Save", "Reset defaults", "Export"]:
		var button := Button.new()
		button.text = caption
		button.focus_mode = Control.FOCUS_NONE
		buttons.add_child(button)
		if caption == "Save": button.pressed.connect(func() -> void: message.text = "Sound settings saved." if audio.tuning.save_settings() == OK else "Could not save sound settings.")
		elif caption == "Reset defaults": button.pressed.connect(_reset)
		else: button.pressed.connect(func() -> void: export_dialog.popup_centered(Vector2i(800, 550)))
	message = Label.new()
	message.text = "Save remembers this mix. Export can become new defaults."
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 12)
	column.add_child(message)
	export_dialog = FileDialog.new()
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.filters = PackedStringArray(["*.cfg ; Sound settings"])
	export_dialog.current_file = "submarine_audio.cfg"
	export_dialog.file_selected.connect(func(path: String) -> void: message.text = "Sound settings exported." if audio.tuning.save_settings(path) == OK else "Could not export sound settings.")
	add_child(export_dialog)
	get_viewport().size_changed.connect(_resize)
	_resize()
	visible = false

func _row(parent: VBoxContainer, row: Array) -> void:
	var key := str(row[0])
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	labels[key] = label
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = row[2]
	slider.max_value = row[3]
	slider.step = row[4]
	slider.value = audio.tuning.settings[key]
	slider.focus_mode = Control.FOCUS_NONE
	sliders[key] = slider
	parent.add_child(slider)
	var update_label := func(value: float) -> void: label.text = "%s: %.2f %s" % [row[1], value, row[5]]
	update_label.call(slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		audio.tuning.settings[key] = value
		update_label.call(value)
	)
	# Rebuild once on release rather than restarting loops every drag tick.
	if key == "loop_blend_ms": slider.drag_ended.connect(func(_changed: bool) -> void: audio.rebuild_loops())

func _resize() -> void: offset_bottom = minf(800.0, get_viewport_rect().size.y - 18.0)
func stop_preview() -> void:
	preview_button.button_pressed = false
	audio.preview = false
	audio.solo_role = ""
	all_button.button_pressed = true
func _reset() -> void:
	audio.tuning.settings = audio.tuning.defaults.duplicate()
	for key in sliders: sliders[key].value = audio.tuning.settings[key]
	audio.rebuild_loops()
	message.text = "Defaults restored. Save to keep this mix."
