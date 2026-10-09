extends VBoxContainer

const Storage = preload("res://player_storage.gd")
var remember_preferences := true
var cache_directory := "user://video_previews"
var decoder := ""
var selected_path := ""
var worker: Thread
var converting_path := ""
var player: VideoStreamPlayer
var still: TextureRect
var info: Label
var play_button: Button
var volume: HSlider
var picker: FileDialog

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if remember_preferences:
		var config := ConfigFile.new()
		if config.load(Storage.preferences_path()) == OK: decoder = str(config.get_value("video","ffmpeg",""))
	info = Label.new(); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(info)
	var transport := HBoxContainer.new(); add_child(transport)
	play_button = _button(transport,"Play",toggle_playback)
	_button(transport,"Stop",stop_playback)
	_button(transport,"Choose FFmpeg…",func() -> void: picker.popup_centered(Vector2i(850,600)))
	var label := Label.new(); label.text = "Volume"; transport.add_child(label)
	volume = HSlider.new(); volume.scrollable = false; volume.min_value = 0; volume.max_value = 1; volume.step = 0.01; volume.value = 0.5; volume.custom_minimum_size.x = 140
	volume.value_changed.connect(func(value: float) -> void: player.volume = value)
	transport.add_child(volume)
	player = VideoStreamPlayer.new(); player.expand = true; player.volume = 0.5; player.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(player)
	player.finished.connect(func() -> void: play_button.text = "Play")
	still = TextureRect.new(); still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	still.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; still.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(still)
	picker = FileDialog.new(); picker.access = FileDialog.ACCESS_FILESYSTEM; picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.use_native_dialog = true; picker.title = "Choose the FFmpeg executable"
	if OS.get_name() == "Windows": picker.filters = PackedStringArray(["*.exe ; FFmpeg executable"])
	picker.file_selected.connect(set_decoder); add_child(picker)
	clear()

func _button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = caption; button.pressed.connect(callback); parent.add_child(button); return button

func set_decoder(path: String) -> void:
	decoder = path
	if remember_preferences:
		var preferences := Storage.preferences_path()
		Storage.ensure_parent(preferences)
		var config := ConfigFile.new(); config.load(preferences)
		config.set_value("video","ffmpeg",path); config.save(preferences)
	if not selected_path.is_empty(): show_video(selected_path)

static func smacker_info(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() < 104: return {}
	var signature := file.get_buffer(4).get_string_from_ascii()
	if signature not in ["SMK2","SMK4"]: return {}
	var width := file.get_32(); var height := file.get_32(); var frames := file.get_32()
	return {"width":width,"height":height,"frames":frames}

func clear() -> void:
	selected_path = ""
	if player != null:
		player.stop(); player.stream = null; player.paused = false; player.hide()
	if still != null: still.texture = null; still.hide()
	if play_button != null: play_button.disabled = true; play_button.text = "Play"

func show_video(path: String) -> void:
	clear(); selected_path = path
	if path.get_extension().to_lower() == "ogv": _load_preview(path,false); return
	var metadata := smacker_info(path)
	if metadata.is_empty(): info.text = "This Smacker file could not be read."; return
	info.text = "%d × %d · %d %s" % [metadata.width,metadata.height,metadata.frames,"frame" if metadata.frames == 1 else "frames"]
	if metadata.frames == 1: info.text += " · Single-frame cutscene placeholder"
	if worker != null: info.text += "\nWaiting for the previous preview to finish…"; return
	var single_frame: bool = metadata.frames == 1
	var cache := cache_directory
	var source := FileAccess.open(path,FileAccess.READ)
	var key := (path + str(FileAccess.get_modified_time(path)) + str(source.get_length()) + "preview1").sha256_text()
	source.close()
	var output := cache.path_join(key + (".png" if single_frame else ".ogv"))
	if FileAccess.file_exists(output): _load_preview(output,single_frame); return
	if decoder.is_empty() or not FileAccess.file_exists(decoder):
		info.text += "\nChoose FFmpeg to preview SMK files."; return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache)) != OK:
		info.text += "\nCould not create the preview cache folder."; return
	info.text += "\nPreparing preview…"
	converting_path = path
	worker = Thread.new()
	var arguments := PackedStringArray(["-nostdin","-v","error","-y","-i",ProjectSettings.globalize_path(path)])
	if single_frame: arguments.append_array(PackedStringArray(["-frames:v","1","-an"]))
	else: arguments.append_array(PackedStringArray(["-map","0:v:0","-map","0:a:0?","-c:v","libtheora","-q:v","8","-c:a","libvorbis","-q:a","5"]))
	arguments.append(ProjectSettings.globalize_path(output))
	var executable := decoder
	var error := worker.start(func() -> Dictionary:
		var messages := []
		var code := OS.execute(executable,arguments,messages,true,false)
		return {"code":code,"output":output,"still":single_frame,"messages":"\n".join(messages)}
	)
	if error != OK: worker = null; info.text += "\nCould not start the preview decoder."

func _load_preview(path: String, single_frame: bool) -> void:
	if single_frame:
		var image := Image.load_from_file(path)
		if image == null: info.text += "\nCould not load the decoded frame."; return
		still.texture = ImageTexture.create_from_image(image); still.show()
	else:
		var stream := VideoStreamTheora.new(); stream.file = ProjectSettings.globalize_path(path)
		player.stream = stream; player.show(); player.play(); play_button.disabled = false; play_button.text = "Pause"
		if selected_path.get_extension().to_lower() == "ogv": info.text = selected_path.get_file()

func toggle_playback() -> void:
	if player.stream == null: return
	if player.is_playing(): player.paused = not player.paused
	else: player.paused = false; player.play()
	play_button.text = "Play" if player.paused else "Pause"

func stop_playback() -> void:
	if player != null: player.stop(); player.paused = false
	if play_button != null: play_button.text = "Play"

func _process(_delta: float) -> void:
	if worker == null or worker.is_alive(): return
	var result: Dictionary = worker.wait_to_finish(); worker = null
	if selected_path.is_empty(): return
	if selected_path != converting_path: show_video(selected_path); return
	if result.code == 0 and FileAccess.file_exists(result.output): _load_preview(result.output,result.still)
	else:
		DirAccess.remove_absolute(result.output)
		info.text += "\nCould not decode this cutscene. Choose an FFmpeg build with Smacker and Theora support."
		info.tooltip_text = result.messages.left(2000)

func _exit_tree() -> void:
	if worker != null: worker.wait_to_finish(); worker = null
