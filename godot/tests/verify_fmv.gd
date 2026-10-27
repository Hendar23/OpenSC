extends SceneTree
const Movies = preload("res://fmv_player.gd")
const Library = preload("res://fmv_library.gd")
const Storage = preload("res://player_storage.gd")
var checks := 0
var failures := 0
var player: CanvasLayer
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func settle() -> void:
	for frame in range(6): await process_frame
func skip(code: Key = KEY_Y) -> void:
	var key := InputEventKey.new(); key.keycode = code; key.physical_keycode = code; key.pressed = true
	Input.parse_input_event(key)
	await settle()
	key.pressed = false; Input.parse_input_event(key)
func run() -> void:
	var decoder := Library.decoder_path()
	Storage.root_override = "res://tests/cache-fmv-fixtures"
	Storage.ensure_parent(Storage.preferences_path())
	var ignore := FileAccess.open(Storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string(""); ignore.close()
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): push_error("OPENSC_TEST_GAME_FOLDER is required"); quit(1); return
	preload("res://input_bindings.gd").install()
	# Actual files and decoder, not mocked successful conversions.
	player = Movies.new(); root.add_child(player)
	await player.prepare(folder,Callable(),decoder)
	check(player.movies.size() == 12 and player.warnings.is_empty(),"All twelve full Smacker clips convert during preparation")
	if player.movies.size() != 12: player.free(); quit(1); return
	if OS.get_name() == "Windows": check(Library.cache_path(folder.path_join("FMV/INTRO.SMK")) == Library.cache_path(folder.path_join("FMV/intro.smk")),"Catalogue previews and gameplay share one conversion despite path case")
	# Cache keys must still detect same-length source changes, rather than
	# accepting a stale film just because its name or timestamp looks familiar.
	var fixture := Storage.root_override.path_join("source-key.smk")
	var bytes := FileAccess.get_file_as_bytes(Library.source_path(folder,"intro")).slice(0,104)
	var file := FileAccess.open(fixture,FileAccess.WRITE); file.store_buffer(bytes); file.close()
	Library.Cache.reset_session()
	var original_key := Library.cache_path(fixture)
	bytes[103] = bytes[103] ^ 1
	file = FileAccess.open(fixture,FileAccess.WRITE); file.store_buffer(bytes); file.close()
	Library.Cache.reset_session()
	check(Library.cache_path(fixture) != original_key,"Changed source bytes invalidate the movie cache even at the same file size")
	DirAccess.remove_absolute(fixture)
	var count: int = player.conversions
	player.prepared_folder = ""
	await player.prepare(folder,Callable(),"missing-decoder")
	check(player.conversions == 0 and player.movies.size() == 12,"A warm launch uses validated conversions without executing a decoder")
	check(Library.movie("dock",0,1) == "traddock" and Library.movie("dock",0,2) == "techdock" and Library.movie("dock",0,4) == "refdock","City films follow original race flags")
	check(Library.movie("dock",0,3).is_empty(),"Aquatraz has no invented docking film")
	for city in [1,2,3,4]:
		check(Library.movie("peace",city) == ("btvpeace" if city in [1,3] else "pnnpeace"),"Peace bulletin matches sponsor city "+str(city))
	check(Library.movie("cities_destroyed",3) == "btvflat" and Library.movie("cities_destroyed",4) == "pnnflat","Later destruction news uses the recovered faction table")
	for row in [["walker_catastrophe","walkfail"],["world_destroyed","destruct"],["campaign_escape","outro"],["antagonist_destroyed","altout"]]:
		check(Library.movie(row[0]) == row[1] and Library.terminal(row[0]),"Recovered ending cue: "+row[0])
	check(Library.movie("player_died").is_empty(),"Ordinary player death must not trigger a catastrophic ending")
	var bus := AudioServer.get_bus_index("Effects")
	if bus < 0: AudioServer.add_bus(); bus = AudioServer.bus_count-1; AudioServer.set_bus_name(bus,"Effects")
	AudioServer.set_bus_mute(bus,false); AudioServer.set_bus_volume_db(bus,-6)
	check(player.request("intro") and player.active and paused,"Playing a prepared film pauses gameplay immediately")
	check(AudioServer.is_bus_mute(bus) and is_equal_approx(player.movies.intro.player.volume,db_to_linear(-6)),"Gameplay audio is silenced while the film respects effects volume")
	var video: VideoStreamPlayer = player.movies.intro.player
	await create_timer(0.3).timeout
	check(video.stream != null and video.is_playing() and not video.paused,"Prepared original video plays with its soundtrack")
	var stretch := root.get_stretch_transform().get_scale()
	check((video.size*player.scale*stretch).is_equal_approx(Vector2(512,320)),"Movie displays at double size (512x320 physical pixels) after window scaling")
	check(player.shade.size == root.get_visible_rect().size*stretch,"Opaque black cover fills the physical display")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/fmv-native-size.png")
	await skip()
	check(not player.active and not paused and not AudioServer.is_bus_mute(bus),"Y skips and restores gameplay and audio")
	player.request("dock",0,1); player.request("peace",2)
	await skip(KEY_ESCAPE)
	check(player.active and player.current == "pnnpeace" and paused,"Esc skips just the current film without leaking into gameplay")
	var confirm := InputEventJoypadButton.new(); confirm.button_index = JOY_BUTTON_A; confirm.pressed = true
	Input.parse_input_event(confirm); await settle()
	confirm.pressed = false; Input.parse_input_event(confirm)
	check(not player.active and not paused,"Controller A skips the queued film")
	paused = true; AudioServer.set_bus_mute(bus,true)
	player.request("dock",0,2); await skip()
	check(paused and AudioServer.is_bus_mute(bus),"Playback preserves a pre-existing pause and muted effects")
	paused = false; AudioServer.set_bus_mute(bus,false)
	player.request("antagonist_destroyed")
	# Theora follows the audio clock, including with a fixed simulation FPS.
	var deadline := Time.get_ticks_msec()+10000
	while player.active and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(not player.active,"Natural end of the full alternate ending returns control")
	check(player.conversions == 0,"Playback, repeats, skips and natural completion never convert assets")
	player.free(); print("FMV playback: %d checks, %d failures; initial conversions: %d" % [checks,failures,count]); quit(1 if failures else 0)
