extends VBoxContainer

signal summary_changed

const BMP = preload("res://legacy_bmp.gd")
const LegacyAudio = preload("res://legacy_audio.gd")
const AudioLoop = preload("res://audio_loop.gd")
const Waveform = preload("res://audio_waveform.gd")
var selected_path := ""
var selected_kind := ""
var summary := ""
var image: Image
var image_panel: PanelContainer
var image_tools: HBoxContainer
var image_scroll: ScrollContainer
var image_holder: CenterContainer
var image_view: TextureRect
var image_zoom: HSlider
var image_zoom_label: Label
var fit_image := true
var audio_panel: PanelContainer
var audio_player: AudioStreamPlayer
var audio_source: AudioStream
var audio_play: Button
var audio_stop: Button
var audio_seek: HSlider
var audio_time: Label
var audio_loop: CheckButton
var audio_volume: HSlider
var audio_info: Label
var raw_tools: HBoxContainer
var raw_rate: OptionButton
var raw_format: OptionButton
var raw_channels: OptionButton
var waveform: Control
var seeking := false
var text_view: TextEdit
var video_preview: VBoxContainer
var remember_preferences := true

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_images()
	_build_audio()
	video_preview = preload("res://video_preview.gd").new()
	video_preview.remember_preferences = remember_preferences
	add_child(video_preview)
	text_view = TextEdit.new()
	text_view.editable = false
	text_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(text_view)
	clear()

func button(parent: Node, caption: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = caption
	result.focus_mode = Control.FOCUS_NONE
	result.pressed.connect(action)
	parent.add_child(result)
	return result

func _build_images() -> void:
	image_tools = HBoxContainer.new()
	add_child(image_tools)
	button(image_tools, "Fit image", func() -> void: fit_image = true; _update_image_size())
	button(image_tools, "100%", func() -> void: fit_image = false; image_zoom.value = 1.0; _update_image_size())
	image_zoom = HSlider.new()
	image_zoom.min_value = 0.05
	image_zoom.max_value = 8.0
	image_zoom.step = 0.05
	image_zoom.value = 1.0
	image_zoom.custom_minimum_size.x = 200
	image_zoom.value_changed.connect(func(_value: float) -> void: fit_image = false; _update_image_size())
	image_tools.add_child(image_zoom)
	image_zoom_label = Label.new()
	image_tools.add_child(image_zoom_label)
	image_panel = PanelContainer.new()
	image_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(image_panel)
	image_scroll = ScrollContainer.new()
	image_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image_panel.add_child(image_scroll)
	image_holder = CenterContainer.new()
	image_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image_scroll.add_child(image_holder)
	image_view = TextureRect.new()
	image_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image_holder.add_child(image_view)
	image_scroll.resized.connect(func() -> void: if fit_image: _update_image_size())
	image_scroll.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.ctrl_pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: image_zoom.value *= 1.1; accept_event()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: image_zoom.value /= 1.1; accept_event()
	)

