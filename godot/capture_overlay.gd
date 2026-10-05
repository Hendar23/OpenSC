extends CanvasLayer
var fps_label: Label
var last_screenshot := ""
var screenshot_label: Label
var message_time := 0.0

func _ready() -> void:
	preload("res://input_bindings.gd").install()
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	fps_label = Label.new()
	add_child(fps_label)
	fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fps_label.offset_left = -140
	fps_label.offset_right = -12
	fps_label.offset_top = 10
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	fps_label.add_theme_constant_override("shadow_offset_x",1)
	fps_label.add_theme_constant_override("shadow_offset_y",1)
	fps_label.hide()
	screenshot_label = Label.new(); add_child(screenshot_label)
	screenshot_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	screenshot_label.offset_left = -280; screenshot_label.offset_right = -12
	screenshot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	screenshot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screenshot_label.add_theme_font_size_override("font_size",14)
	screenshot_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	screenshot_label.add_theme_constant_override("shadow_offset_x",1); screenshot_label.add_theme_constant_override("shadow_offset_y",1)
	screenshot_label.hide()

func _process(delta: float) -> void:
	if fps_label.visible: fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	screenshot_label.offset_top = 10 + maxf(24,fps_label.size.y) + 4 if fps_label.visible else 10
	message_time = maxf(0,message_time - delta)
	if message_time <= 0: screenshot_label.hide()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.is_action_pressed("fps_toggle"):
		fps_label.visible = not fps_label.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("screenshot"):
		save_screenshot()
		get_viewport().set_input_as_handled()

func screenshot_folder() -> String:
	var folder := ProjectSettings.globalize_path("res://..").simplify_path() if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
	return folder.path_join("Screenshots")

func save_screenshot() -> void:
	screenshot_label.hide()
	await RenderingServer.frame_post_draw
	var folder := screenshot_folder()
	var result := DirAccess.make_dir_recursive_absolute(folder)
	if result != OK: push_warning("Cannot create screenshot folder: " + error_string(result)); return
	var stamp := Time.get_datetime_string_from_system().replace("T"," ").replace(":","-")
	var base := folder.path_join("OpenSC " + stamp)
	var path := base + ".png"
	var suffix := 2
	while FileAccess.file_exists(path):
		path = base + " (%d).png" % suffix
		suffix += 1
	result = get_viewport().get_texture().get_image().save_png(path)
	if result == OK:
		last_screenshot = path; print("Screenshot saved: " + path)
		screenshot_label.text = "Screenshot saved"; screenshot_label.show(); message_time = 2.5
	else: push_warning("Cannot save screenshot: " + error_string(result))
