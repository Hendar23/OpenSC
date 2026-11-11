extends RefCounted
## Disposable conversions only. Saves, settings and live world state never go here.
const VERSION := 2
static var enabled := true
static var hits := 0
static var misses := 0
static var writes := 0
static var _files := {}
static var _directories := {}
static var _code := {}
static var _unwritable := {}
static var resident_enabled := false
static var resident_hits := 0
static var generation := 0
static var _resident := {}
const RESIDENT_LIMIT := 1536
const DISK_BUDGET := 4 * 1024 * 1024 * 1024
const UNUSED_LIFETIME := 14 * 24 * 60 * 60
static var _index_root := ""
static var _index := {}
static var _identities := {}
static var _used := {}
static var _maintaining := false

static func reset_session() -> void:
	_files.clear(); _directories.clear(); _code.clear()
	_resident.clear(); resident_hits = 0; generation += 1
	_identities.clear(); _used.clear(); _unwritable.clear()
	hits = 0; misses = 0; writes = 0

static func fingerprint(path: String) -> String:
	# Hash once per session; a new launch or mod refresh checks the bytes again.
	# Keep res:// virtual in exports: globalizing it would bypass the PCK.
	var absolute := path.simplify_path() if path.begins_with("res://") else ProjectSettings.globalize_path(path).simplify_path()
	if not _files.has(absolute):
		_files[absolute] = FileAccess.get_sha256(absolute) if FileAccess.file_exists(absolute) else "missing"
	return str(_files[absolute])

static func directory_signature(path: String) -> String:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if not _directories.has(absolute):
		var records: Array[String] = []
		_directory_records(absolute, records)
		_directories[absolute] = JSON.stringify(records).sha256_text()
	return str(_directories[absolute])

