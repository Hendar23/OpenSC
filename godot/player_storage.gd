extends RefCounted

# Personal files use the OS Documents location, including redirected Documents.
static var root_override := ""

static func root_path() -> String:
	if not root_override.is_empty(): return root_override
	return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("OpenSC")

static func preferences_path() -> String:
	return root_path().path_join("preferences.cfg")

static func saves_path() -> String:
	return root_path().path_join("savegame")

static func ensure_parent(path: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
