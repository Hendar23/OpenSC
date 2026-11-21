extends RefCounted

# Personal files use the OS Documents location, including redirected Documents.
static var root_override := ""
static var _default_root := ""

static func root_path() -> String:
	if not root_override.is_empty(): return root_override
	if _default_root.is_empty():
		# On Linux this may start xdg-user-dir. Resolve it once, and use the
		# app data folder if the OS cannot resolve an absolute Documents path.
		var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		_default_root = documents.path_join("OpenSC") if documents.is_absolute_path() else ProjectSettings.globalize_path("user://player")
	return _default_root

static func preferences_path() -> String:
	return root_path().path_join("preferences.cfg")

static func saves_path() -> String:
	return root_path().path_join("savegame")

static func screenshots_path() -> String:
	return root_path().path_join("Screenshots")

static func mods_path() -> String:
	return root_path().path_join("Mods")

static func open_player_folder(opener: Callable = Callable()) -> Error:
	var folder := ProjectSettings.globalize_path(root_path()).simplify_path()
	var result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(screenshots_path()))
	if result != OK: return result
	result = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(mods_path()))
	if result != OK: return result
	return opener.call(folder) if opener.is_valid() else OS.shell_open(folder)

static func ensure_parent(path: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
