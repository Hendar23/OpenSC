extends SceneTree
const Front = preload("res://front_end.gd")
const Graphics = preload("res://player_graphics.gd")
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
	var game := Node.new(); root.add_child(game)
	var front := Front.new(); front.remember_preferences = false; game.add_child(front)
	front.show_menu(false); front._activate_button("options"); front._activate_button("graphics")
	var menu: CanvasLayer = front.graphics_menu
	var graphics: Node = front.player_graphics
	check(menu.visible and menu.controls.display_mode.has_focus(),"Graphics opens with controller focus")
	check(not front.buttons.graphics.visible and front.menu_layer.visible,"Graphics replaces the options while retaining the live backdrop")
	check(menu.order.size() == 8 and not menu.controls.has("hud_scale"),"Seven settings and Back are navigable; HUD scaling is automatic")
	check(menu.order.filter(func(control: Control) -> bool: return control is Button).all(func(control: Control) -> bool: return control.get_theme_font_size("font_size") == 14) and menu.labels.values().all(func(label: Label) -> bool: return label.get_theme_font_size("font_size") == 14),"Graphics uses the main menu font size")
	check(menu.get_child(0).color.a == 0.0,"Graphics retains the live sea")
	check(front.menu_theme.default_font is FontFile and front.menu_theme.default_font.multichannel_signed_distance_field and menu.layout.theme == front.menu_theme,"Scaled menu text uses a shared sharp distance-field font")
	paused = true
	press(menu,"menu_up"); check(menu.back.has_focus(),"Up wraps to Back")
	press(menu,"menu_up"); check(menu.controls.brightness.has_focus(),"Up selects Brightness")
	check(not menu.controls.brightness.scrollable,"Wheel cannot adjust brightness")
	press(menu,"menu_right")
	check(graphics.brightness_material.get_shader_parameter("brightness") == 1.01,"Brightness updates the post-process live")
	menu._change("anti_aliasing",2)
	check(root.msaa_3d == Viewport.MSAA_4X,"Anti-aliasing applies MSAA 4x")
	var feed := SubViewport.new(); game.add_child(feed)
	check(feed.msaa_3d == Viewport.MSAA_4X,"New camera feeds inherit anti-aliasing")
	var sun := DirectionalLight3D.new(); game.add_child(sun)
	menu._change("shadows",0); graphics.apply_sun(sun)
	check(not sun.shadow_enabled and root.positional_shadow_atlas_size == 0 and feed.positional_shadow_atlas_size == 0,"Off disables directional and positional shadows, including feeds")
	menu._change("shadows",3); graphics.apply_sun(sun)
	check(sun.shadow_enabled and sun.directional_shadow_max_distance == 120.0 and root.positional_shadow_atlas_size == 4096,"High restores shadows at higher resolution and distance")
	menu._change("frame_limit",120); check(Engine.max_fps == 120,"Frame-rate limit applies")
	menu._change("frame_limit",0); check(Engine.max_fps == 0,"Unlimited removes the cap")
	menu._change("vsync",false); check(not graphics.settings.vsync,"VSync toggles independently")
	check(not graphics.resolutions().is_empty() and graphics.settings.resolution in graphics.resolutions(),"Resolution list includes the current monitor size")
	if DisplayServer.get_name() != "headless":
		graphics.set_value("resolution",Vector2i(1280,720)); graphics.set_value("display_mode",2)
		await process_frame; await process_frame
		check(root.mode == Window.MODE_WINDOWED and not root.borderless and root.size == Vector2i(1280,720),"Windowed resolution controls the window size")
		check(root.content_scale_size == Vector2i(1280,720) and root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"UI retains its original canvas sizing and rasterizes at native resolution")
		graphics.set_value("display_mode",1); await process_frame; await process_frame
		check(root.mode == Window.MODE_FULLSCREEN and root.borderless,"Borderless uses desktop fullscreen")
		check(is_equal_approx(root.scaling_3d_scale,minf(1280.0 / root.size.x,720.0 / root.size.y)),"Fullscreen resolution scales the 3D scene while UI stays native")
		graphics.set_value("display_mode",0); await process_frame; await process_frame
		check(root.mode == Window.MODE_EXCLUSIVE_FULLSCREEN,"Fullscreen uses exclusive fullscreen")
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_width() >= DisplayServer.window_get_size().x,"Final UI framebuffer is not reduced with the 3D scene (framebuffer %s, window %s)" % [root.get_texture().get_size(),DisplayServer.window_get_size()])
	var path := "res://tests/graphics-preferences-test.cfg"
	var config := ConfigFile.new(); config.set_value("audio","effects_volume",175); config.save(path)
	graphics.settings_path = path; graphics.remember_preferences = true
	check(graphics.set_value("brightness",125.0) == OK,"Graphics saves automatically")
	config.load(path); check(config.get_value("audio","effects_volume") == 175,"Saving graphics preserves audio preferences")
	# Avoid display mode changes in this unit test; full display checks run in the native game test.
	var restored := Graphics.new(); restored.settings_path = path; restored.remember_preferences = false; front.add_child(restored)
	restored.load_preferences()
	check(restored.settings.brightness == 125.0 and restored.settings.shadows == 3 and restored.settings.anti_aliasing == 2,"All graphics settings persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	press(menu,"menu_cancel"); check(not menu.visible and front.buttons.graphics.has_focus(),"Back restores Graphics option focus")
	paused = false; game.free(); Engine.max_fps = 0
	print("Graphics menu: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
