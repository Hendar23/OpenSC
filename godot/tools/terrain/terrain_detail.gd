extends RefCounted
## Builds optional render geometry from the player's original BSP conversion.

const Cave = preload("res://cave_daylight.gd")
const OtherCaves = preload("res://other_cave_daylight.gd")
const Docking = preload("res://docking_controller.gd")
const Rounding = preload("res://tools/terrain/terrain_rounding.gd")
const Pipe = preload("res://tools/terrain/terrain_pipe.gd")
const TinCan = preload("res://tools/terrain/terrain_tin_can.gd")
const STEPS := 4
const LOD_ERROR := 0.12
const EDGE_CORNERS := [Vector2i(1, 2), Vector2i(2, 0), Vector2i(0, 1)]

var center: Vector3
var radius: float
var strength: float
var water_height: float
var noise := FastNoiseLite.new()
var patterns := {}
var dock_bounds: Array[AABB] = []
var cave_bounds: Array[AABB] = []
var chunk_docks: Array[AABB] = []
var chunk_caves: Array[AABB] = []

func round_world(world: Node3D, folder: String, tree: SceneTree, progress: Callable, profile: Dictionary) -> void:
	if profile.rounding > 0.0:
		await Rounding.new().apply(world, folder, tree, progress, profile, _cave_bounds())
	if profile.pipe_rounding: Pipe.apply(world, _pattern)
	if profile.can_rounding: TinCan.apply(world, _pattern)

func add_detail(world: Node3D, tree: SceneTree, progress: Callable, profile: Dictionary) -> void:
	center = profile.center
	radius = profile.radius
	strength = profile.strength
	water_height = world.get_meta("surface_height")
	noise.seed = 32143
	noise.frequency = 0.64
	dock_bounds = _dock_bounds(world)
	cave_bounds = _cave_bounds()
	await _refine_world(world, tree, progress)

static func read_profile(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 4096: return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("schema_version") != 1: return {}
	if not _valid_number(data.get("strength"), 0.01, 0.25): return {}
	var rounding: Variant = data.get("rounding", 0.0)
	if not _valid_number(rounding, 0.0, 1.0): return {}
	var pipe_rounding: Variant = data.get("pipe_rounding", false)
	var can_rounding: Variant = data.get("can_rounding", false)
	if not pipe_rounding is bool or not can_rounding is bool: return {}
	var aliases: Variant = data.get("exploration_aliases", [])
	if not preload("res://terrain_asset.gd")._valid_exploration({"exploration_signature": "original", "exploration_aliases": aliases}): return {}
	var profile := {"center": Vector3.ZERO, "radius": 0.0, "strength": float(data.strength), "rounding": float(rounding), "pipe_rounding": pipe_rounding, "can_rounding": can_rounding, "exploration_aliases": aliases}
	if not data.has("center") and not data.has("radius"): return profile
	var origin: Variant = data.get("center")
	if not origin is Array or origin.size() != 3: return {}
	for coordinate in origin:
		if not _valid_number(coordinate, -10000.0, 10000.0): return {}
	if not _valid_number(data.get("radius"), 4.0, 50.0): return {}
	profile.center = Vector3(origin[0], origin[1], origin[2])
	profile.radius = float(data.radius)
	return profile

static func _valid_number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

func _refine_world(world: Node3D, tree: SceneTree, progress: Callable) -> void:
	var start := Time.get_ticks_usec()
	progress.call("Preparing detailed terrain")
	for node in world.get_children():
		if not node is MeshInstance3D or not node.has_meta("terrain_material") or node.has_meta("terrain_source_mesh"): continue
		var texture: String = node.get_meta("terrain_texture")
		if not preload("res://world_loader.gd").is_natural_ground(texture): continue
		var source: Mesh = node.mesh
		var material := source.surface_get_material(0) as StandardMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		var box := source.get_aabb()
		if not _in_region(box.position, box.end) or box.position.y >= water_height - 0.6: continue
		chunk_docks = dock_bounds.filter(func(dock: AABB) -> bool: return dock.grow(5.0).intersects(box))
		chunk_caves = cave_bounds.filter(func(cave: AABB) -> bool: return cave.grow(4.0).intersects(box))
		var steps := 2 if node.has_meta("terrain_rounded") else STEPS
		var geometry := refine(source.surface_get_arrays(0), _is_sand(texture), steps)
		if not geometry.is_empty():
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, geometry[0], [], {LOD_ERROR: geometry[1]})
			mesh.surface_set_material(0, material)
			node.set_meta("terrain_source_mesh", source)
			node.mesh = mesh
		if Time.get_ticks_usec() - start >= 6000:
			await tree.process_frame
			start = Time.get_ticks_usec()

