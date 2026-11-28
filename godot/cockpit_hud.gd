extends CanvasLayer

const Assets = preload("res://clump_loader.gd")
const Modern = preload("res://modern_model.gd")
const Mods = preload("res://mod_registry.gd")
const Display = preload("res://hud_display.gd")
const Map = preload("res://hud_map.gd")
const SideMonitors = preload("res://cockpit_side_monitors.gd")
const HUD_WIDTH := 641.0
const HUD_REFERENCE_SIZE := Vector2(1280.0, 720.0)
const MODEL_PIXELS_PER_UNIT := 3
const MOUNT_DEPTH := 0.075
const MOUNT_REFERENCE_FOV := 75.0
const MOUNT_UNITS_PER_PIXEL := 2.0 * MOUNT_DEPTH * tan(deg_to_rad(MOUNT_REFERENCE_FOV) * 0.5) / HUD_REFERENCE_SIZE.y
const INSTRUMENT_TILT := deg_to_rad(24.0)
const INSTRUMENT_SCALE := 0.96
const INSTRUMENT_TOP_MARGIN := 4.0
const DEFINITIONS := [
	{"id": "tilt", "frame": "ATTITUDE", "mask": "MATTITUD", "size": Vector2(94,100), "screen": Rect2(17,37,48,48)},
	{"id": "equipment", "frame": "TOOLS", "mask": "MTOOLS", "size": Vector2(130,94), "screen": Rect2(42,18,68,48)},
	{"id": "map", "frame": "MAPROV", "mask": "MMAPROV", "size": Vector2(176,122), "screen": Rect2(24,18,128,82)},
	{"id": "weapon", "frame": "WEAPON", "mask": "MWEAPON", "size": Vector2(123,90), "screen": Rect2(19,18,64,48)},
	{"id": "shield", "frame": "ATTITUDE", "mask": "MATTITUD", "size": Vector2(94,100), "screen": Rect2(17,37.5,48,48)}
]
var enabled: Array[bool] = [true,true,true,true,true]
var instruments: Array[Control] = []
var displays: Array[Control] = []
var model_views: Array[SubViewport] = []
var slide_tweens: Array[Tween] = [null,null,null,null,null]
var map_data := Map.new()
var holder: Control
var mounted_root: Node3D
var mounted_panels: Array[Node3D] = []
var mounted_sprites: Array[SubViewport] = []
var side_monitors: Node3D
var map_zoom := 2.0:
	set(value):
		map_zoom = clampf(value,0.5,4.0)
		map_data.npc_view_span = Vector2(140.0 / map_zoom,140.0 / map_zoom * 82.0 / 128.0)
		for display in displays:
			if display.kind == "map": display.map_span = 140.0 / map_zoom
var pilot: Node3D
var equipment: Node3D
var weapons: Node3D
var lighting_environment: Environment
var sunlight: DirectionalLight3D
var lighting_elapsed := 1.0
var sunlight_visible := true
var natural_light: RefCounted
var bottom_camera_enabled := false
var bottom_view: SubViewport
var bottom_camera: Camera3D
var monitor_bottom_view: SubViewport
var monitor_bottom_camera: Camera3D
var rear_camera_enabled := false
var rear_camera: Camera3D
var rov_camera: Camera3D
var crt_reflection_strength := 0.25:
	set(value):
		crt_reflection_strength = clampf(value,0.0,1.0)
		for view in model_views:
			var glass: ShaderMaterial = view.get_meta("crt_glass")
			glass.set_shader_parameter("reflection_strength",crt_reflection_strength)
			for material: StandardMaterial3D in view.get_meta("crt_screen_materials"):
				material.clearcoat = crt_reflection_strength
				material.metallic_specular = crt_reflection_strength
				material.metallic = float(view.get_meta("crt_original_metallic")) * crt_reflection_strength

func setup_lighting(environment: Environment, light: DirectionalLight3D) -> void:
	lighting_environment = environment
	sunlight = light
	lighting_elapsed = 1.0

