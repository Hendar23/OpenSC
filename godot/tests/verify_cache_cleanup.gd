extends "res://tests/test_scene_tree.gd"

const Cache = preload("res://asset_cache.gd")
const Storage = preload("res://player_storage.gd")
var checks := 0
var failures := 0
var fixture := ""

func _init() -> void: Cache.enabled = true
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func write(path: String, text: String) -> void:
	Storage.ensure_parent(path)
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_string(text); file.close()
func exists(id: String) -> bool: return FileAccess.file_exists(Cache.path_for(id, "bin"))
func entry(id: String) -> void: Cache.save_data(id, {"payload": "x".repeat(1024)})

func run() -> void:
	fixture = "res://tests/cache-cleanup-%d-fixtures" % OS.get_process_id()
	Storage.root_override = fixture
	Cache.reset_session()
	var active := Cache.key("active", [])
	var recent := Cache.key("recent", [])
	var old := Cache.key("old", [])
	var obsolete := Cache.key("obsolete", [])
	for id in [active, recent, old, obsolete]: entry(id)
	var folder := Cache._folder()
	Cache._used.clear()
	Cache._index[old].used = Time.get_unix_time_from_system() - Cache.UNUSED_LIFETIME - 100
	Cache._index[obsolete].code = "previous converter"
	check(not Cache.load_data(active).is_empty(), "Active cache entry loads")
	var unknown := "a".repeat(64)
	write(folder.path_join(unknown + ".res"), "old unmanaged conversion")
	write(folder.path_join(unknown + ".res.sha256"), "old checksum")
	write(folder.path_join("keep.txt"), "unrelated content")
	write(folder.path_join("nested/" + unknown + ".res"), "never recurse")
	write(Storage.saves_path().path_join("save.dat"), "save")
	write(Storage.preferences_path(), "preferences")
	write(Storage.mods_path().path_join("mod.json"), "authored mod")
	var frames := [0]
	var updates: Array[String] = []
	var tick := func() -> void: frames[0] += 1
	process_frame.connect(tick)
	var report := await Cache.maintain(self, func(message: String) -> void: updates.append(message))
	process_frame.disconnect(tick)
	check(frames[0] > 0, "Maintenance yields to the loading screen")
	check(report.entries_removed == 3 and report.bytes_removed > 0, "Old, obsolete and unmanaged generated entries removed")
	check(exists(active) and exists(recent), "Active and recent entries retained")
	check(not exists(old) and not exists(obsolete), "Expired and changed-converter entries removed")
	check(not FileAccess.file_exists(folder.path_join(unknown + ".res.sha256")), "Checksums removed with resources")
	check(FileAccess.get_file_as_string(folder.path_join("keep.txt")) == "unrelated content", "Unrecognised files preserved")
	check(FileAccess.file_exists(folder.path_join("nested/" + unknown + ".res")), "Nested folders not traversed")
	check(FileAccess.get_file_as_string(Storage.saves_path().path_join("save.dat")) == "save" and FileAccess.get_file_as_string(Storage.preferences_path()) == "preferences" and FileAccess.get_file_as_string(Storage.mods_path().path_join("mod.json")) == "authored mod", "Saves, preferences and mods untouched")
	check(not updates.is_empty() and updates[0] == "Cleaning asset cache", "Maintenance reports progress")
	# Model a separate launch: discard in-memory tracking and reload the ledger.
	Cache._index_root = ""; Cache.reset_session()
	Cache._ensure_index()
	check(Cache._index.has(active) and Cache._index.has(recent) and not Cache._index.has(old), "Usage survives process/session state")
	Cache._index[recent].used = Time.get_unix_time_from_system() - 100
	check(not Cache.load_data(active).is_empty(), "Warm entry still reads without conversion")
	var writes := Cache.writes
	report = await Cache.maintain(self, Callable(), 1)
	check(exists(active) and not exists(recent), "Disk budget removes least-recently-used inactive entry")
	check(report.bytes_remaining > 1 and Cache.writes == writes, "Live working set is protected even above budget; no reconversion")
	write(folder.path_join(".usage.json"), "interrupted metadata")
	Cache._index_root = ""; Cache._ensure_index()
	check(Cache._index.is_empty() and not Cache.load_data(active).is_empty(), "Corrupt usage metadata is ignored without losing usable conversions")
	Cache.enabled = false
	report = await Cache.maintain(self, Callable(), 0)
	check(exists(active) and report.entries_removed == 0, "Disabled cache remains untouched")
	Cache.enabled = true
	_remove(fixture)
	print("Cache cleanup: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _remove(path: String) -> void:
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path): _remove(path.path_join(name))
	DirAccess.remove_absolute(path)
