extends SceneTree
const Mods = preload("res://mod_registry.gd")
const Library = preload("res://fmv_library.gd")
const Movies = preload("res://fmv_player.gd")
const Storage = preload("res://player_storage.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	var mod_folder := OS.get_environment("OPENSC_TEST_FMV_MOD")
	if folder.is_empty() or mod_folder.is_empty():
		push_error("OPENSC_TEST_GAME_FOLDER and OPENSC_TEST_FMV_MOD are required"); quit(1); return
	Storage.root_override = ProjectSettings.globalize_path("res://../.local/fmv-upscale/test-player")
	Mods.initialize(false,mod_folder.get_base_dir(),Storage.preferences_path())
	var pack := Mods._read_pack(mod_folder)
	check(pack.valid and pack.errors.is_empty() and pack.assets.has("video.intro"),"Video manifest accepted")
	if not pack.assets.has("video.intro"): quit(1); return
	var replacement: String = pack.assets["video.intro"].path
	var info := Library.theora_info(replacement)
	check(info.get("width",0) == 1024 and info.get("height",0) == 640,"Encoded upscale is 1024x640 Theora")
	check(Library.theora_info(Library.source_path(folder,"intro")).is_empty(),"Smacker cannot masquerade as Theora")
	var player := Movies.new(); root.add_child(player)
	# Prime the stock clips before verifying toggles can reuse that cache.
	await player.prepare(folder)
	Mods.apply([str(pack.id)],[],false)
	await player.prepare(folder)
	check(player.movies.size() == 12 and player.warnings.is_empty(),"Other original movies remain available")
	if player.movies.size() != 12: player.free(); quit(1); return
	check(player.movies.intro.path == replacement,"Enabled mod replaces intro")
	check(player.movies.intro.size == Vector2(512,320),"Upscale preserves original display framing")
	player.request("intro")
	await create_timer(1.0).timeout
	var video: VideoStreamPlayer = player.movies.intro.player
	check(video.is_playing() and video.get_video_texture() != null and video.get_video_texture().get_width() == 1024,"Real decoder plays high resolution video")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(Storage.root_override.path_join("playback.png"))
	await player._finish_current()
	check(not player.active and not paused,"Skipping mod restores gameplay")
	# Simulate a corrupt higher-priority video while retaining the valid lower layer.
	var invalid: Dictionary = pack.assets["video.intro"].duplicate()
	invalid.path = Library.source_path(folder,"intro")
	Mods.layers["video.intro"].append(invalid)
	await player.prepare(folder)
	check(player.movies.intro.path == replacement and not Mods.runtime_warnings.is_empty(),"Invalid priority layer falls back to valid mod")
	Mods.apply([],[],false)
	await player.prepare(folder)
	check(player.movies.intro.path == Library.cache_path(Library.source_path(folder,"intro")),"Disabling mod restores original without restart")
	check(player.conversions == 0,"Disabling mod reuses original cache")
	player.free()
	print("FMV mods: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
