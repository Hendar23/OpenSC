extends "res://tests/test_scene_tree.gd"
const Storage = preload("res://player_storage.gd")
class Front extends "res://front_end.gd":
	var opened := ""
	func _open_player_folder() -> Error:
		return preload("res://player_storage.gd").open_player_folder(func(path: String) -> Error: opened = path; return OK)
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Storage.root_override = "res://tests/cache-player-folder-fixtures"
	Storage.ensure_parent(Storage.preferences_path())
	var ignore := FileAccess.open(Storage.root_path().path_join(".gdignore"),FileAccess.WRITE); ignore.store_string(""); ignore.close()
	var capture := preload("res://capture_overlay.gd").new()
	var folder := ProjectSettings.globalize_path(Storage.root_path()).simplify_path()
	check(capture.screenshot_folder() == folder.path_join("Screenshots"),"Capture resolves Screenshots beside player saves/preferences, independently of the executable")
	check(ProjectSettings.globalize_path(Storage.preferences_path()).get_base_dir() == folder and ProjectSettings.globalize_path(Storage.saves_path()).get_base_dir() == folder,"Screenshots, saves and preferences share the same player-data root")
	var front := Front.new(); front.remember_preferences = false; root.add_child(front)
	front.show_menu(false)
	check(not front.buttons.player_folder.visible,"Folder shortcut stays out of the main-menu button list")
	front._activate_button("options")
	var button: Button = front.buttons.player_folder
	check(button.visible and front.is_button_available("player_folder") and button.text == "Open Player Folder","Options exposes an enabled, clearly named folder button")
	var order: Array = front._visible_button_order()
	check(order.has("player_folder") and order.back() == "back","Folder button participates in controller navigation with Back remaining last")
	button.pressed.emit()
	check(front.opened == folder,"Pressing the real Options button opens the common folder through the OS folder action")
	check(DirAccess.dir_exists_absolute(folder.path_join("Screenshots")),"Opening the player folder creates Screenshots even before the first capture")
	check(front.menu_page == "options" and front.menu_layer.visible,"Opening the folder preserves the current Options page")
	# Exercise the destination without launching a graphics device.
	var picture := Image.create(2,2,false,Image.FORMAT_RGB8); picture.fill(Color.CYAN)
	var path := capture.screenshot_folder().path_join("folder-test.png")
	check(picture.save_png(path) == OK and Image.load_from_file(path).get_size() == Vector2i(2,2),"The resolved screenshot destination accepts readable PNG files")
	DirAccess.remove_absolute(path)
	front.free(); capture.free()
	print("Player folder: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
