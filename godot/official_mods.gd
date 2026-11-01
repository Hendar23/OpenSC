extends Node
## Catalogue metadata is separate from installed packs and never enables a mod.
const Storage = preload("res://player_storage.gd")
const Mods = preload("res://mod_registry.gd")
const CATALOGUE_URL := "https://raw.githubusercontent.com/Hendar23/OpenSC-Mods/main/catalogue.json"
const RELEASE_PREFIX := "https://github.com/Hendar23/OpenSC-Mods/releases/download/"
signal progress(message: String, fraction: float)
var entries: Array[Dictionary] = []
var last_error := ""
var fetching := false
var busy := false
var request_node: HTTPRequest
var download_name := ""

func _init() -> void: process_mode = Node.PROCESS_MODE_ALWAYS

func cache_path() -> String:
	return Storage.root_path().path_join("cache/official-mods/catalogue.json")

static func safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 80 or value in [".",".."]: return false
	for character in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789-_.": return false
	return not value.begins_with(".") and not value.ends_with(".")

static func compatible(minimum: String) -> bool:
	var current := str(ProjectSettings.get_setting("application/config/version","0.0.0")).split(".")
	var required := minimum.split(".")
	for index in range(3):
		var a := int(current[index]) if index < current.size() else 0
		var b := int(required[index]) if index < required.size() else 0
		if a != b: return a > b
	return true

static func newer(candidate: String, installed: String) -> bool:
	var a := candidate.trim_prefix("v").get_slice("+",0).split("-",true,1)
	var b := installed.trim_prefix("v").get_slice("+",0).split("-",true,1)
	var left := a[0].split("."); var right := b[0].split(".")
	for component in left + right:
		if not component.is_valid_int() or int(component) < 0: return false
	for index in range(maxi(left.size(),right.size())):
		var x := int(left[index]) if index < left.size() else 0
		var y := int(right[index]) if index < right.size() else 0
		if x != y: return x > y
	if a.size() != b.size(): return a.size() == 1
	if a.size() == 1: return false
	left = a[1].split("."); right = b[1].split(".")
	for index in range(mini(left.size(),right.size())):
		if left[index] == right[index]: continue
		if left[index].is_valid_int() and right[index].is_valid_int(): return int(left[index]) > int(right[index])
		if left[index].is_valid_int() != right[index].is_valid_int(): return not left[index].is_valid_int()
		return left[index] > right[index]
	return left.size() > right.size()

func update_for(pack: Dictionary) -> Dictionary:
	if not pack.get("valid",false): return {}
	for entry in entries:
		if entry.id == pack.id and newer(entry.version,pack.version): return entry
	return {}

func parse_catalogue(text: String) -> bool:
	var parser := JSON.new()
	if parser.parse(text) != OK: return false
	var data = parser.data
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("mods") is Array: return false
	var parsed: Array[Dictionary] = []
	var ids := {}
	for value in data.mods:
		if not value is Dictionary: return false
		for key in ["id","name","description","version","url","sha256","min_game_version"]:
			if not value.get(key) is String: return false
		if not safe_id(value.id) or ids.has(value.id) or value.name.is_empty() or value.version.is_empty(): return false
		if not value.url.begins_with(RELEASE_PREFIX) or "?" in value.url or "#" in value.url: return false
		if value.sha256.length() != 64: return false
		for character in value.sha256:
			if character not in "0123456789abcdef": return false
		for key in ["size","unpacked_size"]:
			if not (value.get(key) is float or value.get(key) is int) or value[key] <= 0 or value[key] > 2147483647 or value[key] != floor(value[key]): return false
		ids[value.id] = true
		parsed.append(value.duplicate(true))
	entries = parsed
	return true

func load_cached() -> void:
	if FileAccess.file_exists(cache_path()): parse_catalogue(FileAccess.get_file_as_string(cache_path()))

func refresh_catalogue() -> bool:
	if fetching or busy: return false
	fetching = true
	var response := await _request(CATALOGUE_URL,"",2097152)
	fetching = false
	if not response.get("ok",false) or not parse_catalogue(response.get("body",PackedByteArray()).get_string_from_utf8()):
		last_error = "Couldn’t refresh official mods."
		return false
	last_error = ""
	if Storage.ensure_parent(cache_path()) == OK:
		var file := FileAccess.open(cache_path(),FileAccess.WRITE)
		if file != null: file.store_buffer(response.body); file.close()
	return true

