extends RefCounted

static func find_game_folder(require_map: bool = true, config_path: String = "user://opensubculture.cfg") -> String:
	var config := ConfigFile.new()
	if config.load(config_path) != OK: return ""
	var folder := str(config.get_value("game", "folder", ""))
	return folder if valid_game_folder(folder, require_map) else ""

static func valid_game_folder(folder: String, require_map: bool = true) -> bool:
	return not folder.is_empty() and FileAccess.file_exists(folder.path_join("CLUMPS/SUB.DFF")) and (
		not require_map or FileAccess.file_exists(folder.path_join("DATA/SCEN1.BSP")))