func _update_instrument_lighting(delta: float) -> void:
	if sunlight == null or lighting_environment == null or pilot == null: return
	lighting_elapsed += delta
	if lighting_elapsed >= 0.15:
		lighting_elapsed = 0.0
		sunlight_visible = false
		if sunlight.light_energy > 0.0:
			var start: Vector3 = pilot.global_position + pilot.global_basis * Vector3(0,0.05,-0.16)
			var query := PhysicsRayQueryParameters3D.create(start,start + sunlight.global_basis.z * 600.0,1)
			sunlight_visible = pilot.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	var natural: float = natural_light.visibility(pilot.global_position) if natural_light != null else 1.0
	var direct := sunlight.light_energy * natural if sunlight_visible else 0.0
	var ambient := lighting_environment.ambient_light_color * lighting_environment.ambient_light_energy * natural
	var cave_ambient: float = float(natural_light.settings.cave_ambient) * (1.0 - natural) if natural_light != null else 0.0
	ambient += Color(0.75,0.8,0.88) * cave_ambient
	var illumination := ambient + sunlight.light_color * direct * 0.55
	var instrument_light_basis := pilot.global_basis.inverse() * sunlight.global_basis
	var casing := Color(clampf(illumination.r,0.0,1.0),clampf(illumination.g,0.0,1.0),clampf(illumination.b,0.0,1.0))
	for display in displays: display.casing_light = casing
	if is_instance_valid(side_monitors):
		for display in side_monitors.displays: display.casing_light = casing
	for view in model_views:
		var environment: WorldEnvironment = view.get_node("InstrumentEnvironment")
		environment.environment.ambient_light_color = ambient
		environment.environment.ambient_light_energy = 1.0
		var light: DirectionalLight3D = view.get_node("InstrumentSun")
		light.basis = instrument_light_basis
		light.light_color = sunlight.light_color
		light.light_energy = direct
		var glass: ShaderMaterial = view.get_meta("crt_glass")
		var mounted := is_instance_valid(mounted_root) and mounted_root.visible
		glass.set_shader_parameter("sunlight_direction", sunlight.global_basis.z if mounted else light.basis.z)
		glass.set_shader_parameter("sunlight_color",sunlight.light_color)
		glass.set_shader_parameter("sunlight_energy",direct)

func setup(player: Node3D, mounted_equipment: Node3D, world: Node3D, folder: String, mounted_weapons: Node3D = null) -> void:
	pilot = player
	equipment = mounted_equipment
	weapons = mounted_weapons
	name = "CockpitHUD"
	layer = 0
	if map_data.texture == null: map_data.setup(world,player.collision_height() + 2.0 * player.safe_margin)
	map_data.initialize_exploration()
	map_data.bake_world(world,get_tree())
	holder = Control.new()
	# Original sprites store white RGB outside their binary alpha mask.
	# Nearest filtering avoids blending that white into visible edge pixels.
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var cache := {}
	var tilt_icon := _tilt_sprite(folder)
	for definition in DEFINITIONS:
		var display := Display.new()
		display.kind = definition.id
		if definition.id == "map": display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		display.pilot = pilot
		display.equipment = equipment
		display.weapons = weapons
		display.map_data = map_data
		display.frame = Assets._load_texture(folder, definition.frame, definition.mask, cache)
		display.sub_icon = tilt_icon
		display.shield_blue = Assets._load_texture(folder, "HBSEG", "HSEGMASK", cache)
		display.shield_orange = Assets._load_texture(folder, "HOSEG", "HSEGMASK", cache)
		display.radiation_icon = Assets._load_texture(folder, "RADIO", "RADIOM", cache)
		if definition.id == "map": display.recording_icon = Assets._load_texture(folder,"REC","RECM",cache)
		display.screen = definition.screen
		display.size = definition.size
		display.mouse_filter = Control.MOUSE_FILTER_IGNORE
		displays.append(display)
		var replacement := _model_instrument(definition, display)
		var instrument := replacement
		if instrument == null:
			instrument = Control.new()
			instrument.mouse_filter = Control.MOUSE_FILTER_IGNORE
			instrument.add_child(display)
		instrument.name = definition.id.capitalize() + "Instrument"
		holder.add_child(instrument)
		instruments.append(instrument)
	get_viewport().size_changed.connect(_layout)
	_setup_bottom_camera(world)
	visibility_changed.connect(_refresh_views)
	_layout()

