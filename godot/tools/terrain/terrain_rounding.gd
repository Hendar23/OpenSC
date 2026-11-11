extends RefCounted
## One subdivision pass over connected natural terrain, across BSP render seams.

const World = preload("res://world_loader.gd")
const Scenery = preload("res://scenery_loader.gd")
const EDGE := [Vector2i(1, 2), Vector2i(2, 0), Vector2i(0, 1)]
const MAX_SHIFT := 2.6
const MAX_SIDE_SHIFT := 0.72
const SEAM_MARGIN := 2.3
const SUPPORT_CELL := 4.0

var points := PackedVector3Array()
var point_ids := {}
var edge_faces := {}
var cliff_points := {}
var corner_weights := PackedFloat32Array()
var rounded := PackedVector3Array()
var edge_points := {}
var normal_sums := {}
var seam_cells := {}

func apply(world: Node3D, folder: String, tree: SceneTree, progress: Callable, profile: Dictionary, caves: Array[AABB]) -> void:
	var docks := PackedVector3Array()
	for city in Scenery.read_database(folder.path_join("DATA/SCEN1.DDB")).get("Cities", []):
		docks.append(Scenery.placement(city, world.get_meta("database_offset")).origin)
	progress.call("Rounding the terrain ridges")
	await tree.process_frame
	var chunks := await bake(world, tree, profile, docks, caves)
	for node in world.get_children():
		if not chunks.has(str(node.name)): continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, chunks[str(node.name)])
		mesh.surface_set_material(0, node.mesh.surface_get_material(0))
		node.mesh = mesh
		node.set_meta("terrain_rounded", true)

func bake(world: Node3D, tree: SceneTree, profile: Dictionary, docks: PackedVector3Array, caves: Array[AABB]) -> Dictionary:
	var sources := {}
	var slice := Time.get_ticks_usec()
	for node in world.get_children():
		if not node is MeshInstance3D or not node.has_meta("terrain_texture"): continue
		if not World.is_natural_ground(node.get_meta("terrain_texture")): continue
		var material := node.mesh.surface_get_material(0) as StandardMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ids := PackedInt32Array()
		ids.resize(vertices.size())
		for i in vertices.size(): ids[i] = _point_id(vertices[i])
		for i in range(0, ids.size(), 3):
			var a := ids[i]
			var b := ids[i + 1]
			var c := ids[i + 2]
			if a == b or a == c or b == c: continue
			var normal := (points[b] - points[a]).cross(points[c] - points[a]).normalized()
			var cliff := 1.0 - smoothstep(0.28, 0.72, absf(normal.y)) if not normal.is_zero_approx() else 0.0
			if cliff > 0.0:
				for id in [a, b, c]: cliff_points[id] = maxf(cliff_points.get(id, 0.0), cliff)
			_add_edge(b, c, a)
			_add_edge(c, a, b)
			_add_edge(a, b, c)
		sources[str(node.name)] = [arrays, ids]
		if Time.get_ticks_usec() - slice >= 8000:
			await tree.process_frame
			slice = Time.get_ticks_usec()
	var surface: float = world.get_meta("surface_height")
	_index_open_edges()
	corner_weights.resize(points.size())
	for i in points.size(): corner_weights[i] = _weight(points[i], profile, surface, docks, caves)
	await _round_points(tree, profile, surface, docks, caves)
	var result := {}
	for name in sources:
		var chunk := _build_chunk(sources[name][0], sources[name][1])
		if not chunk.is_empty(): result[name] = chunk
		if Time.get_ticks_usec() - slice >= 8000:
			await tree.process_frame
			slice = Time.get_ticks_usec()
	for name in result:
		var arrays: Array = result[name]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			if not normal_sums.has(vertices[i]): continue
			var computed: Vector3 = normal_sums[vertices[i]].normalized()
			if computed.dot(normals[i]) < 0.0: computed = -computed
			normals[i] = normals[i].lerp(computed, 0.84).normalized()
		if Time.get_ticks_usec() - slice >= 8000:
			await tree.process_frame
			slice = Time.get_ticks_usec()
	return result

func _point_id(point: Vector3) -> int:
	if not point_ids.has(point):
		point_ids[point] = points.size()
		points.append(point)
	return point_ids[point]

static func _edge_key(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))

func _add_edge(a: int, b: int, opposite: int) -> void:
	var key := _edge_key(a, b)
	var faces: Vector3i = edge_faces.get(key, Vector3i.ZERO)
	if faces.x == 0: faces.y = opposite
	if faces.x == 1: faces.z = opposite
	faces.x += 1
	edge_faces[key] = faces

func _index_open_edges() -> void:
	# Separate BSP shells can meet along overlapping edges with different
	# vertices. Keep the nearby supporting surface as well as the edge itself.
	var margin := Vector3.ONE * SEAM_MARGIN
	for key: Vector2i in edge_faces:
		if edge_faces[key].x == 2: continue
		var a := points[key.x]
		var b := points[key.y]
		var lower := _support_cell(a.min(b) - margin)
		var upper := _support_cell(a.max(b) + margin)
		for x in range(lower.x, upper.x + 1):
			for y in range(lower.y, upper.y + 1):
				for z in range(lower.z, upper.z + 1):
					var cell := Vector3i(x, y, z)
					if not seam_cells.has(cell): seam_cells[cell] = []
					seam_cells[cell].append(key)

static func _support_cell(point: Vector3) -> Vector3i:
	return Vector3i((point / SUPPORT_CELL).floor())

