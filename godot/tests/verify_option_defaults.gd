extends "res://tests/test_scene_tree.gd"
const Defaults = preload("res://option_defaults.gd")
class Graphics extends "res://player_graphics.gd":
	func desktop_size() -> Vector2i: return Vector2i(1920,1080)
	func apply_display() -> void: pass
	func apply_rendering() -> void: pass
class ReleaseReset extends "res://game.gd":
	func _bootstrap() -> void: pass
	func _can_restore_defaults() -> bool: return true
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-option-defaults-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var path: String = storage.root_override.path_join("fresh.cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var authored := ConfigFile.new()
	check(authored.load(Defaults.PATH) == OK,"Release option defaults exist")
	check(not authored.has_section_key("graphics","resolution"),"Desktop resolution is chosen on first launch")
	check(Array(authored.get_sections()).all(func(section: String) -> bool: return section in Defaults.SECTIONS),"Only public option sections are shipped")
	var fallback := Defaults.load_preferences(path)
	check(fallback.encode_to_text() == authored.encode_to_text(),"Missing player preferences use captured release defaults")
	var gameplay := preload("res://gameplay_menu.gd").new(); gameplay.settings_path = path; root.add_child(gameplay)
	check(gameplay.disable_random_pirates == bool(authored.get_value("gameplay","disable_random_pirates")),"Fresh General menu uses captured random-pirate choice")
	check(gameplay.zapper_auto_aim == bool(authored.get_value("gameplay","zapper_auto_aim")) and gameplay.replay_enabled == bool(authored.get_value("gameplay","photo_replay")),"Fresh General menu uses captured aim and replay choices")
	check(gameplay.wildlife_limit == int(authored.get_value("gameplay","wildlife_limit")) and gameplay.bubble_limit == int(authored.get_value("gameplay","bubble_limit")),"Fresh population limits use captured choices")
	var graphics := Graphics.new(); graphics.settings_path = path; root.add_child(graphics)
	check(graphics.settings.resolution == Vector2i(1920,1080),"Fresh graphics resolution matches the desktop")
	for key in ["anti_aliasing","shadows","frame_limit","contrast","fog_distance","vsync"]:
		check(graphics.settings[key] == authored.get_value("graphics",key),"Fresh graphics uses captured " + key)
	var scope := Node.new(); root.add_child(scope); var front := Node.new(); scope.add_child(front)
	var audio := preload("res://effects_audio.gd").new(); audio.settings_path = path; front.add_child(audio)
	check(is_equal_approx(audio.volume,float(authored.get_value("audio","effects_volume"))),"Fresh sound volume uses captured choice")
	var personal := ConfigFile.new()
	personal.set_value("gameplay","disable_random_pirates",not gameplay.disable_random_pirates)
	personal.set_value("graphics","resolution",Vector2i(1600,900))
	personal.set_value("graphics","fog_distance",45.0)
	personal.set_value("audio","effects_volume",15.0)
	personal.set_value("game","folder","fixture-only-private-path")
	personal.save(path); var before := FileAccess.get_file_as_bytes(path)
	var merged := Defaults.load_preferences(path)
	check(merged.get_value("gameplay","disable_random_pirates") != authored.get_value("gameplay","disable_random_pirates"),"Existing player's pirate choice overrides release defaults")
	check(not merged.has_section_key("gameplay","wildlife_limit"),"Existing option sections retain legacy fallbacks for unspecified keys")
	check(not merged.has_section("game"),"Option merging ignores private path sections")
	var saved_graphics := Graphics.new(); saved_graphics.settings_path = path; root.add_child(saved_graphics)
	check(saved_graphics.settings.resolution == Vector2i(1600,900) and saved_graphics.settings.fog_distance == 45.0,"Subsequent launches preserve saved resolution and graphics choices")
	check(saved_graphics.settings.contrast == 100.0,"Older graphics preferences use neutral contrast")
	var saved_gameplay := preload("res://gameplay_menu.gd").new(); saved_gameplay.settings_path = path; root.add_child(saved_gameplay)
	check(saved_gameplay.disable_random_pirates != gameplay.disable_random_pirates,"General menu preserves existing player's choice")
	var saved_audio := preload("res://effects_audio.gd").new(); saved_audio.settings_path = path; front.add_child(saved_audio)
	check(saved_audio.volume == 15.0,"Sound menu preserves existing player's volume")
	check(before == FileAccess.get_file_as_bytes(path),"Loading defaults never rewrites existing preferences")
	gameplay.free(); saved_gameplay.free(); graphics.free(); saved_graphics.free(); scope.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	verify_restore(authored)
	print("Option defaults: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func verify_restore(authored: ConfigFile) -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "user://options-reset-fixture-" + str(OS.get_process_id())
	var path: String = storage.preferences_path()
	var config := ConfigFile.new()
	config.set_value("game", "folder", "original-install")
	config.set_value("game", "language", "fr")
	config.set_value("developer", "enabled", true)
	config.set_value("hud", "map", false)
	config.set_value("bindings", "menu_down", [])
	config.set_value("mods", "enabled", ["fixture-pack"])
	config.set_value("mods", "order", ["fixture-pack"])
	config.set_value("graphics", "resolution", Vector2i(1600,900))
	config.set_value("gameplay", "disable_random_pirates", true)
	config.set_value("audio", "effects_volume", 15.0)
	storage.ensure_parent(path)
	config.save(path)
	var original_preferences := FileAccess.get_file_as_bytes(path)
	var save_path: String = storage.saves_path().path_join("preserve.json")
	var mod_path: String = storage.mods_path().path_join("fixture-pack/mod.json")
	for fixture in [save_path, mod_path]:
		storage.ensure_parent(fixture)
		var file := FileAccess.open(fixture, FileAccess.WRITE)
		file.store_string("{}")
		file.close()
	var tuning_paths := ["res://view_defaults.cfg", "res://submarine_tuning.cfg", "res://submarine_audio.cfg"]
	var tuning_before := tuning_paths.map(func(file: String) -> String: return FileAccess.get_sha256(file))
	var game := ReleaseReset.new()
	game.game_folder = "original-install"
	root.add_child(game)
	game.game_language = "fr"
	game.has_started_game = true
	game.day_night.hour = 14.5
	game.player_progress.status.credits = 4567
	var progress = game.player_progress
	game.front_end.show_menu(false)
	game.front_end._activate_button("options")
	game.front_end._activate_button("restore_defaults")
	check(game.restore_defaults_prompt.visible and game.restore_defaults_prompt.dialog_text == "Are you sure?" and FileAccess.get_file_as_bytes(path) == original_preferences,"Restore Defaults asks a short question before writing")
	game.restore_defaults_prompt.hide()
	game.restore_defaults_prompt.canceled.emit()
	check(FileAccess.get_file_as_bytes(path) == original_preferences,"Cancel leaves the preferences intact")
	game.front_end._activate_button("restore_defaults")
	game.restore_defaults_prompt.hide()
	game.restore_defaults_prompt.confirmed.emit()
	config.clear()
	check(config.load(path) == OK and Array(config.get_sections()) == ["game", "mods"],"Confirm clears only settings overrides")
	check(config.get_value("game", "folder") == "original-install" and config.get_value("game", "language") == "fr","Reset preserves folder and language")
	check(config.get_value("mods", "enabled") == ["fixture-pack"] and config.get_value("mods", "order") == ["fixture-pack"],"Reset preserves selected mods and priority")
	check(Defaults.load_preferences(path).encode_to_text() == authored.encode_to_text(),"Later launches will use the same defaults")
	check(game.front_end.gameplay_menu.disable_random_pirates == bool(authored.get_value("gameplay", "disable_random_pirates")) and game.front_end.effects_audio.volume == float(authored.get_value("audio", "effects_volume")),"Live gameplay and audio use release defaults")
	check(game.front_end.player_graphics.settings.resolution == game.front_end.player_graphics.desktop_size(),"Live graphics returns to desktop resolution")
	check(game.has_started_game and is_same(game.player_progress, progress) and progress.status.credits == 4567 and game.day_night.hour == 14.5,"Reset preserves progress and the current game clock")
	var bindings = preload("res://input_bindings.gd")
	check(bindings.bindings == bindings.defaults(),"Live controls return to the default bindings")
	check(FileAccess.get_file_as_string(save_path) == "{}" and FileAccess.get_file_as_string(mod_path) == "{}","Reset preserves saves and installed mods")
	check(tuning_paths.map(func(file: String) -> String: return FileAccess.get_sha256(file)) == tuning_before,"Reset leaves the authored F1 defaults untouched")
	game.free()
