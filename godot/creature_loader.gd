extends RefCounted

const Assets = preload("res://clump_loader.gd")
const Scenery = preload("res://scenery_loader.gd")
const Fish = preload("res://fish_controller.gd")
const SPECIES := ["ANGEL", "JACKFISH", "LIONFISH", "SILVER", "STINGRAY", "DOGFISH", "ANGLER", "BARACUDA"]
const RECORDED_CREATURES := ["BLOWFISH", "LIONFISH", "EEL", "BADJELLY", "TURTLE"]

# These are authored mission records, not proof of an ambient population.
static func spawn_records(folder: String, offset: Vector3) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var tables := Scenery.read_database(folder.path_join("DATA/SCEN1.DDB"))
	for row in tables.get("Objects", []):
		if str(row.get("clump", "")).to_upper() not in RECORDED_CREATURES: continue
		var pose := Scenery.placement(row, offset)
		if not pose.origin.is_finite(): continue
		records.append({"index": row.index, "model": row.clump, "position": pose.origin,
			"mission_id": row.get("MissionID", -1), "auto_create": int(row.get("AutoCreate", 0)) == 1,
			"comment": row.get("Comment", ""), "param1": row.get("param1"), "param2": row.get("param2")})
	return records

static func populate(world: Node3D, folder: String, tree: SceneTree, progress: Callable) -> void:
	var records := spawn_records(folder, world.get_meta("database_offset"))
	world.set_meta("creature_spawn_records", records)
	if world.has_node("AmbientFish"): return
	var population := Node3D.new()
	population.name = "AmbientFish"
	population.set_meta("provisional_population", true)
	world.add_child(population)
	var bounds: AABB = world.get_meta("bounds")
	var surface: float = world.get_meta("surface_height")
	var player: Vector3 = world.get_meta("player_spawn", bounds.get_center())
	var rng := RandomNumberGenerator.new()
	rng.seed = 8675309 + int(world.get_meta("wildlife_generation", 0)) * 104729
	var count := 0
	for school in range(SPECIES.size()):
		var template := Assets.load_clump(folder.path_join("CLUMPS/" + SPECIES[school] + ".DFF"), PackedStringArray(), true)
		if template == null: continue
		var boxes: Array[AABB] = []
		_collect_bounds(template, template.transform, boxes)
		var model_radius := 0.5
		if not boxes.is_empty():
			var box := boxes[0]
			for index in range(1, boxes.size()): box = box.merge(boxes[index])
			model_radius = maxf(0.25, box.size.length() * 0.5 + box.get_center().length())
		var center := Vector3(INF, INF, INF)
		for attempt in range(80):
			var x := rng.randf_range(bounds.position.x + 12.0, bounds.end.x - 12.0)
			var z := rng.randf_range(bounds.position.z + 12.0, bounds.end.z - 12.0)
			if school == 0:
				x = player.x + rng.randf_range(-14.0, 14.0)
				z = player.z + rng.randf_range(-14.0, 14.0)
			var candidate := _open_water(world, x, z, surface, model_radius, rng)
			if candidate.is_finite():
				center = candidate
				break
		if center.is_finite():
			for member in range(4):
				var point := center + Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-0.5, 0.5), rng.randf_range(-3.0, 3.0))
				if not _clear(world, point, model_radius) or point.y + model_radius >= surface: continue
				var fish := Fish.new()
				fish.name = "%s_%d" % [SPECIES[school], member]
				fish.set_meta("species", SPECIES[school])
				fish.set_meta("spawn_source", "provisional_ambient")
				fish.set_meta("spawn_position", point)
				fish.setup(template.duplicate() as Node3D, point, bounds, surface, model_radius, school * 100 + member + 42)
				population.add_child(fish)
				count += 1
		template.free()
		progress.call("Adding ambient fish: %d" % count)
		await tree.process_frame
	world.set_meta("ambient_fish_count", count)
	if not world.has_meta("scenery_base_summary"): world.set_meta("scenery_base_summary", world.get_meta("scenery_summary", ""))
	world.set_meta("scenery_summary", "%s · %d ambient fish" % [world.get_meta("scenery_base_summary"), count])

static func _open_water(world: Node3D, x: float, z: float, surface: float, radius: float, rng: RandomNumberGenerator) -> Vector3:
	var bounds: AABB = world.get_meta("bounds")
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, surface - 0.1, z), Vector3(x, bounds.position.y - 0.1, z), 1)
	query.hit_back_faces = true
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return Vector3(INF, INF, INF)
	var low: float = hit.position.y + radius + 1.5
	var high := surface - radius - 1.0
	if low >= high: return Vector3(INF, INF, INF)
	var point := Vector3(x, rng.randf_range(low, high), z)
	return point if _clear(world, point, radius) else Vector3(INF, INF, INF)

static func _clear(world: Node3D, point: Vector3, radius: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius + 0.05
	query.shape = sphere
	query.transform.origin = point
	query.collision_mask = 5
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

static func _collect_bounds(node: Node3D, pose: Transform3D, boxes: Array[AABB]) -> void:
	if node is MeshInstance3D: boxes.append(pose * node.mesh.get_aabb())
	for child in node.get_children():
		if child is Node3D: _collect_bounds(child, pose * child.transform, boxes)
