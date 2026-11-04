extends RefCounted
## Resolve read-only input before a fixture overrides writable player storage.
static func source() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mods="): return argument.trim_prefix("--mods=")
	var configured := OS.get_environment("OPENSC_TEST_MODS_FOLDER")
	return configured if not configured.is_empty() else preload("res://player_storage.gd").mods_path()
