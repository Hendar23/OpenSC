extends SceneTree
const ReplayAudio = preload("res://replay_audio.gd")
class Events extends RefCounted:
	signal session_started(loaded: bool)
class Context extends Node3D:
	var events := Events.new()
	var photo_mode: Node3D
	var world_root: Node3D
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func block(count: int, value: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array(); result.resize(count); result.fill(value); return result

func run() -> void:
	var bus_count := AudioServer.bus_count
	var effects_count := AudioServer.get_bus_effect_count(0)
	var audio := ReplayAudio.new(); root.add_child(audio); audio.setup()
	check(audio.output.bus == StringName(audio.output_bus) and audio.output.bus != &"Effects","Recorded mix bypasses a second effects-volume application")
	check(audio.output.process_mode == Node.PROCESS_MODE_ALWAYS,"Replay output can run while gameplay audio remains paused")
	# Use a tiny rate for deterministic sample-level tests without real devices.
	audio.rate = 100
	audio.append(block(10,Vector2(0.5,-0.5)),0.1)
	audio.append(block(10,Vector2(-0.25,0.25)),0.2)
	var result := audio.samples(0.05,10)
	check(result.size() == 10 and result[0] == Vector2(0.5,-0.5) and result[4] == result[0] and result[5] == Vector2(-0.25,0.25),"Seeking mid-sound preserves stereo and crosses chunk boundaries at the right sample")
	check(audio.samples(-0.05,10)[0] == Vector2.ZERO and audio.samples(0.3,10)[0] == Vector2.ZERO,"Missing history and future samples are silent")
	audio.write_end = -1; audio.append(block(10,Vector2.ONE),0.4)
	result = audio.samples(0.15,20)
	check(result[0] == Vector2(-0.25,0.25) and result[5] == Vector2.ZERO and result[14] == Vector2.ZERO and result[15] == Vector2.ONE,"A recording pause creates a silent gap without replaying stale sounds")
	audio.trim(0.35)
	check(audio.frame_count == 5 and absf(audio.chunks[0].start-0.35) < 0.00001,"Expiry trims the partial oldest chunk accurately")
	audio.clear()
	for index in range(700): audio.append(block(5,Vector2.ONE),(index+1)*0.05)
	check(audio.frame_count <= 3000 and audio.chunks.size() <= 601 and audio.chunks[0].start >= 5.0-0.00001,"Long recording has a hard thirty-second memory bound")
	audio.set_recording(true)
	check(audio.recording and AudioServer.get_bus_effect_count(0) == effects_count+1,"Recording installs one non-destructive master mix tap")
	audio.set_recording(true)
	check(AudioServer.get_bus_effect_count(0) == effects_count+1,"Repeated recording updates cannot install duplicate capture effects")
	audio.set_recording(false)
	check(not AudioServer.is_bus_effect_enabled(0,audio._tap_index()),"Pausing disables capture, preventing playback feedback")
	# Test output state transitions with the real stream object, Dummy driver only.
	audio.rate = AudioServer.get_mix_rate(); audio.clear()
	audio.append(block(int(audio.rate),Vector2(0.1,-0.1)),1.0)
	paused = true
	audio.update(0.2,true)
	check(audio.active and audio.output.playing,"Normal-speed replay starts recorded sound while the tree is paused")
	audio.update(0.25,false)
	check(not audio.active and not audio.output.playing,"Pause, scrub or slow-speed gating stops output immediately")
	audio.update(0.7,true)
	check(audio.active and audio.read_time >= 0.7 and audio.read_time <= 0.83,"Returning to normal speed starts at the selected timestamp")
	audio.stop()
	check(not audio.active and not audio.output.playing,"Leaving replay cannot leak an old recorded voice")
	audio.clear()
	check(audio.frame_count == 0 and audio.chunks.is_empty() and not audio.recording,"Option disable, docking and new/load clear all recorded audio")
	paused = false; audio.free()
	check(AudioServer.bus_count == bus_count and AudioServer.get_bus_effect_count(0) == effects_count,"Teardown removes only its own temporary bus and capture effect")
	# Exercise the actual replay controls and the mix tap, without loading a
	# world, touching preferences or initializing a graphics rendering device.
	preload("res://natural_light.gd").ensure_globals()
	var context := Context.new(); root.add_child(context)
	context.photo_mode = Node3D.new(); context.add_child(context.photo_mode)
	context.world_root = context
	var replay := preload("res://photo_replay.gd").new()
	context.photo_mode.add_child(replay); replay.setup(context); replay.set_process(false)
	var tone := AudioStreamPlayer.new(); context.add_child(tone)
	var wave := AudioStreamWAV.new(); wave.format = AudioStreamWAV.FORMAT_8_BITS; wave.mix_rate = 8000
	var pcm := PackedByteArray(); pcm.resize(128); pcm.fill(24); wave.data = pcm
	wave.loop_mode = AudioStreamWAV.LOOP_FORWARD; wave.loop_end = 128
	tone.stream = wave
	replay.audio.set_recording(true); tone.play()
	await create_timer(0.15).timeout
	replay.capture(0.15)
	check(replay.audio.frame_count > 0,"The real audio bus tap captures mixed samples under the Dummy driver")
	var peak := 0.0
	for chunk in replay.audio.chunks:
		for sample in chunk.frames: peak = maxf(peak,absf(sample.x))
	check(peak > 0.01,"Recorded mix contains the original waveform, not just empty buffers")
	replay.capture(0.05)
	paused = true
	check(replay.begin() and not replay.audio.recording,"Entering photo replay disables capture before recorded playback can begin")
	replay.seek(0.05); replay.toggle_play()
	check(replay.playing and replay.audio.active,"Actual normal-speed play control starts recorded audio")
	replay.toggle_play()
	check(not replay.audio.active,"Actual pause control stops recorded audio")
	replay.toggle_play(); replay.speed = 0.25; replay.advance(0.01)
	check(replay.playing and not replay.audio.active,"Actual slow-motion playback stays silent")
	replay.speed = 1.0; replay.advance(0.01)
	check(replay.audio.active,"Normal-speed audio resumes at the slow-motion cursor")
	replay.seek(0.06)
	check(not replay.audio.active,"Actual seek discards queued output immediately")
	replay.playing = true; replay.advance(0.01,-1)
	check(not replay.playing and not replay.audio.active,"Holding scrub stops both playback and recorded audio")
	replay.toggle_play(); replay.end()
	check(not replay.audio.active and is_instance_valid(tone) and tone.stream == wave,"Leaving replay stops only its recorded voice, retaining the original player")
	paused = false
	check(tone.playing,"Original live audio resumes when gameplay is unpaused")
	replay.set_enabled(false)
	check(replay.audio.chunks.is_empty() and not replay.audio.recording,"Turning replay off clears sound through the real setting handler")
	tone.stop(); context.free()
	# AudioServer releases stopped voices on its mixing thread, not a render frame.
	await create_timer(0.15).timeout
	check(AudioServer.bus_count == bus_count and AudioServer.get_bus_effect_count(0) == effects_count,"Integrated teardown restores the audio bus layout")
	print("Replay audio: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
