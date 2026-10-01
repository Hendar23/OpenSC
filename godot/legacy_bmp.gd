extends RefCounted

# Some original 8-bit textures use RLE8; others have incorrect bfSize fields.
# Decode from actual bytes rather than rewriting or converting the game files.
static func load_image(path: String) -> Image:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	var data := file.get_buffer(file.get_length())
	if data.size() >= 32 and data.slice(0, 4) == PackedByteArray([0x59, 0xa6, 0x6a, 0x95]): return decode_raster(data)
	if data.size() < 54 or data.slice(0, 2).get_string_from_ascii() != "BM": return null
	if data.decode_u16(28) != 8: return Image.load_from_file(path)
	return decode_indexed(data, true)

static func _big_u32(data: PackedByteArray, offset: int) -> int:
	return (int(data[offset]) << 24) | (int(data[offset + 1]) << 16) | (int(data[offset + 2]) << 8) | int(data[offset + 3])

static func decode_raster(data: PackedByteArray) -> Image:
	if data.size() < 32: return null
	var width := _big_u32(data, 4)
	var height := _big_u32(data, 8)
	var depth := _big_u32(data, 12)
	var kind := _big_u32(data, 20)
	var map_type := _big_u32(data, 24)
	var map_size := _big_u32(data, 28)
	if width < 1 or height < 1 or width * height > 16777216 or depth not in [8, 16, 24] or kind not in [0, 1, 3]: return null
	var start := 32 + map_size
	var stride := ((width * depth + 15) / 16) * 2
	if start + stride * height > data.size(): return null
	if depth == 8 and (map_type != 1 or map_size < 3 or map_size % 3 != 0): return null
	var output := PackedByteArray()
	output.resize(width * height * 3)
	for y in range(height):
		for x in range(width):
			var source := start + y * stride + x * (depth / 8)
			var dest := (y * width + x) * 3
			if depth == 16:
				# The game's 16-bit variants have big-endian raster headers but
				# little-endian RGB565 pixels and a pixel-count length field.
				var pixel := int(data[source]) | (int(data[source + 1]) << 8)
				output[dest] = ((pixel >> 11) & 31) * 255 / 31
				output[dest + 1] = ((pixel >> 5) & 63) * 255 / 63
				output[dest + 2] = (pixel & 31) * 255 / 31
			elif depth == 24:
				output[dest] = data[source if kind == 3 else source + 2]
				output[dest + 1] = data[source + 1]
				output[dest + 2] = data[source + 2 if kind == 3 else source]
			else:
				var index := int(data[source])
				var colors := map_size / 3
				if index >= colors: return null
				for channel in range(3): output[dest + channel] = data[32 + channel * colors + index]
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, output)

static func decode_indexed(data: PackedByteArray, show_palette_markers: bool = false) -> Image:
	if data.size() < 54: return null
	var dib := int(data.decode_u32(14))
	var width := int(data.decode_s32(18))
	var signed_height := int(data.decode_s32(22))
	var height := absi(signed_height)
	var compression := int(data.decode_u32(30))
	var pixels := int(data.decode_u32(10))
	var palette_count := int(data.decode_u32(46))
	if palette_count == 0: palette_count = 256
	if dib < 40 or width < 1 or height < 1 or width * height > 16777216 or palette_count > 256: return null
	var palette_start := 14 + dib
	if palette_start + palette_count * 4 > pixels or pixels > data.size(): return null
	var indices := PackedByteArray()
	indices.resize(width * height)
	if compression == 0:
		var stride := (width + 3) & ~3
		if pixels + stride * height > data.size(): return null
		for row in range(height):
			for column in range(width): indices[row * width + column] = data[pixels + row * stride + column]
	elif compression == 1:
		var cursor := pixels
		var x := 0
		var y := 0
		while cursor + 2 <= data.size():
			var count := int(data[cursor])
			var value := int(data[cursor + 1])
			cursor += 2
			if count > 0:
				if y >= height or x + count > width: return null
				for column in range(count): indices[y * width + x + column] = value
				x += count
			elif value == 0:
				x = 0
				y += 1
			elif value == 1: break
			elif value == 2:
				if cursor + 2 > data.size(): return null
				x += int(data[cursor])
				y += int(data[cursor + 1])
				cursor += 2
				if x > width or y >= height: return null
			else:
				if y >= height or x + value > width or cursor + value > data.size(): return null
				for column in range(value): indices[y * width + x + column] = data[cursor + column]
				x += value
				cursor += value + (value & 1)
	else: return null
	var rgba := PackedByteArray()
	rgba.resize(width * height * 4)
	var markers := 0
	for row in range(height):
		var target_row := height - 1 - row if signed_height > 0 else row
		for column in range(width):
			var index := int(indices[row * width + column])
			if index >= palette_count:
				if not show_palette_markers: return null
				# FONTRTLO.BMP uses index 255 outside its four-colour palette
				# for glyph separators. Show these explicitly in the inspector.
				var marker := (target_row * width + column) * 4
				rgba[marker] = 255
				rgba[marker + 1] = 0
				rgba[marker + 2] = 255
				rgba[marker + 3] = 255
				markers += 1
				continue
			var source := palette_start + index * 4
			var target := (target_row * width + column) * 4
			rgba[target] = data[source + 2]
			rgba[target + 1] = data[source + 1]
			rgba[target + 2] = data[source]
			rgba[target + 3] = 255
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)
	if markers > 0: image.set_meta("palette_markers", markers)
	return image
