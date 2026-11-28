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
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	preload("res://input_bindings.gd").install()
	var front := Front.new(); front.remember_preferences = false; root.add_child(front)
	front.show_menu(false); front._activate_button("options")
	var options_bounds: Rect2 = front.buttons.display.get_global_rect().merge(front.buttons.back.get_global_rect())
	check(is_equal_approx(options_bounds.get_center().y, root.get_visible_rect().get_center().y), "The Options buttons are vertically centred")
	front._activate_button("gameplay")
	var menu: CanvasLayer = front.gameplay_menu
	check(menu.visible and menu.classic_sub_physics_button.has_focus() and not front.buttons.gameplay.visible,"Gameplay opens focused on Classic Sub physics")
	check(front.buttons.gameplay.text == "Gameplay" and menu.option_rows.get_child_count() == 4,"Gameplay contains its four play preferences")
	check(menu.layout.theme == front.menu_theme and menu.get_child(0).color.a == 0,"Gameplay matches menu fonts and preserves the live sea")
	if DisplayServer.get_name() != "headless":
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/gameplay-wildlife-cap.png")
	else:
		for frame in range(3): await process_frame
	var gameplay_button: Button = menu.classic_sub_physics_button
	var gameplay_bounds := gameplay_button.get_global_rect().merge(menu.back.get_global_rect())
	check(menu.layout.scale.is_equal_approx(front.menu_layout.scale), "Gameplay uses the Options menu scale")
	check(is_equal_approx(gameplay_button.get_global_rect().size.y, front.buttons.display.get_global_rect().size.y), "Gameplay and Options buttons are the same height")
	check(is_equal_approx(gameplay_bounds.get_center().y, root.get_visible_rect().get_center().y), "The Gameplay buttons are vertically centred")
	var bubbles = preload("res://propeller_bubbles.gd")
	check(menu.bubble_limit == 200,"Global bubble limit defaults to 200")
	var wakes: Array[Node3D] = []
	for index in 2:
		var wake := bubbles.new(); front.add_child(wake); wake.set_physics_process(false); wake.set_process(false); wakes.append(wake)
	for tick in 40:
		for wake in wakes: wake.emit_from(0,Vector3.ZERO,Vector3.ZERO,1,1000,1)
	check(bubbles.total_bubbles() == 200 and wakes.all(func(wake: Node3D) -> bool: return not wake.particles.is_empty()),"All emitters share200 slots and new wakes can replace old bubbles")
	var burst := CPUParticles3D.new(); front.add_child(burst); burst.amount = 96; burst.lifetime = 2.4
	bubbles.reserve_burst(burst)
	check(bubbles.total_bubbles() == 200 and int(burst.get_meta("bubble_budget")) == 96,"Death bursts share the same global limit as wakes")
	menu._set_bubble_limit(50)
	check(bubbles.total_bubbles() == 50,"Lowering the limit immediately trims existing bubbles")
	menu._set_bubble_limit(0)
	for wake in wakes: wake.emit_from(0,Vector3.ZERO,Vector3.ZERO,1,1000,1)
	check(bubbles.total_bubbles() == 0 and not burst.visible,"Off clears wakes and death bursts and stops new bubbles")
	burst.free()
	menu._set_bubble_limit(-1)
	for tick in 30:
		for wake in wakes: wake.emit_from(0,Vector3.ZERO,Vector3.ZERO,1,1000,1)
	check(bubbles.total_bubbles() > 200,"Unlimited restores the existing per-emitter capacity")
	for wake in wakes: wake.free()
	check(bubbles.total_bubbles() == 0,"Freed emitters release their global slots")
	menu._set_bubble_limit(200)
	paused = true
	check(menu.classic_sub_physics_button.text == "Classic Sub physics: Off","Classic sub physics defaults Off")
	press(menu,"menu_accept"); check(menu.classic_sub_physics,"Confirm enables Classic sub physics while paused")
	press(menu,"menu_left"); check(not menu.classic_sub_physics,"Left disables Classic sub physics")
	press(menu,"menu_right"); check(menu.classic_sub_physics,"Right enables Classic sub physics")
	press(menu,"menu_down"); check(menu.cockpit_3d_button.has_focus() and menu.cockpit_3d_enabled,"Down selects the 3D cockpit, enabled by default")
	press(menu,"menu_accept"); check(not menu.cockpit_3d_enabled,"Controller confirm restores the classic cockpit")
	press(menu,"menu_down"); check(menu.crosshair_button.has_focus() and menu.crosshair_enabled,"Crosshair defaults On and is reachable by controller")
	press(menu,"menu_accept"); check(not menu.crosshair_enabled,"Confirm turns the crosshair Off")
	press(menu,"menu_down"); check(menu.replay_button.has_focus() and menu.replay_enabled,"Down selects photo replay, enabled by default")
	press(menu,"menu_accept"); check(not menu.replay_enabled,"Controller can disable replay recording while paused")
	press(menu,"menu_down"); check(menu.back.has_focus(),"Down selects Back")
	press(menu,"menu_accept"); check(not menu.visible and front.buttons.gameplay.has_focus(),"Back restores Gameplay option focus")
	_verify_moved_options(front,menu)
	await _verify_layout(front,menu)
	paused = false
	var path := "res://tests/gameplay-preferences-test.cfg"
	var config := ConfigFile.new(); config.set_value("audio","effects_volume",175); config.save(path)
	menu.settings_path = path; menu.remember_preferences = true; menu._toggle()
	menu._set_bubble_limit(500)
	menu._cycle_wildlife_limit()
	config.load(path)
	check(config.get_value("gameplay","zapper_auto_aim",false) == true,"Auto aim choice saves automatically")
	check(config.get_value("gameplay","wildlife_limit",0) == 100,"Wildlife cap saves automatically")
	check(config.get_value("audio","effects_volume") == 175,"Gameplay saving preserves other preferences")
	config.set_value("gameplay","enhanced_explosions",false); config.save(path)
	var restored := Gameplay.new(); restored.settings_path = path; front.add_child(restored)
	check(restored.classic_sub_physics,"Classic sub physics choice persists on next launch")
	check(restored.bubble_limit == 500,"Bubble limit persists under the existing preference key")
	check(not restored.crosshair_enabled,"First-person crosshair choice saves and loads")
	check(not restored.cockpit_3d_enabled,"Classic cockpit choice saves and loads")
	check(restored.disable_random_pirates,"Random pirate disabling preference persists on next launch")
	check(not restored.random_pirate_weapons,"Pirate weapons preference persists on the next launch")
	check(restored.zapper_auto_aim,"Gameplay choice loads on next launch")
	check(restored.wildlife_limit == 100,"Wildlife cap loads on next launch")
	check(not restored.sun_shafts_enabled,"Sun shafts choice saves and loads")
	check(not restored.lens_flares_enabled and not preload("res://lens_flare.gd").effects_enabled,"Lens flare preference persists and applies on next launch")
	check(not restored.replay_enabled,"Replay choice saves and loads")
	check(not restored.fmvs_enabled,"FMV choice saves and loads without affecting existing preferences")
	check(restored.classic_explosions and preload("res://mine_explosion.gd").classic_enabled and preload("res://mine_explosion.gd").enhanced_enabled,"Classic preference persists and restores the previous enhanced effects")
	restored._toggle_classic_explosions()
	menu.reload_preferences()
	check(not menu.classic_explosions and not preload("res://mine_explosion.gd").classic_enabled,"Reload applies a changed explosion mode")
	menu._toggle_replay(); config.clear(); config.load(path)
	check(config.get_value("gameplay","photo_replay",false),"Replay can be enabled again and saved")
	check(not config.has_section_key("gameplay","enhanced_explosions"),"Saving removes the obsolete explosion setting")
	config.erase_section_key("gameplay","bubble_limit"); config.set_value("graphics","bubble_limit",100); config.save(path)
	var legacy := Gameplay.new(); legacy.settings_path = path; front.add_child(legacy)
	check(legacy.bubble_limit == 100,"Moving the menu preserves a previously saved legacy bubble limit")
	legacy._set_bubble_limit(200); config.clear(); config.load(path)
	check(config.get_value("gameplay","bubble_limit") == 200 and not config.has_section_key("graphics","bubble_limit"),"Saving still consolidates the legacy bubble preference")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	front.free(); print("Gameplay menu: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func _verify_moved_options(front: Front, menu: CanvasLayer) -> void:
	front._activate_button("graphics")
	var graphics: CanvasLayer = front.graphics_menu
	graphics.controls.sun_shafts_enabled.grab_focus()
	check(menu.sun_shafts_enabled and graphics.controls.sun_shafts_enabled.text.contains("On"),"Sun shafts default on in Graphics")
	press(graphics,"menu_accept"); check(not menu.sun_shafts_enabled,"Sun shafts toggle works while paused")
	press(graphics,"menu_down"); check(graphics.controls.lens_flares_enabled.has_focus(),"Down selects lens flares")
	check(menu.lens_flares_enabled and preload("res://lens_flare.gd").effects_enabled,"Lens flares default on")
	press(graphics,"menu_accept"); check(not menu.lens_flares_enabled and not preload("res://lens_flare.gd").effects_enabled,"Confirm disables lens flares while paused")
	press(graphics,"menu_right"); check(menu.lens_flares_enabled and preload("res://lens_flare.gd").effects_enabled,"Right enables lens flares immediately")
	press(graphics,"menu_left"); check(not menu.lens_flares_enabled,"Left disables lens flares")
	press(graphics,"menu_down"); check(graphics.controls.classic_explosions.has_focus() and not menu.classic_explosions,"Classic explosions are selectable and off by default")
	press(graphics,"menu_accept"); check(menu.classic_explosions and preload("res://mine_explosion.gd").classic_enabled,"Confirm restores classic explosions")
	press(graphics,"menu_left"); check(not menu.classic_explosions and not preload("res://mine_explosion.gd").classic_enabled,"Left restores current explosion effects")
	press(graphics,"menu_right"); check(menu.classic_explosions,"Right enables classic explosions")
	press(graphics,"menu_down"); check(graphics.controls.bubble_limit.has_focus(),"Down selects maximum bubbles")
	press(graphics,"menu_left"); check(menu.bubble_limit == 100,"Controller lowers maximum bubbles")
	press(graphics,"menu_right"); check(menu.bubble_limit == 200,"Controller restores default bubble limit")
	press(graphics,"menu_down"); check(graphics.controls.wildlife_limit.has_focus() and menu.wildlife_limit == 80,"Down selects Active wildlife with its default limit")
	press(graphics,"menu_left"); check(menu.wildlife_limit == 60,"Controller lowers the wildlife limit")
	press(graphics,"menu_right"); check(menu.wildlife_limit == 80,"Controller restores the wildlife limit")
	press(graphics,"menu_cancel")

	front._activate_button("display")
	var display: CanvasLayer = front.display_menu
	display.controls.fmvs_enabled.grab_focus()
	check(menu.fmvs_enabled and display.controls.fmvs_enabled.text.contains("On"),"Display shows FMVs enabled by default")
	press(display,"menu_accept"); check(not menu.fmvs_enabled,"Controller confirm disables FMVs")
	press(display,"menu_down"); check(display.controls.fmv_size.has_focus(),"FMV size follows Play FMVs")
	press(display,"menu_cancel")

	front._activate_button("difficulty")
	var difficulty: CanvasLayer = front.difficulty_menu
	check(difficulty.visible and difficulty.controls.keys() == ["disable_random_pirates","random_pirate_weapons","zapper_auto_aim"],"Difficulty contains the three independent options")
	check(difficulty.controls.disable_random_pirates.has_focus() and not menu.disable_random_pirates,"Difficulty opens on the random pirate toggle")
	press(difficulty,"menu_accept"); check(menu.disable_random_pirates,"Confirm disables random pirates")
	press(difficulty,"menu_left"); check(not menu.disable_random_pirates,"Left re-enables random pirates")
	press(difficulty,"menu_right"); check(menu.disable_random_pirates,"Right disables random pirates")
	press(difficulty,"menu_down"); check(difficulty.controls.random_pirate_weapons.has_focus() and menu.random_pirate_weapons,"Down selects the current NPC weapon toggle")
	press(difficulty,"menu_accept"); check(not menu.random_pirate_weapons,"Confirm restores torpedo-only attack submarines")
	press(difficulty,"menu_down"); check(difficulty.controls.zapper_auto_aim.has_focus() and not menu.zapper_auto_aim,"Auto aim is last and starts off")
	press(difficulty,"menu_accept"); check(menu.zapper_auto_aim and difficulty.controls.zapper_auto_aim.text.contains("On"),"Confirm enables auto aim while paused")
	press(difficulty,"menu_left"); check(not menu.zapper_auto_aim,"Left toggles auto aim independently")
	press(difficulty,"menu_cancel"); check(not difficulty.visible and front.buttons.difficulty.has_focus(),"Back restores Difficulty option focus")

func _verify_layout(front: Front, menu: CanvasLayer) -> void:
	var locale := TranslationServer.get_locale()
	for language in ["fr","de"]:
		TranslationServer.set_locale(language)
		front._activate_button("gameplay")
		root.size = Vector2i(640,360)
		for frame in 3: await process_frame
		check(menu.classic_sub_physics_button.has_focus(),"Gameplay keeps the same first row in %s" % language)
		check(root.get_visible_rect().encloses(menu.back.get_global_rect()) and not menu.scroll.get_global_rect().intersects(menu.back.get_global_rect()),"Back stays visible below gameplay settings")
		press(menu,"menu_down")
		check(menu.cockpit_3d_button.has_focus() and menu.cockpit_3d_button.text.begins_with("Cockpit 3D" if language == "fr" else "3D-Cockpit"),"The next option is the translated cockpit setting")
		press(menu,"menu_cancel")
	TranslationServer.set_locale(locale)
	root.size = Vector2i(1280,720)
