extends Node

const BMP = preload("res://legacy_bmp.gd")
const Mods = preload("res://mod_registry.gd")
const MENU_BACKGROUND = preload("res://game_assets/ui/main_menu.png")
const WEBSITE_URL := "https://github.com/Hendar23/OpenSC"
const LegacyAudio = preload("res://legacy_audio.gd")
const SoundTuning = preload("res://sound_tuning.gd")
const MENU_SOUNDS := {"activate": "ACTIVATE", "over": "OVERBUTT", "off": "OFFBUTT"}
const MENU_NEIGHBOURS := {
	"new_game": {JOY_BUTTON_DPAD_DOWN: "load", JOY_BUTTON_DPAD_RIGHT: "controls"},
	"load": {JOY_BUTTON_DPAD_UP: "new_game", JOY_BUTTON_DPAD_DOWN: "continue", JOY_BUTTON_DPAD_RIGHT: "audio"},
	"continue": {JOY_BUTTON_DPAD_UP: "load", JOY_BUTTON_DPAD_DOWN: "website", JOY_BUTTON_DPAD_RIGHT: "graphics"},
	"controls": {JOY_BUTTON_DPAD_LEFT: "new_game", JOY_BUTTON_DPAD_DOWN: "audio"},
	"audio": {JOY_BUTTON_DPAD_UP: "controls", JOY_BUTTON_DPAD_DOWN: "graphics", JOY_BUTTON_DPAD_LEFT: "load"},
	"graphics": {JOY_BUTTON_DPAD_UP: "audio", JOY_BUTTON_DPAD_DOWN: "website", JOY_BUTTON_DPAD_LEFT: "continue"},
	"website": {JOY_BUTTON_DPAD_UP: "continue", JOY_BUTTON_DPAD_DOWN: "exit"},
	"exit": {JOY_BUTTON_DPAD_UP: "website"}
}
signal new_game_requested
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	audio_tuning.load_settings()
	progress_pattern.compile("(\\d+) / (\\d+)")
	loading_layer = CanvasLayer.new(); loading_layer.layer = 10; add_child(loading_layer)
	menu_layer = CanvasLayer.new(); menu_layer.layer = 11; add_child(menu_layer)
	loading_layout = _screen(loading_layer)
	menu_layout = _screen(menu_layer)
	loading_picture = _picture(loading_layout)
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
	for entry in [
		["new_game",Rect2(74,258,206,36)], ["load",Rect2(74,302,206,36)],
		["continue",Rect2(74,345,206,36)], ["controls",Rect2(366,258,206,36)],
		["audio",Rect2(366,302,206,36)], ["graphics",Rect2(366,345,206,36)],
		["website",Rect2(218,391,206,36)], ["exit",Rect2(230,435,184,37)]
	]:
		var button := Button.new()
		button.position = entry[1].position; button.size = entry[1].size
		button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
		button.add_theme_stylebox_override("disabled",StyleBoxEmpty.new())
		var hover := StyleBoxFlat.new(); hover.bg_color = Color(0.65,0.85,1.0,0.12)
		hover.set_corner_radius_all(18)
		button.add_theme_stylebox_override("hover",hover)
		button.add_theme_stylebox_override("pressed",hover)
		var focus := hover.duplicate() as StyleBoxFlat
		focus.border_color = Color(0.8,0.95,1.0,0.7); focus.set_border_width_all(1)
		button.add_theme_stylebox_override("focus",focus)
		button.set_meta("available",entry[0] in ["new_game","website","exit"])
		if not button.get_meta("available"): button.tooltip_text = "Not available yet"
		menu_layout.add_child(button); buttons[entry[0]] = button
		button.mouse_entered.connect(func() -> void: _enter_button(button))
		button.mouse_exited.connect(func() -> void: _leave_button(button))
		button.focus_entered.connect(func() -> void: _enter_button(button))
		button.focus_exited.connect(func() -> void: _leave_button(button))
		button.pressed.connect(_activate_button.bind(str(entry[0])))
	menu_layer.hide()
	get_viewport().size_changed.connect(_layout)
	_layout()

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
	menu_picture.texture = _texture(folder,"INTROTEX/ENGLISH/MAIN.BMP","texture.menu_main",MENU_BACKGROUND)
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	assigning_focus = true
	buttons["continue" if can_resume else "new_game"].grab_focus()
	active_button = buttons["continue" if can_resume else "new_game"]
	assigning_focus = false

func hide_menu() -> void:
	menu_layer.hide()
	active_button = null

func _input(event: InputEvent) -> void:
	if menu_layer.visible and event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT]:
		get_viewport().set_input_as_handled()
		var selected := get_viewport().gui_get_focus_owner() as Button
		for id in buttons:
			if buttons[id] == selected:
				var target: String = MENU_NEIGHBOURS[id].get(event.button_index,"")
				if not target.is_empty(): buttons[target].grab_focus()
				break
		return
	if menu_layer.visible and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		var selected := get_viewport().gui_get_focus_owner() as Button
		# Consume A before GUI/gameplay input can activate the same press again.
		get_viewport().set_input_as_handled()
		if selected != null and selected in buttons.values() and not selected.disabled:
			selected.pressed.emit()
		return
	if can_resume and not loading_layer.visible and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		toggle_menu_requested.emit()
		get_viewport().set_input_as_handled()
