extends SceneTree
const Editor = preload("res://asset_editor.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var editor := Editor.new(); editor.remember_preferences = false; root.add_child(editor)
	await process_frame
	editor.category.select(6); editor._filter_assets()
	check(editor.filtered_names.size() == 12,"All original cutscenes appear in their own category")
	var index: int = editor.filtered_names.find("FMV/INTRO.SMK")
	check(index >= 0,"Intro is discoverable")
	editor._select_asset(index)
	var video: Node = editor.media.video_preview
	video.cache_directory = "res://tests/cutscene-fixtures"
	check(video.info.text.contains("Single-frame"),"The installed intro is identified honestly as a one-frame placeholder")
	check(video.info.text.contains("Choose FFmpeg"),"Missing decoder asks explicitly rather than searching PC-specific folders")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		video.set_decoder(args[0])
		for frame in range(600):
			if video.worker == null: break
			await create_timer(0.02).timeout
		check(video.still.texture != null and video.still.visible,"Smacker frame decodes and displays")
		if video.still.texture == null: print(video.info.text,"\n",video.info.tooltip_text)
		check(video.worker == null,"Conversion completes asynchronously")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tests/cutscene-preview.png")
		editor.category.select(0); editor._filter_assets()
		check(not video.visible and video.still.texture == null and video.player.stream == null,"Changing selection clears cutscene playback")
		if args.size() > 1:
			editor._open_asset_file(args[1]); await process_frame
			for frame in range(600):
				if video.worker == null: break
				await create_timer(0.02).timeout
			check(editor.category.selected == 6 and video.player.stream != null and video.player.is_playing(),"Opening a multi-frame movie plays it in the video category")
			video.toggle_playback(); check(video.player.paused,"Video pauses")
			video.stop_playback(); check(not video.player.is_playing(),"Video stops")
	editor.queue_free(); await process_frame
	print("Cutscenes: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
