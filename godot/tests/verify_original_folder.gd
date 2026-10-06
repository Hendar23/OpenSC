extends SceneTree
const Game = preload("res://game.gd")
const Paths = preload("res://asset_paths.gd")
var failures := 0

class MissingFolderGame extends Game:
	func _bootstrap() -> void:
		_prompt_game_folder("Choose the original Sub Culture folder containing CLUMPS and DATA.")

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition: failures += 1; push_error(message)

func _run() -> void:
	var config_path := "res://tests/original-folder-test.cfg"
	var config := ConfigFile.new()
	config.set_value("game","folder","res://game_assets")
	config.save(config_path)
	check(Paths.find_game_folder(true,config_path).is_empty(),"An invalid saved folder is rejected without searching nearby folders")
	config.erase_section("game"); config.save(config_path)
	check(Paths.find_game_folder(true,config_path).is_empty(),"An unset folder requires user selection")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
	check(Paths.find_game_folder(true,config_path).is_empty(),"Missing preferences require user selection")
	var game := MissingFolderGame.new()
	game.remember_preferences = false
	root.add_child(game)
	await process_frame; await process_frame
	check(game.front_end.loading_layer.visible and game.front_end.loading_picture.texture != null,"Missing files keep a loading screen visible")
	check(game.folder_prompt.visible and game.folder_dialog.use_native_dialog,"Missing files offer the native folder picker")
	check(game.world_root == null and game.gameplay_catalogue.is_empty() and not game.startup_complete,"No original data or world is loaded before folder selection")
	game.folder_prompt.hide()
	await game._choose_game_folder("res://game_assets")
	check(game.folder_prompt.visible and game.folder_prompt.dialog_text.contains("CLUMPS/SUB.DFF"),"Invalid selection explains the required files and allows retry")
	game.folder_prompt.hide(); game.folder_dialog.canceled.emit()
	check(game.folder_prompt.visible and game.world_root == null,"Cancelling folder selection leaves a retry prompt")
	game.queue_free(); await process_frame
	print("Original folder: 8 checks, %d failures" % failures)
	quit(1 if failures else 0)