func _setup_bottom_camera(world: Node3D) -> void:
	# Auxiliary cameras share one feed; only the selected one renders the world.
	bottom_view = _create_feed_view("HUDCameraFeed", world.get_world_3d())
	bottom_camera = Camera3D.new(); bottom_camera.name = "BottomCamera"
	bottom_camera.near = 0.01; bottom_camera.fov = 65
	bottom_camera.cull_mask &= ~(2 | preload("res://first_person_cockpit.gd").RENDER_LAYER) # Hull/tools/canopy stay out of auxiliary feeds.
	bottom_view.add_child(bottom_camera); bottom_camera.current = true
	rear_camera = Camera3D.new(); rear_camera.name = "RearCamera"
	rear_camera.near = 0.01; rear_camera.fov = 65
	rear_camera.cull_mask &= ~(2 | preload("res://first_person_cockpit.gd").RENDER_LAYER)
	bottom_view.add_child(rear_camera)
	rov_camera = Camera3D.new(); rov_camera.name = "ROVCamera"
	rov_camera.near = 0.01
	rov_camera.cull_mask &= ~(preload("res://remote_vehicle.gd").RENDER_LAYER | preload("res://first_person_cockpit.gd").RENDER_LAYER)
	bottom_view.add_child(rov_camera)
	# A second viewport is needed only when the centre shows rear or ROV
	# while the dedicated bottom monitor is also in view.
	monitor_bottom_view = _create_feed_view("CockpitBottomFeed", world.get_world_3d())
	monitor_bottom_camera = bottom_camera.duplicate(0) as Camera3D
	monitor_bottom_view.add_child(monitor_bottom_camera)
	monitor_bottom_camera.make_current()
	_update_bottom_camera()
	_update_rear_camera()

func _create_feed_view(view_name: String, world: World3D) -> SubViewport:
	var view := SubViewport.new()
	view.name = view_name
	view.size = Vector2i(384, 246)
	view.world_3d = world
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.handle_input_locally = false
	add_child(view)
	return view

func set_bottom_camera_enabled(on: bool) -> void:
	bottom_camera_enabled = on
	if on:
		rear_camera_enabled = false
	_update_bottom_camera(); _refresh_views()

func set_rear_camera_enabled(on: bool) -> void:
	rear_camera_enabled = on
	if on:
		bottom_camera_enabled = false
	_update_rear_camera(); _refresh_views()

func controlled_rover() -> Node3D:
	if not is_instance_valid(equipment) or equipment.support_tools == null: return null
	var rover: Node3D = equipment.support_tools.rover
	return rover if is_instance_valid(rover) and rover.deployed and not rover.dead else null

func _refresh_camera_feed() -> void:
	var rover := controlled_rover()
	var selected: Camera3D = rov_camera if rover != null else rear_camera if rear_camera_enabled else bottom_camera if bottom_camera_enabled else null
	var alive: bool = is_instance_valid(pilot) and not pilot.dead
	var centre_active: bool = selected != null and visible and enabled[2] and instruments[2].visible and alive
	var monitor_active: bool = is_instance_valid(side_monitors) and side_monitors.seen[1] and alive
	var separate := monitor_active and centre_active and selected != bottom_camera
	var shared := bottom_camera if monitor_active and not centre_active else selected
	if shared != null and bottom_view.get_camera_3d() != shared: shared.make_current()
	bottom_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if (centre_active or monitor_active) else SubViewport.UPDATE_DISABLED
	monitor_bottom_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if separate else SubViewport.UPDATE_DISABLED
	if monitor_active:
		var display: Control = side_monitors.displays[1]
		var feed := monitor_bottom_view.get_texture() if separate else bottom_view.get_texture()
		if display.camera_feed != feed: display.set_camera_feed(feed)
	var texture: Texture2D = bottom_view.get_texture() if selected != null else null
	if displays[2].camera_feed != texture: displays[2].set_camera_feed(texture)
	displays[2].rov_recording = rover != null and rover.recording > 0
	displays[2].set_rov_interference(rover.camera_interference() if rover != null else 0.0)
	if rover == null: return
	rov_camera.global_transform = rover.camera_pose()
	var main_camera := get_viewport().get_camera_3d()
	if main_camera != null:
		rov_camera.fov = main_camera.fov; rov_camera.far = main_camera.far
		rov_camera.environment = main_camera.environment; rov_camera.attributes = main_camera.attributes