func _build_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.volume_db = linear_to_db(0.5)
	audio_player.finished.connect(func() -> void:
		audio_play.text = "Play"; audio_seek.set_value_no_signal(audio_seek.max_value)
	)
	add_child(audio_player)
	audio_panel = PanelContainer.new()
	audio_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(audio_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	audio_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "Audio preview"
	heading.add_theme_font_size_override("font_size", 26)
	column.add_child(heading)
	audio_info = Label.new()
	audio_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(audio_info)
	waveform = Waveform.new()
	waveform.size_flags_vertical = Control.SIZE_EXPAND_FILL
	waveform.custom_minimum_size.y = 150
	column.add_child(waveform)
	raw_tools = HBoxContainer.new()
	column.add_child(raw_tools)
	var raw_label := Label.new()
	raw_label.text = "RAW format:"
	raw_tools.add_child(raw_label)
	raw_rate = OptionButton.new()
	for rate in [8000, 11025, 16000, 22050, 44100, 48000]: raw_rate.add_item("%d Hz" % rate, rate)
	raw_rate.select(1)
	raw_tools.add_child(raw_rate)
	raw_format = OptionButton.new()
	for caption in ["8-bit unsigned PCM", "8-bit signed PCM", "16-bit little-endian PCM"]: raw_format.add_item(caption)
	raw_tools.add_child(raw_format)
	raw_channels = OptionButton.new()
	raw_channels.add_item("Mono")
	raw_channels.add_item("Stereo")
	raw_tools.add_child(raw_channels)
	for control in [raw_rate, raw_format, raw_channels]: control.item_selected.connect(func(_index: int) -> void: show_asset(selected_path, "audio"))
	var transport := HBoxContainer.new()
	column.add_child(transport)
	audio_play = button(transport, "Play", _toggle_audio)
	audio_stop = button(transport, "Stop", _stop_audio)
	audio_loop = CheckButton.new()
	audio_loop.text = "Loop"
	audio_loop.toggled.connect(_set_audio_loop)
	transport.add_child(audio_loop)
	audio_time = Label.new()
	audio_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transport.add_child(audio_time)
	var volume_label := Label.new()
	volume_label.text = "Volume"
	transport.add_child(volume_label)
	audio_volume = HSlider.new()
	audio_volume.min_value = 0.0
	audio_volume.max_value = 1.0
	audio_volume.step = 0.01
	audio_volume.value = 0.5
	audio_volume.custom_minimum_size.x = 120
	audio_volume.value_changed.connect(func(value: float) -> void: audio_player.volume_db = linear_to_db(maxf(0.00001, value)))
	transport.add_child(audio_volume)
	audio_seek = HSlider.new()
	audio_seek.step = 0.01
	audio_seek.drag_started.connect(func() -> void: seeking = true)
	audio_seek.drag_ended.connect(func(changed: bool) -> void:
		seeking = false
		if changed: _seek_audio(audio_seek.value)
	)
	audio_seek.value_changed.connect(func(value: float) -> void: if not seeking: _seek_audio(value))
	column.add_child(audio_seek)

func clear() -> void:
	if video_preview != null: video_preview.clear()
	audio_source = null
	if audio_player != null:
		audio_player.stop()
		audio_player.stream = null
		audio_player.stream_paused = false
	image = null
	if image_view != null: image_view.texture = null
	for control in [image_panel, image_tools, audio_panel, text_view, video_preview]:
		if control != null: control.visible = false
	selected_path = ""
	selected_kind = ""
	summary = ""

func show_asset(path: String, kind: String) -> void:
	clear()
	selected_path = path
	selected_kind = kind
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: _error("Could not read this file."); return
	var bytes := file.get_length()
	file.close()
	summary = "%s · %s" % [path.get_extension().to_upper(), String.humanize_size(bytes)]
	if kind == "image":
		image = BMP.load_image(path) if path.get_extension().to_lower() in ["bmp", "ras"] else Image.load_from_file(path)
		if image == null or image.is_empty(): _error("This image could not be decoded. It may be an empty placeholder."); return
		image_view.texture = ImageTexture.create_from_image(image)
		image_panel.visible = true
		image_tools.visible = true
		fit_image = true
		summary += " · %d × %d pixels" % [image.get_width(), image.get_height()]
		if image.has_meta("palette_markers"): summary += " · %d out-of-palette markers shown in magenta" % int(image.get_meta("palette_markers"))
		call_deferred("_update_image_size")
	elif kind == "audio":
		if bytes > 67108864: _error("This audio file is too large to preview (limit: 64 MiB)."); return
		_show_audio(path)
	elif kind == "video":
		video_preview.show(); video_preview.show_video(path)
	elif kind == "text":
		if bytes > 262144: _error("This text file is too large to preview (limit: 256 KiB)."); return
		var data := FileAccess.get_file_as_bytes(path)
		if data.has(0): _error("This file contains binary data rather than plain text."); return
		text_view.text = data.get_string_from_utf8()
		text_view.visible = true
	summary_changed.emit()

func _error(message: String) -> void:
	text_view.text = message
	text_view.visible = true
	summary += " · Preview unavailable"

func _update_image_size() -> void:
	if image == null or not image_panel.visible: return
	var zoom := image_zoom.value
	if fit_image:
		var available := image_scroll.size - Vector2(20, 20)
		zoom = maxf(0.01, minf(available.x / image.get_width(), available.y / image.get_height()))
		image_zoom.set_value_no_signal(zoom)
	image_view.custom_minimum_size = Vector2(image.get_size()) * zoom
	image_zoom_label.text = "%.0f%%" % (zoom * 100)

static func raw_stream(data: PackedByteArray, rate: int, format: int, stereo: bool) -> AudioStreamWAV:
	return LegacyAudio.raw_stream(data, rate, format, stereo)

func _show_audio(path: String) -> void:
	var extension := path.get_extension().to_lower()
	var stream: AudioStream
	match extension:
		"wav": stream = AudioStreamWAV.load_from_file(path)
		"mp3": stream = AudioStreamMP3.load_from_file(path)
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
		"raw": stream = raw_stream(FileAccess.get_file_as_bytes(path), raw_rate.get_selected_id(), raw_format.selected, raw_channels.selected == 1)
	if stream == null or stream.get_length() <= 0.0: _error("This audio file could not be decoded."); return
	audio_source = stream
	_set_audio_loop(audio_loop.button_pressed)
	audio_panel.visible = true
	raw_tools.visible = extension == "raw"
	audio_play.text = "Play"
	audio_seek.max_value = stream.get_length()
	audio_seek.set_value_no_signal(0)
	audio_seek.editable = true
	audio_info.text = "%s\n%s · %.2f seconds" % [path.get_file(), summary, stream.get_length()]
	if extension == "raw": audio_info.text += "\nHeaderless PCM: format and sample rate are preview assumptions; adjust below."
	elif stream is AudioStreamWAV: audio_info.text += " · %d Hz · %s" % [stream.mix_rate, "Stereo" if stream.stereo else "Mono"]
	summary += " · %.2f seconds" % stream.get_length()
	waveform.peaks = _peaks(stream)
	waveform.progress = 0.0
	waveform.queue_redraw()
	_update_audio_time()

func _set_audio_loop(enabled: bool) -> void:
	if audio_source == null: return
	var playing := audio_player.playing
	var paused := audio_player.stream_paused
	var position := audio_seek.value if paused else (audio_player.get_playback_position() if playing else 0.0)
	audio_player.stream = AudioLoop.prepare(audio_source, enabled)
	if playing or paused:
		audio_player.play(position)
		audio_player.stream_paused = paused

static func _peaks(stream: AudioStream) -> PackedFloat32Array:
	var peaks := PackedFloat32Array()
	if not stream is AudioStreamWAV or stream.format not in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS]: return peaks
	var data: PackedByteArray = stream.data
	var bytes := 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var count := data.size() / bytes
	var bins := mini(512, count)
	for bin in range(bins):
		var start := int(float(bin) * count / bins)
		var end := int(float(bin + 1) * count / bins)
		var peak := 0.0
		for index in range(start, end, maxi(1, (end - start) / 256)):
			var value := float(data.decode_s16(index * bytes)) / 32768.0 if bytes == 2 else float(int(data[index]) if data[index] < 128 else int(data[index]) - 256) / 128.0
			peak = maxf(peak, absf(value))
		peaks.append(peak)
	return peaks

