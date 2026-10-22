extends Node
## Bounded stereo mix history, independent of gameplay audio players.
const DURATION := 30.0
const LOOKAHEAD := 0.12
var tap: AudioEffectCapture
var output: AudioStreamPlayer
var generator: AudioStreamGenerator
var voice: AudioStreamGeneratorPlayback
var chunks: Array[Dictionary] = []
var rate := 48000.0
var frame_count := 0
var recording := false
var write_end := -1.0
var discarded := 0
var read_time := 0.0
var active := false
var output_bus := ""

func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rate = AudioServer.get_mix_rate()
	# Bypass Effects on output: its gain is already included in the recording.
	output_bus = "PhotoReplay_%d" % get_instance_id()
	AudioServer.add_bus()
	var bus := AudioServer.bus_count-1
	AudioServer.set_bus_name(bus,output_bus); AudioServer.set_bus_send(bus,"Master")
	output = AudioStreamPlayer.new(); output.name = "RecordedSound"
	output.bus = output_bus; output.process_mode = Node.PROCESS_MODE_ALWAYS
	generator = AudioStreamGenerator.new(); generator.mix_rate = rate
	generator.buffer_length = LOOKAHEAD*2
	output.stream = generator; add_child(output)

func _tap_index() -> int:
	if tap == null: return -1
	for index in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0,index) == tap: return index
	return -1

func set_recording(value: bool) -> void:
	if value == recording: return
	recording = value; write_end = -1
	if value and tap == null:
		tap = AudioEffectCapture.new(); tap.buffer_length = 0.5
		AudioServer.add_bus_effect(0,tap)
	var index := _tap_index()
	if index >= 0:
		AudioServer.set_bus_effect_enabled(0,index,value)
		tap.clear_buffer(); discarded = tap.get_discarded_frames()

func capture(time: float, oldest: float) -> void:
	if not recording or tap == null: return
	var lost := tap.get_discarded_frames()
	if lost != discarded:
		# A long stall overflowed the tap. Omit this interval rather than play
		# old queued audio at the wrong time after the stall.
		tap.clear_buffer(); discarded = lost; write_end = -1
	else:
		var count := tap.get_frames_available()
		if count > 0: append(tap.get_buffer(count),time)
	trim(oldest)

func append(frames: PackedVector2Array, time: float) -> void:
	if frames.is_empty(): return
	var duration := frames.size()/rate
	# Keep adjacent audio blocks sample-contiguous despite render-frame jitter.
	var start := time-duration
	if write_end >= 0 and absf(write_end-start) < 0.1: start = write_end
	chunks.append({"start":start,"frames":frames})
	write_end = start+duration; frame_count += frames.size()
	trim(time-DURATION)

func trim(oldest: float) -> void:
	while not chunks.is_empty():
		var chunk: Dictionary = chunks[0]
		var remove := clampi(int(ceil((oldest-float(chunk.start))*rate-0.00001)),0,chunk.frames.size())
		if remove == 0: break
		frame_count -= remove
		if remove == chunk.frames.size(): chunks.pop_front()
		else:
			chunks[0] = {"start":float(chunk.start)+remove/rate,"frames":chunk.frames.slice(remove)}
			break
	# The timestamp anchor may lead by a mixing block; enforce a hard frame cap.
	var excess := frame_count-int(rate*DURATION)
	while excess > 0 and not chunks.is_empty():
		var chunk: Dictionary = chunks[0]
		var remove := mini(excess,chunk.frames.size())
		excess -= remove; frame_count -= remove
		if remove == chunk.frames.size(): chunks.pop_front()
		else: chunks[0] = {"start":float(chunk.start)+remove/rate,"frames":chunk.frames.slice(remove)}

func samples(time: float, count: int) -> PackedVector2Array:
	# Packed-array slicing/copying avoids per-sample GDScript work at mix rate.
	var result := PackedVector2Array(); var at := time
	for chunk in chunks:
		var end: float = float(chunk.start)+chunk.frames.size()/rate
		if end <= at+0.25/rate: continue
		if result.size() >= count: break
		if float(chunk.start) > at+0.5/rate:
			var gap := mini(count-result.size(),maxi(0,int(round((float(chunk.start)-at)*rate))))
			result.resize(result.size()+gap); at += gap/rate
		if result.size() >= count: break
		var offset := clampi(int(round((at-float(chunk.start))*rate)),0,chunk.frames.size())
		var take := mini(count-result.size(),chunk.frames.size()-offset)
		result.append_array(chunk.frames.slice(offset,offset+take)); at += take/rate
	result.resize(count) # Unrecorded intervals are silence, never future sounds.
	return result

func update(time: float, audible: bool) -> void:
	if not audible or chunks.is_empty(): stop(); return
	if not active:
		output.play(); voice = output.get_stream_playback()
		active = voice != null; read_time = time
	if not active: return
	# Recover after a playback hitch without letting sound drift behind visuals.
	if read_time < time-0.1 or read_time > time+LOOKAHEAD*2:
		stop(); update(time,true); return
	var count := mini(voice.get_frames_available(),maxi(0,int((time+LOOKAHEAD-read_time)*rate)))
	if count > 0 and voice.push_buffer(samples(read_time,count)): read_time += count/rate

func stop() -> void:
	if output != null and active: output.stop()
	voice = null; active = false

func clear() -> void:
	stop(); set_recording(false)
	chunks.clear(); frame_count = 0; write_end = -1
	if tap != null: tap.clear_buffer()

func _exit_tree() -> void:
	clear()
	var index := _tap_index()
	if index >= 0: AudioServer.remove_bus_effect(0,index)
	var bus := AudioServer.get_bus_index(output_bus)
	if bus > 0: AudioServer.remove_bus(bus)