static func _directory_records(path: String, records: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(path):
		records.append(path + ":missing"); return
	var files := DirAccess.get_files_at(path); files.sort()
	for name in files:
		if name.begins_with(".") or name.ends_with(".import"): continue
		records.append(path.path_join(name) + ":" + fingerprint(path.path_join(name)))
	var folders := DirAccess.get_directories_at(path); folders.sort()
	for name in folders:
		if not name.begins_with("."): _directory_records(path.path_join(name), records)

# Converter dependencies are explicit: UI/mission edits and release versions do
# not invalidate decoded assets. Hash source/compiled code to retain correctness
# in both source checkouts and exports.
const CONVERTERS := {
	"image": ["res://legacy_bmp.gd"],
	"texture": ["res://clump_loader.gd", "res://legacy_bmp.gd", "res://mod_registry.gd"],
	"clump": ["res://clump_loader.gd", "res://legacy_bmp.gd", "res://mod_registry.gd"],
	"world": ["res://world_loader.gd", "res://clump_loader.gd", "res://legacy_bmp.gd", "res://mod_registry.gd"],
	"modern-model": ["res://modern_model.gd", "res://legacy_bmp.gd", "res://mod_registry.gd"],
	"catalogue": ["res://original_game_data.gd", "res://scenery_loader.gd", "res://mailbox.gd", "res://submarine_weapons.gd"],
	"scenery-database": ["res://scenery_loader.gd"],
	"world-light": ["res://natural_light.gd", "res://world_cache.gd"],
	"world-map": ["res://hud_map.gd", "res://world_cache.gd"],
	"world-navigation": ["res://submarine_traffic.gd", "res://world_cache.gd"],
}
static func code_signature(kind: String = "") -> String:
	if not _code.has(kind):
		var records: Array = [VERSION, Engine.get_version_info().get("hex")]
		for path in ["res://asset_cache.gd"] + CONVERTERS.get(kind, []):
			records.append([path, fingerprint(path)])
			var remap := ConfigFile.new()
			if FileAccess.file_exists(path + ".remap") and remap.load(path + ".remap") == OK:
				records.append(fingerprint(str(remap.get_value("remap", "path", ""))))
		_code[kind] = var_to_bytes(records).hex_encode().sha256_text()
	return _code[kind]

static func key(kind: String, paths: Array, options: Variant = null) -> String:
	var records: Array = [VERSION, code_signature(kind), kind, options]
	for path in paths: records.append([ProjectSettings.globalize_path(str(path)).simplify_path(), fingerprint(str(path))])
	var result := JSON.stringify(records).sha256_text()
	if enabled:
		_ensure_index()
		_identities[result] = {"kind": kind, "code": code_signature(kind)}
	return result

static func _folder() -> String:
	return ProjectSettings.globalize_path(preload("res://player_storage.gd").root_path().path_join("cache/assets")).simplify_path()

static func _ensure_index() -> void:
	var folder := _folder()
	if _index_root == folder: return
	_index_root = folder; _index.clear(); _identities.clear(); _used.clear()
	var path := folder.path_join(".usage.json")
	if FileAccess.file_exists(path):
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data is Dictionary: _index = parser.data

static func _touch(path: String) -> void:
	if not enabled: return
	_ensure_index()
	var id := path.get_file().get_basename()
	var record: Variant = _identities.get(id, _index.get(id, {}))
	if not record is Dictionary: record = {}
	record = record.duplicate()
	if not record.has("kind"):
		record = {"kind": "fmv" if path.get_extension() == "ogv" else "external", "code": "1" if path.get_extension() == "ogv" else code_signature("external")}
	record.used = Time.get_unix_time_from_system()
	_index[id] = record; _used[id] = true

static func path_for(key_value: String, extension: String) -> String:
	return preload("res://player_storage.gd").root_path().path_join("cache/assets").path_join(key_value + "." + extension)

static func _valid(path: String) -> bool:
	if not enabled: return false
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(path + ".sha256"): return false
	var valid := FileAccess.get_file_as_string(path + ".sha256") == FileAccess.get_sha256(path)
	if valid: _touch(path)
	return valid

static func load_resource(key_value: String) -> Resource:
	var path := path_for(key_value, "res")
	if resident_enabled and _resident.has(path):
		_touch(path); resident_hits += 1; return _resident[path]
	if _valid(path):
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource != null:
			_remember(path,resource); hits += 1; return resource
	misses += 1; return null

static func _remember(path: String, resource: Resource) -> void:
	# Mutable decoded Images must not be shared: texture conversion edits alpha.
	# Packed scenes create independent nodes while sharing immutable GPU assets.
	if not resident_enabled or not (resource is PackedScene or resource is Texture2D): return
	if not _resident.has(path) and _resident.size() >= RESIDENT_LIMIT: _resident.erase(_resident.keys()[0])
	_resident[path] = resource

static func _finish(temp: String, path: String) -> void:
	if DirAccess.rename_absolute(temp, path) != OK: return
	var checksum := FileAccess.open(path + ".sha256", FileAccess.WRITE)
	if checksum != null:
		checksum.store_string(FileAccess.get_sha256(path)); checksum.close(); writes += 1
		_touch(path)

static func _prepare_write(path: String) -> bool:
	var folder := path.get_base_dir()
	if _unwritable.has(folder): return false
	if preload("res://player_storage.gd").ensure_parent(path) != OK:
		_unwritable[folder] = true; return false
	return true

static func save_resource(key_value: String, resource: Resource) -> void:
	_remember(path_for(key_value,"res"),resource)
	if not enabled: return
	var path := path_for(key_value, "res")
	if not _prepare_write(path): return
	var temp := path.get_basename() + ".tmp.res"
	# Cached resources may have paths from earlier loads. Serialize them as local
	# subresources, so each entry is self-contained, then restore their live paths.
	var paths := {}
	_clear_paths(resource, paths)
	var result := ResourceSaver.save(resource, temp, ResourceSaver.FLAG_COMPRESS)
	for entry in paths: entry.resource_path = paths[entry]
	if result == OK: _finish(temp, path)
	else: _unwritable[path.get_base_dir()] = true

static func _clear_paths(value: Variant, paths: Dictionary) -> void:
	if value is Resource:
		if value is Script or paths.has(value): return
		paths[value] = value.resource_path
		value.resource_path = ""
		for property in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE: _clear_paths(value.get(property.name), paths)
	elif value is Array:
		for entry in value: _clear_paths(entry, paths)
	elif value is Dictionary:
		for entry in value.values(): _clear_paths(entry, paths)

static func load_scene(key_value: String) -> Node3D:
	var packed := load_resource(key_value) as PackedScene
	return packed.instantiate() as Node3D if packed != null else null

static func save_scene(key_value: String, root: Node3D) -> void:
	if not enabled and not resident_enabled: return
	# Pack every converted node, while leaving the caller's ownership unchanged.
	var owners := {}
	for child in root.find_children("*", "", true, false):
		owners[child] = child.owner; child.owner = root
	var packed := PackedScene.new()
	var result := packed.pack(root)
	for child in owners: child.owner = owners[child]
	if result == OK: save_resource(key_value, packed)

static func load_data(key_value: String) -> Dictionary:
	var path := path_for(key_value, "bin")
	if _valid(path):
		var data: Variant = bytes_to_var(FileAccess.get_file_as_bytes(path))
		if data is Dictionary: hits += 1; return data
	misses += 1; return {}

static func save_data(key_value: String, data: Dictionary) -> void:
	if not enabled: return
	var path := path_for(key_value, "bin")
	if not _prepare_write(path): return
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file != null:
		file.store_buffer(var_to_bytes(data)); file.flush()
		var result := file.get_error(); file.close()
		if result == OK: _finish(temp, path)
	else: _unwritable[path.get_base_dir()] = true

static func _safe_cleanup_folder(folder: String) -> bool:
	var root := ProjectSettings.globalize_path(preload("res://player_storage.gd").root_path()).simplify_path().trim_suffix("/")
	if folder != root.path_join("cache/assets"): return false
	for component in [root, root.path_join("cache"), folder]:
		var parent := DirAccess.open(str(component).get_base_dir())
		if parent != null and parent.is_link(str(component).get_file()): return false
	return true

static func _remove_cached_files(directory: DirAccess, files: Array) -> int:
	var removed := 0
	for entry in files:
		# Only names matched by the strict generated-cache pattern reach here.
		# Recheck links immediately before removal, and never recurse.
		if not directory.is_link(str(entry.name)) and directory.remove(str(entry.name)) == OK:
			removed += int(entry.bytes)
	return removed

static func maintain(tree: SceneTree, progress: Callable = Callable(), disk_budget: int = DISK_BUDGET, unused_lifetime: int = UNUSED_LIFETIME) -> Dictionary:
	var report := {"bytes_removed": 0, "entries_removed": 0, "bytes_remaining": 0}
	if not enabled or _maintaining: return report
	_ensure_index()
	var folder := _folder()
	if not _safe_cleanup_folder(folder): return report
	var directory := DirAccess.open(folder)
	if directory == null: return report
	if directory.is_link(".usage.json") or directory.is_link(".usage.tmp.json"): return report
	_maintaining = true
	if progress.is_valid(): progress.call("Cleaning asset cache")
	await tree.process_frame
	var pattern := RegEx.new(); pattern.compile("^([0-9a-f]{64})\\.(res|bin|ogv)(\\.sha256)?$")
	var temporary := RegEx.new(); temporary.compile("^[0-9a-f]{64}\\.tmp\\.(res|bin|ogv)$")
	var groups := {}
	var now := Time.get_unix_time_from_system()
	var slice := Time.get_ticks_usec()
	var scanned := 0
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if not directory.current_is_dir() and not directory.is_link(name):
			var match := pattern.search(name)
			var path := folder.path_join(name)
			var file := FileAccess.open(path, FileAccess.READ) if match != null or temporary.search(name) != null else null
			if file != null:
				var bytes := file.get_length(); file.close()
				if match != null:
					var id := match.get_string(1)
					if not groups.has(id): groups[id] = {"id": id, "files": [], "bytes": 0, "used": 0.0, "obsolete": true}
					groups[id].files.append({"name": name, "bytes": bytes})
					groups[id].bytes += bytes
				elif now - FileAccess.get_modified_time(path) > 3600:
					report.bytes_removed += _remove_cached_files(directory, [{"name": name, "bytes": bytes}])
				scanned += 1
		if Time.get_ticks_usec() - slice > 4000:
			if progress.is_valid(): progress.call("Cleaning asset cache: checked %d files" % scanned)
			await tree.process_frame
			if _folder() != folder: directory.list_dir_end(); _maintaining = false; return report
			slice = Time.get_ticks_usec()
		name = directory.get_next()
	directory.list_dir_end()
	var candidates: Array = groups.values()
	for entry in candidates:
		var record: Variant = _index.get(entry.id)
		if record is Dictionary and record.get("kind") is String and record.get("code") is String and (record.get("used") is float or record.get("used") is int):
			entry.used = minf(now, maxf(0.0, float(record.used)))
			entry.obsolete = record.code != ("1" if record.kind == "fmv" else code_signature(str(record.kind)))
		report.bytes_remaining += int(entry.bytes)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.used) < float(b.used))
	for entry in candidates:
		# Keep everything used by this load, even if a legitimate working set is
		# larger than the budget. Cleanup never disables caching or drops visuals.
		if not _used.has(entry.id) and (entry.obsolete or now - float(entry.used) > unused_lifetime or int(report.bytes_remaining) > disk_budget):
			var removed := _remove_cached_files(directory, entry.files)
			report.bytes_removed += removed; report.bytes_remaining -= removed
			if removed == int(entry.bytes):
				_index.erase(entry.id); groups.erase(entry.id); report.entries_removed += 1
		if Time.get_ticks_usec() - slice > 4000:
			if progress.is_valid(): progress.call("Cleaning asset cache: removed %d old entries" % int(report.entries_removed))
			await tree.process_frame
			if _folder() != folder: _maintaining = false; return report
			slice = Time.get_ticks_usec()
	for id in _index.keys():
		if not groups.has(id): _index.erase(id)
	var output := FileAccess.open(folder.path_join(".usage.tmp.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(_index)); output.close()
		DirAccess.rename_absolute(folder.path_join(".usage.tmp.json"), folder.path_join(".usage.json"))
	_maintaining = false
	return report
