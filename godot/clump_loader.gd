extends RefCounted
class_name SubCultureClumpLoader
const LegacyBMP = preload("res://legacy_bmp.gd")
const Mods = preload("res://mod_registry.gd")
const Modern = preload("res://modern_model.gd")

static func load_submarine(path: String) -> Node3D:
	return load_clump(path, PackedStringArray(["Hull", "RearPropeller", "LeftPod", "RightPod", "RightPropeller", "LeftPropeller"]))

# Scenery uses the same legacy frame/atomic format, with varying frame counts.
static func load_clump(path: String, names: PackedStringArray = PackedStringArray(), include_morphs: bool = false) -> Node3D:
	if path.get_extension().to_lower() == "glb": return Modern.load_model(path)
	for replacement in Mods.candidates(Mods.model_id(path)):
		var loaded: Node3D = Modern.load_model(replacement.path, replacement) if str(replacement.path).get_extension().to_lower() == "glb" else _load_legacy(replacement.path, names, include_morphs)
		if loaded != null:
			if str(replacement.path).get_extension().to_lower() == "dff": loaded.scale *= float(replacement.scale)
			loaded.set_meta("asset_mod", replacement.name)
			loaded.set_meta("asset_source", replacement.path)
			loaded.set_meta("asset_id", Mods.model_id(path))
			return loaded
		Mods.note("%s: could not load %s; using the next replacement or original." % [replacement.name, replacement.id])
	return _load_legacy(path, names, include_morphs)

static func _load_legacy(path: String, names: PackedStringArray = PackedStringArray(), include_morphs: bool = false) -> Node3D:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return null
	var data := file.get_buffer(file.get_length())
	file.close()
	if not _has_tag(data, 20, "lmrf") or not _fits(data, 36, 4):
		push_error("Unsupported frame list in " + path)
		return null
	var frame_count := int(data.decode_u32(36))
	if frame_count < 1 or frame_count > 256 or (not names.is_empty() and frame_count != names.size()):
		push_error("Unexpected frame count in " + path)
		return null
	var root := Node3D.new()
	root.name = path.get_file().get_basename()
	root.set_meta("asset_source", path)
	var frames: Array[Node3D] = []
	for i in range(frame_count):
		var record := 40 + i * 80
		if not _has_tag(data, record, "trts") or not _fits(data, record + 8, 72) or data.decode_u32(record + 4) != 72:
			root.free()
			return null
		var p := record + 8
		var frame := Node3D.new()
		frame.name = names[i] if not names.is_empty() else "Frame_%d" % i
		var basis := Basis(_vector(data, p), _vector(data, p + 16), _vector(data, p + 32))
		var origin := _vector(data, p + 48)
		var parent := int(data.decode_s32(p + 64))
		if not basis.is_finite() or not origin.is_finite() or parent >= i or parent < -1:
			frame.free()
			root.free()
			return null
		if parent == -1:
			root.add_child(frame)
		else:
			frames[parent].add_child(frame)
		frame.transform = Transform3D(basis, origin)
		frame.set_meta("rest_basis", basis)
		frames.append(frame)
	var geometries: Array[int] = []
	# Chunk IDs are aligned to four bytes. Validate headers before accepting them.
	for offset in range(40 + frame_count * 80, data.size() - 52, 4):
		if _has_tag(data, offset, "moeg") and _has_tag(data, offset + 8, "trts"):
			geometries.append(offset)
	if geometries.is_empty() or (not names.is_empty() and geometries.size() != names.size()):
		push_error("Unexpected geometry count in " + path)
		root.free()
		return null
	var used_frames := {}
	var texture_cache := {}
	for i in range(geometries.size()):
		var geometry := geometries[i]
		var end := data.size()
		if i + 1 < geometries.size():
			end = geometries[i + 1] - 20
		if not _has_tag(data, geometry - 20, "trts") or data.decode_u32(geometry - 16) != 12:
			root.free()
			return null
		var frame_id := int(data.decode_u32(geometry - 12))
		if frame_id >= frames.size() or (not names.is_empty() and used_frames.has(frame_id)):
			root.free()
			return null
		used_frames[frame_id] = true
		var mesh := _build_mesh(data, geometry, end, path, texture_cache, include_morphs)
		if mesh == null:
			root.free()
			return null
		var instance := MeshInstance3D.new()
		instance.name = "Mesh_%d" % i
		instance.mesh = mesh
		frames[frame_id].add_child(instance)
	return root


