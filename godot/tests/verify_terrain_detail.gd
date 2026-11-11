extends SceneTree

const Terrain = preload("res://tools/terrain/terrain_detail.gd")
const World = preload("res://world_loader.gd")
const Mods = preload("res://mod_registry.gd")
const Keys = preload("res://world_cache.gd")
const Pipe = preload("res://tools/terrain/terrain_pipe.gd")
const TinCan = preload("res://tools/terrain/terrain_tin_can.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)

func run() -> void:
	var builder := Terrain.new()
	for locked in 8:
		var pattern := builder._pattern(locked)
		var weights: Array[Vector3i] = pattern.weights
		var indices: PackedInt32Array = pattern.indices
		var area := 0
		for i in range(0, indices.size(), 3):
			var a := weights[indices[i]]
			var b := weights[indices[i + 1]] - a
			var c := weights[indices[i + 2]] - a
			var face_area := b.y * c.z - b.z * c.y
			check(face_area > 0, "Refinement preserves triangle winding for edge mask %d" % locked)
			area += face_area
		check(area == Terrain.STEPS * Terrain.STEPS, "Refinement covers the entire base triangle for edge mask %d" % locked)
		for weight in weights:
			for edge in 3:
				if weight[edge] == 0 and (locked & (1 << edge)) != 0:
					check(maxi(weight.x, maxi(weight.y, weight.z)) == Terrain.STEPS, "Locked boundaries keep the original unsplit edges")
	check_relief(builder)
	var args := OS.get_cmdline_user_args()
	if args.size() == 3: await check_original(args[0], args[1], args[2])
	print("Terrain detail: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check_relief(builder: RefCounted) -> void:
	builder.strength = 0.25
	builder.water_height = 10.0
	builder.noise.frequency = 0.64
	var positions := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT * 3.0, Vector3.BACK * 3.0])
	var source := []
	source.resize(Mesh.ARRAY_MAX)
	source[Mesh.ARRAY_VERTEX] = positions.duplicate()
	source[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	source[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
	var protected_source := source.duplicate(true)
	protected_source[Mesh.ARRAY_VERTEX] = positions
	protected_source[Mesh.ARRAY_NORMAL] = source[Mesh.ARRAY_NORMAL].duplicate()
	protected_source[Mesh.ARRAY_TEX_UV] = source[Mesh.ARRAY_TEX_UV].duplicate()
	var fine: PackedVector3Array = builder.refine(source, true)[0][Mesh.ARRAY_VERTEX]
	var depth := 0.0
	for point in fine: depth = maxf(depth, absf(point.y))
	check(depth > 0.01 and depth <= 0.125, "Sand relief displaces the geometry within the visual clearance budget")
	builder.chunk_docks.assign([AABB(Vector3(-1.0, -1.0, -1.0), Vector3(5.0, 2.0, 5.0))])
	var protected: PackedVector3Array = builder.refine(protected_source, false)[0][Mesh.ARRAY_VERTEX]
	check(protected.size() > 3, "Dock protection still permits aligned terrain tessellation")
	for point in protected: check(point.y == 0.0, "Terrain beneath a dock remains on the original plane")

func check_original(game_folder: String, mods_folder: String, player_folder: String) -> void:
	preload("res://player_storage.gd").root_override = player_folder
	Mods.initialize(false, mods_folder)
	const ID := "high-poly-terrain"
	var progress := func(_message: String) -> void: pass
	var world := await World.load_world(game_folder.path_join("DATA/SCEN1.BSP"), self, progress)
	check(world != null, "Original world loads")
	if world == null: return
	root.add_child(world)
	var base_triangles := int(world.get_meta("triangles"))
	var original_map := Keys.terrain_signature(world)
	var original_faces := natural_faces(world)
	var open_edges := boundary_edges(original_faces, PackedInt32Array())
	var pipe := buried_pipe(world)
	check(pipe != null, "Original Buried Pipe mesh is identified")
	if pipe == null: return
	var original_pipe: PackedVector3Array = pipe.mesh.get_faces()
	var pipe_edges := boundary_edges(original_pipe, PackedInt32Array())
	var can := world.get_children().filter(func(node: Node) -> bool: return node.get_meta("terrain_texture", "") == "CAN")
	check(can.size() == 1, "Original starting can mesh is identified")
	if can.size() != 1: return
	var original_can: PackedVector3Array = can[0].mesh.get_faces()
	await World.add_collision(world, self, progress)
	await physics_frame
	var original_collision := Keys.collision_signature(world, 17)
	var original_peak := terrain_height(world, Vector3(328.02, 165.0, 240.24))
	var original_pipe_contact := terrain_height(world, Vector3(214.35, 154.0, 183.1))
	check(not world.has_meta("terrain_asset_hash"), "Disabled mod loads the original world")
	var pipe_name := pipe.name
	var can_name: StringName = can[0].name
	var original_offset: Vector3 = world.get_meta("database_offset")
	var original_surface: float = world.get_meta("surface_height")
	world.free()
	Mods.apply([ID], [ID], false)
	check(Mods.candidates("terrain.scen1").size() == 1, "Terrain pack is discovered as an opt-in asset")
	var start := Time.get_ticks_msec()
	world = await World.load_world(game_folder.path_join("DATA/SCEN1.BSP"), self, progress)
	check(world != null and world.has_meta("terrain_asset_hash"), "The baked terrain is loaded through the normal world entry point")
	if world == null or not world.has_meta("terrain_asset_hash"): return
	root.add_child(world)
	check(world.get_meta("database_offset") == original_offset and world.get_meta("surface_height") == original_surface, "Replacement terrain preserves original placements and water height")
	pipe = world.get_node_or_null(NodePath(pipe_name))
	var baked_can := world.get_node_or_null(NodePath(can_name)) as MeshInstance3D
	check(pipe != null and baked_can != null, "Baked asset includes both the pipe and tin can")
	if pipe == null or baked_can == null: return
	var rounded_map := Keys.terrain_signature(world)
	var rounded_faces := natural_faces(world)
	check(rounded_faces.size() <= original_faces.size() * 4 and original_faces.size() / 3 <= base_triangles, "Rounding subdivides each original face at most once")
	check(rounded_map != original_map, "Rounding changes the original geometry used by navigation")
	check(open_edges == boundary_edges(rounded_faces, PackedInt32Array()), "Rounding preserves the original open edges across the whole map")
	var tryton_corner := Vector2(201.856, 134.4725)
	check(closest_horizontal(original_faces, tryton_corner) < 0.002 and closest_horizontal(rounded_faces, tryton_corner) > 0.05, "A hard Tryton corner rounds sideways")
	var rounded_pipe: PackedVector3Array = pipe.mesh.get_faces()
	check(rounded_pipe.size() > original_pipe.size() * 5, "The baked pipe has a denser circular cross-section")
	check(pipe_edges == boundary_edges(rounded_pipe, PackedInt32Array()), "Buried Pipe preserves all original boundaries into rock")
	check(pipe_height(rounded_pipe) - pipe_height(original_pipe) > 0.01, "Buried Pipe arcs between the old flat sides")
	var rounded_can := baked_can.mesh.get_faces()
	check(rounded_can.size() > original_can.size() * 6, "The tin can gains a curved shell")
	var original_span := can_radius_span(original_can)
	var rounded_span := can_radius_span(rounded_can)
	check(rounded_span < original_span * 0.36, "The can's body cross-section is round instead of ten-sided")
	check(not world.has_meta("collision_ready"), "Original cached collision is invalidated for rounded geometry")
	await World.add_collision(world, self, progress)
	await physics_frame
	var rounded_collision := Keys.collision_signature(world, 17)
	var mouth := Vector3(257.95, 153.10, 273.82)
	var interior := TinCan.BASE + TinCan.AXIS * 0.5
	var entry := PhysicsRayQueryParameters3D.create(mouth, interior, 1)
	check(world.get_world_3d().direct_space_state.intersect_ray(entry).is_empty(), "The rounded can still has an open mouth")
	check(world.has_node("TinCanBaseCollision"), "The rounded can retains solid support beneath its coins")
	check(rounded_collision != original_collision, "Collision follows the reshaped terrain")
	var rounded_peak := terrain_height(world, Vector3(328.02, 165.0, 240.24))
	var rounded_pipe_contact := terrain_height(world, Vector3(214.35, 154.0, 183.1))
	check(is_finite(original_peak) and is_finite(rounded_peak) and original_peak - rounded_peak > 0.8, "Touka ridge contact follows the visibly lower crest")
	check(rounded_pipe_contact - original_pipe_contact > 0.01, "Buried Pipe collision follows the rounder surface")
	var elapsed := Time.get_ticks_msec() - start
	var added := 0
	var count := 0
	for node in world.get_children():
		if not node.has_meta("terrain_source_mesh"): continue
		count += 1
		var source := Keys.terrain_source(node)
		var detail: ArrayMesh = node.mesh
		var name := str(node.name)
		check(World.is_natural_ground(node.get_meta("terrain_texture")), name + " keeps architecture untouched")
		check(source.surface_get_material(0) == detail.surface_get_material(0), name + " keeps the original material")
		var arrays := detail.surface_get_arrays(0)
		var base: PackedVector3Array = source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		check(vertices.slice(0, base.size()) == base, name + " distant geometry retains the rounded silhouette")
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		added += (indices.size() - base.size()) / 3
		check(boundary_edges(base, PackedInt32Array()) == boundary_edges(vertices, indices), name + " retains its exact boundary edges")
	check(count > 100 and added > 50000, "Opting in adds real triangles across the map")
	check(Keys.terrain_signature(world) == rounded_map, "Navigation map uses the rounded terrain")
	check(Keys.collision_signature(world, 17) == rounded_collision, "Fine visual relief uses the rounded terrain collision")
	var rendered := 0
	for node in world.get_children():
		if node is MeshInstance3D: rendered += node.mesh.get_faces().size() / 3
	print("Detailed chunks: %d. Original natural: %d/%d. Rounded natural: %d. Rendered total: %d. Load: %d ms." % [count, original_faces.size() / 3, base_triangles, rounded_faces.size() / 3, rendered, elapsed])
	print("Touka ridge collision height: %.3f -> %.3f" % [original_peak, rounded_peak])
	print("Buried Pipe triangles: %d -> %d, contact height: %.3f -> %.3f" % [original_pipe.size() / 3, rounded_pipe.size() / 3, original_pipe_contact, rounded_pipe_contact])
	print("Tin can triangles: %d -> %d, outer radius spread: %.4f -> %.4f" % [original_can.size() / 3, rounded_can.size() / 3, original_span, rounded_span])
	var pristine := await World.load_world(game_folder.path_join("DATA/SCEN1.BSP"), self, progress, false)
	check(Keys.terrain_signature(pristine) == original_map, "Rounded terrain never overwrites the original world cache")
	pristine.free()
	world.free()

func terrain_height(world: Node3D, start: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(start, start - Vector3.UP * 25.0, 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.position.y if not hit.is_empty() else NAN

func closest_horizontal(faces: PackedVector3Array, target: Vector2) -> float:
	var nearest := INF
	for point in faces: nearest = minf(nearest, target.distance_squared_to(Vector2(point.x, point.z)))
	return sqrt(nearest)

func can_radius_span(faces: PackedVector3Array) -> float:
	var low := INF
	var high := 0.0
	for i in range(0, faces.size(), 3):
		for corner in 3:
			var a := faces[i + corner] - TinCan.BASE
			var b := faces[i + (corner + 1) % 3] - TinCan.BASE
			var a_depth := a.dot(TinCan.AXIS) - 1.7
			var b_depth := b.dot(TinCan.AXIS) - 1.7
			if a_depth * b_depth >= 0.0: continue
			var point := a.lerp(b, a_depth / (a_depth - b_depth))
			var radius := Vector2(point.dot(TinCan.SIDE), point.z).length()
			if radius < 1.52: continue
			low = minf(low, radius)
			high = maxf(high, radius)
	return high - low if is_finite(low) else INF

func buried_pipe(world: Node3D) -> MeshInstance3D:
	for node in world.get_children():
		if node.get_meta("terrain_texture", "") == "PIPE" and node.mesh.get_aabb().intersects(Pipe.BURIED): return node
	return null

func pipe_height(faces: PackedVector3Array) -> float:
	var origin := Vector3(214.35, 154.0, 183.1)
	var height := -INF
	for i in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, Vector3.DOWN, faces[i], faces[i+1], faces[i+2])
		if hit != null: height = maxf(height, hit.y)
	return height

func natural_faces(world: Node3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for node in world.get_children():
		if node is MeshInstance3D and World.is_natural_ground(node.get_meta("terrain_texture", "")):
			faces.append_array(Keys.terrain_source(node).get_faces())
	return faces

func boundary_edges(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var counts := {}
	var indexed := not indices.is_empty()
	for i in range(0, indices.size() if indexed else vertices.size(), 3):
		for j in 3:
			var a := vertices[indices[i + j] if indexed else i + j]
			var k := i + (j + 1) % 3
			var b := vertices[indices[k] if indexed else k]
			if a == b: continue
			var edge := [a, b] if a < b else [b, a]
			counts[edge] = int(counts.get(edge, 0)) + 1
	var boundary := {}
	for edge in counts:
		if counts[edge] == 1: boundary[edge] = true
	return boundary
