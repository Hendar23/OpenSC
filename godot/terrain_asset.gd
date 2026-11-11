extends RefCounted
## Versioned, data-only SCEN1 terrain geometry. See tools/terrain/FORMAT.md.

const MAGIC := 0x5453434f # OCST in little-endian byte order.
const VERSION := 1
const MAX_CHUNKS := 4096
const MAX_RECORD := 32 * 1024 * 1024
const MAX_FILE := 256 * 1024 * 1024
const MAX_VERTICES := 4_000_000
const MAX_INDICES := 12_000_000

static func load_asset(path: String, folder: String, tree: SceneTree, progress: Callable, make_material: Callable) -> Node3D:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 16 or file.get_length() > MAX_FILE: return null
	if file.get_32() != MAGIC or file.get_32() != VERSION: return null
	var header: Variant = _read_record(file)
	if not _valid_header(header): return null
	var root := Node3D.new()
	root.name = "Environment"
	root.set_meta("bounds", header.bounds)
	root.set_meta("surface_height", float(header.surface_height))
	root.set_meta("database_offset", header.database_offset)
	var identity := _exploration_identity(header)
	if not identity.signature.is_empty():
		root.set_meta("terrain_exploration_signature", identity.signature)
	var texture_cache := {}
	var materials := {}
	var names := {}
	var triangles := 0
	var vertex_total := 0
	var index_total := 0
	var bounds: AABB = header.bounds.grow(1.0)
	progress.call("Loading replacement terrain")
	await tree.process_frame
	for index in int(header.chunks):
		var chunk: Variant = _read_record(file)
		if not _valid_chunk(chunk, bounds):
			root.free()
			return null
		var cell: Vector2i = chunk.cell
		var name := "Material_%d_%d_%d" % [chunk.slot, cell.x, cell.y]
		vertex_total += chunk.vertices.size()
		index_total += chunk.indices.size()
		if names.has(name) or vertex_total > MAX_VERTICES or index_total > MAX_INDICES:
			root.free()
			return null
		names[name] = true
		var reference: Dictionary = chunk.material
		if not materials.has(reference): materials[reference] = make_material.call(reference, folder, texture_cache)
		var material: Material = materials[reference]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = chunk.vertices
		arrays[Mesh.ARRAY_NORMAL] = chunk.normals
		arrays[Mesh.ARRAY_TEX_UV] = chunk.uvs
		if not chunk.indices.is_empty(): arrays[Mesh.ARRAY_INDEX] = chunk.indices
		var instance := MeshInstance3D.new()
		instance.name = name
		instance.set_meta("terrain_material", chunk.slot)
		instance.set_meta("terrain_texture", str(reference.texture).to_upper())
		instance.set_meta("terrain_cell", cell)
		var lods := {}
		var coarse: int = chunk.coarse_count
		if coarse > 0:
			var coarse_arrays := arrays.duplicate()
			coarse_arrays[Mesh.ARRAY_VERTEX] = chunk.vertices.slice(0, coarse)
			coarse_arrays[Mesh.ARRAY_NORMAL] = chunk.normals.slice(0, coarse)
			coarse_arrays[Mesh.ARRAY_TEX_UV] = chunk.uvs.slice(0, coarse)
			coarse_arrays[Mesh.ARRAY_INDEX] = null
			instance.set_meta("terrain_source_mesh", _mesh(coarse_arrays, material, {}))
			var indices := PackedInt32Array()
			indices.resize(coarse)
			for i in coarse: indices[i] = i
			lods[float(chunk.lod_error)] = indices
		instance.mesh = _mesh(arrays, material, lods)
		root.add_child(instance)
		triangles += int((chunk.vertices.size() if chunk.indices.is_empty() else chunk.indices.size()) / 3.0)
		if index % 16 == 15: await tree.process_frame
	if file.get_position() != file.get_length():
		root.free()
		return null
	root.set_meta("triangles", triangles)
	root.set_meta("sectors", int(header.chunks))
	return root

static func _mesh(arrays: Array, material: Material, lods: Dictionary) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	result.surface_set_material(0, material)
	return result