static func _dock_bounds(world: Node3D) -> Array[AABB]:
	var result: Array[AABB] = []
	var to_world := world.global_transform.affine_inverse()
	for node in world.find_children("*", "Node3D", true, false):
		if not node.has_meta("city_id"): continue
		var boxes: Array[AABB] = []
		Docking._bounds(node, to_world * node.global_transform, boxes)
		if boxes.is_empty(): continue
		var combined := boxes[0]
		for index in range(1, boxes.size()): combined = combined.merge(boxes[index])
		result.append(combined)
	return result

static func _cave_bounds() -> Array[AABB]:
	var result: Array[AABB] = [Cave.REGION]
	for profile in OtherCaves.PROFILES:
		var mouth: Vector3 = profile[0]
		var axis: Vector3 = profile[1]
		var side := Vector3(-axis.z, 0, axis.x)
		var end: Vector3 = mouth + axis * float(profile[3])
		var box := AABB(mouth, Vector3.ZERO).expand(end)
		var rim: Vector2 = profile[2]
		var section_bounds: Array = profile[4] if not profile[4].is_empty() else [Vector4(-rim.y, rim.y, -rim.x, rim.x)]
		for section: Vector4 in section_bounds:
			box = box.expand(mouth + Vector3.UP * section.x + side * section.z)
			box = box.expand(end + Vector3.UP * section.y + side * section.w)
		result.append(box.grow(1.0))
	return result

func _in_region(low: Vector3, high: Vector3) -> bool:
	return radius == 0.0 or center.distance_squared_to(center.clamp(low, high)) < radius * radius

static func _is_sand(texture: String) -> bool:
	return texture.begins_with("SAND") or texture.begins_with("SEAB") or texture.begins_with("BEA") or (texture.length() == 3 and texture.left(2) in ["SA", "SB"])

func refine(source: Array, sand: bool, steps: int = STEPS) -> Array:
	# BSP chunks have one material and non-indexed faces. Each face keeps its
	# own UV corners, while positions are matched along shared smooth edges.
	var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
	var selected := {}
	var edges := {}
	var pinned := {}
	for first in range(0, points.size(), 3):
		var a := points[first]
		var b := points[first + 1]
		var c := points[first + 2]
		var longest := maxf(a.distance_squared_to(b), maxf(b.distance_squared_to(c), c.distance_squared_to(a)))
		var altitude_squared := (b - a).cross(c - a).length_squared() / maxf(longest, 0.000001)
		var low := a.min(b).min(c)
		var high := a.max(b).max(c)
		if altitude_squared < 0.10 or low.y >= water_height - 0.6 or not _in_region(low, high):
			for i in range(first, first + 3): pinned[points[i]] = true
			continue
		var keys: Array[Array] = []
		for edge in EDGE_CORNERS:
			var i: int = first + edge.x
			var j: int = first + edge.y
			if points[i] > points[j]:
				var swap := i
				i = j
				j = swap
			var key := [points[i], points[j], normals[i], normals[j]]
			keys.append(key)
			edges[key] = int(edges.get(key, 0)) + 1
		selected[first] = keys
	if selected.is_empty(): return []
	for edge in edges:
		if edges[edge] != 2:
			pinned[edge[0]] = true
			pinned[edge[1]] = true
	var indices := PackedInt32Array()
	var original := PackedInt32Array()
	original.resize(points.size())
	for i in original.size(): original[i] = i
	for first in range(0, original.size(), 3):
		if not selected.has(first):
			indices.append_array(PackedInt32Array([first, first + 1, first + 2]))
			continue
		var keys: Array = selected[first]
		var locked := 0
		for edge in 3:
			if edges[keys[edge]] != 2: locked |= 1 << edge
		var layout := _pattern(locked, steps)
		var offset := points.size()
		var p := PackedVector3Array([points[first], points[first + 1], points[first + 2]])
		var n := PackedVector3Array([normals[first], normals[first + 1], normals[first + 2]])
		var pins := Vector3(float(pinned.has(p[0])), float(pinned.has(p[1])), float(pinned.has(p[2])))
		for weights: Vector3i in layout.weights:
			var w := Vector3(weights) / float(steps)
			var point := p[0] * w.x + p[1] * w.y + p[2] * w.z
			var normal := (n[0] * w.x + n[1] * w.y + n[2] * w.z).normalized()
			# Identical arithmetic on both sides of a shared edge, even where
			# the source triangle orders its two corners in reverse.
			if maxi(weights.x, maxi(weights.y, weights.z)) < steps and (weights.x == 0 or weights.y == 0 or weights.z == 0):
				var edge := 0 if weights.x == 0 else 1 if weights.y == 0 else 2
				var pair: Vector2i = EDGE_CORNERS[edge]
				var key: Array = keys[edge]
				var t: float = w[pair.y] if p[pair.x] == key[0] else w[pair.x]
				point = key[0].lerp(key[1], t)
				normal = key[2].lerp(key[3], t).normalized()
			var pin := maxf(w.x * pins.x, maxf(w.y * pins.y, w.z * pins.z))
			var amount := _envelope(point, sand) * (1.0 - smoothstep(0.52, 1.0, pin))
			points.append(point + normal * (_height(point, sand) * amount))
			normals.append(_detail_normal(point, normal, amount, sand))
			uvs.append(uvs[first] * w.x + uvs[first + 1] * w.y + uvs[first + 2] * w.z)
		for index: int in layout.indices: indices.append(offset + index)
	if indices.size() <= original.size(): return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return [arrays, original]