static func _vector(data: PackedByteArray, offset: int) -> Vector3:
	return Vector3(data.decode_float(offset), data.decode_float(offset + 4), data.decode_float(offset + 8))


static func _build_mesh(data: PackedByteArray, geometry: int, end: int, path: String, texture_cache: Dictionary, include_morphs: bool = false) -> ArrayMesh:
	if geometry < 0 or not _has_tag(data, geometry + 8, "trts"):
		push_error("No supported geometry found in %s" % path)
		return null
	if not _fits(data, geometry + 12, 4) or data.decode_u32(geometry + 12) != 36:
		push_error("Unexpected geometry header in %s" % path)
		return null
	var triangle_count := int(data.decode_u32(geometry + 24))
	var vertex_count := int(data.decode_u32(geometry + 28))
	var morph_count := int(data.decode_u32(geometry + 36))
	if vertex_count < 3 or vertex_count > 100000 or triangle_count < 1 or triangle_count > 100000 or morph_count < 1 or morph_count > 64:
		push_error("Implausible mesh counts in %s" % path)
		return null
	# Each morph target has its own sphere/flags struct, positions and normals.
	# Static scenery uses the first (rest) target; later targets animate doors.
	var has_normals := (int(data.decode_u32(geometry + 20)) & 16) != 0
	var target_size := vertex_count * (24 if has_normals else 12) + 32
	var vertex_header := end - target_size * morph_count
	var triangle_offset := vertex_header - triangle_count * 8
	var uv_offset := triangle_offset - vertex_count * 4
	if uv_offset < geometry + 52 or not _has_tag(data, vertex_header, "trts"):
		push_error("Mesh arrays do not fit the expected layout in %s" % path)
		return null
	if data.decode_u32(vertex_header + 4) != 24:
		push_error("Unexpected vertex struct size in %s" % path)
		return null
	for target in range(morph_count):
		var header := vertex_header + target * target_size
		if not _has_tag(data, header, "trts") or data.decode_u32(header + 4) != 24 or data.decode_u32(header + 24) != 1 or data.decode_u32(header + 28) != int(has_normals):
			push_error("Unsupported morph target arrays in " + path)
			return null

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	uvs.resize(vertex_count)
	var position_offset := vertex_header + 32
	for i in range(vertex_count):
		var p := position_offset + i * 12
		var n := position_offset + (vertex_count + i) * 12
		vertices[i] = Vector3(data.decode_float(p), data.decode_float(p + 4), data.decode_float(p + 8))
		normals[i] = _vector(data, n) if has_normals else Vector3.ZERO
		var packed_uv := int(data.decode_u32(uv_offset + i * 4))
		# The low 12 bits hold V. The upper field holds U with a 128-pixel
		# bias. Coordinates are in pixels for the 128 by 128 texture atlas.
		uvs[i] = Vector2((float(packed_uv >> 12) - 128.0) / 128.0, float(packed_uv & 0xfff) / 128.0)
		if not vertices[i].is_finite() or not normals[i].is_finite():
			push_error("Invalid vertex coordinates in %s" % path)
			return null

	var by_material := {}
	for i in range(triangle_count):
		var p := triangle_offset + i * 8
		var a := int(data.decode_u16(p))
		var b := int(data.decode_u16(p + 2))
		var c := int(data.decode_u16(p + 4))
		var material := int(data.decode_u16(p + 6))
		if a >= vertex_count or b >= vertex_count or c >= vertex_count or material > 127:
			push_error("Invalid triangle in %s" % path)
			return null
		if not by_material.has(material):
			by_material[material] = PackedInt32Array()
		var indices: PackedInt32Array = by_material[material]
		# Legacy faces are counterclockwise; Godot's front faces are clockwise.
		# Keep the outward normals and reverse the face, including morph poses.
		indices.append_array(PackedInt32Array([a, c, b]))
		by_material[material] = indices
		if not has_normals:
			var normal := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).normalized()
			for vertex in [a, b, c]: normals[vertex] += normal
	if not has_normals:
		for vertex in range(normals.size()): normals[vertex] = normals[vertex].normalized()

	var palette := [Color(0.31, 0.62, 0.65), Color(0.76, 0.63, 0.33),
		Color(0.28, 0.34, 0.40), Color(0.65, 0.49, 0.31)]
	var mesh := ArrayMesh.new()
	var morph_arrays: Array[Array] = []
	if include_morphs and morph_count > 1:
		mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		var bounds := AABB(vertices[0], Vector3.ZERO)
		for vertex in vertices: bounds = bounds.expand(vertex)
		for target in range(1, morph_count):
			var pose_vertices := PackedVector3Array()
			var pose_normals := PackedVector3Array()
			pose_vertices.resize(vertex_count)
			pose_normals.resize(vertex_count)
			var offset := vertex_header + target * target_size + 32
			for vertex in range(vertex_count):
				pose_vertices[vertex] = _vector(data, offset + vertex * 12)
				pose_normals[vertex] = _vector(data, offset + (vertex_count + vertex) * 12) if has_normals else Vector3.ZERO
				if not pose_vertices[vertex].is_finite() or not pose_normals[vertex].is_finite():
					push_error("Invalid morph coordinates in " + path)
					return null
				bounds = bounds.expand(pose_vertices[vertex])
			if not has_normals:
				for material_id in by_material:
					var indices: PackedInt32Array = by_material[material_id]
					for triangle in range(0, indices.size(), 3):
						var a := indices[triangle]
						var b := indices[triangle + 1]
						var c := indices[triangle + 2]
						var normal := (pose_vertices[c] - pose_vertices[a]).cross(pose_vertices[b] - pose_vertices[a]).normalized()
						for vertex in [a, b, c]: pose_normals[vertex] += normal
				for vertex in range(vertex_count): pose_normals[vertex] = pose_normals[vertex].normalized()
			var pose_arrays := []
			pose_arrays.resize(Mesh.ARRAY_MAX)
			pose_arrays[Mesh.ARRAY_VERTEX] = pose_vertices
			pose_arrays[Mesh.ARRAY_NORMAL] = pose_normals
			morph_arrays.append(pose_arrays)
			mesh.add_blend_shape("Pose_%d" % target)
		mesh.custom_aabb = bounds
	var references := _material_references(data, geometry + 52, uv_offset)
	var game_folder := path.get_base_dir().get_base_dir()
	var keys := by_material.keys()
	keys.sort()
	for material_id in keys:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = by_material[material_id]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, morph_arrays)
		var surface_material := StandardMaterial3D.new()
		surface_material.albedo_color = palette[int(material_id) % palette.size()]
		surface_material.metallic = 0.1
		surface_material.roughness = 0.7
		surface_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if int(material_id) < references.size():
			var reference: Dictionary = references[int(material_id)]
			var texture: Texture2D = _load_texture(game_folder, reference["texture"], reference["mask"], texture_cache)
			if texture != null:
				surface_material.albedo_texture = texture
				surface_material.albedo_color = Color.WHITE
				surface_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				surface_material.texture_repeat = true
				if not str(reference["mask"]).is_empty():
					surface_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					surface_material.alpha_scissor_threshold = 0.5
		mesh.surface_set_material(mesh.get_surface_count() - 1, surface_material)
	return mesh


