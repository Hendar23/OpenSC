extends RefCounted
## Retail filenames and cues: SC.EXE 00478360, 0041ef60, 0048d360.
const Cache = preload("res://asset_cache.gd")
const Storage = preload("res://player_storage.gd")
const FILES := ["intro","traddock","techdock","refdock","btvpeace","pnnpeace","walkfail","btvflat","pnnflat","destruct","outro","altout"]
const NEWS := ["btvpeace","pnnpeace","walkfail","btvflat","pnnflat"]
const ENCODING_OPTIONS := ["-map","0:v:0","-map","0:a:0?","-c:v","libtheora","-q:v","8","-threads","2","-c:a","libvorbis","-q:a","5"]

static func smacker_info(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() < 104: return {}
	var signature := file.get_buffer(4).get_string_from_ascii()
	if signature not in ["SMK2","SMK4"]: return {}
	var width := file.get_32(); var height := file.get_32(); var frames := file.get_32()
	return {"width":width,"height":height,"frames":frames}

static func movie(cue: String, city: int = 0, race: int = 0) -> String:
	match cue:
		"intro": return "intro"
		"dock": return {1:"traddock",2:"techdock",4:"refdock"}.get(race,"")
		"peace": return "btvpeace" if city in [1,3] else "pnnpeace" if city in [2,4] else ""
		"cities_destroyed": return "btvflat" if city in [1,3] else "pnnflat" if city in [2,4] else ""
		"walker_catastrophe": return "walkfail"
		"world_destroyed": return "destruct"
		"campaign_escape": return "outro"
		"antagonist_destroyed": return "altout"
	return ""

static func terminal(cue: String) -> bool:
	return cue in ["walker_catastrophe","world_destroyed","campaign_escape","antagonist_destroyed"]

static func source_path(folder: String, id: String) -> String:
	var directory := folder.path_join("FMV")
	if id in NEWS: directory = _child(directory,"ENGLISH")
	return _child(directory,id+".smk")

static func _child(folder: String, name: String) -> String:
	var direct := folder.path_join(name)
	if FileAccess.file_exists(direct) or DirAccess.dir_exists_absolute(direct): return direct
	var directory := DirAccess.open(folder)
	if directory == null: return direct
	for entry in directory.get_files():
		if entry.nocasecmp_to(name) == 0: return folder.path_join(entry)
	for entry in directory.get_directories():
		if entry.nocasecmp_to(name) == 0: return folder.path_join(entry)
	return direct

static func decoder_path() -> String:
	var config := ConfigFile.new()
	if config.load(Storage.preferences_path()) == OK:
		var configured := str(config.get_value("video","ffmpeg",""))
		if FileAccess.file_exists(configured): return configured
	var filename := "ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg"
	# A portable converter can sit beside the executable; source users can use
	# the existing asset viewer preference or their normal PATH installation.
	var candidates := [OS.get_executable_path().get_base_dir(),ProjectSettings.globalize_path("res://../Tools")]
	candidates.append_array(Array(OS.get_environment("PATH").split(";" if OS.get_name() == "Windows" else ":",false)))
	for directory: String in candidates:
		var path := directory.path_join(filename)
		if FileAccess.file_exists(path): return path
	return ""

static func cache_path(source: String) -> String:
	# Catalogue paths are uppercase; filesystem enumeration may preserve case.
	# They identify the same file on Windows and must share one conversion.
	var canonical := ProjectSettings.globalize_path(source).simplify_path()
	if OS.get_name() == "Windows": canonical = canonical.to_lower()
	# Ogg files are independent of engine, UI and mission code. Invalidate only
	# for changed source bytes or the actual encoding recipe, without adding a
	# converter to asset_cache.gd (which invalidates every other asset kind).
	var key := JSON.stringify(["fmv",1,canonical,Cache.fingerprint(canonical),ENCODING_OPTIONS]).sha256_text()
	return Cache.path_for(key,"ogv")

static func convert(decoder: String, source: String, output: String) -> Dictionary:
	# No scaling or frame-rate conversion: retain the original pixels/timing.
	# A temporary Ogg and checksum prevent interrupted imports becoming clips.
	if not Cache._prepare_write(output): return {"ok":false,"error":"Could not create FMV cache"}
	var temp := output.get_basename()+".tmp.ogv"
	var arguments := PackedStringArray(["-nostdin","-v","error","-y","-threads","2","-i",ProjectSettings.globalize_path(source)])
	arguments.append_array(PackedStringArray(ENCODING_OPTIONS)); arguments.append(ProjectSettings.globalize_path(temp))
	var messages := []
	var code := OS.execute(decoder,arguments,messages,true,false)
	if code == 0 and FileAccess.file_exists(temp):
		Cache._finish(temp,output)
		if Cache._valid(output): return {"ok":true}
	DirAccess.remove_absolute(temp)
	return {"ok":false,"error":"\n".join(messages).left(2000)}
