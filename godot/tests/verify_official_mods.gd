extends SceneTree
const Official = preload("res://official_mods.gd")
const Mods = preload("res://mod_registry.gd")
const Storage = preload("res://player_storage.gd")
var checks := 0
var failures := 0
var base := "res://tests/official-fixture-" + str(OS.get_process_id())

class Transport extends "res://official_mods.gd":
	var catalogue := ""
	var archives := {}
	var fail := false
	var reject_publish := ""
	var reject_once := false
	var requests: Array[String] = []
	func _request(url: String, destination: String, _limit: int) -> Dictionary:
		requests.append(url)
		await get_tree().process_frame
		if fail: return {"ok":false}
		if destination.is_empty(): return {"ok":true,"body":catalogue.to_utf8_buffer()}
		if not archives.has(url): return {"ok":false}
		var file := FileAccess.open(destination,FileAccess.WRITE)
		file.store_buffer(FileAccess.get_file_as_bytes(archives[url])); file.close()
		return {"ok":true}
	func _publish(source: String, destination: String) -> String:
		if destination.get_file() == reject_publish:
			if reject_once: reject_publish = ""
			DirAccess.make_dir_recursive_absolute(destination)
			var file := FileAccess.open(destination.path_join("payload.txt"),FileAccess.WRITE)
			file.store_string("partial"); file.close()
			return "Simulated disk failure."
		return await super._publish(source,destination)

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_string(text); file.close()

func entry(id: String, malicious: bool = false, version: String = "1.0.0") -> Dictionary:
	var path := base.path_join(id + "-" + version + ("-bad" if malicious else "") + ".zip")
	var manifest := JSON.stringify({"schema_version":1,"id":id,"name":id,"version":version,"assets":{}})
	var payload := "mod data" if version == "1.0.0" else "mod data " + version
	var zip := ZIPPacker.new(); zip.open(path)
	zip.start_file(id + "/mod.json"); zip.write_file(manifest.to_utf8_buffer()); zip.close_file()
	zip.start_file(id + ("/../escaped.txt" if malicious else "/payload.txt")); zip.write_file(payload.to_utf8_buffer()); zip.close_file(); zip.close()
	return {"id":id,"name":id,"description":"Fixture mod.","version":version,"min_game_version":"0.8.2","url":Official.RELEASE_PREFIX + id + "/" + path.get_file(),"size":FileAccess.get_file_as_bytes(path).size(),"unpacked_size":manifest.to_utf8_buffer().size() + payload.length(),"sha256":FileAccess.get_sha256(path),"fixture":path}

func update_button(panel: Window, id: String) -> Button:
	for button in panel.find_children("*","Button",true,false):
		if str(button.get_meta("mod_id","")) == id and button.text in ["Update","Update queued"]: return button
	return null