static func _material_references(data: PackedByteArray, start: int, end: int) -> Array[Dictionary]:
	var offsets: Array[int] = []
	for offset in range(start, end - 8, 4):
		if _has_tag(data, offset, "ltam"):
			offsets.append(offset)
	var references: Array[Dictionary] = []
	for i in range(offsets.size()):
		var limit := end
		if i + 1 < offsets.size():
			limit = offsets[i + 1]
		var texture := ""
		var mask := ""
		for offset in range(offsets[i] + 8, limit - 8, 4):
			if _has_tag(data, offset, "rxet") and _has_tag(data, offset + 8, "gnts"):
				texture = _chunk_string(data, offset + 8, limit)
				var second := offset + 16 + int(data.decode_u32(offset + 12))
				if _has_tag(data, second, "gnts"):
					mask = _chunk_string(data, second, limit)
				break
		var color := Color.WHITE
		if _fits(data, offsets[i] + 20, 4):
			var c := offsets[i] + 20
			color = Color(float(data[c]) / 255.0, float(data[c + 1]) / 255.0, float(data[c + 2]) / 255.0)
		references.append({"texture": texture, "mask": mask, "color": color})
	return references


static func _chunk_string(data: PackedByteArray, offset: int, limit: int) -> String:
	if not _fits(data, offset, 8):
		return ""
	var length := int(data.decode_u32(offset + 4))
	if length < 1 or length > 256 or offset + 8 + length > limit:
		return ""
	var end := offset + 8
	while end < offset + 8 + length and data[end] != 0:
		end += 1
	return data.slice(offset + 8, end).get_string_from_ascii()