func _pattern(locked: int, steps: int = STEPS) -> Dictionary:
	var pattern_key := Vector2i(locked, steps)
	if patterns.has(pattern_key): return patterns[pattern_key]
	var weights: Array[Vector3i] = []
	var lookup := {}
	var grid := {}
	for x in range(steps + 1):
		for y in range(steps + 1 - x):
			var bary := Vector3i(steps - x - y, x, y)
			for edge in 3:
				if bary[edge] != 0 or (locked & (1 << edge)) == 0: continue
				# Collapse samples along a locked edge into its two corners.
				# The fine mesh then shares the original unsplit edge exactly.
				var pair: Vector2i = EDGE_CORNERS[edge]
				var corner := pair.x if bary[pair.x] >= bary[pair.y] else pair.y
				bary = Vector3i.ZERO
				bary[corner] = steps
				break
			if not lookup.has(bary):
				lookup[bary] = weights.size()
				weights.append(bary)
			grid[Vector2i(x, y)] = lookup[bary]
	var indices := PackedInt32Array()
	for x in steps:
		for y in steps - x:
			var a: int = grid[Vector2i(x, y)]
			var b: int = grid[Vector2i(x + 1, y)]
			var c: int = grid[Vector2i(x, y + 1)]
			if a != b and b != c and a != c: indices.append_array(PackedInt32Array([a, b, c]))
			if x + y < steps - 1:
				var d: int = grid[Vector2i(x + 1, y + 1)]
				if b != d and d != c and b != c: indices.append_array(PackedInt32Array([b, d, c]))
	patterns[pattern_key] = {"weights": weights, "indices": indices}
	return patterns[pattern_key]

func _envelope(point: Vector3, sand: bool) -> float:
	var region := 1.0 if radius == 0.0 else 1.0 - smoothstep(radius * 0.52, radius, center.distance_to(point))
	var submerged := smoothstep(0.6, 2.4, water_height - point.y)
	var protection := 1.0
	for dock in chunk_docks:
		protection = minf(protection, smoothstep(1.0, 5.0, point.distance_to(point.clamp(dock.position, dock.end))))
	for cave in chunk_caves:
		protection = minf(protection, lerpf(0.32, 1.0, smoothstep(0.0, 4.0, point.distance_to(point.clamp(cave.position, cave.end)))))
	return strength * region * submerged * protection * (0.50 if sand else 1.0)

func _height(point: Vector3, sand: bool) -> float:
	if sand:
		var wave := sin(point.dot(Vector3(2.8, 0.28, 5.4)) + 2.0 * noise.get_noise_3dv(point * 0.46))
		return 0.7 * wave + 0.25 * noise.get_noise_3dv(point)
	var broad := noise.get_noise_3dv(point * 0.66)
	var layered := noise.get_noise_3dv(Vector3(point.x * 0.68, point.y * 2.35 + point.z * 0.50, point.z * 0.89))
	return clampf(1.08 * broad + 0.65 * layered, -1.0, 1.0)

func _detail_normal(point: Vector3, normal: Vector3, amount: float, sand: bool) -> Vector3:
	if amount <= 0.00001 or normal.is_zero_approx(): return normal
	var tangent := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.FORWARD).normalized()
	var bitangent := normal.cross(tangent)
	const STEP := 0.10
	var dx := _height(point + tangent * STEP, sand) - _height(point - tangent * STEP, sand)
	var dy := _height(point + bitangent * STEP, sand) - _height(point - bitangent * STEP, sand)
	return (normal - (tangent * dx + bitangent * dy) * (amount / (2.0 * STEP))).normalized()
