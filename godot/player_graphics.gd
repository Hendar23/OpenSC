extends Node

const Storage = preload("res://player_storage.gd")
const DEFAULTS := {"display_mode":0,"resolution":Vector2i.ZERO,"limit_resolutions":false,"vsync":true,"frame_limit":0,"anti_aliasing":0,"shadows":2,"reflective_canopies":true,"brightness":100.0}
const FRAME_LIMITS := [0,30,60,90,120,144,165,240]
const RESOLUTIONS := [
	Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(1920,1200),
	Vector2i(2560,1080),Vector2i(2560,1440),Vector2i(2560,1600),Vector2i(3440,1440),
	Vector2i(3840,1600),Vector2i(3840,2160),Vector2i(5120,1440),Vector2i(5120,2160),
	Vector2i(5120,2880),Vector2i(7680,2160),Vector2i(7680,4320),
]
signal changed
var settings := DEFAULTS.duplicate()
var remember_preferences := true
var settings_path := ""
var brightness_material: ShaderMaterial

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if settings_path.is_empty(): settings_path = Storage.preferences_path()
	settings.resolution = desktop_size()
	if remember_preferences: load_preferences()
	_validate()
	var layer := CanvasLayer.new(); layer.layer = -1; add_child(layer)
	var screen := ColorRect.new(); screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); layer.add_child(screen)
	brightness_material = ShaderMaterial.new(); brightness_material.shader = preload("res://player_brightness.gdshader")
	screen.material = brightness_material
	if remember_preferences: apply_display()
	get_tree().node_added.connect(_configure_viewport)
	get_window().size_changed.connect(_apply_resolution)
	apply_rendering()

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		for key in DEFAULTS:
			if config.has_section_key("graphics",key): settings[key] = config.get_value("graphics",key)
	_validate()

func desktop_size() -> Vector2i:
	var size := DisplayServer.screen_get_size(get_window().current_screen)
	return size if size.x >= 1050 and size.y >= 600 else Vector2i(1280,720)

func resolutions() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var desktop := desktop_size()
	for value in RESOLUTIONS + [desktop,settings.resolution]:
		if settings.limit_resolutions and (value.x > desktop.x or value.y > desktop.y): continue
		if value not in result: result.append(value)
	result.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return result

func _validate() -> void:
	for key in ["display_mode","anti_aliasing","shadows"]:
		settings[key] = clampi(int(settings[key]),0,3 if key != "display_mode" else 2)
	settings.reflective_canopies = bool(settings.reflective_canopies)
	settings.vsync = bool(settings.vsync)
	settings.limit_resolutions = bool(settings.limit_resolutions)
	if int(settings.frame_limit) not in FRAME_LIMITS: settings.frame_limit = 0
	if not settings.resolution is Vector2i: settings.resolution = desktop_size()
	settings.resolution = settings.resolution.clamp(Vector2i(1050,600),RESOLUTIONS.back().max(desktop_size()))
	if settings.limit_resolutions: settings.resolution = settings.resolution.min(desktop_size())
	for key in ["brightness"]:
		var value := float(settings[key])
		settings[key] = clampf(value,50.0,150.0) if is_finite(value) else 100.0

func set_value(key: String,value: Variant) -> Error:
	if not settings.has(key): return ERR_INVALID_PARAMETER
	var previous_resolution: Vector2i = settings.resolution
	settings[key] = value; _validate()
	if key in ["display_mode","resolution"] or settings.resolution != previous_resolution: apply_display()
	apply_rendering(); changed.emit()
	if not remember_preferences: return OK
	var config := ConfigFile.new(); var result := config.load(settings_path)
	if result != OK and result != ERR_FILE_NOT_FOUND: return result
	for setting in settings: config.set_value("graphics",setting,settings[setting])
	if config.has_section_key("graphics","hud_scale"): config.erase_section_key("graphics","hud_scale")
	result = Storage.ensure_parent(settings_path)
	return config.save(settings_path) if result == OK else result

func apply_display() -> void:
	var window := get_window()
	var mode := int(settings.display_mode)
	window.mode = Window.MODE_WINDOWED
	window.borderless = mode == 1
	if mode == 2:
		# Keep the selected preset visible, while fitting the actual window to
		# the monitor when its physical display is smaller than that preset.
		window.size = settings.resolution.min(desktop_size())
		var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
		window.position = usable.position + (usable.size - window.size) / 2
	else:
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if mode == 0 else Window.MODE_FULLSCREEN
	# Rasterize menus and HUD at the actual window size. Only the 3D scene
	# uses the selected render resolution, so reducing it cannot blur text.
	window.content_scale_size = Vector2i(1280,720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_apply_resolution()

func _apply_resolution() -> void:
	var size := Vector2(get_window().size)
	var resolution := Vector2(settings.resolution)
	get_viewport().scaling_3d_scale = clampf(minf(resolution.x / maxf(size.x,1.0),resolution.y / maxf(size.y,1.0)),0.1,1.0)

func apply_rendering() -> void:
	preload("res://exterior_reflections.gd").ensure_globals()
	RenderingServer.global_shader_parameter_set("osc_exterior_enabled",settings.reflective_canopies)
	get_tree().call_group("exterior_canopy_reflections","set_enabled",settings.reflective_canopies)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED,get_window().get_window_id())
	Engine.max_fps = int(settings.frame_limit)
	_configure_viewport(get_viewport())
	for viewport in get_parent().get_parent().find_children("*","SubViewport",true,false): _configure_viewport(viewport)
	RenderingServer.directional_shadow_atlas_set_size([256,1024,2048,4096][int(settings.shadows)],true)
	brightness_material.set_shader_parameter("brightness",float(settings.brightness) / 100.0)

func _configure_viewport(node: Node) -> void:
	if not node is Viewport: return
	if node.get_meta("exterior_capture",false):
		node.msaa_3d = Viewport.MSAA_DISABLED; node.positional_shadow_atlas_size = 0
		return
	node.msaa_3d = int(settings.anti_aliasing)
	node.positional_shadow_atlas_size = [0,1024,2048,4096][int(settings.shadows)]

func apply_sun(sun: DirectionalLight3D) -> void:
	sun.shadow_enabled = int(settings.shadows) > 0
	sun.directional_shadow_max_distance = [0.0,45.0,90.0,120.0][int(settings.shadows)]
