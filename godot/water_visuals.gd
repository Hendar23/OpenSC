extends RefCounted
const DEFAULTS := {"caustics_strength":0.5,"caustics_size":2.0,"caustics_speed":0.6,"caustics_depth":18.0,"wave_height":0.04,"wave_size":4.0,"wave_speed":0.8,"wave_direction":25.0,"surface_shine":0.35}
const PlantShader = preload("res://plant_current.gdshader")
var settings := DEFAULTS.duplicate()
var texture: NoiseTexture2D
var materials := {}
var caustic_passes: Array[Dictionary] = []
var caustics_active := true
var sun_above_water := true
var surface: ShaderMaterial
static var globals_registered := false

func _init() -> void:
	preload("res://natural_light.gd").ensure_globals()
	if not globals_registered:
		for key in ["caustics_strength","caustics_size","caustics_speed","caustics_depth","wave_speed","wave_direction","caustics_visibility","caustics_fog_start","caustics_fog_curve"]:
			RenderingServer.global_shader_parameter_add("osc_" + key,RenderingServer.GLOBAL_VAR_TYPE_FLOAT,0.0)
		RenderingServer.global_shader_parameter_add("osc_water_height",RenderingServer.GLOBAL_VAR_TYPE_FLOAT,0.0)
		RenderingServer.global_shader_parameter_add("osc_sun_direction",RenderingServer.GLOBAL_VAR_TYPE_VEC3,Vector3.UP)
		RenderingServer.global_shader_parameter_add("osc_caustics_texture",RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,null)
		globals_registered = true
	# Low-frequency clouds produce soft pools of light, rather than cell edges.
	var noise := FastNoiseLite.new(); noise.seed = 719; noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM; noise.fractal_octaves = 2; noise.fractal_gain = 0.35
	noise.frequency = 0.012
	var gradient := Gradient.new()
	gradient.set_color(0,Color.BLACK); gradient.set_color(1,Color.WHITE)
	gradient.add_point(0.35,Color.BLACK); gradient.add_point(0.7,Color.WHITE)
	texture = NoiseTexture2D.new(); texture.width = 512; texture.height = 512; texture.seamless = true; texture.normalize = true
	texture.noise = noise; texture.color_ramp = gradient
	RenderingServer.global_shader_parameter_set("osc_caustics_texture",texture)
	configure({})
	fog(250.0,5.0,1.8)

func fog(visibility: float, start: float, curve: float) -> void:
	RenderingServer.global_shader_parameter_set("osc_caustics_visibility",visibility)
	RenderingServer.global_shader_parameter_set("osc_caustics_fog_start",start)
	RenderingServer.global_shader_parameter_set("osc_caustics_fog_curve",curve)

func configure(values: Dictionary) -> void:
	settings.merge(values,true)
	_update_caustics()
	for key in ["caustics_strength","caustics_size","caustics_speed","caustics_depth","wave_speed","wave_direction"]:
		RenderingServer.global_shader_parameter_set("osc_" + key,deg_to_rad(float(settings[key])) if key == "wave_direction" else settings[key])
	if surface != null:
		for key in ["wave_height","wave_size","wave_speed","wave_direction","surface_shine"]:
			surface.set_shader_parameter(key,deg_to_rad(float(settings[key])) if key == "wave_direction" else settings[key])

func lighting(height: float, direction: Vector3) -> void:
	sun_above_water = direction.y > 0.01
	_update_caustics()
	RenderingServer.global_shader_parameter_set("osc_water_height",height)
	RenderingServer.global_shader_parameter_set("osc_sun_direction",direction)
	if surface != null: surface.set_shader_parameter("sun_direction",direction)

func reset_materials() -> void:
	materials.clear(); caustic_passes.clear()

func _update_caustics() -> void:
	var enabled := float(settings.caustics_strength) > 0.0 and sun_above_water
	if enabled == caustics_active: return
	caustics_active = enabled
	for binding in caustic_passes:
		for owner_ref in binding.owners:
			var owner: Material = owner_ref.get_ref()
			if owner != null: owner.next_pass = binding.overlay if enabled else binding.overlay.next_pass

func attach(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for index in range(node.mesh.get_surface_count()):
			var original: Material = node.get_active_material(index)
			if original == null or original.get_meta("caustics_attached",false): continue
			var plant: bool = original is ShaderMaterial and original.shader == PlantShader
			if not original is StandardMaterial3D and not plant: continue
			if original is StandardMaterial3D and original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA: continue
			var material: Material = original if plant else materials.get(original.get_instance_id())
			if material == null: material = original.duplicate(); materials[original.get_instance_id()] = material
			if not material.get_meta("caustics_attached",false):
				var overlay := ShaderMaterial.new(); overlay.shader = preload("res://caustics.gdshader")
				overlay.set_shader_parameter("is_plant",plant)
				if plant:
					for parameter in original.shader.get_shader_uniform_list(): overlay.set_shader_parameter(parameter.name,original.get_shader_parameter(parameter.name))
				elif original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					overlay.set_shader_parameter("alpha_cutout",original.albedo_texture != null)
					overlay.set_shader_parameter("alpha_texture",original.albedo_texture)
					overlay.set_shader_parameter("alpha_threshold",original.alpha_scissor_threshold)
				if plant:
					overlay.set_shader_parameter("alpha_cutout",original.get_shader_parameter("has_texture"))
					overlay.set_shader_parameter("alpha_texture",original.get_shader_parameter("albedo_texture"))
				overlay.next_pass = material.next_pass
				var owners := [weakref(material)]
				material.set_meta("caustics_owners",owners)
				material.set_meta("caustics_overlay",overlay)
				caustic_passes.append({"owners":owners,"overlay":overlay})
				material.next_pass = overlay if caustics_active else overlay.next_pass
				material.set_meta("caustics_attached",true)
			node.set_surface_override_material(index,material)
			if node.material_override != null:
				node.material_override = material
	for child in node.get_children(): attach(child)

func sync_plants(current: RefCounted) -> void:
	for patch in current.patches:
		for material in patch.materials.duplicate():
			var overlay: Material = material.get_meta("caustics_overlay",null)
			if overlay != null:
				patch.materials.append(overlay); current.materials.append(overlay)
	current.configure({})