static func _load_texture(game_folder: String, texture_name: String, mask_name: String, cache: Dictionary) -> Texture2D:
	if texture_name.is_empty():
		return null
	var key := texture_name + "|" + mask_name
	if cache.has(key):
		return cache[key]
	for replacement in Mods.candidates("texture." + texture_name):
		var mod_image := _replacement_image(replacement.path)
		if mod_image != null and not mod_image.is_empty():
			# Modern replacement textures supply their own alpha rather than
			# requiring an old, differently-sized mask texture.
			var mod_texture := ImageTexture.create_from_image(mod_image)
			mod_texture.set_meta("asset_mod", replacement.name)
			cache[key] = mod_texture
			return mod_texture
		Mods.note("%s: could not load texture %s; using the next replacement or original." % [replacement.name, texture_name])
	var texture_path := game_folder.path_join("GAMETEX").path_join(texture_name.to_upper() + ".BMP")
	var image := LegacyBMP.load_image(texture_path)
	if image == null or image.is_empty():
		push_warning("Could not load texture: " + texture_path)
		cache[key] = null
		return null
	image.convert(Image.FORMAT_RGBA8)
	if not mask_name.is_empty():
		var mask_path := game_folder.path_join("GAMETEX").path_join(mask_name.to_upper() + ".BMP")
		var mask := LegacyBMP.load_image(mask_path)
		for replacement in Mods.candidates("texture." + mask_name):
			var candidate := _replacement_image(replacement.path)
			if candidate != null and candidate.get_size() == image.get_size(): mask = candidate; break
		if mask == null or mask.is_empty() or mask.get_size() != image.get_size():
			push_warning("Could not load matching mask: " + mask_path)
			cache[key] = null
			return null
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel := image.get_pixel(x, y)
				pixel.a = mask.get_pixel(x, y).r
				image.set_pixel(x, y, pixel)
	var texture := ImageTexture.create_from_image(image)
	cache[key] = texture
	return texture

static func _replacement_image(path: String) -> Image:
	return LegacyBMP.load_image(path) if path.get_extension().to_lower() in ["bmp", "ras"] else Image.load_from_file(path)


static func _fits(data: PackedByteArray, offset: int, size: int) -> bool:
	return offset >= 0 and offset + size <= data.size()


static func _has_tag(data: PackedByteArray, offset: int, tag: String) -> bool:
	if not _fits(data, offset, tag.length()):
		return false
	for i in range(tag.length()):
		if data[offset + i] != tag.unicode_at(i):
			return false
	return true


static func _find_last(data: PackedByteArray, tag: String) -> int:
	for offset in range(data.size() - tag.length(), -1, -1):
		if _has_tag(data, offset, tag):
			return offset
	return -1