func _request(url: String, destination: String, limit: int) -> Dictionary:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	http.use_threads = true
	http.timeout = 30.0 if destination.is_empty() else 600.0
	http.body_size_limit = limit
	http.download_file = destination
	http.accept_gzip = destination.is_empty()
	add_child(http)
	if not destination.is_empty(): request_node = http
	var error := http.request(url)
	if error != OK:
		if request_node == http: request_node = null
		http.queue_free()
		return {"ok":false}
	var response: Array = await http.request_completed
	if request_node == http: request_node = null
	http.queue_free()
	return {"ok":response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200,"body":response[3]}

func _process(_delta: float) -> void:
	if is_instance_valid(request_node):
		progress.emit("Downloading " + download_name, float(request_node.get_downloaded_bytes()) / maxf(1.0,float(request_node.get_body_size())))

func missing(ids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		if entry.id not in ids: continue
		if Mods.packs.any(func(pack: Dictionary) -> bool: return pack.id == entry.id): continue
		result.append(entry)
	return result

static func safe_member(path: String, id: String) -> bool:
	if not path.begins_with(id + "/") or "\\" in path or ":" in path: return false
	for component in path.trim_suffix("/").split("/"):
		if component.is_empty() or component in [".",".."] or component.ends_with(".") or component.ends_with(" "): return false
		var stem := component.get_slice(".",0).to_upper()
		if stem in ["CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9","LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9"]: return false
	return true

func _checksum(path: String) -> String:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return ""
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		hash.update(file.get_buffer(4194304))
		await get_tree().process_frame
	file.close()
	return hash.finish().hex_encode()

func _extract(archive: String, stage: String, entry: Dictionary) -> String:
	var zip := ZIPReader.new()
	if zip.open(archive) != OK: return "Could not open the downloaded ZIP."
	var members := zip.get_files()
	var seen := {}; var total := 0
	for member in members:
		if not safe_member(member,entry.id) or seen.has(member.to_lower()):
			zip.close(); return "The downloaded ZIP contains an invalid path."
		seen[member.to_lower()] = true
	for member in members:
		var path := stage.path_join(member)
		if member.ends_with("/"): continue
		var bytes := zip.read_file(member)
		total += bytes.size()
		if total > int(entry.unpacked_size): zip.close(); return "The downloaded ZIP is larger than expected."
		if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: zip.close(); return "Could not create the mod folder."
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null: zip.close(); return "Could not write the mod files."
		file.store_buffer(bytes)
		var result := file.get_error(); file.close()
		if result != OK: zip.close(); return "Could not write the mod files."
		progress.emit("Installing " + str(entry.name),float(total) / maxf(1.0,float(entry.unpacked_size)))
		await get_tree().process_frame
	zip.close()
	if total != int(entry.unpacked_size): return "The downloaded ZIP is incomplete."
	var pack := Mods._read_pack(stage.path_join(entry.id))
	if pack.is_empty() or not pack.valid or not pack.errors.is_empty() or pack.id != entry.id or pack.version != entry.version: return "The downloaded mod does not match its catalogue entry."
	return ""

func install(ids: Array[String], updates: Array[String] = []) -> bool:
	if busy: return false
	busy = true; last_error = ""
	var needed := missing(ids)
	var update_targets := {}
	for pack in Mods.packs:
		if str(pack.id) not in updates: continue
		var entry := update_for(pack)
		if entry.is_empty(): continue
		needed.append(entry)
		update_targets[entry.id] = pack.folder
	var stages: Array[String] = []
	var changes: Array[Dictionary] = []
	var retained: Array[String] = []
	var token := str(Time.get_ticks_usec())
	for entry in needed:
		if not compatible(entry.min_game_version): last_error = entry.name + " requires OpenSC " + entry.min_game_version + "."; break
		var stage := Mods.root.path_join(".official-" + token + "-" + str(entry.id))
		stages.append(stage)
		if DirAccess.make_dir_recursive_absolute(stage) != OK: last_error = "Could not create the download folder."; break
		var archive := stage.path_join("download.zip")
		download_name = entry.name
		progress.emit("Downloading " + download_name,0.0)
		var response := await _request(entry.url,archive,int(entry.size))
		if not response.get("ok",false): last_error = "Could not download " + entry.name + "."; break
		var file := FileAccess.open(archive,FileAccess.READ)
		var size := file.get_length() if file != null else -1
		if file != null: file.close()
		progress.emit("Verifying " + download_name,0.0)
		if size != int(entry.size) or await _checksum(archive) != entry.sha256: last_error = "Download verification failed for " + entry.name + "."; break
		last_error = await _extract(archive,stage,entry)
		if not last_error.is_empty(): break
	if last_error.is_empty():
		for index in needed.size():
			var entry: Dictionary = needed[index]
			var source := stages[index].path_join(entry.id)
			var destination: String = update_targets.get(entry.id,Mods.root.path_join(entry.id))
			var backup := ""
			var added: Array[String] = []
			if update_targets.has(entry.id):
				if destination.get_base_dir() != Mods.root or not _plain_tree(destination): last_error = "Could not safely back up " + entry.name + "."; break
				var current := Mods._read_pack(destination)
				if current.is_empty() or current.id != entry.id or update_for(current) != entry: last_error = "The installed mod changed. Refresh mods and try again."; break
				backup = stages[index].path_join("backup")
				progress.emit("Backing up " + str(entry.name),0.0)
				last_error = await _publish(destination,backup)
				if not last_error.is_empty(): break
				for relative in _tree_files(source):
					if not FileAccess.file_exists(backup.path_join(relative)): added.append(relative)
			else:
				if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination): last_error = "The mod folder already exists: " + entry.name; break
			changes.append({"destination":destination,"backup":backup,"stage":stages[index],"added":added})
			progress.emit("Installing " + str(entry.name),0.0)
			last_error = await _publish(source,destination)
			if not last_error.is_empty(): break
	if not last_error.is_empty():
		changes.reverse()
		for change in changes:
			if change.backup.is_empty(): _remove_owned(change.destination); continue
			for relative in change.added: DirAccess.remove_absolute(change.destination.path_join(relative))
			var restored := await _publish(change.backup,change.destination)
			if not restored.is_empty():
				retained.append(change.stage)
				last_error += "\nPrevious version backup retained at " + change.backup
	for stage in stages:
		if stage not in retained: _remove_owned(stage)
	busy = false
	return last_error.is_empty()