func _update_rear_camera() -> void:
	if rear_camera == null or not is_instance_valid(pilot): return
	var pose: Transform3D = pilot.get_global_transform_interpolated()
	var axes := pose.basis.orthonormalized()
	rear_camera.global_transform = Transform3D(Basis.looking_at(axes.z,axes.y),pose.origin)
	var main_camera := get_viewport().get_camera_3d()
	if main_camera != null: rear_camera.far = main_camera.far

func _update_bottom_camera() -> void:
	if bottom_camera == null or not is_instance_valid(pilot) or not is_instance_valid(equipment): return
	var intake: Node3D = equipment.vacuum
	var pose: Transform3D = intake.get_global_transform_interpolated()
	var axes := pose.basis.orthonormalized()
	# Down is intake-local -Y; the nose of the sub remains at the top of the picture.
	bottom_camera.global_transform = Transform3D(Basis.looking_at(-axes.y,-axes.z),pose.origin)
	var main_camera := get_viewport().get_camera_3d()
	if main_camera != null: bottom_camera.far = main_camera.far
	monitor_bottom_camera.global_transform = bottom_camera.global_transform
	monitor_bottom_camera.far = bottom_camera.far

func toggle(index: int) -> void:
	if index < 0 or index >= enabled.size(): return
	set_enabled(index,not enabled[index])

func set_enabled(index: int,show_panel: bool,animate: bool = true) -> void:
	if index < 0 or index >= enabled.size(): return
	enabled[index] = show_panel
	if slide_tweens[index] != null:
		slide_tweens[index].kill()
		slide_tweens[index] = null
	var instrument := instruments[index]
	var hidden_y: float = -DEFINITIONS[index].size.y - 4.0
	var target_y := 0.0 if show_panel else hidden_y
	if not animate:
		instrument.position.y = target_y
		instrument.visible = show_panel
	else:
		instrument.visible = true
		var duration := 0.3 * clampf(absf(instrument.position.y - target_y) / absf(hidden_y),0.15,1.0)
		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		slide_tweens[index] = tween
		tween.tween_property(instrument,"position:y",target_y,duration)
		tween.tween_callback(func() -> void:
			instrument.visible = enabled[index]
			slide_tweens[index] = null
		)
	_refresh_views()

func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var fit_scale := (viewport.x - 16.0) / HUD_WIDTH
	# Preserve the previous 641-pixel HUD at 1280×720, proportionally sized
	# at higher resolutions and constrained to fit narrow windows.
	var scale_factor := minf(minf(viewport.x / HUD_REFERENCE_SIZE.x,viewport.y / HUD_REFERENCE_SIZE.y),fit_scale)
	holder.position = Vector2((viewport.x - HUD_WIDTH * scale_factor) * 0.5, 0)
	holder.scale = Vector2.ONE * scale_factor
	var x := 0.0
	for i in range(instruments.size()):
		if instruments[i].get_parent() == holder:
			instruments[i].position.x = x
			instruments[i].size = DEFINITIONS[i].size
		x += DEFINITIONS[i].size.x + 6.0
	if is_instance_valid(side_monitors) and get_viewport().get_camera_3d() != null:
		side_monitors.layout(viewport, get_viewport().get_camera_3d())

