extends RefCounted

const IMAGE_EXTENSIONS := ["bmp", "ras", "png", "jpg", "jpeg", "webp"]
const AUDIO_EXTENSIONS := ["wav", "raw", "mp3", "ogg"]
const TEXT_EXTENSIONS := ["txt", "csv", "cfg", "conf"]
const VIDEO_EXTENSIONS := ["smk", "ogv"]
const Mods = preload("res://mod_registry.gd")

static func index(folder: String) -> Dictionary:
	var result := {}
	_scan(folder, folder, result, 0)
	var music := folder.get_base_dir().path_join("OST")
	if DirAccess.dir_exists_absolute(music): _scan(music, folder.get_base_dir(), result, 0)
	for pack in Mods.packs:
		for entry in pack.assets.values():
			var key := "Mods/%s/%s" % [str(pack.id), str(entry.relative)]
			var kind := "text" if str(entry.id).begins_with("map.") else "audio" if str(entry.id).begins_with("audio.") else "image" if str(entry.id).begins_with("texture.") else "model"
			result[key] = {"path": entry.path, "relative": key, "folder": key.get_base_dir(), "kind": kind, "mod_asset": true, "descriptor": entry}
	return result

static func _scan(folder: String, base: String, result: Dictionary, depth: int) -> void:
	if depth > 8: return
	var directory := DirAccess.open(folder)
	if directory == null: return
	for filename in directory.get_files():
		var extension := filename.get_extension().to_lower()
		var kind := ""
		if extension == "glb" or (extension == "dff" and folder.get_file().to_upper() == "CLUMPS"): kind = "model"
		elif extension in IMAGE_EXTENSIONS: kind = "image"
		elif extension in AUDIO_EXTENSIONS and (extension != "raw" or "/WAVES" in folder.to_upper().replace("\\", "/")): kind = "audio"
		elif extension in TEXT_EXTENSIONS: kind = "text"
		elif extension in VIDEO_EXTENSIONS: kind = "video"
		if kind.is_empty(): continue
		var path := folder.path_join(filename)
		var relative := path.trim_prefix(base + "/").trim_prefix(base + "\\").replace("\\", "/")
		# Retain the existing model identifiers; other assets include their folder.
		var key := filename if kind == "model" else relative
		result[key] = {"path": path, "relative": relative, "folder": relative.get_base_dir(), "kind": kind}
	for child in directory.get_directories():
		if child.begins_with(".") or child.to_lower() in ["backup", "backups"]: continue
		if directory.is_link(child): continue
		_scan(folder.path_join(child), base, result, depth + 1)
