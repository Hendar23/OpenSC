extends RefCounted

const Assets = preload("res://clump_loader.gd")
const Scenery = preload("res://scenery_loader.gd")

static func portrait(folder: String, race: int) -> Texture2D:
	var name := "RTTRADH.BMP"
	if race == 2: name = "RTTECHH.BMP"
	elif race == 4: name = "RTFACTH.BMP"
	return Assets._load_texture(folder, name.get_basename(), "", {})

static func messages(folder: String) -> Dictionary:
	var result := {}
	var file := FileAccess.open(folder.path_join("DATA/ENGLISH/LANGUAGE.ENC"), FileAccess.READ)
	if file == null: return result
	var data := file.get_buffer(file.get_length())
	if data.size() < 4: return result
	var count := int(data.decode_u32(0))
	if count < 1 or count > 256: return result
	var base := 4 + count * 21
	if not Assets._fits(data, 0, base): return result
	for index in range(count):
		var entry := 4 + index * 21
		if Scenery._string(data, entry, 13).to_upper() != "MESSAGES.TXT": continue
		var start := base + int(data.decode_u32(entry + 17))
		var size := int(data.decode_u32(entry + 13))
		if not Assets._fits(data, start, size): return result
		var text := data.slice(start, start + size)
		for byte in range(text.size()): text[byte] ^= 255
		var terminator := text.find(0)
		if terminator >= 0: text.resize(terminator)
		for line in text.get_string_from_ascii().replace("\r", "").split("\n", false):
			var fields := line.split("\t")
			if fields.size() >= 5: result[fields[0].strip_edges()] = fields[4].strip_edges()
		return result
	return result
