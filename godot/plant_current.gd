extends RefCounted
const DEFAULTS := {"enabled":true,"strength":0.12,"speed":0.3,"direction":0.0,"variation":0.35,"wavelength":1.5,"ripple":0.08,"twist":0.3,"wash_strength":0.65,"wash_range":4.5,"wash_recovery":1.0}
var settings := DEFAULTS.duplicate()
var materials: Array[ShaderMaterial] = []
var plant_count := 0
var patches: Array[Dictionary] = []
var world: Node3D
var flexible_meshes := {}
var batch_materials := {}
var patch_cells := {}
var indexed_patch_count := -1
var recovering := {}
const CELL_SIZE := 8.0

func attach(parent_world: Node3D) -> void:
	world = parent_world
	materials.clear(); patches.clear(); plant_count = 0
	# Full world replacement releases derived meshes and their source materials.
	# Scenery-only rerolls call _collect(), preserving their shared resources.
	flexible_meshes.clear()
	batch_materials.clear()
	patch_cells.clear(); recovering.clear(); indexed_patch_count = -1
	_collect(parent_world)
	configure({})

func _collect(node: Node) -> void:
	if node is MultiMeshInstance3D and node.get_meta("marine_plant", false):
		_prepare_batch(node)
		return
	var model := str(node.get_meta("editor_model","" )).to_upper().trim_prefix("MODEL.")
	var source := str(node.get_meta("asset_source","")).get_file().get_basename().to_upper()
	if model in ["REED","BUSH1","BUSH2","BUSH3","BUSH4"] or source in ["REED","BUSH1","BUSH2","BUSH3","BUSH4"]:
		_prepare(node,not node.get_meta("modern_model",false)); plant_count += 1
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
		var bounds := mesh.get_aabb()
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
	# Ambient sway uses each instance's model matrix. Keep these shared batches
	# out of point-based propeller wash so one nearby plant cannot bend a colony.

func _prepare(node: Node, subdivide_sparse: bool = true) -> void:
	if node is MeshInstance3D:
		# Modern plants already have authored bending vertices and cached LODs.
		# Legacy-only subdivision multiplied some biome meshes by four and
		# rebuilding their surfaces also discarded the distance index buffers.
		if subdivide_sparse: node.mesh = _flexible_mesh(node.mesh)
		var bounds: AABB = node.mesh.get_aabb()
		var patch_materials: Array[ShaderMaterial] = []
		for surface in range(node.mesh.get_surface_count()):
			var original := node.get_active_material(surface) as StandardMaterial3D
			if original == null: continue
			var material := ShaderMaterial.new(); material.shader = preload("res://plant_current.gdshader")
			material.set_shader_parameter("albedo_color",original.albedo_color)
			material.set_shader_parameter("has_texture",original.albedo_texture != null)
			if original.albedo_texture != null: material.set_shader_parameter("albedo_texture",original.albedo_texture)
			if original.get_meta("terrain_mipmaps", false):
				material.set_shader_parameter("terrain_mipmaps", true)
				material.set_shader_parameter("terrain_albedo_texture", original.albedo_texture)
			material.set_shader_parameter("roughness_value",original.roughness)
			material.set_shader_parameter("metallic_value",original.metallic)
			material.set_shader_parameter("root_height",bounds.position.y)
			material.set_shader_parameter("plant_height",bounds.size.y)
			material.set_shader_parameter("root_center",bounds.get_center())
			node.set_surface_override_material(surface,material)
			# Include displaced tips in the renderer's visibility bounds.
			node.extra_cull_margin = bounds.size.length() * 2.0
			materials.append(material)
			patch_materials.append(material)
		# Sample around the leafy upper body, rather than only at the root.
		var sample := bounds.get_center(); sample.y = bounds.position.y + bounds.size.y * 0.65
		patches.append({"point":node.global_transform * sample,"materials":patch_materials,"bend":Vector3.ZERO})
	for child in node.get_children(): _prepare(child,subdivide_sparse)

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
			if str(key).begins_with("wash_"): continue
			var value: Variant = deg_to_rad(float(settings[key])) if key == "direction" else settings[key]
			material.set_shader_parameter("sway_" + str(key),value)

