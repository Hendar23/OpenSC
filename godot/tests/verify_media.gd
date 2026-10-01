extends SceneTree
const Editor = preload("res://asset_editor.gd")
const Media = preload("res://media_preview.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error("FAIL: " + label)
func choose(editor: Node, name: String, category: int) -> void:
	editor.search.text = ""
	editor.folder_filter.select(0)
	editor.category.select(category)
	editor._filter_assets()
	var index: int = editor.filtered_names.find(name)
	check(index >= 0, name + " is discoverable")
	if index >= 0: editor._select_asset(index)
func _run() -> void:
	var editor := Editor.new()
	editor.remember_preferences = false
	root.add_child(editor)
	await process_frame
	var counts := {"model": 0, "image": 0, "audio": 0, "text": 0}
	for entry in editor.catalog.values(): counts[entry.kind] += 1
	print("Media catalog: ", counts)
	check(counts.model >= 139 and counts.image >= 985 and counts.audio >= 447, "Original models, bitmaps and raw sounds are indexed")
	check(counts.audio >= 457, "Adjacent MP3 soundtrack is included")
	choose(editor, "GAMETEX/RTFACTH.BMP", 3)
	await process_frame
	check(editor.media.image != null and editor.media.image.get_size() == Vector2i(64, 80), "Portrait BMP loads at original dimensions")
	check(editor.model == null and not editor.preview.visible and editor.media.image_panel.visible and not editor.animation_bar.visible, "Image preview replaces model and hides model-only controls")
	editor.media.fit_image = false
	editor.media.image_zoom.value = 1
	editor.media._update_image_size()
	check(editor.media.image_view.custom_minimum_size == Vector2(64, 80), "100% zoom preserves native pixel size")
	editor.media.image_zoom.value = 2
	check(editor.media.image_view.custom_minimum_size == Vector2(128, 160), "Image zoom scales both dimensions equally")
	editor.media.fit_image = true
	editor.media._update_image_size()
	check(editor.media.image_view.custom_minimum_size.y <= editor.media.image_scroll.size.y + 1, "Fit keeps image inside available preview")
	choose(editor, "GAMETEX/BLADES.BMP", 3)
	check(editor.media.image != null and editor.media.image.get_size() == Vector2i(128, 128), "RLE8 bitmap previews")
	choose(editor, "INTROTEX/2SUB.BMP", 3)
	check(editor.media.image != null and editor.media.image.get_size() == Vector2i(245, 92), "Disguised 16-bit Sun raster BMP previews")
	var decoded := 0
	var invalid := 0
	var original_images := 0
	for entry in editor.catalog.values():
		if entry.kind != "image" or entry.has("mod_asset"): continue
		original_images += 1
		var bitmap: Image = preload("res://legacy_bmp.gd").load_image(entry.path)
		if bitmap == null: invalid += 1; print("Unsupported image: ", entry.relative)
		else: decoded += 1
	print("Original image decode: ", decoded, " loaded, ", invalid, " unsupported")
	check(decoded == original_images and invalid == 0, "Every original BMP and RAS image decodes")
	var corrupt_path := ProjectSettings.globalize_path("res://tests/media-invalid.bmp")
	var corrupt := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt.store_8(0)
	corrupt.close()
	editor.media.show_asset(corrupt_path, "image")
	check(editor.media.image == null and editor.media.text_view.visible, "Invalid images show explanation without stale preview")
	DirAccess.remove_absolute(corrupt_path)
	editor.folder_filter.select(editor.folder_names.find("GAMETEX"))
	editor.search.text = "RTFACTH"
	editor._filter_assets()
	check(editor.filtered_names == ["GAMETEX/RTFACTH.BMP"], "Folder and search filters combine without filename collisions")
	choose(editor, "WAVES/DOCK.RAW", 4)
	var stream: AudioStreamWAV = editor.media.audio_player.stream
	check(stream != null and stream.mix_rate == 11025 and not stream.stereo, "RAW defaults to configurable 11025 Hz mono PCM")
	check(not editor.media.audio_player.playing and editor.media.raw_tools.visible, "Selecting audio does not autoplay")
	check(not editor.media.waveform.peaks.is_empty(), "PCM waveform is generated")
	var converted := Media.raw_stream(PackedByteArray([0, 128, 255]), 11025, 0, false)
	check(converted.data == PackedByteArray([128, 0, 127]), "Unsigned raw samples are converted to Godot signed PCM without shifting silence")
	editor.media.raw_rate.select(3)
	editor.media.raw_rate.item_selected.emit(3)
	check(editor.media.audio_player.stream.mix_rate == 22050 and editor.media.summary.contains("0.45"), "RAW rate adjustment updates stream and duration")
	editor.media.audio_player.volume_db = -80
	editor.media._toggle_audio()
	await create_timer(0.1).timeout
	check(editor.media.audio_player.playing, "Audio transport starts playback")
	editor.media._toggle_audio()
	check(editor.media.audio_player.stream_paused, "Pause holds playback")
	editor.media.audio_loop.button_pressed = true
	check(editor.media.audio_player.stream_paused, "Enabling native looping preserves paused playback")
	var looped: AudioStreamWAV = editor.media.audio_player.stream
	check(looped.loop_mode == AudioStreamWAV.LOOP_FORWARD and looped.loop_end + 1 == looped.data.size(), "RAW preview uses the shared loop guard")
	editor.media.audio_loop.button_pressed = false
	check(editor.media.audio_player.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and editor.media.audio_player.stream_paused, "Disabling looping restores one-shot playback and pause state")
	editor.media.audio_seek.value = 0.2
	check(editor.media.audio_player.stream_paused, "Seeking while paused preserves pause state")
	editor.media._toggle_audio()
	check(not editor.media.audio_player.stream_paused, "Play resumes paused audio")
	editor.media._stop_audio()
	check(not editor.media.audio_player.playing and is_zero_approx(editor.media.audio_seek.value), "Stop returns playhead to start")
	# Exercise a real WAV container using a generated fixture; original files stay read-only.
	var fixture := AudioStreamWAV.new()
	fixture.format = AudioStreamWAV.FORMAT_16_BITS
	fixture.mix_rate = 8000
	fixture.data = PackedByteArray()
	var samples := PackedByteArray()
	samples.resize(16000)
	for index in range(8000): samples.encode_s16(index * 2, int(sin(float(index) * TAU * 220 / 8000) * 3000))
	fixture.data = samples
	var fixture_path := ProjectSettings.globalize_path("res://tests/media-fixture.wav")
	fixture.save_to_wav(fixture_path)
	editor._open_asset_file(fixture_path)
	check(editor.selected_name == fixture_path and editor.media.audio_panel.visible, "Open asset file previews external WAV through the browser")
	check(editor.media.audio_player.stream is AudioStreamWAV and is_equal_approx(editor.media.audio_seek.max_value, 1), "WAV loader preserves duration and native sample rate")
	check(not editor.media.raw_tools.visible and not editor.media.waveform.peaks.is_empty(), "WAV uses header format and displays waveform")
	DirAccess.remove_absolute(fixture_path)
	choose(editor, "OST/01_Ambient.mp3", 4)
	check(editor.media.audio_player.stream is AudioStreamMP3 and editor.media.audio_seek.max_value > 10, "MP3 soundtrack previews with its duration")
	editor.media.audio_loop.button_pressed = true
	check(editor.media.audio_player.stream.loop and not editor.media.audio_source.loop, "Compressed looping changes a runtime copy rather than the source")
	choose(editor, "README.TXT", 5)
	check(editor.media.text_view.visible and not editor.media.text_view.text.is_empty(), "Text files have a read-only preview")
	choose(editor, "ANGEL.DFF", 0)
	check(editor.model != null and editor.animation_playing and not editor.media.visible and editor.media.audio_player.stream == null, "Returning to animated 3D stops media playback and restores model controls")
	editor.search.text = "nothing-matches"
	editor._filter_assets()
	check(editor.model == null and not editor.preview.visible and editor.media.audio_player.stream == null, "Empty results clear stale previews")
	editor.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Media verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