func mount_instruments(cockpit: Node3D, neutral_eye: Vector3, render_layer: int) -> void:
	if not is_instance_valid(mounted_root): _setup_mounted_instruments(cockpit, neutral_eye, render_layer)
	if mounted_root.visible: return
	for i in instruments.size():
		var model_view := instruments[i].get_node_or_null("ModelViewport") as SubViewport
		if model_view != null:
			var model: Node3D = model_view.get_meta("instrument_model")
			model.reparent(mounted_panels[i], false)
			model.transform = model_view.get_meta("mounted_transform")
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				mesh.set_meta("hud_render_layers", mesh.layers)
				mesh.set_meta("hud_shadow_mode", mesh.cast_shadow)
				mesh.layers = render_layer
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			displays[i].reparent(mounted_sprites[i], false)
	holder.hide()
	mounted_root.show()
	_refresh_views()


func _setup_mounted_instruments(cockpit: Node3D, neutral_eye: Vector3, render_layer: int) -> void:
	mounted_root = Node3D.new()
	mounted_root.name = "InstrumentMounts"
	cockpit.add_child(mounted_root)
	mounted_root.hide()
	# The physical mounts use the reference HUD layout at the default seat.
	# A resize only changes how the camera projects that geometry.
	var row_x := -HUD_WIDTH * 0.5
	for i in instruments.size():
		var frame: Vector2 = DEFINITIONS[i].size
		var model_view := instruments[i].get_node_or_null("ModelViewport") as SubViewport
		var top_margin := INSTRUMENT_TOP_MARGIN if model_view != null else 0.0
		var offset := Vector2(row_x + frame.x * 0.5, (HUD_REFERENCE_SIZE.y - frame.y) * 0.5 - top_margin) * MOUNT_UNITS_PER_PIXEL
		var panel := Node3D.new()
		panel.name = "%sMount" % DEFINITIONS[i].id.capitalize()
		panel.position = neutral_eye + Vector3(offset.x, offset.y, -MOUNT_DEPTH)
		panel.set_meta("rest_height", panel.position.y)
		mounted_root.add_child(panel)
		mounted_panels.append(panel)
		if model_view != null:
			var bounds: AABB = model_view.get_meta("instrument_bounds")
			var rest: Transform3D = model_view.get_meta("instrument_transform")
			var factor := frame.y * MOUNT_UNITS_PER_PIXEL * INSTRUMENT_SCALE / model_view.get_camera_3d().size
			var front_centre := Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z)
			var basis := Basis(Vector3.RIGHT, INSTRUMENT_TILT).scaled(Vector3.ONE * factor)
			model_view.set_meta("mounted_transform", Transform3D(basis, -(basis * front_centre)) * rest)
		mounted_sprites.append(null if model_view != null else _mount_sprite(panel, frame, render_layer))
		row_x += frame.x + 6.0
	side_monitors = SideMonitors.new()
	mounted_root.add_child(side_monitors)
	side_monitors.setup(self, neutral_eye, render_layer)
	_layout()

func _mount_sprite(panel: Node3D, frame: Vector2, render_layer: int, units_per_pixel := MOUNT_UNITS_PER_PIXEL, resolution_scale := 1) -> SubViewport:
	var sprite := SubViewport.new()
	sprite.size = Vector2i((frame * resolution_scale).ceil())
	sprite.disable_3d = true
	sprite.transparent_bg = true
	sprite.render_target_update_mode = SubViewport.UPDATE_DISABLED
	panel.add_child(sprite)
	var plane := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = frame * units_per_pixel
	plane.mesh = quad
	plane.layers = render_layer
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var artwork := StandardMaterial3D.new()
	artwork.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	artwork.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	artwork.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	artwork.albedo_texture = sprite.get_texture()
	plane.material_override = artwork
	panel.add_child(plane)
	return sprite


func release_mounted_instruments() -> void:
	if not is_instance_valid(mounted_root) or not mounted_root.visible: return
	for i in instruments.size():
		var model_view := instruments[i].get_node_or_null("ModelViewport") as SubViewport
		if model_view != null:
			var model: Node3D = model_view.get_meta("instrument_model")
			model.reparent(model_view, false)
			model.transform = model_view.get_meta("instrument_transform")
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				mesh.layers = mesh.get_meta("hud_render_layers")
				mesh.cast_shadow = mesh.get_meta("hud_shadow_mode")
		else:
			displays[i].reparent(instruments[i], false)
	mounted_root.hide()
	holder.show()
	_refresh_views()