func _weight(point: Vector3, profile: Dictionary, surface: float, docks: PackedVector3Array, caves: Array[AABB]) -> float:
	var value := smoothstep(0.28, 1.0, surface - point.y)
	if profile.radius > 0.0:
		value *= 1.0 - smoothstep(profile.radius * 0.65, profile.radius, point.distance_to(profile.center))
	for dock in docks:
		value = minf(value, smoothstep(4.5, 9.0, point.distance_to(dock)))
	for cave in caves:
		value = minf(value, smoothstep(0.35, 3.5, point.distance_to(point.clamp(cave.position, cave.end))))
	if value > 0.0:
		for key: Vector2i in seam_cells.get(_support_cell(point), []):
			var nearest := Geometry3D.get_closest_point_to_segment(point, points[key.x], points[key.y])
			value = minf(value, smoothstep(1.15, SEAM_MARGIN, point.distance_to(nearest)))
			if value == 0.0: break
	return value * float(profile.rounding)

func _round_points(tree: SceneTree, profile: Dictionary, surface: float, docks: PackedVector3Array, caves: Array[AABB]) -> void:
	var sums := PackedVector3Array()
	var counts := PackedInt32Array()
	var shortest := PackedFloat32Array()
	sums.resize(points.size())
	counts.resize(points.size())
	shortest.resize(points.size())
	shortest.fill(INF)
	for key: Vector2i in edge_faces:
		var sides: Vector3i = edge_faces[key]
		if sides.x != 2:
			corner_weights[key.x] = 0.0
			corner_weights[key.y] = 0.0
			continue
		sums[key.x] += points[key.y]
		sums[key.y] += points[key.x]
		counts[key.x] += 1
		counts[key.y] += 1
		var length := points[key.x].distance_to(points[key.y])
		shortest[key.x] = minf(shortest[key.x], length)
		shortest[key.y] = minf(shortest[key.y], length)
	for i in points.size():
		var point := points[i]
		var weight := corner_weights[i]
		if counts[i] >= 3 and weight > 0.0:
			var shift := (sums[i] / float(counts[i]) - point) * 0.56
			point += _limit(shift, cliff_points.get(i, 0.0), shortest[i] * 0.28) * weight
		rounded.append(point)
	await tree.process_frame
	for key: Vector2i in edge_faces:
		var sides: Vector3i = edge_faces[key]
		if sides.x != 2: continue
		var midpoint := (points[key.x] + points[key.y]) * 0.5
		var weight := minf(maxf(corner_weights[key.x], corner_weights[key.y]), _weight(midpoint, profile, surface, docks, caves))
		if weight <= 0.0: continue
		var neighbor_midpoint := (points[sides.y] + points[sides.z]) * 0.5
		var shift := (neighbor_midpoint - midpoint) * 0.25
		var cliff := minf(cliff_points.get(key.x, 0.0), cliff_points.get(key.y, 0.0))
		var span := points[key.x].distance_to(points[key.y])
		edge_points[key] = midpoint + _limit(shift, cliff, span * 0.23) * weight

static func _limit(shift: Vector3, cliff: float, local_limit: float) -> Vector3:
	# Ground uses height smoothing. Steep connected walls can also turn in plan,
	# with less sideways travel on small faces and no travel at open joins.
	var sideways := (Vector2(shift.x, shift.z) * (0.72 * cliff)).limit_length(minf(local_limit, MAX_SIDE_SHIFT))
	return Vector3(sideways.x, clampf(shift.y, -MAX_SHIFT, MAX_SHIFT), sideways.y)

func _build_chunk(source: Array, ids: PackedInt32Array) -> Array:
	var source_uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
	var source_normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var changed := false
	for i in range(0, ids.size(), 3):
		var corners := Vector3i(ids[i], ids[i + 1], ids[i + 2])
		var positions := PackedVector3Array([rounded[corners.x], rounded[corners.y], rounded[corners.z]])
		var face_normals := PackedVector3Array([source_normals[i], source_normals[i + 1], source_normals[i + 2]])
		var face_uvs := PackedVector2Array([source_uvs[i], source_uvs[i + 1], source_uvs[i + 2]])
		var midpoints := Vector3i.ZERO
		var moved := false
		for j in 3:
			moved = moved or positions[j] != points[corners[j]]
			var pair: Vector2i = EDGE[j]
			var key := _edge_key(corners[pair.x], corners[pair.y])
			var midpoint: Variant = edge_points.get(key)
			if midpoint == null:
				midpoints[j] = pair.x
				continue
			midpoints[j] = positions.size()
			positions.append(midpoint)
			face_normals.append((face_normals[pair.x] + face_normals[pair.y]).normalized())
			face_uvs.append((face_uvs[pair.x] + face_uvs[pair.y]) * 0.5)
			moved = true
		var faces := [Vector3i(0, midpoints.z, midpoints.y), Vector3i(1, midpoints.x, midpoints.z), Vector3i(2, midpoints.y, midpoints.x), Vector3i(midpoints.x, midpoints.y, midpoints.z)] if moved else [Vector3i(0, 1, 2)]
		for face: Vector3i in faces:
			if moved and (face.x == face.y or face.y == face.z or face.z == face.x): continue
			var normal := (positions[face.z] - positions[face.x]).cross(positions[face.y] - positions[face.x])
			for j in 3:
				var index: int = face[j]
				var vertex := positions[index]
				vertices.append(vertex)
				normals.append(face_normals[index])
				uvs.append(face_uvs[index])
				if moved and (index >= 3 or corner_weights[corners[index]] > 0.0):
					normal_sums[vertex] = normal_sums.get(vertex, Vector3.ZERO) + normal
		changed = changed or moved
	if not changed: return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	return arrays
