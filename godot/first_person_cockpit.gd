extends Node3D
## Optional camera-local geometry; it never enters the world collision/map data.
const RENDER_LAYER := 1 << 19
const Mods = preload("res://mod_registry.gd")
const Modern = preload("res://modern_model.gd")
const CONTROLS := [
	["scratch_count","Scratch count",0.0,12.0,1.0],
	["scratch_strength","Scratch brightness",0.0,2.0,0.01],
	["scratch_length","Scratch length",0.01,0.3,0.005],
	["scratch_width","Scratch width",0.0002,0.004,0.0001],
	["reflection_strength","Reflection strength",0.0,2.0,0.01],
	["inner_reflection_mix","Inner reflection",0.0,1.0,0.01],
	["roughness_value","Glass roughness",0.05,0.8,0.01],
	["grime_strength","Dirt and smudges",0.0,2.0,0.01],
	["refraction_strength","Curved-edge distortion",0.0,2.0,0.01],
	["edge_tint","Edge tint",0.0,2.0,0.01],
	["tint_red","Glass red",0.0,1.0,0.01],
	["tint_green","Glass green",0.0,1.0,0.01],
	["tint_blue","Glass blue",0.0,1.0,0.01],
	["reflection_resolution","Reflection resolution",64.0,512.0,64.0],
	["reflection_range","Reflection distance",5.0,100.0,1.0]]
const DEFAULTS := {"scratch_count":4.0,"scratch_strength":0.4,"scratch_length":0.12,"scratch_width":0.0008,"reflection_strength":0.4,"inner_reflection_mix":0.75,"roughness_value":0.14,"grime_strength":0.08,"refraction_strength":0.0,"edge_tint":0.025,"tint_red":0.82,"tint_green":0.94,"tint_blue":0.96,"reflection_resolution":256.0,"reflection_range":40.0}
var game: Node
var model: Node3D
var refraction_layer: CanvasLayer
var reflections: Node
var settings := DEFAULTS.duplicate()
var pack_id := ""
var glass_materials: Array[ShaderMaterial] = []

static func create_refraction(strength: float, tint: float) -> CanvasLayer:
	var layer := CanvasLayer.new(); layer.name = "CanopyRefraction"; layer.layer = -1
	# Copy after all 3D transparency, before the HUD. Bubbles and particles are
	# refracted with the world, while instruments and messages remain sharp.
	var copy := BackBufferCopy.new(); copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT; layer.add_child(copy)
	var pane := ColorRect.new(); pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pane); pane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new(); material.shader = preload("res://cockpit_refraction.gdshader")
	material.set_shader_parameter("refraction_strength",strength); material.set_shader_parameter("edge_tint",tint)
	pane.material = material
	return layer

func setup(context: Node) -> void:
	game = context; name = "FirstPersonCockpit"; process_mode = Node.PROCESS_MODE_ALWAYS
	for descriptor in Mods.candidates("cockpit.first_person"):
		var candidate := Modern.load_model(descriptor.path,descriptor) if str(descriptor.path).get_extension().to_lower() == "glb" else preload("res://clump_loader.gd").load_clump(descriptor.path)
		if candidate == null:
			Mods.note("%s: could not load first-person cockpit; trying the next mod." % descriptor.name); continue
		if str(descriptor.path).get_extension().to_lower() == "dff": candidate.scale *= float(descriptor.scale)
		model = candidate; add_child(model)
		pack_id = str(descriptor.pack); settings.merge(descriptor.get("glass",{}),true)
		var roles: Dictionary = model.get_meta("submarine_parts",{})
		var glass_part: Node = model.get_node_or_null(NodePath(str(roles.get("glass","")))) if roles.has("glass") else null
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			mesh.layers = RENDER_LAYER; mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mesh == glass_part or mesh.name.begins_with("Canopy_Glass"):
				var original := mesh.get_active_material(0) as StandardMaterial3D
				var glass := ShaderMaterial.new(); glass.shader = preload("res://cockpit_glass.gdshader")
				if original != null:
					if glass_materials.is_empty():
						settings.tint_red = original.albedo_color.r; settings.tint_green = original.albedo_color.g; settings.tint_blue = original.albedo_color.b
						settings.roughness_value = float(descriptor.get("glass",{}).get("roughness_value",clampf(original.roughness,0.05,0.8)))
					glass.set_shader_parameter("glass_tint",Vector3(original.albedo_color.r,original.albedo_color.g,original.albedo_color.b))
					glass.set_shader_parameter("roughness_value",clampf(original.roughness,0.05,0.8))
				for key in descriptor.get("glass",{}):
					if key not in ["refraction_strength","edge_tint"]: glass.set_shader_parameter(key,descriptor.glass[key])
				mesh.material_override = glass
				glass_materials.append(glass)
		game.natural_light.attach(model)
		var preferences := ConfigFile.new()
		if preferences.load(preload("res://current_settings.gd").path("view_defaults.cfg")) == OK:
			for row in CONTROLS:
				var saved: Variant = preferences.get_value("view","canopy/" + pack_id + "/" + row[0],settings[row[0]])
				if (saved is float or saved is int) and is_finite(float(saved)): settings[row[0]] = clampf(float(saved),row[2],row[3])
		if preferences.load(preload("res://current_settings.gd").path("canopy.cfg")) == OK:
			for row in CONTROLS:
				var saved: Variant = preferences.get_value(pack_id,row[0],settings[row[0]])
				if (saved is float or saved is int) and is_finite(float(saved)): settings[row[0]] = clampf(float(saved),row[2],row[3])
		if not glass_materials.is_empty():
			reflections = preload("res://canopy_reflections.gd").new(); add_child(reflections)
			reflections.setup(get_world_3d(),glass_materials,game.camera)
		refraction_layer = create_refraction(float(settings.refraction_strength),float(settings.edge_tint)); add_child(refraction_layer)
		_apply_settings()
		break
	refresh()

func set_setting(key: String, value: float) -> void:
	for row in CONTROLS:
		if row[0] != key: continue
		settings[key] = snappedf(clampf(value,row[2],row[3]),row[4]); _apply_settings(); return

func persist_settings() -> Error:
	if not game.remember_preferences: return OK
	var path := preload("res://current_settings.gd").path("canopy.cfg")
	var preferences := ConfigFile.new(); preferences.load(path)
	for key in settings: preferences.set_value(pack_id,key,settings[key])
	return preferences.save(path)

func _apply_settings() -> void:
	for material in glass_materials:
		for key in settings:
			if key in ["refraction_strength","edge_tint","tint_red","tint_green","tint_blue","reflection_resolution","reflection_range"]: continue
			material.set_shader_parameter(key,settings[key])
		material.set_shader_parameter("glass_tint",Vector3(settings.tint_red,settings.tint_green,settings.tint_blue))
	if refraction_layer != null:
		var material: ShaderMaterial = refraction_layer.get_child(1).material
		material.set_shader_parameter("refraction_strength",settings.refraction_strength); material.set_shader_parameter("edge_tint",settings.edge_tint)
	if reflections != null: reflections.configure(int(settings.reflection_resolution),float(settings.reflection_range),game.camera)

func refresh() -> void:
	visible = model != null and game.first_person and game.pilot_mode and not game.world_loading and not game.pilot.dead and not game.dock_interface_active and not game.map_open and not game.front_end.menu_layer.visible and game.camera.current
	if refraction_layer != null: refraction_layer.visible = visible

func _process(delta: float) -> void:
	refresh()
	if reflections != null: reflections.update_capture(delta,visible,game.camera)