func _publish(source: String, destination: String) -> String:
	# Existing destinations are fully backed up before this method writes them.
	# Publish the manifest last. Avoid directory renames on redirected Documents.
	var pending: Array[String] = [source]
	while not pending.is_empty():
		var folder: String = pending.pop_back()
		var directory := DirAccess.open(folder)
		if directory == null: return "Could not read the staged mod."
		directory.include_hidden = true
		for child in directory.get_directories(): pending.append(folder.path_join(child))
		for filename in directory.get_files():
			var path := folder.path_join(filename)
			if path == source.path_join("mod.json"): continue
			var target := destination.path_join(path.trim_prefix(source + "/"))
			if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK or DirAccess.copy_absolute(path,target) != OK: return "Could not finish installing the mod."
			await get_tree().process_frame
	if DirAccess.make_dir_recursive_absolute(destination) != OK: return "Could not create the mod folder."
	if DirAccess.copy_absolute(source.path_join("mod.json"),destination.path_join("mod.json")) != OK: return "Could not finish installing the mod."
	return ""

static func _plain_tree(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	if parent == null or parent.is_link(path.get_file()): return false
	var directory := DirAccess.open(path)
	if directory == null: return false
	directory.include_hidden = true
	for filename in directory.get_files():
		if directory.is_link(filename): return false
	for folder in directory.get_directories():
		if directory.is_link(folder) or not _plain_tree(path.path_join(folder)): return false
	return true

static func _tree_files(path: String, relative: String = "") -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(path.path_join(relative))
	if directory == null: return result
	directory.include_hidden = true
	for filename in directory.get_files(): result.append(relative.path_join(filename) if not relative.is_empty() else filename)
	for folder in directory.get_directories(): result.append_array(_tree_files(path,relative.path_join(folder)))
	return result

static func _remove_owned(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	directory.include_hidden = true
	for filename in directory.get_files(): directory.remove(filename)
	for folder in directory.get_directories(): _remove_owned(path.path_join(folder))
	DirAccess.remove_absolute(path)
