extends RefCounted

const Assets = preload("res://clump_loader.gd")

# Serialized fields are always present; the row mask says which values are
# initialized. Runtime pointers and each matrix's fourth lanes are garbage.
static func read_database(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Scenery database is unavailable: " + path)
		return {}
	return decode_database(file.get_buffer(file.get_length()))

static func decode_database(data: PackedByteArray) -> Dictionary:
	if not Assets._has_tag(data, 0, "Dive"):
		push_warning("Unsupported scenery database")
		return {}
	var tables := {}
	var offset := 24
	while offset < data.size():
		if not Assets._fits(data, offset, 32): return {}
		var name := _string(data, offset, 20)
		var columns := int(data.decode_u32(offset + 20))
		var count := int(data.decode_u32(offset + 28))
		if columns < 1 or columns > 64 or count > 10000: return {}
		offset += 32
		var fields: Array[Dictionary] = []
		for column in range(columns):
			if not Assets._fits(data, offset, 36): return {}
			var kind := int(data.decode_u32(offset + 20))
			var length := int(data.decode_u32(offset + 24))
			if kind > 3 or length < 1 or length > 4096: return {}
			var size := ((length + 3) & ~3) if kind == 2 else length * 4
			fields.append({"name": _string(data, offset, 20), "kind": kind,
				"length": length, "size": size, "bit": int(data.decode_u32(offset + 32))})
			offset += 36
		var rows: Array[Dictionary] = []
		for index in range(count):
			if not Assets._fits(data, offset, 4): return {}
			var mask := int(data.decode_u32(offset))
			var row := {"index": index}
			offset += 4
			for field in fields:
				if not Assets._fits(data, offset, int(field.size)): return {}
				if (mask & int(field.bit)) != 0 and int(field.kind) != 3:
					var value: Variant
					if int(field.kind) == 2:
						value = _string(data, offset, int(field.length))
					elif int(field.length) > 1:
						var values: Array[float] = []
						for component in range(int(field.length)):
							values.append(data.decode_float(offset + component * 4))
						value = values
					elif int(field.kind) == 1:
						value = data.decode_float(offset)
					else:
						value = data.decode_s32(offset)
					row[field.name] = value
				offset += int(field.size)
			rows.append(row)
		tables[name] = rows
		# Later tables describe missions and use additional string layouts.
		if tables.has("Cities") and tables.has("Objects") and tables.has("Lights"):
			return tables
	return tables

static func read_definitions(path: String) -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return definitions
	var data := file.get_buffer(file.get_length())
	if data.size() < 4: return definitions
	var count := int(data.decode_u32(0))
	if count < 1 or count > 256: return definitions
	var base := 4 + count * 21
	if not Assets._fits(data, 0, base): return definitions
	for index in range(count):
		var offset := 4 + index * 21
		if _string(data, offset, 13).to_upper() != "OBJECTS.CSV": continue
		var size := int(data.decode_u32(offset + 13))
		var start := base + int(data.decode_u32(offset + 17))
		if not Assets._fits(data, start, size): return definitions
		var text := data.slice(start, start + size)
		for byte in range(text.size()): text[byte] ^= 255
		var lines := text.get_string_from_ascii().replace("\r", "").split("\n", false)
		if lines.is_empty(): return definitions
		var headers := lines[0].split(",")
		for line_index in range(1, lines.size()):
			var values := lines[line_index].split(",")
			if values.size() != headers.size(): return []
			var definition := {}
			for column in range(headers.size()):
				definition[headers[column].strip_edges()] = values[column].strip_edges()
			definitions.append(definition)
		return definitions
	return definitions

static func _string(data: PackedByteArray, start: int, length: int) -> String:
	var end := start
	while end < start + length and data[end] != 0: end += 1
	return data.slice(start, end).get_string_from_ascii()

static func placement(row: Dictionary, offset: Vector3) -> Transform3D:
	var matrix: Array = row.get("matrix", [])
	if matrix.size() != 16: return Transform3D(Basis.IDENTITY, Vector3(INF, INF, INF))
	var basis := Basis(Vector3(matrix[0], matrix[1], matrix[2]),
		Vector3(matrix[4], matrix[5], matrix[6]), Vector3(matrix[8], matrix[9], matrix[10]))
	var origin := Vector3(matrix[12], matrix[13], matrix[14]) + offset
	if not basis.is_finite() or not origin.is_finite() or absf(basis.determinant()) < 0.00001:
		return Transform3D(Basis.IDENTITY, Vector3(INF, INF, INF))
	return Transform3D(basis, origin)

static func populate(world: Node3D, folder: String, tree: SceneTree, progress: Callable) -> void:
	if world.has_meta("scenery_ready"): return
	var tables := read_database(folder.path_join("DATA/SCEN1.DDB"))
	if tables.is_empty():
		world.set_meta("scenery_summary", "Scenery database could not be read.")
		return
	var definitions := read_definitions(folder.path_join("DATA/DATA.ENC"))
	var offset: Vector3 = world.get_meta("database_offset")
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	world.add_child(scenery)
	var cache := {}
	var props := 0
	var plants := 0
	var patches := 0
	var skipped := 0
	# Scatter before adding prop collision, so grounding rays see only BSP terrain.
	for row in tables.get("Objects", []):
		if int(row.get("ObjectID", -1)) not in [26, 27]: continue
		var pose := placement(row, offset)
		if not pose.origin.is_finite(): continue
		var patch := Node3D.new()
		patch.name = "PlantPatch_%d" % int(row.index)
		patch.set_meta("source_comment", row.get("Comment", ""))
		patch.set_meta("source_position", pose.origin)
		patch.set_meta("approximate_scatter", true)
		scenery.add_child(patch)
		plants += await _plant_patch(patch, row, pose.origin, world, folder, cache, tree)
		patches += 1
		progress.call("Restoring plant patches: %d / 10" % patches)
		await tree.process_frame
	for row in tables.get("Cities", []):
		if _place_prop(scenery, row, str(row.get("clump", "")), offset, folder, cache, true): props += 1
	for row in tables.get("Objects", []):
		var model_name := ""
		var solid := true
		var object_id := int(row.get("ObjectID", -1))
		if int(row.get("AutoCreate", 0)) == 1:
			# The database stores one-based object-definition IDs.
			var type_id := int(row.get("ObjectType", 0)) - 1
			if type_id >= 0 and type_id < definitions.size():
				var definition: Dictionary = definitions[type_id]
				if definition.get("visible") == "yes" and definition.get("render") == "yes":
					model_name = str(definition.get("dff", "")).to_upper()
					solid = definition.get("collision") == "yes"
				# Pulse-light generators have no mesh; don't render their editor clump.
				if definition.get("object") == "PULSELIGHT":
					_add_light(scenery, placement(row, offset).origin, 0.7, 4.0)
		elif object_id == 32 and row.get("clump") == "CLAM":
			model_name = "CLAM"
		elif row.get("clump") == "PIPEBARS":
			model_name = "PIPEBARS"
		if model_name.is_empty() or model_name == "NONE":
			skipped += 1
			continue
		if _place_prop(scenery, row, model_name, offset, folder, cache, solid): props += 1
		else: skipped += 1
		if int(row.index) % 16 == 0:
			progress.call("Restoring scenery: %d objects" % props)
			await tree.process_frame
	for row in tables.get("Lights", []):
		var pose := placement(row, offset)
		_add_light(scenery, pose.origin, float(row.get("intensity", 1.0)), maxf(1.0, float(row.get("radius", 1.0))))
	for row in tables.get("Scenarios", []):
		if int(row.get("ID", 0)) == 1:
			world.set_meta("player_spawn", Vector3(float(row.PlayerX), float(row.PlayerY), float(row.PlayerZ)) + offset)
	for template in cache.values():
		if template != null: template.free()
	world.set_meta("scenery_ready", true)
	world.set_meta("scenery_props", props)
	world.set_meta("plant_count", plants)
	world.set_meta("plant_patches", patches)
	world.set_meta("scenery_summary", "%d scenery objects · %d plants in %d patches" % [props, plants, patches])
	world.set_meta("skipped_records", skipped)

static func _template(name: String, folder: String, cache: Dictionary, include_morphs: bool = false) -> Node3D:
	var key := name + (":animated" if include_morphs else ":static")
	if cache.has(key): return cache[key]
	var path := folder.path_join("CLUMPS").path_join(name + ".DFF")
	var template: Node3D = Assets.load_clump(path, PackedStringArray(), include_morphs) if FileAccess.file_exists(path) else null
	if template == null: push_warning("Scenery model unavailable or unsupported: " + name)
	cache[key] = template
	return template

static func _place_prop(parent: Node3D, row: Dictionary, name: String, offset: Vector3, folder: String, cache: Dictionary, solid: bool) -> bool:
	var pose := placement(row, offset)
	if not pose.origin.is_finite(): return false
	var template := _template(name, folder, cache, row.has("CityID"))
	if template == null: return false
	var instance := template.duplicate() as Node3D
	instance.name = "%s_%d" % [name, int(row.index)]
	instance.transform = pose * template.transform
	instance.set_meta("source_comment", row.get("Comment", row.get("CityName", "")))
	if row.has("CityID"):
		instance.set_meta("city_id", row.CityID)
		instance.set_meta("race_id", int(row.get("RaceID", 1)))
		instance.set_meta("city_name", str(row.get("CityName", "Dock")).strip_edges())
	parent.add_child(instance)
	if solid: _add_prop_collision(instance)
	return true

static func _add_prop_collision(instance: Node3D) -> void:
	var faces := PackedVector3Array()
	_collect_faces(instance, Transform3D.IDENTITY, faces)
	if faces.is_empty(): return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "SceneryCollision"
	body.collision_layer = 1
	body.collision_mask = 2
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	instance.add_child(body)

static func _collect_faces(node: Node3D, pose: Transform3D, faces: PackedVector3Array) -> void:
	if node is MeshInstance3D:
		for vertex in node.mesh.get_faces(): faces.append(pose * vertex)
	for child in node.get_children():
		if child is Node3D: _collect_faces(child, pose * child.transform, faces)

static func _plant_patch(parent: Node3D, row: Dictionary, center: Vector3, world: Node3D, folder: String, cache: Dictionary, tree: SceneTree) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(row.index) * 7919 + 104729
	# Provisional interpretation: param1 is patch radius, param2 is plant count.
	var radius := clampf(float(row.get("param1", 10.0)), 1.0, 60.0)
	var count := clampi(int(row.get("param2", 20.0)), 1, 200)
	var names := ["REED"] if int(row.ObjectID) == 26 else ["BUSH1", "BUSH2", "BUSH3", "BUSH4"]
	var plants := 0
	var surface := float(world.get_meta("surface_height"))
	var bounds: AABB = world.get_meta("bounds")
	for index in range(count):
		for attempt in range(12):
			var angle := rng.randf() * TAU
			var spread := sqrt(rng.randf()) * radius
			var point := center + Vector3(cos(angle), 0.0, sin(angle)) * spread
			var start := Vector3(point.x, minf(surface - 0.1, center.y + 8.0), point.z)
			var end := Vector3(point.x, maxf(bounds.position.y, center.y - 18.0), point.z)
			var query := PhysicsRayQueryParameters3D.create(start, end, 1)
			query.hit_back_faces = true
			var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
			# Legacy triangles use both winding directions, as does the viewer's
			# double-sided terrain. A vertical ray still identifies the top surface.
			if hit.is_empty() or absf(Vector3(hit.normal).dot(Vector3.UP)) < 0.5: continue
			var template := _template(names[rng.randi_range(0, names.size() - 1)], folder, cache)
			if template == null: break
			var plant := template.duplicate() as Node3D
			plant.position = hit.position
			plant.rotation.y = rng.randf() * TAU
			plant.name = "Plant_%d" % index
			parent.add_child(plant)
			plants += 1
			break
		if index % 24 == 0: await tree.process_frame
	return plants

static func _add_light(parent: Node3D, point: Vector3, energy: float, radius: float) -> void:
	if not point.is_finite() or not is_finite(energy) or not is_finite(radius): return
	var light := OmniLight3D.new()
	light.position = point
	light.light_color = Color(0.48, 0.8, 0.68)
	light.light_energy = clampf(energy, 0.0, 2.0)
	light.omni_range = clampf(radius, 1.0, 12.0)
	parent.add_child(light)
