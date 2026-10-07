extends SceneTree
const Audio = preload("res://submarine_audio.gd")
const Pilot = preload("res://submarine_controller.gd")
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
	var folder := Paths.find_game_folder()
	for role in Audio.SAMPLES:
		var stream: AudioStreamWAV = Audio.load_sound(folder, role)
		check(stream != null and stream.mix_rate == 11025 and not stream.stereo, "Original propulsion sample decodes at its original rate")
		check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == stream.data.size(), "Entire original sample loops continuously")
	var pilot := Pilot.new()
	pilot.remember_settings = false
	root.add_child(pilot)
	pilot.visual = Node3D.new()
	pilot.add_child(pilot.visual)
	pilot.submarine_audio.setup(pilot, folder)
	pilot.set_process(false)
	var sound: Node = pilot.submarine_audio
	check(sound.shield_warning.stream != null and sound.shield_warning.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,"Original LOSHIELD sample repeats")
	pilot.active = true; pilot.freeze = true
	pilot.restore_health(100,30); sound.update(0)
	check(not sound.shield_warning.playing,"Warning is silent at exactly 30 percent")
	pilot.restore_health(100,29); sound.update(0)
	check(sound.shield_warning.playing,"Warning starts below 30 percent")
	pilot.visual.hide(); sound.update(0)
	check(sound.shield_warning.playing,"Camera visibility cannot silence low shield warning")
	pilot.visual.show(); pilot.restore_health(200,60); sound.update(0)
	check(not sound.shield_warning.playing,"Warning uses percentage of shield capacity")
	pilot.restore_health(100,20); sound.update(0); pilot.active = false; sound.update(0)
	check(not sound.shield_warning.playing,"Docked or inactive submarine stops warning")
	pilot.active = true; pilot.restore_health(100,0); sound.update(0)
	check(not sound.shield_warning.playing,"Destroyed submarine stops warning")
	pilot.restore_health(); pilot.active = false
	sound.update(0.1)
	check(sound.players.values().all(func(p: AudioStreamPlayer) -> bool: return not p.playing), "Stopped propulsion is silent")
	pilot.pod_rotation_power = 1.0
	sound.update(0.5)
	check(sound.players.pod_rotation.playing and not sound.players.main_propeller.playing and not sound.players.side_pods.playing, "PROP1 plays independently while pod angles change")
	pilot.pod_rotation_power = 0.0
	for frame in range(120): sound.update(1.0 / 60.0)
	check(not sound.players.pod_rotation.playing, "Holding a steady pod angle does not keep its rotation motor playing")
	pilot.propeller_speeds = Vector3(0.5, 0, 0)
	pilot.movement.main_power = 0.5
	for frame in range(60): sound.update(1.0 / 60)
	var main: AudioStreamPlayer = sound.players.main_propeller
	var low_pitch := main.pitch_scale
	var low_volume := main.volume_db
	check(main.playing and not sound.players.side_pods.playing, "Main propeller plays independently of side pods")
	check(not sound.players.pod_rotation.playing, "Main propulsion no longer triggers the pod rotation sample")
	pilot.propeller_speeds = Vector3.ONE
	pilot.movement.main_power = 1
	pilot.velocity = Vector3.FORWARD * float(pilot.movement.settings.forward_speed)
	for frame in range(60): sound.update(1.0 / 60)
	check(main.pitch_scale > low_pitch and main.volume_db > low_volume and sound.players.side_pods.playing, "Acceleration raises playback pitch and volume smoothly")
	sound.solo_role = "side_pods"
	sound.update(0.1)
	check(main.volume_db == -80 and sound.players.side_pods.volume_db > -60, "Solo isolates a layer without stopping its playback phase")
	sound.solo_role = ""
	pilot.movement.main_power = 0
	pilot.propeller_speeds *= 0.8
	sound.update(0.1)
	check(main.playing and sound.levels.x > 0, "Propulsion loop continues during visual propeller spin-down")
	pilot.propeller_speeds = Vector3.ZERO
	for frame in range(120): sound.update(1.0 / 60)
	check(sound.players.values().all(func(p: AudioStreamPlayer) -> bool: return not p.playing), "All loops stop after propellers coast to rest even if hull is moving")
	pilot.propeller_speeds = Vector3(-1, -1, -1)
	pilot.movement.main_power = -1
	sound.update(0.5)
	check(main.playing and main.pitch_scale > 0 and sound.players.side_pods.playing, "Reverse thrust plays loops at a positive playback rate")
	pilot.visual.visible = false
	sound.update(0.1)
	check(sound.players.values().all(func(p: AudioStreamPlayer) -> bool: return not p.playing), "Hidden docked submarine is silent")
	pilot.visual.visible = true
	sound.update(0.5)
	pilot.reset_at(Vector3.ZERO)
	check(sound.levels.is_zero_approx() and not main.playing, "Reset clears propulsion audio immediately")
	sound.update(0.5)
	pilot.visual.free()
	sound.update(0.1)
	check(sound.players.values().all(func(p: AudioStreamPlayer) -> bool: return not p.playing), "Removing the hull during world reload silences its loops safely")
	var seam_source := AudioStreamWAV.new()
	seam_source.format = AudioStreamWAV.FORMAT_8_BITS
	seam_source.mix_rate = 11025
	var abrupt := PackedByteArray()
	abrupt.resize(1000)
	for index in range(1000): abrupt[index] = 136 if index < 500 else 120
	seam_source.data = abrupt
	var joined: AudioStreamWAV = Audio.seamless_loop(seam_source, 15)
	check(joined.format == AudioStreamWAV.FORMAT_16_BITS and joined.loop_end * 2 == joined.data.size(), "Smoothed loop uses uncompressed 16-bit PCM and correct frame bounds")
	check(abs(joined.data.decode_s16(0) - joined.data.decode_s16(joined.data.size() - 2)) < 256, "Overlap blend removes an abrupt wraparound step")
	check(seam_source.data == abrupt and Audio.seamless_loop(seam_source, 0) == seam_source, "Smoothing leaves original samples untouched and can be disabled")
	# Exercise the engine mixer, not just the byte seam. Its loop-end overread
	# previously injected a spike even when adjacent source samples were smooth.
	for bits in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS]:
		for stereo in [false, true]:
			var fixture_stream := AudioStreamWAV.new()
			fixture_stream.format = bits
			fixture_stream.stereo = stereo
			fixture_stream.mix_rate = int(AudioServer.get_mix_rate())
			fixture_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			fixture_stream.loop_begin = 1
			fixture_stream.loop_end = 5
			var bytes := 1 if bits == AudioStreamWAV.FORMAT_8_BITS else 2
			var channels := 2 if stereo else 1
			var pcm := PackedByteArray()
			pcm.resize(5 * channels * bytes)
			for frame in range(5):
				for channel in range(channels):
					var sample := (20 - frame * 3) * (1 if channel == 0 else -1)
					var offset := (frame * channels + channel) * bytes
					if bytes == 1: pcm[offset] = sample & 255
					else: pcm.encode_s16(offset, sample * 256)
			fixture_stream.data = pcm
			var guarded: AudioStreamWAV = Audio.guarded_loop(fixture_stream)
			check(guarded.loop_end == 5 and guarded.data.size() == 6 * channels * bytes and fixture_stream.data == pcm, "Guard frame preserves loop duration and source PCM for mono/stereo 8/16-bit streams")
			var playback := guarded.instantiate_playback()
			playback.start()
			var mixed := playback.mix_audio(1.0, 512)
			var correct := mixed.size() == 512
			for frame in range(2, mixed.size()):
				var source_frame := frame - 2 if frame < 7 else 1 + ((frame - 7) % 4)
				var expected := float((20 - source_frame * 3) * 256) / 32767.0
				correct = correct and absf(mixed[frame].x - expected) < 0.0001 and absf(mixed[frame].y - expected * (-1 if stereo else 1)) < 0.0001
			check(correct, "Actual mixer repeats every loop frame without an invalid boundary sample")
			playback.stop()
	for role in Audio.SAMPLES:
		var loop: AudioStreamWAV = sound.players[role].stream
		var peak := 0.0
		for frame in range(loop.loop_end): peak = maxf(peak, absf(float(loop.data.decode_s16(frame * 2)) / 32767.0))
		var low: float = sound.tuning.settings[role + "_pitch_min"]
		var high: float = sound.tuning.settings[role + "_pitch_max"] + sound.tuning.settings[role + "_speed_pitch"]
		for pitch in [low, (low + high) / 2.0, high]:
			var playback := loop.instantiate_playback()
			playback.start()
			var no_spikes := true
			for block in range(256):
				for sample in playback.mix_audio(pitch, 512): no_spikes = no_spikes and absf(sample.x) < peak * 1.15
			check(no_spikes, "%s has no invalid wrap spikes across exported pitch range" % role)
			playback.stop()
	# A smooth motor tone should retain its level through a mismatched join.
	var tone := AudioStreamWAV.new()
	tone.format = AudioStreamWAV.FORMAT_16_BITS
	tone.mix_rate = 11025
	var tone_data := PackedByteArray()
	tone_data.resize(4096 * 2)
	for frame in range(4096): tone_data.encode_s16(frame * 2, int(sin(TAU * frame / 40.0) * 10000))
	tone.data = tone_data
	var smooth: AudioStreamWAV = Audio.seamless_loop(tone, 19.0)
	var even_level := true
	for start in range(smooth.loop_end - 209, smooth.loop_end):
		var energy := 0.0
		for frame in range(start, start + 40): energy += float(smooth.data.decode_s16((frame % smooth.loop_end) * 2)) ** 2
		even_level = even_level and sqrt(energy / 40.0) > 6500.0
	check(even_level, "Tonal loop keeps its level through the blend instead of making a repeating dip")
	# A modern WAV override uses the same stable ID and original fallback.
	var fixture := "res://tests/audio-mod-fixture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(4410)
	wave.data = samples
	wave.save_to_wav(ProjectSettings.globalize_path(fixture.path_join("engine.wav")))
	var manifest := FileAccess.open(fixture.path_join("mod.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema_version": 1, "id": "audio.test", "assets": {"audio.submarine.main_propeller": "engine.wav"}}))
	manifest.close()
	Mods.initialize(false, "res://tests")
	Mods.apply(["audio.test"], Mods.order, false)
	var replaced: AudioStreamWAV = Audio.load_sound(folder, "main_propeller")
	check(replaced.mix_rate == 22050 and replaced.get_meta("asset_mod", "") == "audio.test", "Modern WAV mod overrides the original main propeller sample")
	Mods.apply([], Mods.order, false)
	check(Audio.load_sound(folder, "main_propeller").get_meta("asset_source").ends_with("PROP3.RAW"), "Disabling sound mod restores the original sample")
	for path in ["engine.wav", "mod.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.path_join(path)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	pilot.free()
	# Give the audio mixer a buffer to release stopped playback instances.
	await create_timer(0.25).timeout
	Mods.initialize(false)
	print("Submarine audio verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
