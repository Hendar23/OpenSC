extends RefCounted

const Assets = preload("res://clump_loader.gd")
const CHUNK_SIZE := 48.0

# Decode the static atomic sectors in the supplied SCEN1.BSP. Game objects
# and mission state are stored separately and are not reconstructed here.
static func load_world(path: String, tree: SceneTree, progress: Callable) -> Node3D:
	var disk_cache := preload("res://asset_cache.gd")
	var cache_key := Assets.conversion_key("world", path)
	var cached := disk_cache.load_scene(cache_key)
	if cached != null:
		progress.call("Loading cached environment")
		await tree.process_frame
		return cached
	progress.call("Converting assets")
	await tree.process_frame
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open world: " + path)
		return null
	var data := file.get_buffer(file.get_length())
	file.close()
	if not Assets._has_tag(data, 0, "dlrw") or not Assets._fits(data, 68, 4):
		push_error("Unsupported world file")
		return null
	var material_end := -1
	var sectors: Array[int] = []
	for offset in range(60, data.size() - 55, 4):
		if material_end == -1 and Assets._has_tag(data, offset, "nalp") and Assets._has_tag(data, offset + 8, "trts"):
			material_end = offset
		if Assets._has_tag(data, offset, "cesa") and Assets._has_tag(data, offset + 8, "trts") and data.decode_u32(offset + 12) == 40:
			sectors.append(offset)
	if material_end < 0 or sectors.is_empty():
		push_error("No supported world sectors found")
		return null
	var references := Assets._material_references(data, 60, material_end)
	if references.size() != int(data.decode_u32(68)):
		push_error("World material list does not match its declared count")
		return null
	var buffers := {}
	var lower := Vector3(INF, INF, INF)
	var upper := Vector3(-INF, -INF, -INF)
	var triangle_total := 0
	for sector_index in range(sectors.size()):
		var offset := sectors[sector_index]
		var triangle_count := int(data.decode_u32(offset + 16))
		var vertex_count := int(data.decode_u32(offset + 20))
		var vertices_offset := offset + 56
		var triangles_offset := vertices_offset + vertex_count * 16
		var uvs_offset := triangles_offset + triangle_count * 4
		if vertex_count > 255 or triangle_count > 10000 or not Assets._fits(data, uvs_offset, triangle_count * 8):
			push_error("Unsupported world sector layout at %d" % offset)
			return null
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		vertices.resize(vertex_count)
		normals.resize(vertex_count)
		for i in range(vertex_count):
			var p := vertices_offset + i * 16
			vertices[i] = Assets._vector(data, p)
			if not vertices[i].is_finite():
				push_error("Invalid world vertex")
				return null
			normals[i] = Vector3(_signed_byte(data[p + 12]), _signed_byte(data[p + 13]), _signed_byte(data[p + 14])).normalized()
			lower = lower.min(vertices[i])
			upper = upper.max(vertices[i])
		for i in range(triangle_count):
			var p := triangles_offset + i * 4
			var material := int(data[p])
			if material >= references.size():
				push_error("World triangle refers to an invalid material")
				return null
			var centroid := Vector3.ZERO
			for corner in range(3):
				var vertex_index := int(data[p + 1 + corner])
				if vertex_index >= vertex_count: push_error("Invalid world triangle"); return null
				centroid += vertices[vertex_index] / 3.0
			var cell := Vector2i(floori(centroid.x / CHUNK_SIZE),floori(centroid.z / CHUNK_SIZE))
			var key := "%d:%d:%d" % [material,cell.x,cell.y]
			if not buffers.has(key):
				buffers[key] = {"material":material,"cell":cell,"vertices": [], "normals": [], "uvs": []}
			var buffer: Dictionary = buffers[key]
			var positions: Array = buffer["vertices"]
			var vertex_normals: Array = buffer["normals"]
			var texture_coordinates: Array = buffer["uvs"]
			# The seventh byte stores the coordinate mip level. Most faces use
			# 128-pixel coordinates, but some roof faces use 64 or 32 instead.
			var coordinate_level := int(data[uvs_offset + i * 8 + 6])
			if coordinate_level > 7:
				push_error("Unsupported world texture-coordinate level")
				return null
			var coordinate_size := 128.0 / pow(2.0,coordinate_level)
			# Convert legacy winding to Godot's clockwise front faces, moving
			# each corner's UV and normal with its position.
			var lid_normal := Vector3.ZERO
			if str(references[material].texture).to_upper() == "CANTOP":
				var a: Vector3 = vertices[int(data[p+1])]
				var b: Vector3 = vertices[int(data[p+2])]
				var c: Vector3 = vertices[int(data[p+3])]
				# Its shared smooth normals mix the two coplanar sides, creating
				# dark fan-shaped patches on an otherwise flat metal lid.
				lid_normal = (b-a).cross(c-a).normalized()
			for corner in PackedInt32Array([0, 2, 1]):
				var index := int(data[p + 1 + corner])
				if index >= vertex_count:
					push_error("World triangle refers to an invalid vertex")
					return null
				positions.append(vertices[index])
				vertex_normals.append(lid_normal if not lid_normal.is_zero_approx() else normals[index])
				var uv := uvs_offset + i * 8 + corner * 2
				# BSP corners store U then V, unlike the packed DFF coordinates.
				texture_coordinates.append(Vector2(float(data[uv]), float(data[uv + 1])) / coordinate_size)
		triangle_total += triangle_count
		if sector_index % 24 == 0:
			progress.call("Converting assets: environment: %d / %d sectors" % [sector_index + 1, sectors.size()])
			await tree.process_frame
	var root := Node3D.new()
	root.name = "Environment"
	var cache := {}
	var game_folder := path.get_base_dir().get_base_dir()
	var material_ids := buffers.keys()
	material_ids.sort()
	var shared_materials := {}
	for key in material_ids:
		var buffer: Dictionary = buffers[key]
		var material_id: int = buffer.material
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(buffer["vertices"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(buffer["normals"])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(buffer["uvs"])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if not shared_materials.has(material_id):
			shared_materials[material_id] = _terrain_material(references[material_id],game_folder,cache)
		mesh.surface_set_material(0, shared_materials[material_id])
		var instance := MeshInstance3D.new()
		instance.name = "Material_%d_%d_%d" % [material_id,buffer.cell.x,buffer.cell.y]
		instance.set_meta("terrain_material",material_id)
		instance.set_meta("terrain_cell",buffer.cell)
		instance.mesh = mesh
		root.add_child(instance)
		if root.get_child_count() % 16 == 0:
			progress.call("Converting assets: environment textures: %d / %d" % [root.get_child_count(), material_ids.size()])
			await tree.process_frame
	root.set_meta("bounds", AABB(lower, upper - lower))
	# Legacy BSP sectors use positive coordinates; database matrices are relative
	# to the world origin stored in the BSP header. Keep the existing terrain view.
	root.set_meta("database_offset", -Assets._vector(data, 28))
	root.set_meta("surface_height", upper.y)
	root.set_meta("triangles", triangle_total)
	root.set_meta("sectors", sectors.size())
	root.set_meta("asset_cache_key", cache_key)
	disk_cache.save_scene(cache_key, root)
	return root


static func _terrain_material(reference: Dictionary, folder: String, cache: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	# Legacy terrain has mixed face winding. Keep caves and undersides visible.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The can lid explicitly authors both sides at the same depth. Drawing
	# their backs too makes its opposite-facing triangle fans fight each other.
	if str(reference.texture).to_upper() == "CANTOP": material.cull_mode = BaseMaterial3D.CULL_BACK
	material.albedo_color = reference["color"]
	var texture: Texture2D = Assets._load_texture(folder,reference["texture"],reference["mask"],cache)
	if texture != null:
		material.albedo_texture = texture; material.albedo_color = Color.WHITE
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST; material.texture_repeat = true
		if texture.get_meta("terrain_mipmaps", false):
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			material.set_meta("terrain_mipmaps", true)
		if not str(reference["mask"]).is_empty():
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			material.alpha_scissor_threshold = 0.5
	return material


static func _signed_byte(value: int) -> float:
	if value > 127:
		value -= 256
	return float(value) / 127.0

# Build collision only when piloting is first requested. Keep it separate from
# rendering so the original inspection views remain available.
static func add_collision(root: Node3D, tree: SceneTree, progress: Callable) -> void:
	if root.has_meta("collision_ready"): return
	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	body.collision_layer = 1
	body.collision_mask = 2
	root.add_child(body)
	var shelter := StaticBody3D.new()
	shelter.name = "TerrainLightCollision"
	shelter.collision_layer = 16
	shelter.collision_mask = 0
	root.add_child(shelter)
	var cells := {}
	for child in root.get_children():
		if not child is MeshInstance3D: continue
		var center: Vector3 = child.mesh.get_aabb().get_center()
		var cell: Vector2i = child.get_meta("terrain_cell",Vector2i(floori(center.x / CHUNK_SIZE),floori(center.z / CHUNK_SIZE)))
		if not cells.has(cell): cells[cell] = {"faces":PackedVector3Array(),"solid":PackedVector3Array()}
		var buffer: Dictionary = cells[cell]
		for surface in range(child.mesh.get_surface_count()):
			var arrays: Array = child.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var faces := PackedVector3Array()
			if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty():
				for index in arrays[Mesh.ARRAY_INDEX]: faces.append(child.transform * vertices[index])
			else:
				for vertex in vertices: faces.append(child.transform * vertex)
			buffer.faces.append_array(faces)
			# Leaves must not be mistaken for solid cave ceilings by shelter rays.
			var material := child.mesh.surface_get_material(surface) as StandardMaterial3D
			if material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED: buffer.solid.append_array(faces)
	var count := 0
	for cell in cells:
		var buffer: Dictionary = cells[cell]
		var shape := ConcavePolygonShape3D.new(); shape.backface_collision = true; shape.set_faces(buffer.faces)
		var collider := CollisionShape3D.new(); collider.shape = shape; body.add_child(collider)
		if not buffer.solid.is_empty():
			var light_shape := CollisionShape3D.new()
			if buffer.solid.size() == buffer.faces.size(): light_shape.shape = shape
			else:
				var solid := ConcavePolygonShape3D.new(); solid.backface_collision = true; solid.set_faces(buffer.solid); light_shape.shape = solid
			shelter.add_child(light_shape)
		count += 1
		if count % 16 == 0:
			progress.call("Building environment collision: %d chunks" % count)
			await tree.process_frame
	root.set_meta("collision_ready", true)
	var ceiling := StaticBody3D.new()
	ceiling.name = "WaterSurfaceCollision"
	# Separate layer keeps surface hits out of terrain placement/spawn rays.
	ceiling.collision_layer = 4
	ceiling.collision_mask = 2
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.DOWN, -float(root.get_meta("surface_height")))
	var surface_collider := CollisionShape3D.new()
	surface_collider.shape = plane
	ceiling.add_child(surface_collider)
	root.add_child(ceiling)
	if root.has_meta("asset_cache_key"):
		preload("res://asset_cache.gd").save_scene(str(root.get_meta("asset_cache_key")), root)
