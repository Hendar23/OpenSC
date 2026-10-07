extends CanvasLayer

const Assets = preload("res://clump_loader.gd")
const Modern = preload("res://modern_model.gd")
const Mods = preload("res://mod_registry.gd")
const Display = preload("res://hud_display.gd")
const Map = preload("res://hud_map.gd")
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
var scale_multiplier := 0.5:
	set(value):
		scale_multiplier = clampf(value, 0.25, 1.5)
		if holder != null: _layout()
var map_zoom := 2.0:
	set(value):
		map_zoom = clampf(value,0.5,4.0)
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
var crt_reflection_strength := 0.25:
	set(value):
		crt_reflection_strength = clampf(value,0.0,1.0)
		for view in model_views:
			var glass: ShaderMaterial = view.get_meta("crt_glass")
			glass.set_shader_parameter("reflection_strength",crt_reflection_strength)
			var material: StandardMaterial3D = view.get_meta("crt_glass_material")
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
	var casing := Color(clampf(illumination.r,0.0,1.0),clampf(illumination.g,0.0,1.0),clampf(illumination.b,0.0,1.0))
	for display in displays: display.casing_light = casing
	for view in model_views:
		var environment: WorldEnvironment = view.get_node("InstrumentEnvironment")
		environment.environment.ambient_light_color = ambient
		environment.environment.ambient_light_energy = 1.0
		var light: DirectionalLight3D = view.get_node("InstrumentSun")
		light.basis = pilot.global_basis.inverse() * sunlight.global_basis
		light.light_color = sunlight.light_color
		light.light_energy = direct
		var glass: ShaderMaterial = view.get_meta("crt_glass")
		glass.set_shader_parameter("sunlight_direction",light.basis.z)
		glass.set_shader_parameter("sunlight_color",sunlight.light_color)
		glass.set_shader_parameter("sunlight_energy",direct)

func setup(player: Node3D, mounted_equipment: Node3D, world: Node3D, folder: String, mounted_weapons: Node3D = null) -> void:
	pilot = player
	equipment = mounted_equipment
	weapons = mounted_weapons
	name = "CockpitHUD"
	layer = 0
	map_data.setup(world,player.collision_height() + 2.0 * player.safe_margin)
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
		display.screen = definition.screen
		display.size = definition.size
		display.mouse_filter = Control.MOUSE_FILTER_IGNORE
		displays.append(display)
		var replacement := _model_instrument(definition, display)
		var instrument: Control = replacement if replacement != null else display
		instrument.name = definition.id.capitalize() + "Instrument"
		holder.add_child(instrument)
		instruments.append(instrument)
	get_viewport().size_changed.connect(_layout)
	_layout()

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
	var total := 641.0
	var fit_scale := (viewport.x - 16.0) / total
	var scale_factor := minf(minf(2.0, fit_scale) * scale_multiplier, fit_scale)
	holder.position = Vector2((viewport.x - total * scale_factor) * 0.5, 0)
	holder.scale = Vector2.ONE * scale_factor
	var x := 0.0
	for i in range(instruments.size()):
		instruments[i].position.x = x
		instruments[i].size = DEFINITIONS[i].size
		x += DEFINITIONS[i].size.x + 6.0

func _refresh_views() -> void:
	for i in range(displays.size()): displays[i].set_process(visible and instruments[i].visible)
	for view in model_views:
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible and view.get_parent().visible else SubViewport.UPDATE_DISABLED
		for child in view.get_children():
			if child is SubViewport: child.render_target_update_mode = view.render_target_update_mode

func _process(delta: float) -> void:
	_refresh_views()
	_update_instrument_lighting(delta)
	if pilot != null:
		map_data.explore(pilot.get_global_transform_interpolated().origin + Vector3.UP * 0.05)

func _exit_tree() -> void:
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
			Mods.note("%s: HUD instrument needs a Screen_Display or Dial_Display mesh; using original sprites." % descriptor.name)
			model.free()
			continue
		var container := Control.new()
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var view := SubViewport.new()
		view.size = Vector2i(definition.size * 3.0)
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
		var boxes: Array[AABB] = []
		Assets_bounds(model, Transform3D.IDENTITY, boxes)
		var box: AABB = boxes[0]
		for b in boxes: box = box.merge(b)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(box.size.y, box.size.x / (definition.size.x / definition.size.y)) * 1.12
		camera.position = box.get_center() + Vector3(0,0,maxf(box.size.length() * 2.0, 1.0))
		view.add_child(camera)
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
