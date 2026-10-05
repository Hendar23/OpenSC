extends RefCounted
const DEFAULTS := {"sun_depth":25.0,"sun_falloff":20.0,"cave_ambient":0.03}
static var registered := false
static var transparent_shader: Shader
var settings := DEFAULTS.duplicate()
var image: Image
var bounds := AABB()
var surface := 0.0
var materials := {}
var light_slices: Array[Image] = []
var light_volume: ImageTexture3D
func _init() -> void:
	ensure_globals()
static func ensure_globals() -> void:
	if registered: return
	registered = true
	RenderingServer.global_shader_parameter_add("osc_cave_ambient",RenderingServer.GLOBAL_VAR_TYPE_FLOAT,0.03)
	RenderingServer.global_shader_parameter_add("osc_sky_volume",RenderingServer.GLOBAL_VAR_TYPE_SAMPLER3D,null)
	RenderingServer.global_shader_parameter_add("osc_volume_min",RenderingServer.GLOBAL_VAR_TYPE_VEC3,Vector3.ZERO)
	RenderingServer.global_shader_parameter_add("osc_volume_size",RenderingServer.GLOBAL_VAR_TYPE_VEC3,Vector3.ONE)
	for entry in [["osc_natural_enabled",RenderingServer.GLOBAL_VAR_TYPE_BOOL,false],["osc_overhead",RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,null],["osc_overhead_bounds",RenderingServer.GLOBAL_VAR_TYPE_VEC4,Vector4(0,0,1,1)],["osc_overhead_pixel",RenderingServer.GLOBAL_VAR_TYPE_VEC2,Vector2.ONE],["osc_natural_surface",RenderingServer.GLOBAL_VAR_TYPE_FLOAT,0.0],["osc_sun_depth",RenderingServer.GLOBAL_VAR_TYPE_FLOAT,25.0],["osc_sun_falloff",RenderingServer.GLOBAL_VAR_TYPE_FLOAT,20.0],["osc_natural_ambient",RenderingServer.GLOBAL_VAR_TYPE_VEC4,Vector4(1,1,1,0.3)],["osc_natural_fog_color",RenderingServer.GLOBAL_VAR_TYPE_VEC4,Vector4.ZERO],["osc_natural_fog",RenderingServer.GLOBAL_VAR_TYPE_VEC3,Vector3(1000000,0,1)]]:
		RenderingServer.global_shader_parameter_add(entry[0],entry[1],entry[2])
static func alpha_shader() -> Shader:
	if transparent_shader == null:
		transparent_shader = Shader.new(); transparent_shader.code = preload("res://natural_surface.gdshader").code.replace("// ALPHA_OUTPUT","ALPHA = color.a * opacity;")
	return transparent_shader
static func billboard_material(texture: Texture2D) -> ShaderMaterial:
	ensure_globals()
	var material := ShaderMaterial.new(); material.shader = alpha_shader()
	material.set_shader_parameter("billboard",true); material.set_shader_parameter("has_texture",true); material.set_shader_parameter("albedo_texture",texture)
	material.set_shader_parameter("alpha_threshold",0.001); material.set_shader_parameter("roughness_value",1.0); material.set_shader_parameter("specular_value",0.0)
	material.set_shader_parameter("use_vertex_color",true)
	return material
static func channel_mask(channel: int) -> Vector4:
	if channel == BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: return Vector4(0.333333,0.333333,0.333333,0)
	var mask := Vector4.ZERO; mask[clampi(channel,0,3)] = 1; return mask
func configure(values: Dictionary) -> void:
	settings.merge(values,true)
	for key in DEFAULTS: RenderingServer.global_shader_parameter_set("osc_" + key,settings[key])
