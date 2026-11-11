extends RefCounted
const Mods = preload("res://mod_registry.gd")
const LegacyBMP = preload("res://legacy_bmp.gd")

static func supports(path: String) -> bool:
	return path.get_extension().to_lower() == "glb" or Mods.protected_model_path(path)

static func load_model(path: String, descriptor: Dictionary = {}) -> Node3D:
	Mods.ensure()
	if Mods.protected_model_path(path):
		# Preconverted scenes remain inside the encrypted PCK. ResourceLoader
		# retains shared resources in memory without writing a decrypted cache.
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed == null: return null
		var model := packed.instantiate() as Node3D
		if model == null: return null
		model.scale = Vector3.ONE * float(descriptor.get("scale", 1.0))
		var axis := str(descriptor.get("forward_axis", "-Z"))
		if axis == "-Z" and model.get_child_count() > 0: model.get_child(0).rotation.y += PI
		model.set_meta("pod_tilt_sign", 1.0 if axis == "-Z" else -1.0)
		model.set_meta("asset_source", path)
		model.set_meta("asset_mod", descriptor.get("name", "Opened GLB"))
		return model
	var cache := preload("res://asset_cache.gd")
	var dependencies: Array = []
	for id in descriptor.get("material_textures", {}).values():
		for entry in Mods.candidates(str(id)): dependencies.append([entry, cache.fingerprint(entry.path)])
	var cache_key := cache.key("modern-model", [path], [descriptor, dependencies])
	var cached := cache.load_scene(cache_key)
	if cached != null: return cached
	# Drop-in GLBs must be self-contained; this also makes them portable.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	var bytes := file.get_buffer(file.get_length())
	if bytes.size() < 20 or bytes.slice(0, 4).get_string_from_ascii() != "glTF" or bytes.decode_u32(4) != 2: return null
	var json_size := int(bytes.decode_u32(12))
	if json_size < 1 or 20 + json_size > bytes.size(): return null
	var json: Variant = JSON.parse_string(bytes.slice(20, 20 + json_size).get_string_from_utf8())
	if not json is Dictionary: return null
	for table in ["buffers", "images"]:
		for entry in json.get(table, []):
			if entry.has("uri") and not str(entry.uri).begins_with("data:"): return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK: return null
	_apply_material_textures(state, descriptor)
	if descriptor.get("scenery_lods",false) or str(descriptor.get("id","")) in ["model.reed","model.bush1","model.bush2","model.bush3","model.bush4"]:
		# Runtime GLTF loading does not run the editor's automatic LOD import.
		# Keep the full-detail surface and add distance-only index buffers once,
		# before caching the scene; never simplify geometry during play.
		for item in state.get_meshes():
			var mesh: ImporterMesh = item.mesh
			if mesh != null: mesh.generate_lods(60.0,25.0,[])
	var imported := document.generate_scene(state) as Node3D
	if imported == null: return null
	_apply_source_bounds(state,json)
	var root := Node3D.new()
	root.name = path.get_file().get_basename()
	root.add_child(imported)
	root.scale = Vector3.ONE * float(descriptor.get("scale", 1.0))
	# Normalize to the legacy +Z loader contract; piloting then turns it to -Z.
	if str(descriptor.get("forward_axis", "-Z")) == "-Z": imported.rotation.y += PI
	root.set_meta("pod_tilt_sign", 1.0 if str(descriptor.get("forward_axis", "-Z")) == "-Z" else -1.0)
	root.set_meta("asset_source", path)
	root.set_meta("asset_mod", descriptor.get("name", "Opened GLB"))
	root.set_meta("modern_model", true)
	var mapped := {}
	var parts: Dictionary = descriptor.get("parts", {})
	for role in parts:
		var node := root.get_node_or_null(NodePath(str(parts[role]))) as Node3D
		if node == null: node = imported.get_node_or_null(NodePath(str(parts[role]))) as Node3D
		if node != null:
			node.set_meta("rest_basis", node.basis)
			mapped[str(role)] = str(root.get_path_to(node))
	root.set_meta("submarine_parts", mapped)
	cache.save_scene(cache_key, root)
	return root

static func _apply_source_bounds(state: GLTFState, json: Dictionary) -> void:
	# Offline simplification may drop extreme vertices. Retain the source bounds
	# so existing seeded scatter scales, anchors and culling remain identical.
	var meshes := state.get_meshes()
	var descriptions: Array = json.get("meshes",[])
	for index in mini(meshes.size(),descriptions.size()):
		var extras: Variant = descriptions[index].get("extras",{})
		if not extras is Dictionary: continue
		var values: Variant = extras.get("osc_original_aabb")
		if not values is Array or values.size() != 6: continue
		var valid := true
		for value in values:
			if not (value is int or value is float) or not is_finite(float(value)): valid = false
		if not valid or float(values[3]) <= 0 or float(values[4]) <= 0 or float(values[5]) <= 0: continue
		var bounds := AABB(Vector3(values[0],values[1],values[2]),Vector3(values[3],values[4],values[5]))
		if not bounds.position.is_finite() or not bounds.size.is_finite(): continue
		var mesh: ArrayMesh = meshes[index].mesh.get_mesh()
		# Metadata can expand a mesh's bounds, never clip its remaining geometry.
		if mesh != null and bounds.grow(0.0001).encloses(mesh.get_aabb()):
			mesh.custom_aabb = bounds
			mesh.set_meta("scenery_source_bounds",bounds)

static func source_bounds(mesh: Mesh) -> AABB:
	# ArrayMesh.custom_aabb affects rendering culling, but get_aabb() still
	# reports the remaining triangles. Placement and sway need the source box.
	if not mesh.has_meta("scenery_source_bounds"): return mesh.get_aabb()
	var value: Variant = mesh.get_meta("scenery_source_bounds")
	return value if value is AABB else mesh.get_aabb()

static func _apply_material_textures(state: GLTFState, descriptor: Dictionary) -> void:
	var materials := state.get_materials()
	var textures := {}
	for slot in descriptor.get("material_textures", {}):
		var index := int(str(slot))
		if index < 0 or index >= materials.size() or not materials[index] is BaseMaterial3D:
			Mods.note("%s: GLB material %s is unavailable; keeping embedded textures." % [descriptor.get("name", "GLB"), slot])
			continue
		var id := str(descriptor.material_textures[slot])
		if not textures.has(id):
			textures[id] = null
			for replacement in Mods.candidates(id):
				var image: Image = LegacyBMP.load_image(replacement.path) if str(replacement.path).get_extension().to_lower() in ["bmp", "ras"] else Image.load_from_file(replacement.path)
				if image != null and not image.is_empty():
					var texture := ImageTexture.create_from_image(image)
					texture.set_meta("asset_mod", replacement.name)
					texture.set_meta("asset_source", replacement.path)
					textures[id] = texture
					break
				Mods.note("%s: could not load %s for GLB material; using the next replacement or embedded texture." % [replacement.name, id])
		if textures[id] != null:
			materials[index].albedo_texture = textures[id]
