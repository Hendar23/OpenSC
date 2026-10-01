extends RefCounted

static func find_game_folder(require_map: bool = true) -> String:
	var config := ConfigFile.new()
	config.load("user://opensubculture.cfg")
	var candidates := [str(config.get_value("game", "folder", "")),
		ProjectSettings.globalize_path("res://../Sub Culture"),
		ProjectSettings.globalize_path("res://../Original Sub Culture"),
		OS.get_executable_path().get_base_dir().path_join("Sub Culture")]
	for folder in candidates:
		if valid_game_folder(folder, require_map): return folder
	return ""

static func valid_game_folder(folder: String, require_map: bool = true) -> bool:
	return not folder.is_empty() and FileAccess.file_exists(folder.path_join("CLUMPS/SUB.DFF")) and (
		not require_map or FileAccess.file_exists(folder.path_join("DATA/SCEN1.BSP")))
