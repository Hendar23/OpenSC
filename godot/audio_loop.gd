extends RefCounted

static func prepare(source: AudioStream, enabled: bool, milliseconds: float = 0.0) -> AudioStream:
	if source == null: return null
	var result: AudioStream = source.duplicate()
	if result is AudioStreamWAV:
		result.loop_mode = AudioStreamWAV.LOOP_FORWARD if enabled else AudioStreamWAV.LOOP_DISABLED
		if enabled:
			result.loop_begin = 0
			result.loop_end = int(round(source.get_length() * source.mix_rate))
			result = guarded_loop(seamless_loop(result, milliseconds))
	elif result is AudioStreamOggVorbis or result is AudioStreamMP3:
		result.loop = enabled
	return result

static func guarded_loop(source: AudioStreamWAV) -> AudioStreamWAV:
	if source.format not in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS] or source.loop_mode != AudioStreamWAV.LOOP_FORWARD: return source
	var frame_bytes := (1 if source.format == AudioStreamWAV.FORMAT_8_BITS else 2) * (2 if source.stereo else 1)
	var data := source.data
	var frames := data.size() / frame_bytes
	if source.loop_begin < 0 or source.loop_end <= source.loop_begin or source.loop_end > frames: return source
	# Godot's PCM mixer can decode the exclusive loop_end before wrapping.
	# Supply the first loop frame there, instead of padding/adjacent memory.
	# Keep loop_end unchanged so this does not add time to the loop.
	var result: AudioStreamWAV = source.duplicate()
	var head := data.slice(source.loop_begin * frame_bytes, (source.loop_begin + 1) * frame_bytes)
	data.resize(maxi(data.size(), (source.loop_end + 1) * frame_bytes))
	for byte in range(frame_bytes): data[source.loop_end * frame_bytes + byte] = head[byte]
	result.data = data
	return result

static func seamless_loop(source: AudioStreamWAV, milliseconds: float) -> AudioStreamWAV:
	if milliseconds <= 0.0 or source.format not in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS]: return source
	var input := source.data
	var bytes := 1 if source.format == AudioStreamWAV.FORMAT_8_BITS else 2
	var channels := 2 if source.stereo else 1
	var frames := input.size() / (bytes * channels)
	var overlap := mini(int(source.mix_rate * milliseconds / 1000.0), int(frames / 4))
	if overlap < 2: return source
	var match_info := _match_overlap(input, bytes, channels, frames, overlap)
	overlap = int(match_info.x)
	var correlation := clampf(match_info.y, 0.0, 1.0)
	var output := PackedByteArray()
	output.resize((frames - overlap) * channels * 2)
	for frame in range(frames - overlap):
		for channel in range(channels):
			var index := ((frame + overlap) * channels + channel) * bytes
			var sample := input.decode_s8(index) * 256 if bytes == 1 else input.decode_s16(index)
			if frame >= frames - overlap * 2:
				var head := frame - (frames - overlap * 2)
				var head_index := (head * channels + channel) * bytes
				var other := input.decode_s8(head_index) * 256 if bytes == 1 else input.decode_s16(head_index)
				# Match tonal phase before blending, ease the transition, and
				# compensate for the energy lost when signals are uncorrelated.
				var weight := 0.5 - 0.5 * cos(PI * float(head) / (overlap - 1))
				var energy := (1.0 - weight) ** 2 + weight ** 2 + 2.0 * correlation * weight * (1.0 - weight)
				sample = clampi(int(round(lerpf(float(sample), float(other), weight) / sqrt(energy))), -32768, 32767)
			output.encode_s16((frame * channels + channel) * 2, sample)
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = source.mix_rate
	result.stereo = source.stereo
	result.data = output
	result.loop_mode = AudioStreamWAV.LOOP_FORWARD
	result.loop_end = frames - overlap
	for key in source.get_meta_list(): result.set_meta(key, source.get_meta(key))
	result.set_meta("loop_blend_frames", overlap)
	return result

static func _sample(data: PackedByteArray, index: int, bytes: int) -> float:
	return float(data.decode_s8(index) * 256 if bytes == 1 else data.decode_s16(index))

static func _correlation(data: PackedByteArray, bytes: int, channels: int, frames: int, overlap: int) -> float:
	var dot := 0.0
	var tail_energy := 0.0
	var head_energy := 0.0
	for frame in range(0, overlap, maxi(1, overlap / 128)):
		for channel in range(channels):
			var tail := _sample(data, ((frames - overlap + frame) * channels + channel) * bytes, bytes)
			var head := _sample(data, (frame * channels + channel) * bytes, bytes)
			dot += tail * head
			tail_energy += tail * tail
			head_energy += head * head
	return dot / sqrt(tail_energy * head_energy) if tail_energy * head_energy > 0.0 else 1.0

static func _match_overlap(data: PackedByteArray, bytes: int, channels: int, frames: int, requested: int) -> Vector2:
	var chosen := requested
	var best := _correlation(data, bytes, channels, frames, requested)
	# Search within the slider's duration. Strong correlation indicates a
	# tonal motor loop; retain the requested length for noise-like samples.
	for overlap in range(maxi(2, requested / 2), requested, maxi(1, requested / 512)):
		var correlation := _correlation(data, bytes, channels, frames, overlap)
		if correlation > maxf(0.6, best):
			best = correlation
			chosen = overlap
	return Vector2(chosen, best)
