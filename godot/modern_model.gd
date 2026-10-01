extends RefCounted
const Mods = preload("res://mod_registry.gd")
const LegacyBMP = preload("res://legacy_bmp.gd")

static func load_model(path: String, descriptor: Dictionary = {}) -> Node3D:
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
	var imported := document.generate_scene(state) as Node3D
	if imported == null: return null
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
	return root

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
