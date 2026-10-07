extends Node
const Bindings = preload("res://input_bindings.gd")

const BMP = preload("res://legacy_bmp.gd")
const Mods = preload("res://mod_registry.gd")
const TITLE_PATH := "res://game_assets/ui/title.png"
const WEBSITE_URL := "https://github.com/Hendar23/OpenSC"
const LegacyAudio = preload("res://legacy_audio.gd")
const SoundTuning = preload("res://sound_tuning.gd")
const MENU_SOUNDS := {"activate": "ACTIVATE", "over": "OVERBUTT", "off": "OFFBUTT"}
signal new_game_requested
signal load_requested
signal mods_requested
signal resume_requested
signal toggle_menu_requested
signal exit_requested
signal menu_sound_played(role: String)

var loading_layer: CanvasLayer
var menu_layer: CanvasLayer
var loading_picture: TextureRect
var menu_picture: TextureRect
var loading_status: Label
var progress_bar: ProgressBar
var loading_layout: Control
var menu_layout: Control
var buttons := {}
var can_resume := false
var progress_pattern := RegEx.new()
var sound_players := {}
var audio_tuning := SoundTuning.new()
var active_button: Button
var assigning_focus := false
var menu_config := {}
var button_order: Array[String] = []
var controls_menu: CanvasLayer
var back_shortcut_busy: Callable
var menu_page := "main"
const OPTION_BUTTONS := ["controls","graphics","audio","mods","back"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	audio_tuning.load_settings()
	progress_pattern.compile("(\\d+) / (\\d+)")
	loading_layer = CanvasLayer.new(); loading_layer.layer = 10; add_child(loading_layer)
	menu_layer = CanvasLayer.new(); menu_layer.layer = 11; add_child(menu_layer)
	loading_layout = _screen(loading_layer)
	menu_layout = _screen(menu_layer)
	menu_layout.get_parent().color = Color(0.0,0.01,0.025,0.25)
	loading_picture = _picture(loading_layout)
	loading_picture.texture = ImageTexture.create_from_image(Image.load_from_file(TITLE_PATH))
	menu_picture = _picture(menu_layout)
	progress_bar = ProgressBar.new()
	progress_bar.position = Vector2(140,14); progress_bar.size = Vector2(360,20)
	progress_bar.show_percentage = false
	progress_bar.add_theme_font_size_override("font_size",1)
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new(); background.bg_color = Color(0.01,0.035,0.06,0.9)
	background.border_color = Color(0.35,0.7,0.8); background.set_border_width_all(1)
	var fill := StyleBoxFlat.new(); fill.bg_color = Color(0.2,0.75,0.85)
	progress_bar.add_theme_stylebox_override("background",background)
	progress_bar.add_theme_stylebox_override("fill",fill)
	loading_layout.add_child(progress_bar)
	loading_status = Label.new(); loading_status.text = "Loading…"
	loading_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_status.add_theme_font_size_override("font_size",12)
	progress_bar.add_child(loading_status)
	loading_status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_menu()
	controls_menu = preload("res://controls_menu.gd").new(); add_child(controls_menu)
	controls_menu.closed.connect(func() -> void: restore_button_focus("controls"))
	menu_layer.hide()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build_menu() -> void:
	menu_config = JSON.parse_string(FileAccess.get_file_as_string("res://game_assets/ui/main_menu.json"))
	for candidate in Mods.candidates("ui.main"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate.path))
		if data is Dictionary and data.get("schema_version") == 1: menu_config.merge(data,true); break
	var title: Array = menu_config.title_rect
	menu_picture.position = Vector2(title[0],title[1]); menu_picture.size = Vector2(title[2],title[3])
	menu_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var rounded := ShaderMaterial.new(); rounded.shader = preload("res://rounded_title.gdshader")
	rounded.set_shader_parameter("corner_radius",float(menu_config.get("title_corner_radius",12)))
	menu_picture.material = rounded
	var rect: Array = menu_config.button_rect
	var entries: Array = menu_config.buttons.duplicate(true)
	# Older custom menu layouts still get an entrance and return button.
	for entry in [{"id":"options","label":"Options"},{"id":"back","label":"Back"}]:
		if not entries.any(func(item: Dictionary) -> bool: return item.get("id") == entry.id): entries.append(entry)
	for entry in entries:
		var id := str(entry.get("id",""))
		if id not in ["new_game","load","continue","options","back","controls","mods","audio","graphics","website","exit"] or buttons.has(id): continue
		var button := Button.new(); button.text = str(entry.get("label",id))
		button.position = Vector2(rect[0],rect[1] + button_order.size() * float(menu_config.button_spacing))
		button.size = Vector2(rect[2],rect[3]); button.add_theme_font_size_override("font_size",14)
		var normal := StyleBoxFlat.new(); normal.bg_color = Color(0.01,0.05,0.07,0.82)
		normal.border_color = Color(0.24,0.55,0.6,0.7); normal.set_border_width_all(1); normal.set_corner_radius_all(5)
		var hover := normal.duplicate() as StyleBoxFlat; hover.bg_color = Color(0.04,0.23,0.28,0.95)
		button.add_theme_stylebox_override("normal",normal); button.add_theme_stylebox_override("hover",hover)
		button.add_theme_stylebox_override("pressed",hover); button.add_theme_stylebox_override("focus",hover)
		button.set_meta("available",id in ["new_game","options","back","controls","mods","website","exit"])
		if not button.get_meta("available"): button.tooltip_text = "Not available yet"
		menu_layout.add_child(button); buttons[id] = button; button_order.append(id)
		button.mouse_entered.connect(func() -> void: _enter_button(button))
		button.mouse_exited.connect(func() -> void: _leave_button(button))
		button.focus_entered.connect(func() -> void: _enter_button(button))
		button.focus_exited.connect(func() -> void: _leave_button(button))
		button.pressed.connect(_activate_button.bind(id))
	_set_menu_page("main")
	_update_title_mask()