func build(world: Node3D, progress: Callable = Callable(), resolution: int = 512) -> void:
	bounds = world.get_meta("bounds"); surface = world.get_meta("surface_height")
	image = Image.create(resolution,resolution,false,Image.FORMAT_RF)
	var space := world.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.new(); ray.collision_mask = 1; ray.hit_back_faces = true
	for z in range(resolution):
		for x in range(resolution):
			var point := Vector3(bounds.position.x + (x + 0.5) * bounds.size.x / resolution,surface + 0.1,bounds.position.z + (z + 0.5) * bounds.size.z / resolution)
			ray.from = point; ray.to = Vector3(point.x,bounds.position.y - 2,point.z)
			var hit := space.intersect_ray(ray)
			image.set_pixel(x,z,Color(float(hit.position.y) if not hit.is_empty() else bounds.position.y - 100,0,0))
		if z % 16 == 0:
			if progress.is_valid(): progress.call("Checking sunlight shelter: %d%%" % (z * 100 / resolution))
			await world.get_tree().process_frame
	RenderingServer.global_shader_parameter_set("osc_overhead",ImageTexture.create_from_image(image))
	RenderingServer.global_shader_parameter_set("osc_overhead_bounds",Vector4(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z))
	RenderingServer.global_shader_parameter_set("osc_overhead_pixel",Vector2.ONE / resolution)
	RenderingServer.global_shader_parameter_set("osc_natural_surface",surface)
	# Only terrain can enclose a cave. Buildings and bridges retain outdoor
	# ambient light and use the ordinary sun shadow map.
	light_slices.clear()
	var dimensions := Vector3i(128,64,96)
	var volume_size := Vector3(bounds.size.x,surface - bounds.position.y,bounds.size.z)
	ray.collision_mask = 16
	ray.hit_back_faces = false # Ground backfaces must not become cave roofs.
	for z in range(dimensions.z):
		var slice := Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_R8)
		for y in range(dimensions.y):
			for x in range(dimensions.x):
				var point := bounds.position + (Vector3(x,y,z) + Vector3.ONE * 0.5) / Vector3(dimensions) * volume_size
				ray.from = point; ray.to = Vector3(point.x,surface + 0.2,point.z)
				var ceiling := space.intersect_ray(ray)
				# Steep cliff faces do not form enclosed ceilings. Counting them
				# as roofs let coarse voxels wrap cave darkness around ridges.
				var exposed: bool = ceiling.is_empty() or ceiling.normal.y > -0.4
				slice.set_pixel(x,y,Color.WHITE if exposed else Color.BLACK)
		light_slices.append(slice)
		if z % 4 == 0:
			if progress.is_valid(): progress.call("Checking cave light: %d%%" % (z * 100 / dimensions.z))
			await world.get_tree().process_frame
	light_volume = ImageTexture3D.new()
	light_volume.create(Image.FORMAT_R8,dimensions.x,dimensions.y,dimensions.z,false,light_slices)
	RenderingServer.global_shader_parameter_set("osc_sky_volume",light_volume)
	RenderingServer.global_shader_parameter_set("osc_volume_min",bounds.position)
	RenderingServer.global_shader_parameter_set("osc_volume_size",volume_size)
	RenderingServer.global_shader_parameter_set("osc_natural_enabled",true)
	configure({})
func visibility(point: Vector3, fog: bool = false) -> float:
	var light := 1.0 - smoothstep(float(settings.sun_depth),float(settings.sun_depth + settings.sun_falloff),maxf(0,surface - point.y))
	if image == null: return light
	var uv := Vector2((point.x - bounds.position.x) / bounds.size.x,(point.z - bounds.position.z) / bounds.size.z)
	if uv.x < 0 or uv.y < 0 or uv.x > 1 or uv.y > 1: return light
	if light_slices.is_empty(): return light
	var location := (point - bounds.position) / Vector3(bounds.size.x,surface - bounds.position.y,bounds.size.z)
	if location.y < 0 or location.y > 1: return light
	var dimensions := Vector3i(light_slices[0].get_width(),light_slices[0].get_height(),light_slices.size())
	var grid := location * Vector3(dimensions) - Vector3.ONE * 0.5
	var cell := Vector3i(grid.floor()); var blend := grid - Vector3(cell)
	var exposure := 0.0
	for dz in range(2):
		for dy in range(2):
			for dx in range(2):
				var sample_cell := cell + Vector3i(dx,dy,dz)
				var value := light_slices[clampi(sample_cell.z,0,dimensions.z - 1)].get_pixel(clampi(sample_cell.x,0,dimensions.x - 1),clampi(sample_cell.y,0,dimensions.y - 1)).r
				var weight := (blend.x if dx else 1.0 - blend.x) * (blend.y if dy else 1.0 - blend.y) * (blend.z if dz else 1.0 - blend.z)
				exposure += value * weight
	# Darkness requires a well-enclosed neighbourhood; mixed edge samples
	# retain outdoor ambient instead of projecting dark bands onto slopes.
	# Fog fades sooner under a mixed roof edge, without dimming surface light.
	return light * smoothstep(0.35,0.95,exposure) if fog else light * smoothstep(0.05,0.4,exposure)

