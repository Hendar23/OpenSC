extends SceneTree
const Front = preload("res://front_end.gd")
const Graphics = preload("res://player_graphics.gd")
class SimulatedGraphics extends "res://player_graphics.gd":
	var monitor := Vector2i(1920,1080)
	func desktop_size() -> Vector2i: return monitor
	func apply_display() -> void: pass # Exercise selection without changing a real window.
var checks := 0
var failures := 0
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-graphics-menu-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_path().path_join(".gdignore"),FileAccess.WRITE); ignore.store_string(""); ignore.close()
	call_deferred("_run")
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
	check(menu.order.size() == 10 and not menu.controls.has("hud_scale"),"Nine settings and Back are navigable; HUD scaling is automatic")
	check(menu.order.filter(func(control: Control) -> bool: return control is Button).all(func(control: Control) -> bool: return control.get_theme_font_size("font_size") == 14) and menu.labels.values().all(func(label: Label) -> bool: return label.get_theme_font_size("font_size") == 14),"Graphics uses the main menu font size")
	check(menu.get_child(0).color.a == 0.0,"Graphics retains the live sea")
	check(graphics.settings.reflective_canopies and menu.controls.reflective_canopies.text.contains("On"),"Reflective canopies default on")
	var capture := preload("res://exterior_reflections.gd").new(); game.add_child(capture); capture.setup(root.world_3d)
	menu._cycle("reflective_canopies",1)
	check(not graphics.settings.reflective_canopies and not capture.enabled and not capture.is_processing() and menu.controls.reflective_canopies.text.contains("Off"),"Toggle disables reflections and capture work immediately while paused")
	menu._cycle("reflective_canopies",1)
	check(graphics.settings.reflective_canopies and capture.enabled and capture.is_processing(),"Toggle restores captures immediately")
	var capture_view := SubViewport.new(); capture_view.set_meta("exterior_capture",true); game.add_child(capture_view)

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
	graphics.set_value("reflective_canopies",false)
	check(capture_view.positional_shadow_atlas_size == 0 and capture_view.msaa_3d == Viewport.MSAA_DISABLED,"Graphics changes keep reflection capture lightweight")

	# Avoid display mode changes in this unit test; full display checks run in the native game test.
	var restored := Graphics.new(); restored.settings_path = path; restored.remember_preferences = false; front.add_child(restored)
	restored.load_preferences()
	check(not restored.settings.reflective_canopies,"Disabled canopy preference persists across reload")
	config.load(path); config.erase_section_key("graphics","reflective_canopies"); config.save(path)
	restored.settings.reflective_canopies = true; restored.load_preferences()
	check(restored.settings.reflective_canopies,"Older preferences without canopy setting default on")

	check(restored.settings.brightness == 125.0 and restored.settings.shadows == 3 and restored.settings.anti_aliasing == 2,"All graphics settings persist")
	var simulated := SimulatedGraphics.new(); simulated.remember_preferences = false; front.add_child(simulated)
	for monitor in [Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(2560,1600),Vector2i(3440,1440),Vector2i(3840,2160),Vector2i(5120,1440),Vector2i(5120,2160),Vector2i(5120,2880),Vector2i(7680,2160),Vector2i(7680,4320),Vector2i(3000,2000)]:
		simulated.monitor = monitor; simulated.settings.resolution = monitor; simulated._validate()
		var choices: Array = simulated.resolutions()
		check(choices.has(monitor) and simulated.settings.resolution == monitor,"Native resolution remains selectable and valid on simulated %s" % monitor)
		check(Graphics.RESOLUTIONS.all(func(value: Vector2i) -> bool: return choices.has(value)),"Simulated %s shows every resolution preset regardless of monitor size" % monitor)
		check(choices.all(func(value: Vector2i) -> bool: return choices.find(value) == choices.rfind(value)),"Simulated %s has no duplicate resolution entries" % monitor)
	simulated.monitor = Vector2i(7680,4320); simulated.settings.resolution = Vector2i(5120,2880)
	check(Graphics.RESOLUTIONS.all(func(value: Vector2i) -> bool: return simulated.resolutions().has(value)),"8K display offers every common higher, ultrawide and 16:10 resolution")
	menu.graphics = simulated; menu._refresh()
	check(menu.controls.resolution.text.contains("5120 × 2880") and menu._choices("resolution").has(Vector2i(7680,4320)),"Menu displays 5K and offers 8K without changing the real window")
	simulated.remember_preferences = true; simulated.settings_path = path
	check(simulated.set_value("brightness",100.0) == OK,"High-resolution preference saves without applying a display change")
	simulated.settings.resolution = Vector2i(1280,720); simulated.load_preferences()
	check(simulated.settings.resolution == Vector2i(5120,2880),"High-resolution choice survives preference reload on a capable display")
	simulated.monitor = Vector2i(1920,1080); simulated.load_preferences()
	check(simulated.settings.resolution == Vector2i(5120,2880),"1080p monitor preserves the selected high-resolution preference instead of silently replacing it")
	simulated.remember_preferences = false
	var visited := {}
	for step in simulated.resolutions().size():
		menu._cycle("resolution",1); visited[simulated.settings.resolution] = true
	check(Graphics.RESOLUTIONS.all(func(value: Vector2i) -> bool: return visited.has(value)),"Resolution control cycles through every preset on a 1080p display without getting stuck")
	check(not simulated.settings.limit_resolutions,"Resolution restriction defaults off for existing preferences")
	menu._cycle("limit_resolutions",1)
	check(simulated.settings.limit_resolutions and menu.controls.limit_resolutions.text.contains("On"),"Resolution restriction toggles on through the normal menu button")
	check(simulated.resolutions().all(func(value: Vector2i) -> bool: return value.x <= 1920 and value.y <= 1080) and simulated.settings.resolution == Vector2i(1920,1080),"Enabling restriction limits the list and replaces an oversized selection with native resolution")
	simulated.remember_preferences = true; simulated.set_value("brightness",100.0)
	simulated.settings.limit_resolutions = false; simulated.load_preferences()
	check(simulated.settings.limit_resolutions,"Resolution restriction preference persists across reload")
	menu._cycle("limit_resolutions",1)
	check(not simulated.settings.limit_resolutions and simulated.resolutions().has(Vector2i(7680,4320)),"Turning restriction off restores all higher presets")
	check(menu.controls.brightness.position.y+menu.controls.brightness.size.y < menu.back.position.y and menu.back.position.y+menu.back.size.y <= menu.status.position.y and menu.status.position.y+menu.status.size.y <= menu.layout.size.y,"Added toggle leaves Brightness, Back and status rows separate within the menu")
	menu.graphics = graphics
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	press(menu,"menu_cancel"); check(not menu.visible and front.buttons.graphics.has_focus(),"Back restores Graphics option focus")
	paused = false; game.free(); Engine.max_fps = 0
	print("Graphics menu: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
