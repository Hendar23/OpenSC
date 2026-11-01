extends SceneTree

const Mods = preload("res://mod_registry.gd")
const Storage = preload("res://player_storage.gd")
var base := "res://tests/mod-location-fixture-" + str(OS.get_process_id())
var checks := 0
var failures := 0
var files: Array[String] = []
var directories: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func pack(folder: String, id: String, version: String) -> String:
	DirAccess.make_dir_recursive_absolute(folder)
	directories.append(folder)
	var path := folder.path_join("mod.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"id":id,"name":id,"version":version,"assets":{}}))
	file.close()
	files.append(path)
	return path

func run() -> void:
	Storage.root_override = base.path_join("player")
	var installed := base.path_join("installed")
	var preferences := Storage.preferences_path()
	check(Storage.mods_path() == base.path_join("player/Mods"), "Mods share the redirected player directory")
	Mods.initialize(false)
	check(Mods.root == ProjectSettings.globalize_path(Storage.mods_path()), "Default discovery uses the player Mods directory")
	check(DirAccess.dir_exists_absolute(Mods.root), "Default discovery creates the player Mods directory")
	var original := pack(installed.path_join("old-name"), "shared", "1.0")
	var original_bytes := FileAccess.get_file_as_bytes(original)
	pack(installed.path_join("bundled-only"), "bundled", "1.0")
	var override_file := pack(Storage.mods_path().path_join("different-name"), "shared", "2.0")
	pack(Storage.mods_path().path_join("personal"), "personal", "1.0")
	var config := ConfigFile.new()
	config.set_value("mods","enabled",["shared","bundled"])
	config.set_value("mods","order",["bundled","shared"])
	config.set_value("video","ffmpeg","preserved")
	config.save(preferences); files.append(preferences)
	Mods.initialize(true, Storage.mods_path(), preferences)
	check(Mods.packs.size() == 2, "Only player-folder mods are discovered")
	check(Mods.packs.filter(func(p: Dictionary) -> bool: return p.id == "shared")[0].version == "2.0", "Player-folder version is loaded")
	check(Mods.active_ids() == ["shared"], "Enabled IDs persist while absent installation mods stay inactive")
	check(Mods.packs.all(func(p: Dictionary) -> bool: return p.valid), "Cross-location overrides are not duplicate-ID errors")
	check(Mods.apply(Mods.enabled,Mods.order,true) == OK, "Saving mod choices works from the new location")
	config.load(preferences)
	check(config.get_value("video","ffmpeg") == "preserved", "Mod choices preserve other preferences")
	DirAccess.remove_absolute(override_file)
	Mods.refresh()
	check(Mods.packs.all(func(p: Dictionary) -> bool: return p.id != "shared"), "Removing a player mod never loads the installation copy")
	check(FileAccess.get_file_as_bytes(original) == original_bytes, "Discovery and refresh never alter bundled files")
	pack(Storage.mods_path().path_join("duplicate"), "personal", "3.0")
	Mods.refresh()
	check(Mods.packs.filter(func(p: Dictionary) -> bool: return p.id == "personal").all(func(p: Dictionary) -> bool: return not p.valid), "Duplicates within one location remain invalid")
	Mods.initialize(false, installed, preferences)
	check(Mods.packs.size() == 2, "Explicit fixture roots stay isolated")
	var opened: Array[String] = []
	check(Storage.open_player_folder(func(path: String) -> Error: opened.append(path); return OK) == OK and opened == [ProjectSettings.globalize_path(Storage.root_path())], "Open Player Folder opens the parent of Mods")
	for path in files:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	directories.reverse()
	for folder in directories: DirAccess.remove_absolute(folder)
	for folder in [Storage.mods_path(),Storage.screenshots_path(),Storage.root_path(),installed,base]: DirAccess.remove_absolute(folder)
	Storage.root_override = ""
	print("Mod locations: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