func update_wash(player: Node3D, delta: float) -> void:
	var sources: Array[Dictionary] = []
	if is_instance_valid(player) and is_instance_valid(player.visual) and player.visual.is_visible_in_tree():
		var roles := ["main_propeller","left_propeller","right_propeller"]
		var parts: Dictionary = player.visual.get_meta("submarine_parts",{"main_propeller":"Hull/RearPropeller","left_propeller":"Hull/RightPod/RightPropeller","right_propeller":"Hull/LeftPod/LeftPropeller"})
		for index in range(3):
			var power: float = player.propeller_speeds[index]
			if absf(power) < 0.01 or not parts.has(roles[index]): continue
			var propeller := player.visual.get_node_or_null(NodePath(str(parts[roles[index]]))) as Node3D
			if propeller == null: continue
			var direction: Vector3 = player.global_basis.z if index == 0 else player.global_basis * Vector3(0,-sin(player.movement.tilt),cos(player.movement.tilt))
			sources.append({"position":propeller.get_global_transform_interpolated().origin,"direction":direction.normalized() * signf(power),"power":absf(power)})
	update_sources(sources,delta)

func wash_at(point: Vector3, sources: Array[Dictionary]) -> Vector3:
	if not settings.enabled or settings.wash_strength <= 0.0: return Vector3.ZERO
	var bend := Vector3.ZERO
	for source in sources:
		var offset: Vector3 = point - Vector3(source.position)
		var axis := Vector3(source.direction).normalized()
		var along := offset.dot(axis)
		if along < 0.0 or along >= float(settings.wash_range): continue
		var width := 0.3 + along * 0.35
		var sideways := (offset - axis * along).length()
		if sideways >= width: continue
		var force := (1.0 - smoothstep(width * 0.4,width,sideways)) * pow(1.0 - along / float(settings.wash_range),2.0) * float(source.power)
		if force <= 0.001: continue
		if is_instance_valid(world):
			var ray := PhysicsRayQueryParameters3D.create(source.position,point,1)
			ray.hit_back_faces = true
			if not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		bend += axis * force * float(settings.wash_strength)
	return bend.limit_length(1.2)

func update_sources(sources: Array[Dictionary], delta: float) -> void:
	if indexed_patch_count != patches.size():
		patch_cells.clear(); recovering.clear(); indexed_patch_count = patches.size()
		for index in range(patches.size()):
			var cell := Vector3i((Vector3(patches[index].point) / CELL_SIZE).floor())
			if not patch_cells.has(cell): patch_cells[cell] = []
			patch_cells[cell].append(index)
			if Vector3(patches[index].bend).length_squared() > 0: recovering[index] = true
	var candidates := recovering.duplicate()
	var reach := float(settings.wash_range) * 1.1 + 0.3
	if settings.enabled and settings.wash_strength > 0:
		for source in sources:
			var low := Vector3i(((Vector3(source.position) - Vector3.ONE * reach) / CELL_SIZE).floor())
			var high := Vector3i(((Vector3(source.position) + Vector3.ONE * reach) / CELL_SIZE).floor())
			for x in range(low.x,high.x + 1):
				for y in range(low.y,high.y + 1):
					for z in range(low.z,high.z + 1):
						for index in patch_cells.get(Vector3i(x,y,z),[]): candidates[index] = true
	for index in candidates:
		var patch: Dictionary = patches[index]
		var target := wash_at(patch.point,sources)
		var previous: Vector3 = patch.bend
		if previous.length_squared() < 0.000001 and target.length_squared() < 0.000001: continue
		var rate := 10.0 if target.length_squared() > previous.length_squared() else 3.0 / maxf(float(settings.wash_recovery),0.1)
		var next := previous.lerp(target,1.0 - exp(-rate * delta))
		if next.length_squared() < 0.000001: next = Vector3.ZERO
		patch.bend = next
		if next == Vector3.ZERO: recovering.erase(index)
		else: recovering[index] = true
		for material in patch.materials: material.set_shader_parameter("propeller_bend",next)