func run() -> void:
	root.gui_embed_subwindows = true
	Storage.root_override = base.path_join("player")
	DirAccess.make_dir_recursive_absolute(Storage.mods_path())
	write(Storage.mods_path().path_join("local/mod.json"),JSON.stringify({"schema_version":1,"id":"local","name":"Manual mod","version":"9.0.0","assets":{}}))
	var config := ConfigFile.new()
	config.set_value("mods","enabled",["local","deleted"])
	config.set_value("mods","order",["local","deleted"])
	config.set_value("video","ffmpeg","untouched")
	config.save(Storage.preferences_path())
	Mods.initialize(true,Storage.mods_path(),Storage.preferences_path())
	var alpha := entry("alpha"); var beta := entry("beta")
	var service := Transport.new()
	service.catalogue = JSON.stringify({"schema_version":1,"mods":[alpha,beta]})
	service.archives[alpha.url] = alpha.fixture; service.archives[beta.url] = beta.fixture
	var panel := preload("res://mod_panel.gd").new(); panel.official = service
	root.add_child(panel)
	check(await service.refresh_catalogue(),"Downloads and validates the catalogue")
	check(FileAccess.file_exists(service.cache_path()),"Stores a catalogue for offline browsing")
	var cached := Official.new(); cached.load_cached()
	check(cached.entries.size() == 2,"Cached catalogue restores available mods")
	cached.free()
	check(not service.parse_catalogue('{"schema_version":99,"mods":[]}') and service.entries.size() == 2,"Bad catalogue never replaces the working list")
	check(not service.parse_catalogue('{incomplete') and service.entries.size() == 2,"Malformed JSON preserves the catalogue without a script error")
	var bad := alpha.duplicate(); bad.id = "../escape"
	check(not service.parse_catalogue(JSON.stringify({"schema_version":1,"mods":[bad]})),"Rejects unsafe catalogue IDs")
	bad = alpha.duplicate(); bad.url = "https://example.com/mod.zip"
	check(not service.parse_catalogue(JSON.stringify({"schema_version":1,"mods":[bad]})),"Only official release downloads are accepted")
	service.fail = true
	check(not await service.refresh_catalogue() and service.entries.size() == 2,"Offline refresh preserves cached entries")
	service.fail = false
	var original := FileAccess.get_file_as_bytes(Storage.preferences_path())
	paused = true; panel.open()
	await process_frame; await process_frame; await process_frame
	check(panel.choices.size() == 3 and not panel.choices.has("deleted"),"Menu merges catalogue with manual mods and has no deleted placeholders")
	check("Installed" in panel.choices.local.text and "Not installed" in panel.choices.alpha.text,"Rows distinguish installed and downloadable packs")
	check(panel.choices.local.button_pressed and not panel.choices.alpha.button_pressed,"Catalogue refresh never changes selections")
	check(FileAccess.get_file_as_bytes(Storage.preferences_path()) == original,"Opening and refreshing do not write preferences")
	panel.choices.alpha.button_pressed = true
	check(not DirAccess.dir_exists_absolute(Mods.root.path_join("alpha")),"Checking an absent mod does not start installation")
	var transitions: Array = []
	panel.download_started.connect(func() -> void: transitions.append("started"))
	panel.download_finished.connect(func(ok: bool) -> void: transitions.append(ok))
	var applied: Array = []
	panel.applied.connect(func() -> void: applied.append(true))
	await panel._commit_apply()
	check(transitions == ["started",true] and applied.size() == 1 and not panel.visible,"Apply downloads directly with loading signals and no confirmation")
	check(FileAccess.get_file_as_string(Mods.root.path_join("alpha/payload.txt")) == "mod data","Installs the verified archive into player Mods")
	check(Mods.active_ids() == ["local","alpha"],"Applies choices only after installation succeeds")
	config.load(Storage.preferences_path())
	check(config.get_value("video","ffmpeg") == "untouched","Applying preserves unrelated preferences")
	var count := service.requests.size()
	await service.install(panel.pending_enabled)
	check(service.requests.size() == count,"Already installed mods are never downloaded or updated")
	panel.open(); await process_frame; await process_frame; await process_frame
	check(panel.choices.size() == 3 and "Not installed" not in panel.choices.alpha.text,"Installed official mod appears once, as installed")
	original = FileAccess.get_file_as_bytes(Storage.preferences_path())
	panel.choices.beta.button_pressed = true; service.fail = true
	await panel._commit_apply()
	check(panel.visible and not panel.applying and transitions[-1] == false,"Download failure returns to the Mods menu")
	check(FileAccess.get_file_as_bytes(Storage.preferences_path()) == original and "beta" not in Mods.enabled,"Download failure preserves saved selections")
	check(not DirAccess.dir_exists_absolute(Mods.root.path_join("beta")),"Failed downloads do not leave partially installed mods")
	service.fail = false
	bad = beta.duplicate(); bad.sha256 = "0".repeat(64); service.entries = [bad]
	check(not await service.install(["beta"]) and not DirAccess.dir_exists_absolute(Mods.root.path_join("beta")),"Checksum mismatch rejects the download")
	var traversal := entry("beta",true); service.entries = [traversal]; service.archives[traversal.url] = traversal.fixture
	check(not await service.install(["beta"]) and not FileAccess.file_exists(Mods.root.path_join("escaped.txt")),"Rejects ZIP traversal without writing outside staging")
	var gamma := entry("gamma"); var delta := entry("delta")
	service.entries = [gamma,delta]; service.archives[gamma.url] = gamma.fixture
	check(not await service.install(["gamma","delta"]) and not DirAccess.dir_exists_absolute(Mods.root.path_join("gamma")),"Later failure discards an earlier staged download")
	service.archives[delta.url] = delta.fixture; service.reject_publish = "delta"
	check(not await service.install(["gamma","delta"]) and not DirAccess.dir_exists_absolute(Mods.root.path_join("gamma")) and not DirAccess.dir_exists_absolute(Mods.root.path_join("delta")),"Disk failure rolls back both new installations")
	service.entries = [beta]; service.reject_publish = ""
	write(Mods.root.path_join("beta/keep.txt"),"existing user data")
	check(not await service.install(["beta"]) and FileAccess.get_file_as_string(Mods.root.path_join("beta/keep.txt")) == "existing user data","An existing destination folder is never overwritten or removed")
	Official._remove_owned(Mods.root.path_join("beta"))
	check(DirAccess.get_directories_at(Mods.root).size() == 2,"Temporary download folders are cleaned")
	check(FileAccess.get_file_as_string(Mods.root.path_join("local/mod.json")).contains("9.0.0"),"Manual local mods remain untouched")
	for versions in [["1.10","1.9",true],["1.0","1.0.0",false],["1.0.1","1.0",true],["0.9","1.0",false],["1.0.0","1.0.0-rc.1",true],["1.0.0-rc.2","1.0.0",false],["1.0.0-rc.10","1.0.0-rc.2",true],["1.0.0+build2","1.0.0+build1",false],["invalid","1.0",false]]:
		check(Official.newer(versions[0],versions[1]) == versions[2],"Correct update ordering: " + versions[0] + " versus " + versions[1])
	var upgrade := entry("alpha",false,"1.1.0")
	service.entries = [upgrade,beta]; service.catalogue = JSON.stringify({"schema_version":1,"mods":service.entries})
	service.archives[upgrade.url] = upgrade.fixture
	Mods.apply(["local"],["local","alpha"],true)
	write(Mods.root.path_join("alpha/user-custom.txt"),"keep this file")
	panel.open(); await process_frame; await process_frame; await process_frame
	check("Update available: 1.1.0" in panel.choices.alpha.text and update_button(panel,"alpha") == null,"Shows the newer-version status without a separate Update button")
	check(not panel.choices.alpha.button_pressed,"An available update never enables a disabled mod")
	count = service.requests.size()
	await panel._commit_apply()
	check(service.requests.size() == count and Mods._read_pack(Mods.root.path_join("alpha")).version == "1.0.0","Apply leaves unchecked installed mods on their current version")
	panel.open(); await process_frame; await process_frame; await process_frame
	panel.choices.alpha.button_pressed = true
	check(panel.pending_enabled == ["local","alpha"],"Checking the mod records only the player’s explicit selection")
	check(Mods._read_pack(Mods.root.path_join("alpha")).version == "1.0.0","Checking an outdated mod leaves files untouched until Apply")
	await panel._commit_apply()
	check(Mods._read_pack(Mods.root.path_join("alpha")).version == "1.1.0" and FileAccess.get_file_as_string(Mods.root.path_join("alpha/payload.txt")) == "mod data 1.1.0","Apply replaces the installed version with the verified update")
	check(Mods.enabled == ["local","alpha"] and FileAccess.get_file_as_string(Mods.root.path_join("alpha/user-custom.txt")) == "keep this file","Update applies the chosen enabled state and preserves unrelated local files")
	var next_version := entry("alpha",false,"2.0.0")
	service.entries = [next_version,beta]; service.catalogue = JSON.stringify({"schema_version":1,"mods":service.entries})
	service.archives[next_version.url] = next_version.fixture
	original = FileAccess.get_file_as_bytes(Storage.preferences_path())
	var before_manifest := FileAccess.get_file_as_bytes(Mods.root.path_join("alpha/mod.json"))
	var before_payload := FileAccess.get_file_as_bytes(Mods.root.path_join("alpha/payload.txt"))
	service.fail = true; panel.open(); await process_frame; await process_frame; await process_frame
	check(panel.info.text.contains("Couldn’t refresh official mods.") and "Update available" in panel.choices.alpha.text,"Offline refresh shows an error and keeps cached update information")
	await panel._commit_apply()
	check(panel.visible and not panel.applying and FileAccess.get_file_as_bytes(Storage.preferences_path()) == original,"Offline update returns to menu with saved selections unchanged")
	check(FileAccess.get_file_as_bytes(Mods.root.path_join("alpha/mod.json")) == before_manifest and FileAccess.get_file_as_bytes(Mods.root.path_join("alpha/payload.txt")) == before_payload,"Offline update leaves the installed version intact")
	service.fail = false; service.reject_publish = "alpha"; service.reject_once = true
	check(not await service.install([], ["alpha"]),"A disk failure during update is reported")
	check(FileAccess.get_file_as_bytes(Mods.root.path_join("alpha/mod.json")) == before_manifest and FileAccess.get_file_as_bytes(Mods.root.path_join("alpha/payload.txt")) == before_payload,"Failed update restores the previous manifest and overwritten files")
	check(FileAccess.get_file_as_string(Mods.root.path_join("alpha/user-custom.txt")) == "keep this file","Rollback preserves unrelated files")
	next_version.min_game_version = "99.0.0"
	service.entries = [next_version]; service.catalogue = JSON.stringify({"schema_version":1,"mods":service.entries})
	panel.open(); await process_frame; await process_frame; await process_frame
	check("Update requires OpenSC 99.0.0" in panel.choices.alpha.text and not panel.choices.alpha.disabled,"An incompatible update leaves the installed mod usable")
	count = service.requests.size()
	await panel._commit_apply()
	check(service.requests.size() == count and Mods._read_pack(Mods.root.path_join("alpha")).version == "1.1.0","Apply never replaces a working mod with an incompatible update")
	paused = false; panel.free()
	Official._remove_owned(ProjectSettings.globalize_path(base))
	Storage.root_override = ""
	print("Official mods: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
