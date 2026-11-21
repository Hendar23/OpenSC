extends "res://tests/test_scene_tree.gd"
const Defaults = preload("res://option_defaults.gd")
class Graphics extends "res://player_graphics.gd":
	func desktop_size() -> Vector2i: return Vector2i(1920,1080)
	func apply_display() -> void: pass
	func apply_rendering() -> void: pass
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
	print("Option defaults: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