func _update_title_mask() -> void:
	if menu_picture.texture == null or menu_picture.material == null: return
	var image_size := menu_picture.texture.get_size()
	var factor := minf(menu_picture.size.x / image_size.x,menu_picture.size.y / image_size.y)
	menu_picture.material.set_shader_parameter("card_size",image_size * factor)

func _set_menu_page(next_page: String) -> void:
	menu_page = next_page
	active_button = null
	var area: Array = menu_config.button_rect
	var row := 0
	for id in button_order:
		var on_page: bool = (id in OPTION_BUTTONS) == (menu_page == "options")
		buttons[id].visible = on_page
		if on_page:
			buttons[id].position = Vector2(area[0],area[1] + row * float(menu_config.button_spacing))
			row += 1
	if menu_layer.visible: restore_button_focus("controls" if menu_page == "options" else "options")

func restore_button_focus(id: String) -> void:
	if menu_layer.visible and buttons.has(id) and buttons[id].visible: buttons[id].grab_focus()

func _visible_button_order() -> Array[String]:
	var result: Array[String] = []
	for id in button_order:
		if buttons[id].visible: result.append(id)
	return result

func _screen(layer: CanvasLayer) -> Control:
	var background := ColorRect.new(); background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(background)
	var logical := Control.new(); logical.size = Vector2(640,480)
	background.add_child(logical)
	return logical

func _picture(parent: Control) -> TextureRect:
	var picture := TextureRect.new(); picture.size = Vector2(640,480)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	return picture

func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var scale_factor := minf(viewport.x / 640.0,viewport.y / 480.0)
	for layout in [loading_layout,menu_layout]:
		layout.scale = Vector2.ONE * scale_factor
		layout.position = (viewport - Vector2(640,480) * scale_factor) * 0.5

func load_art(folder: String) -> void:
	loading_picture.texture = _texture(folder,"INTROTEX/LOADING.BMP","texture.menu_loading")
	menu_picture.texture = _texture(folder,"","texture.menu_title",ImageTexture.create_from_image(Image.load_from_file(TITLE_PATH)))
	_update_title_mask()
	_load_menu_audio(folder)

func _load_menu_audio(folder: String) -> void:
	for role in MENU_SOUNDS:
		var path := folder.path_join("WAVES/" + str(MENU_SOUNDS[role]) + ".RAW")
		for replacement in Mods.candidates("audio.menu." + role):
			if LegacyAudio.load_file(replacement.path) != null:
				path = replacement.path
				break
		var player: AudioStreamPlayer = sound_players.get(role)
		if player == null:
			player = AudioStreamPlayer.new(); player.name = "MenuSound_" + role
			player.process_mode = Node.PROCESS_MODE_ALWAYS
			add_child(player); sound_players[role] = player
		# New Game reloads art: keep an already playing click intact.
		if player.stream == null or player.stream.get_meta("asset_source","") != path:
			player.stream = LegacyAudio.load_file(path)

func _play_menu_sound(role: String) -> void:
	var player: AudioStreamPlayer = sound_players.get(role)
	if player == null or not player.is_inside_tree() or player.stream == null: return
	var volume := float(audio_tuning.settings.master_volume)
	if role == "activate": volume += linear_to_db(0.5)
	player.volume_db = -80.0 if volume <= -60.0 else volume
	player.play()
	menu_sound_played.emit(role)

func _enter_button(button: Button) -> void:
	if not menu_layer.visible or button.disabled or active_button == button: return
	if active_button != null and not assigning_focus: _play_menu_sound("off")
	active_button = button
	if not assigning_focus: _play_menu_sound("over")

