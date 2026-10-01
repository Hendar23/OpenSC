extends SceneTree
const Pilot = preload("res://submarine_controller.gd")
const DockAudio = preload("res://docking_audio.gd")
const Paths = preload("res://asset_paths.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(description)
func _run() -> void:
	Mods.initialize(false)
	var pilot := Pilot.new()
	pilot.remember_settings = false
	root.add_child(pilot)
	pilot.visual = Node3D.new()
	pilot.add_child(pilot.visual)
	pilot.set_process(false)
	var folder := Paths.find_game_folder()
	pilot.submarine_audio.setup(pilot, folder)
	var sound := DockAudio.new()
	root.add_child(sound)
	sound.setup(pilot.submarine_audio, folder)
	sound.set_phase(true, true)
	check(sound.players.doors.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "DOCK is a one-shot")
	await create_timer(1.15).timeout
	check(not sound.players.doors.playing and sound.players.sequence.playing, "DOCK finishes without repeating while the docking background continues")
	sound.set_phase(true, true)
	check(not sound.players.doors.playing, "Repeated door-phase updates do not restart the finished DOCK sound")
	pilot.submarine_audio.tuning.settings.loop_blend_ms = 20.0
	sound._process(0.0)
	check(not sound.players.doors.playing, "Changing loop smoothing does not replay the door one-shot")
	sound.set_phase(true, false)
	sound.set_phase(true, true)
	check(sound.players.doors.playing, "The next door movement starts a new DOCK one-shot")
	var background: AudioStreamPlayback = sound.players.sequence.get_stream_playback()
	sound.set_phase(true, false, true)
	check(sound.players.sequence.get_stream_playback() == background and not sound.players.doors.playing and sound.players.door_stop.playing, "Door completion preserves the background loop and plays a one-shot")
	pilot.visual.hide()
	pilot.submarine_audio.update(0.1)
	sound._process(0.1)
	check(sound.players.sequence.playing and sound.players.door_stop.playing, "Dock sounds are independent of submarine visibility")
	pilot.submarine_audio.tuning.settings.master_volume = -60.0
	sound._process(0.0)
	check(sound.players.values().all(func(p: AudioStreamPlayer) -> bool: return p.volume_db == -80.0), "Master mute applies to all docking layers")
	pilot.submarine_audio.tuning.settings.master_volume = 0.0
	pilot.submarine_audio.solo_role = "main_propeller"
	sound._process(0.0)
	check(sound.players.values().all(func(p: AudioStreamPlayer) -> bool: return p.volume_db == -80.0), "Propeller solo excludes docking audio")
	pilot.submarine_audio.solo_role = ""
	sound._process(0.0)
	check(sound.players.sequence.volume_db == -18.0 and sound.players.doors.volume_db == -12.0 and sound.players.door_stop.volume_db == -10.0, "Clearing mute and solo restores each configured docking gain")
	sound.stop()
	check(sound.players.values().all(func(p: AudioStreamPlayer) -> bool: return not p.playing), "Cancellation stops both loops and the finish sound")
	for role in ["sequence"]:
		var stream: AudioStreamWAV = sound.players[role].stream
		var source: AudioStreamWAV = sound.sources[role]
		check(source.data.size() == FileAccess.get_file_as_bytes(source.get_meta("asset_source")).size(), "Preparing docking loop leaves original source length intact")
		var peak := 0.0
		for frame in range(stream.loop_end): peak = maxf(peak, absf(float(stream.data.decode_s16(frame * 2)) / 32767.0))
		var playback := stream.instantiate_playback()
		playback.start()
		var no_spikes := true
		for block in range(512):
			for sample in playback.mix_audio(1.0, 512): no_spikes = no_spikes and absf(sample.x) <= peak * 1.15
		check(no_spikes, "%s has no invalid boundary spikes in the real mixer" % role)
		playback.stop()
	# Test stable docking IDs and original fallback for modern replacements.
	var fixture := "res://tests/docking-audio-mod"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var pcm := PackedByteArray()
	pcm.resize(4410)
	wave.data = pcm
	var assets := {}
	for role in sound.SAMPLES:
		wave.save_to_wav(ProjectSettings.globalize_path(fixture.path_join(role + ".wav")))
		assets["audio.docking." + role] = role + ".wav"
	var manifest := FileAccess.open(fixture.path_join("mod.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema_version": 1, "id": "docking.audio.test", "assets": assets}))
	manifest.close()
	Mods.initialize(false, "res://tests")
	Mods.apply(["docking.audio.test"], Mods.order, false)
	sound.setup(pilot.submarine_audio, folder)
	for role in sound.SAMPLES:
		var stream: AudioStreamWAV = sound.players[role].stream
		check(stream.mix_rate == 22050 and stream.get_meta("asset_mod", "") == "docking.audio.test" and stream.loop_mode == (AudioStreamWAV.LOOP_FORWARD if role == "sequence" else AudioStreamWAV.LOOP_DISABLED), "Modern docking replacement retains the correct playback mode")
	Mods.apply([], Mods.order, false)
	sound.setup(pilot.submarine_audio, folder)
	check(sound.sources.sequence.get_meta("asset_source").ends_with("DOCKING.RAW"), "Disabling docking replacements restores the original sample")
	for role in sound.SAMPLES: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.path_join(role + ".wav")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.path_join("mod.json")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	Mods.initialize(false)
	sound.free()
	pilot.free()
	await create_timer(0.25).timeout
	print("Docking audio verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