func _refresh_views() -> void:
	var mounted := is_instance_valid(mounted_root) and mounted_root.visible
	if is_instance_valid(mounted_root):
		for i in mounted_panels.size():
			var shown := mounted and visible and instruments[i].visible
			mounted_panels[i].visible = shown
			var panel := mounted_panels[i]
			var height := float(panel.get_meta("rest_height")) - instruments[i].position.y * MOUNT_UNITS_PER_PIXEL
			if panel.position.y != height: panel.position.y = height
			if mounted_sprites[i] != null:
				mounted_sprites[i].render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	if is_instance_valid(side_monitors):
		side_monitors.refresh(get_viewport().get_camera_3d(), mounted and visible)
	if bottom_view != null: _refresh_camera_feed()
	for i in range(displays.size()):
		displays[i].set_process(visible and instruments[i].visible)
	for view in model_views:
		var shown: bool = visible and view.get_parent().visible
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown and not mounted else SubViewport.UPDATE_DISABLED
		for child in view.get_children():
			if child is SubViewport: child.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED

func _process(delta: float) -> void:
	_refresh_views()
	if bottom_view != null and bottom_view.render_target_update_mode != SubViewport.UPDATE_DISABLED: _update_bottom_camera()
	if rear_camera_enabled: _update_rear_camera()
	_update_instrument_lighting(delta)
	if pilot != null:
		map_data.explore(pilot.get_global_transform_interpolated().origin + Vector3.UP * 0.05,750)

func _exit_tree() -> void:
	if is_instance_valid(mounted_root): mounted_root.queue_free()
	for tween in slide_tweens:
		if tween != null: tween.kill()
	slide_tweens.clear()

func _tilt_sprite(folder: String) -> Texture2D:
	for replacement in Mods.candidates("texture.hud_tilt"):
		var image := Assets._replacement_image(replacement.path)
		if image != null: return ImageTexture.create_from_image(image)
	# The original BMP contains the same cyan side-view sub used by the
	# attitude gauge. Extract the icon without its rectangular display border.
	var texture := Assets._load_texture(folder,"SHIELDS","MSHIELDS",{})
	if texture == null: return null
	var image := texture.get_image()
	var ratio := Vector2(image.get_size()) / Vector2(100,94)
	var icon := image.get_region(Rect2i(Vector2(25,30) * ratio,Vector2(40,26) * ratio))
	var background := image.get_pixel(int(12 * ratio.x),int(20 * ratio.y))
	for y in range(icon.get_height()):
		for x in range(icon.get_width()):
			var pixel := icon.get_pixel(x,y)
			if Vector3(pixel.r,pixel.g,pixel.b).distance_to(Vector3(background.r,background.g,background.b)) < 0.06:
				pixel.a = 0.0; icon.set_pixel(x,y,pixel)
	return ImageTexture.create_from_image(icon)