func _leave_button(button: Button) -> void:
	if active_button != button: return
	active_button = null
	if menu_layer.visible and not assigning_focus: _play_menu_sound("off")

func _exit_after_sound() -> void:
	var player: AudioStreamPlayer = sound_players.get("activate")
	if player != null and player.playing:
		# Use the clip duration so quitting also completes if the audio device
		# cannot deliver a finished notification. The timer runs while paused.
		await get_tree().create_timer(player.stream.get_length() / player.pitch_scale,true).timeout
	exit_requested.emit()

func is_button_available(id: String) -> bool:
	return bool(buttons[id].get_meta("available",false))

func _activate_button(id: String) -> void:
	_play_menu_sound("activate")
	if not is_button_available(id): return
	match id:
		"new_game": new_game_requested.emit()
		"continue": resume_requested.emit()
		"load": load_requested.emit()
		"options": _set_menu_page("options")
		"back": _set_menu_page("main")
		"mods": mods_requested.emit()
		"controls": controls_menu.open_menu()
		"website": OS.shell_open(WEBSITE_URL)
		"exit": _exit_after_sound()

func _texture(folder: String, relative: String, id: String, built_in: Texture2D = null) -> Texture2D:
	for replacement in Mods.candidates(id):
		var image: Image = BMP.load_image(replacement.path) if str(replacement.path).get_extension().to_lower() in ["bmp","ras"] else Image.load_from_file(replacement.path)
		if image != null: return ImageTexture.create_from_image(image)
	if built_in != null: return built_in
	var image := BMP.load_image(folder.path_join(relative))
	return ImageTexture.create_from_image(image) if image != null else null

func show_loading() -> void:
	if controls_menu != null: controls_menu.close_menu()
	menu_layer.hide(); loading_layer.show()
	active_button = null
	progress_bar.value = 0.0; loading_status.text = "Loading…"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func update_progress(message: String) -> void:
	var fraction := 0.0
	var match := progress_pattern.search(message)
	if match != null: fraction = float(match.get_string(1)) / maxf(1.0,float(match.get_string(2)))
	var value := progress_bar.value
	if message.begins_with("Loading environment textures"): value = 38.0 + fraction * 20.0
	elif message.begins_with("Loading environment:"): value = 8.0 + fraction * 30.0
	elif message.begins_with("Building environment collision"): value = 60.0
	elif message.begins_with("Restoring plant patches"): value = 65.0 + fraction * 15.0
	elif message.begins_with("Restoring scenery"): value = 83.0
	elif message.begins_with("Adding ambient fish"): value = 88.0
	progress_bar.value = maxf(progress_bar.value,value)

func show_menu(resume_available: bool) -> void:
	can_resume = resume_available
	buttons["continue"].set_meta("available",can_resume)
	buttons["continue"].tooltip_text = "" if can_resume else "Start a new game first"
	loading_layer.hide(); menu_layer.show()
	_set_menu_page("main")
	for id in buttons: buttons[id].modulate.a = 1.0 if is_button_available(id) else 0.45
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	assigning_focus = true
	buttons["continue" if can_resume else "new_game"].grab_focus()
	active_button = buttons["continue" if can_resume else "new_game"]
	assigning_focus = false

func hide_menu() -> void:
	if controls_menu != null: controls_menu.close_menu()
	menu_layer.hide()
	active_button = null

func _input(event: InputEvent) -> void:
	if controls_menu != null and controls_menu.visible: return
	if menu_layer.visible:
		var selected := get_viewport().gui_get_focus_owner() as Button
		if menu_page == "options" and Bindings.pressed(event,"menu_cancel"):
			_activate_button("back"); get_viewport().set_input_as_handled(); return
		if Bindings.pressed(event,"menu_up") or Bindings.pressed(event,"menu_down"):
			get_viewport().set_input_as_handled()
			var order := _visible_button_order()
			if order.is_empty(): return
			var index := 0
			for i in order.size():
				if buttons[order[i]] == selected: index = i; break
			var step := 1 if Bindings.pressed(event,"menu_down") else -1
			for i in order.size():
				index = posmod(index + step,order.size())
				if is_button_available(order[index]): buttons[order[index]].grab_focus(); break
			return
		if Bindings.pressed(event,"menu_accept"):
			get_viewport().set_input_as_handled()
			if selected != null and selected in buttons.values() and selected.visible and not selected.disabled: selected.pressed.emit()
			return
	if can_resume and not loading_layer.visible and Bindings.pressed(event,"main_menu"):
		if back_shortcut_busy.is_valid() and back_shortcut_busy.call(event): return
		toggle_menu_requested.emit()
		get_viewport().set_input_as_handled()
