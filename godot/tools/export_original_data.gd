extends SceneTree
const Data = preload("res://original_game_data.gd")
const Paths = preload("res://asset_paths.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if args.size() > 0 else Paths.find_game_folder()
	var output := args[1] if args.size() > 1 else "user://original_gameplay_catalogue.json"
	var catalogue := Data.load_catalogue(folder,false)
	if not catalogue.warnings.is_empty():
		for warning in catalogue.warnings: push_error(warning)
		quit(1); return
	var error := Data.export_catalogue(catalogue,output)
	if error != OK: push_error("Could not write catalogue: " + error_string(error)); quit(1); return
	print("Original gameplay catalogue: ",ProjectSettings.globalize_path(output))
	for table in catalogue.tables: print("  ",table,": ",catalogue.tables[table].records.size()," records")
	quit()