func _toggle_audio() -> void:
	if audio_player.stream == null: return
	if audio_player.stream_paused:
		audio_player.stream_paused = false
		audio_play.text = "Pause"
	elif audio_player.playing:
		audio_player.stream_paused = true
		audio_play.text = "Play"
	else:
		audio_player.play(0.0 if audio_seek.value >= audio_seek.max_value else audio_seek.value)
		audio_play.text = "Pause"

func _stop_audio() -> void:
	if video_preview != null: video_preview.stop_playback()
	audio_player.stop()
	audio_player.stream_paused = false
	audio_seek.set_value_no_signal(0)
	audio_play.text = "Play"
	_update_audio_time()

func _seek_audio(position: float) -> void:
	if audio_player.stream == null: return
	if audio_player.stream_paused:
		audio_player.play(position)
		audio_player.stream_paused = true
	elif audio_player.playing: audio_player.seek(position)
	_update_audio_time()

func _update_audio_time() -> void:
	audio_time.text = "%.2f / %.2f s" % [audio_seek.value, audio_seek.max_value]
	waveform.progress = audio_seek.value / maxf(0.01, audio_seek.max_value)
	waveform.queue_redraw()

func _process(_delta: float) -> void:
	if not audio_panel.visible or audio_player.stream == null: return
	if audio_player.playing and not audio_player.stream_paused and not seeking: audio_seek.set_value_no_signal(audio_player.get_playback_position())
	_update_audio_time()