static func write_record(file: FileAccess, value: Dictionary) -> bool:
	var raw := var_to_bytes(value)
	if raw.size() > MAX_RECORD: return false
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if packed.is_empty() or packed.size() > MAX_RECORD: return false
	file.store_32(raw.size())
	file.store_32(packed.size())
	return file.store_buffer(packed)

static func _read_record(file: FileAccess) -> Variant:
	if file.get_length() - file.get_position() < 8: return null
	var size := file.get_32()
	var packed_size := file.get_32()
	if size <= 0 or size > MAX_RECORD or packed_size <= 0 or packed_size > mini(MAX_RECORD, file.get_length() - file.get_position()): return null
	var raw := file.get_buffer(packed_size).decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size: return null
	return bytes_to_var(raw)

static func _valid_header(header: Variant) -> bool:
	if not header is Dictionary or not header.get("bounds") is AABB or not header.get("database_offset") is Vector3: return false
	if not _valid_exploration(header): return false
	var bounds: AABB = header.bounds
	return bounds.is_finite() and bounds.size.x > 0.0 and bounds.size.z > 0.0 and bounds.size.y > 0.0 \
		and bounds.position.abs().max(bounds.end.abs()).length() <= 100000.0 and header.database_offset.is_finite() \
		and header.database_offset.length() <= 100000.0 and _number(header.get("surface_height"), bounds.position.y, bounds.end.y + 100.0) \
		and header.get("chunks") is int and header.chunks > 0 and header.chunks <= MAX_CHUNKS

static func read_exploration_identity(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 16 or file.get_length() > MAX_FILE: return {}
	if file.get_32() != MAGIC or file.get_32() != VERSION: return {}
	var header: Variant = _read_record(file)
	return _exploration_identity(header) if _valid_header(header) else {}

static func _exploration_identity(header: Dictionary) -> Dictionary:
	return {"signature": header.get("exploration_signature", ""), "aliases": header.get("exploration_aliases", [])}

static func _valid_exploration(header: Dictionary) -> bool:
	var signature: Variant = header.get("exploration_signature", "")
	var aliases: Variant = header.get("exploration_aliases", [])
	if not signature is String or signature.length() > 160 or not aliases is Array or aliases.size() > 32: return false
	for character in signature.to_lower():
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789:_-.": return false
	if signature.is_empty() and not aliases.is_empty(): return false
	for alias in aliases:
		if not alias is String or not alias.begins_with("terrain-asset-v1:") or alias.length() != 81: return false
		for character in alias.trim_prefix("terrain-asset-v1:"):
			if not character in "0123456789abcdef": return false
	return true

static func _valid_chunk(chunk: Variant, bounds: AABB) -> bool:
	if not chunk is Dictionary or not chunk.get("slot") is int or chunk.slot < 0 or chunk.slot >= MAX_CHUNKS or not chunk.get("cell") is Vector2i: return false
	if not chunk.get("vertices") is PackedVector3Array or not chunk.get("normals") is PackedVector3Array or not chunk.get("uvs") is PackedVector2Array or not chunk.get("indices") is PackedInt32Array: return false
	var size: int = chunk.vertices.size()
	if size < 3 or size != chunk.normals.size() or size != chunk.uvs.size(): return false
	var index_count: int = chunk.indices.size()
	if (size if index_count == 0 else index_count) % 3 != 0: return false
	var coarse: Variant = chunk.get("coarse_count")
	if not coarse is int or coarse < 0 or coarse > size or coarse % 3 != 0: return false
	if coarse > 0 and (coarse >= index_count or not _number(chunk.get("lod_error"), 0.001, 1000.0)): return false
	for index: int in chunk.indices:
		if index < 0 or index >= size: return false
	for i in size:
		if not chunk.vertices[i].is_finite() or not bounds.has_point(chunk.vertices[i]) or not chunk.normals[i].is_finite() or not chunk.uvs[i].is_finite(): return false
	var reference: Variant = chunk.get("material")
	if not reference is Dictionary or not _texture_id(reference.get("texture")) or not _texture_id(reference.get("mask")) or not reference.get("color") is Color: return false
	var color: Color = reference.color
	return is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a)

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= low and value <= high

static func _texture_id(value: Variant) -> bool:
	if not value is String or value.length() > 64: return false
	for character in value.to_upper():
		if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true
