extends RefCounted
const DEFAULTS := {"enabled":true,"strength":0.12,"speed":0.3,"direction":0.0,"variation":0.35,"wavelength":1.5,"ripple":0.08,"twist":0.3}
var settings := DEFAULTS.duplicate()
var materials: Array[ShaderMaterial] = []
var plant_count := 0
var flexible_meshes := {}
var batch_materials := {}

func attach(parent_world: Node3D) -> void:
	materials.clear(); plant_count = 0
	# Full world replacement releases derived meshes and their source materials.
	# Scenery-only rerolls call _collect(), preserving their shared resources.
	flexible_meshes.clear()
	batch_materials.clear()
	_collect(parent_world)
	configure({})

func _collect(node: Node) -> void:
	if node is MultiMeshInstance3D and node.get_meta("marine_plant", false):
		_prepare_batch(node)
		return
	var model := str(node.get_meta("editor_model","" )).to_upper().trim_prefix("MODEL.")
	var source := str(node.get_meta("asset_source","")).get_file().get_basename().to_upper()
	if model in ["REED","BUSH1","BUSH2","BUSH3","BUSH4"] or source in ["REED","BUSH1","BUSH2","BUSH3","BUSH4"]:
		var legacy_clump: bool = not node.get_meta("modern_model",false)
		_prepare(node,legacy_clump,legacy_clump and (model == "BUSH4" or source == "BUSH4"))
		plant_count += 1
		return
	for child in node.get_children(): _collect(child)

func _prepare_batch(node: MultiMeshInstance3D) -> void:
	if node.multimesh == null or node.multimesh.mesh == null: return
	var mesh := node.multimesh.mesh
	if mesh.get_surface_count() != 1: return
	var original := mesh.surface_get_material(0) as StandardMaterial3D
	if original == null: return
	var id := mesh.get_instance_id()
	var material: ShaderMaterial = batch_materials.get(id)
	if material == null:
		material = ShaderMaterial.new(); material.shader = preload("res://plant_current.gdshader")
		material.set_shader_parameter("sway_uniform_basis", true)
		var bounds := preload("res://modern_model.gd").source_bounds(mesh)
		material.set_shader_parameter("albedo_color", original.albedo_color)
		material.set_shader_parameter("has_texture", original.albedo_texture != null)
		material.set_shader_parameter("albedo_texture", original.albedo_texture)
		material.set_shader_parameter("terrain_albedo_texture", original.albedo_texture)
		material.set_shader_parameter("terrain_mipmaps", true)
		material.set_shader_parameter("roughness_value", original.roughness)
		material.set_shader_parameter("metallic_value", original.metallic)
		material.set_shader_parameter("root_height", bounds.position.y)
		material.set_shader_parameter("plant_height", bounds.size.y)
		material.set_shader_parameter("root_center", bounds.get_center())
		batch_materials[id] = material; materials.append(material)
	node.material_override = material
	node.extra_cull_margin = maxf(mesh.get_aabb().size.y, 1.0)
	plant_count += node.multimesh.instance_count

func _prepare(node: Node, subdivide_sparse: bool, clamp_texture: bool) -> void:
	if node is MeshInstance3D:
		# Modern plants already have authored bending vertices and cached LODs.
		# Legacy-only subdivision multiplied some biome meshes by four and
		# rebuilding their surfaces also discarded the distance index buffers.
		if subdivide_sparse: node.mesh = _flexible_mesh(node.mesh)
		var bounds: AABB = preload("res://modern_model.gd").source_bounds(node.mesh)
		for surface in range(node.mesh.get_surface_count()):
			var original := node.get_active_material(surface) as StandardMaterial3D
			if original == null: continue
			var material := ShaderMaterial.new(); material.shader = preload("res://plant_current.gdshader")
			material.set_shader_parameter("albedo_color",original.albedo_color)
			material.set_shader_parameter("has_texture",original.albedo_texture != null)
			if original.albedo_texture != null:
				material.set_shader_parameter("albedo_texture",original.albedo_texture)
				var mipmaps: bool = original.get_meta("terrain_mipmaps",false)
				if mipmaps:
					material.set_shader_parameter("terrain_mipmaps",true)
					material.set_shader_parameter("terrain_albedo_texture",original.albedo_texture)
				# BUSH4's legacy UVs extend past the left edge. Repeating
				# the cutout there draws branch tips from the right edge.
				if clamp_texture:
					material.set_shader_parameter("clamp_plant_texture",true)
					var sampler := "clamped_terrain_albedo_texture" if mipmaps else "clamped_albedo_texture"
					material.set_shader_parameter(sampler,original.albedo_texture)
			material.set_shader_parameter("roughness_value",original.roughness)
			material.set_shader_parameter("metallic_value",original.metallic)
			material.set_shader_parameter("root_height",bounds.position.y)
			material.set_shader_parameter("plant_height",bounds.size.y)
			material.set_shader_parameter("root_center",bounds.get_center())
			node.set_surface_override_material(surface,material)
			# Include displaced tips in the renderer's visibility bounds.
			node.extra_cull_margin = bounds.size.length() * 2.0
			materials.append(material)
	for child in node.get_children(): _prepare(child,subdivide_sparse,clamp_texture)

func _flexible_mesh(source: Mesh) -> Mesh:
	# Share a bounded, once-built subdivision between all instances. Old plant
	# triangles need intermediate vertices for waves to curve through the leaves.
	var id := source.get_instance_id()
	if flexible_meshes.has(id): return flexible_meshes[id]
	var mesh := ArrayMesh.new()
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index in arrays[Mesh.ARRAY_VERTEX].size(): indices.append(index)
		var levels := 2 if indices.size() <= 1500 else (1 if indices.size() <= 6000 else 0)
		for level in range(levels):
			var next := []; next.resize(Mesh.ARRAY_MAX)
			for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_COLOR]:
				if arrays[channel] == null or arrays[channel].is_empty(): continue
				var values: Variant = arrays[channel].duplicate(); values.clear()
				for triangle in range(0,indices.size() - 2,3):
					var a: Variant = arrays[channel][indices[triangle]]
					var b: Variant = arrays[channel][indices[triangle + 1]]
					var c: Variant = arrays[channel][indices[triangle + 2]]
					var ab: Variant = (a + b) * 0.5; var bc: Variant = (b + c) * 0.5; var ca: Variant = (c + a) * 0.5
					for value in [a,ab,ca,ab,b,bc,ca,bc,c,ab,bc,ca]:
						values.append(value.normalized() if channel == Mesh.ARRAY_NORMAL else value)
				next[channel] = values
			arrays = next; indices = PackedInt32Array()
			for index in arrays[Mesh.ARRAY_VERTEX].size(): indices.append(index)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		mesh.surface_set_material(surface,source.surface_get_material(surface))
	flexible_meshes[id] = mesh
	return mesh

func configure(values: Dictionary) -> void:
	settings.merge(values,true)
	for material in materials:
		for key in settings:
			var value: Variant = deg_to_rad(float(settings[key])) if key == "direction" else settings[key]
			material.set_shader_parameter("sway_" + str(key),value)