func _model_instrument(definition: Dictionary, display: Control) -> Control:
	for descriptor in Mods.candidates("hud." + str(definition.id)):
		var model := Modern.load_model(descriptor.path, descriptor)
		if model == null: continue
		var screen_mesh: MeshInstance3D
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			if mesh.name in ["Screen_Display","Dial_Display"]: screen_mesh = mesh; break
		if screen_mesh == null:
			Mods.note(String(TranslationServer.translate("%s: HUD instrument needs a Screen_Display or Dial_Display mesh; using original sprites.")) % descriptor.name)
			model.free()
			continue
		var container := Control.new()
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var view := SubViewport.new()
		view.name = "ModelViewport"
		view.size = Vector2i(definition.size * MODEL_PIXELS_PER_UNIT)
		view.own_world_3d = true
		view.transparent_bg = true
		container.add_child(view)
		model_views.append(view)
		view.add_child(model)
		var content := SubViewport.new()
		content.size = Vector2i(definition.screen.size * 3.0)
		content.disable_3d = true
		content.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.add_child(content)
		display.screen_only = true
		display.size = definition.screen.size
		display.scale = Vector2.ONE * 3.0
		content.add_child(display)
		# Retain the model's glass response; only the displayed picture emits
		# its own light. An unshaded replacement discards the CRT highlights.
		var original_material := screen_mesh.get_active_material(0) as StandardMaterial3D
		var material := original_material.duplicate() as StandardMaterial3D if original_material != null else StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		if original_material == null:
			material.albedo_color = Color(0.012,0.042,0.038)
			material.metallic = 0.12
			material.roughness = 0.22
		material.albedo_texture = content.get_texture()
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_texture = content.get_texture()
		material.emission_energy_multiplier = 1.0
		material.clearcoat_enabled = true
		material.clearcoat = 1.0
		material.clearcoat_roughness = 0.12
		material.metallic_specular = 1.0
		var glass := ShaderMaterial.new()
		glass.shader = preload("res://crt_glass.gdshader")
		glass.set_shader_parameter("reflection_strength",crt_reflection_strength)
		material.next_pass = glass
		view.set_meta("crt_glass",glass)
		view.set_meta("crt_glass_material",material)
		view.set_meta("crt_original_metallic",material.metallic)
		material.metallic *= crt_reflection_strength
		material.clearcoat = crt_reflection_strength
		material.metallic_specular = crt_reflection_strength
		screen_mesh.material_override = material
		var screen_materials: Array[StandardMaterial3D] = [material]
		var counter_mesh := model.find_child("Counter_Display",true,false) as MeshInstance3D
		if definition.id in ["equipment","weapon"] and counter_mesh != null:
			# The model's small counter is a separate screen, outside the icon UVs.
			if definition.id == "equipment": display.show_equipment_counter = false
			else: display.show_weapon_counter = false
			var counter_view := SubViewport.new(); counter_view.name = definition.id.capitalize() + "Counter"
			var counter_width := 26 if definition.id == "weapon" else 17
			counter_view.size = Vector2i(counter_width*3,30); counter_view.disable_3d = true
			counter_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; view.add_child(counter_view)
			var counter := Display.new(); counter.kind = definition.id + "_counter"; counter.pilot = pilot; counter.equipment = equipment; counter.weapons = weapons
			counter.screen_only = true; counter.size = Vector2(counter_width,10); counter.scale = Vector2.ONE * 3.0
			counter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; counter_view.add_child(counter)
			var counter_material := material.duplicate() as StandardMaterial3D
			counter_material.albedo_texture = counter_view.get_texture(); counter_material.emission_texture = counter_view.get_texture()
			counter_mesh.material_override = counter_material; screen_materials.append(counter_material)
		view.set_meta("crt_screen_materials",screen_materials)
		var boxes: Array[AABB] = []
		Assets_bounds(model, Transform3D.IDENTITY, boxes)
		var box: AABB = boxes[0]
		for b in boxes: box = box.merge(b)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(box.size.y, box.size.x / (definition.size.x / definition.size.y)) * 1.12
		var view_distance := maxf(box.size.length() * 2.0, 1.0)
		camera.position = box.get_center() + Vector3.BACK * view_distance
		view.add_child(camera)
		view.set_meta("instrument_model", model)
		view.set_meta("instrument_screen", screen_mesh)
		view.set_meta("instrument_transform", model.transform)
		view.set_meta("instrument_bounds", box)
		var environment := WorldEnvironment.new()
		environment.name = "InstrumentEnvironment"
		environment.environment = Environment.new()
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.7
		view.add_child(environment)
		var light := DirectionalLight3D.new()
		light.name = "InstrumentSun"
		light.shadow_enabled = true
		light.rotation_degrees = Vector3(-25,-25,0)
		view.add_child(light)
		var image := TextureRect.new()
		image.name = "InstrumentImage"
		image.texture = view.get_texture()
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(image)
		return container
	return null

static func Assets_bounds(node: Node3D, pose: Transform3D, boxes: Array[AABB]) -> void:
	pose *= node.transform
	if node is MeshInstance3D: boxes.append(pose * node.mesh.get_aabb())
	for child in node.get_children():
		if child is Node3D: Assets_bounds(child, pose, boxes)
