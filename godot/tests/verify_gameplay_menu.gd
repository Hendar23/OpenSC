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
	check(front.buttons.gameplay.text == "General" and menu.sun_shafts_enabled,"General options defaults sun shafts On")
	check(menu.layout.theme == front.menu_theme and menu.get_child(0).color.a == 0,"Gameplay matches menu fonts and preserves the live sea")
	if DisplayServer.get_name() != "headless":
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/gameplay-wildlife-cap.png")
	paused = true; press(menu,"menu_accept")
	check(menu.zapper_auto_aim and menu.toggle.text.ends_with("On"),"Controller confirm enables auto aim while paused")
	press(menu,"menu_left"); check(not menu.zapper_auto_aim,"Left/right can toggle auto aim")
	press(menu,"menu_down"); check(menu.wildlife_button.has_focus(),"Down selects wildlife cap")
	check(menu.wildlife_limit == 80,"Active wildlife defaults to a cap below 100")
	press(menu,"menu_left"); check(menu.wildlife_limit == 60,"Controller left lowers the cap")
	press(menu,"menu_right"); check(menu.wildlife_limit == 80,"Controller right raises the cap")
	press(menu,"menu_down"); check(menu.sun_shafts_button.has_focus(),"Down selects sun shafts")
	press(menu,"menu_accept"); check(not menu.sun_shafts_enabled,"Sun shafts toggle works while paused")
	press(menu,"menu_down"); check(menu.replay_button.has_focus() and menu.replay_enabled,"Down selects photo replay, enabled by default")
	press(menu,"menu_accept"); check(not menu.replay_enabled,"Controller can disable replay recording while paused")
	check(preload("res://mine_explosion.gd").enhanced_enabled and not menu.find_children("*","Button",true,false).any(func(button: Button) -> bool: return button.text.begins_with("Explosions:")),"Enhanced explosions remain enabled without a menu toggle")
	press(menu,"menu_down"); check(menu.fmv_button.has_focus() and menu.fmvs_enabled,"FMVs default On and are reachable by controller")
	press(menu,"menu_accept"); check(not menu.fmvs_enabled,"Controller confirm disables FMVs")
	press(menu,"menu_down"); check(menu.back.has_focus(),"Down selects Back")
	press(menu,"menu_accept"); check(not menu.visible and front.buttons.gameplay.has_focus(),"Back restores Gameplay option focus")
	paused = false
	var path := "res://tests/gameplay-preferences-test.cfg"
	var config := ConfigFile.new(); config.set_value("audio","effects_volume",175); config.save(path)
	menu.settings_path = path; menu.remember_preferences = true; menu._toggle()
	menu._cycle_wildlife_limit()
	config.load(path)
	check(config.get_value("gameplay","zapper_auto_aim",false) == true,"Auto aim choice saves automatically")
	check(config.get_value("gameplay","wildlife_limit",0) == 100,"Wildlife cap saves automatically")
	check(config.get_value("audio","effects_volume") == 175,"Gameplay saving preserves other preferences")
	config.set_value("gameplay","enhanced_explosions",false); config.save(path)
	var restored := Gameplay.new(); restored.settings_path = path; front.add_child(restored)
	check(restored.zapper_auto_aim,"Gameplay choice loads on next launch")
	check(restored.wildlife_limit == 100,"Wildlife cap loads on next launch")
	check(not restored.sun_shafts_enabled,"Sun shafts choice saves and loads")
	check(not restored.replay_enabled,"Replay choice saves and loads")
	check(not restored.fmvs_enabled,"FMV choice saves and loads without affecting existing preferences")
	check(preload("res://mine_explosion.gd").enhanced_enabled,"An old Classic preference cannot disable enhanced explosions")
	menu._toggle_replay(); config.clear(); config.load(path)
	check(config.get_value("gameplay","photo_replay",false),"Replay can be enabled again and saved")
	check(not config.has_section_key("gameplay","enhanced_explosions"),"Saving removes the obsolete explosion setting")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	front.free(); print("Gameplay menu: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