func lighting(environment: Environment, fog_end: float, fog_start: float, fog_curve: float) -> void:
	var ambient := environment.ambient_light_color
	RenderingServer.global_shader_parameter_set("osc_natural_ambient",Vector4(ambient.r,ambient.g,ambient.b,environment.ambient_light_energy))
	var fog := environment.fog_light_color
	RenderingServer.global_shader_parameter_set("osc_natural_fog_color",Vector4(fog.r,fog.g,fog.b,1))
	RenderingServer.global_shader_parameter_set("osc_natural_fog",Vector3(fog_end if environment.fog_enabled else 1000000,fog_start,fog_curve))
func attach(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for index in range(node.mesh.get_surface_count()):
			var plant := node.get_active_material(index) as ShaderMaterial
			if plant != null and plant.shader == preload("res://plant_current.gdshader"):
				var parameters := {}
				for parameter in plant.shader.get_shader_uniform_list(): parameters[parameter.name] = plant.get_shader_parameter(parameter.name)
				plant.shader = preload("res://natural_plant.gdshader")
				for key in parameters: plant.set_shader_parameter(key,parameters[key])
				continue
			var original := node.get_active_material(index) as StandardMaterial3D
			if original == null or original.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: continue
			var material: ShaderMaterial = materials.get(original.get_instance_id())
			if material == null:
				material = ShaderMaterial.new(); material.shader = preload("res://natural_surface.gdshader")
				if original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
					material.shader = alpha_shader()
				for entry in [["albedo_color",original.albedo_color],["has_texture",original.albedo_texture != null],["albedo_texture",original.albedo_texture],["use_vertex_color",original.vertex_color_use_as_albedo],["roughness_value",original.roughness],["metallic_value",original.metallic],["specular_value",original.metallic_specular],["uv_scale",original.uv1_scale],["uv_offset",original.uv1_offset]]: material.set_shader_parameter(entry[0],entry[1])
				material.set_shader_parameter("alpha_threshold",original.alpha_scissor_threshold if original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.0)
				material.set_shader_parameter("has_normal_texture",original.normal_enabled and original.normal_texture != null); material.set_shader_parameter("normal_texture",original.normal_texture); material.set_shader_parameter("normal_scale",original.normal_scale)
				material.set_shader_parameter("has_roughness_texture",original.roughness_texture != null); material.set_shader_parameter("roughness_texture",original.roughness_texture); material.set_shader_parameter("roughness_channel",channel_mask(original.roughness_texture_channel))
				material.set_shader_parameter("has_metallic_texture",original.metallic_texture != null); material.set_shader_parameter("metallic_texture",original.metallic_texture); material.set_shader_parameter("metallic_channel",channel_mask(original.metallic_texture_channel))
				if original.emission_enabled:
					material.set_shader_parameter("emission_color",original.emission * original.emission_energy_multiplier)
					material.set_shader_parameter("has_emission_texture",original.emission_texture != null); material.set_shader_parameter("emission_texture",original.emission_texture)
				material.next_pass = original.next_pass; material.set_meta("natural_original",original); materials[original.get_instance_id()] = material
			node.set_surface_override_material(index,material)
			if node.material_override != null: node.material_override = material
	for child in node.get_children(): attach(child)
