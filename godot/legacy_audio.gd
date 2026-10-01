extends RefCounted

static func load_file(path: String) -> AudioStream:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 16777216: return null
	var data := file.get_buffer(file.get_length())
	if data.is_empty(): return null
	var stream: AudioStream
	match path.get_extension().to_lower():
		"raw": stream = raw_stream(data, 11025, 0, false)
		"wav": stream = AudioStreamWAV.load_from_buffer(data)
		"ogg": stream = AudioStreamOggVorbis.load_from_buffer(data)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = data
			stream = mp3
	if stream == null or stream.get_length() <= 0.0: return null
	stream.set_meta("asset_source", path)
	return stream

static func raw_stream(data: PackedByteArray, rate: int, format: int, stereo: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS if format == 2 else AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = rate
	stream.stereo = stereo
	data = data.duplicate()
	if format == 0:
		for index in range(data.size()): data[index] = (int(data[index]) + 128) & 255
	var frame_bytes := (2 if format == 2 else 1) * (2 if stereo else 1)
	data.resize(data.size() - data.size() % frame_bytes)
	stream.data = data
	return stream
