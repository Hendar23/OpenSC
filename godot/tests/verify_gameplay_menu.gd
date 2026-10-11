extends SceneTree
const Front = preload("res://front_end.gd")
const Gameplay = preload("res://gameplay_menu.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func press(menu: Node,action: String) -> void:
	var event := InputEventAction.new(); event.action = action; event.pressed = true; menu._input(event)
func _run() -> void:
	preload("res://input_bindings.gd").install()
	var front := Front.new(); front.remember_preferences = false; root.add_child(front)
	front.show_menu(false); front._activate_button("options"); front._activate_button("gameplay")
	var menu: CanvasLayer = front.gameplay_menu
	check(menu.visible and menu.toggle.has_focus() and not front.buttons.gameplay.visible,"Gameplay opens focused without overlapping Options")
	check(not menu.zapper_auto_aim and menu.toggle.text.ends_with("Off"),"Zapper auto aim defaults Off")
	check(menu.layout.theme == front.menu_theme and menu.get_child(0).color.a == 0,"Gameplay matches menu fonts and preserves the live sea")
	paused = true; press(menu,"menu_accept")
	check(menu.zapper_auto_aim and menu.toggle.text.ends_with("On"),"Controller confirm enables auto aim while paused")
	press(menu,"menu_left"); check(not menu.zapper_auto_aim,"Left/right can toggle auto aim")
	press(menu,"menu_down"); check(menu.back.has_focus(),"Down selects Back")
	press(menu,"menu_accept"); check(not menu.visible and front.buttons.gameplay.has_focus(),"Back restores Gameplay option focus")
	paused = false
	var path := "res://tests/gameplay-preferences-test.cfg"
	var config := ConfigFile.new(); config.set_value("audio","effects_volume",175); config.save(path)
	menu.settings_path = path; menu.remember_preferences = true; menu._toggle()
	config.load(path)
	check(config.get_value("gameplay","zapper_auto_aim",false) == true,"Auto aim choice saves automatically")
	check(config.get_value("audio","effects_volume") == 175,"Gameplay saving preserves other preferences")
	var restored := Gameplay.new(); restored.settings_path = path; front.add_child(restored)
	check(restored.zapper_auto_aim,"Gameplay choice loads on next launch")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	front.free(); print("Gameplay menu: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
