extends RefCounted

const Mods = preload("res://mod_registry.gd")
const Modern = preload("res://modern_model.gd")
const Scenery = preload("res://scenery_loader.gd")
const CELL_SIZE := 32.0
const MAX_TOTAL := Mods.MAX_SCENERY
const BUILDING_MARGIN := 0.35
const WORK_SLICE_USEC := 4000

# Optional, visual-only decoration. Nothing enters the map document, collision
# world or navigation graph. Only the campaign seed is saved, not instances.
static func new_seed(previous: int = 0) -> int:
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var result := rng.randi_range(1, 2147483647)
	while result == previous: result = rng.randi_range(1, 2147483647)
	return result

static func populate(world: Node3D, folder: String, tree: SceneTree, session_seed: int = 0) -> void:
	if world.has_node("ModScenery"): return
	var packs := Mods.scenery_packs()
	if packs.is_empty(): return
	var parent := Node3D.new(); parent.name = "ModScenery"; world.add_child(parent)
	var exclusions := _exclusions(world, folder)
	var templates: Array[Dictionary] = []
	var layout := HashingContext.new(); layout.start(HashingContext.HASH_SHA256)
	var total := 0
	for pack in packs:
		if total >= MAX_TOTAL: break
		var template := Modern.load_model(pack.scenery.path, {"forward_axis": "+Z", "name": pack.name, "scenery_lods":true})
		if template == null:
			Mods.note("%s: could not load scenery GLB." % pack.name); continue
		var models: Array[Dictionary] = []
		var weight := 0.0
		for entry in pack.scenery.models:
			var mesh := template.find_child(str(entry.node), true, false) as MeshInstance3D
			if mesh == null or mesh.mesh == null or mesh.mesh.get_surface_count() != 1:
				Mods.note("%s: missing single-surface scenery mesh %s." % [pack.name, entry.node]); continue
			var box := mesh.mesh.get_aabb()
			var width := maxf(box.size.x, box.size.z)
			if width <= 0.00001 or not box.position.is_finite() or not box.size.is_finite(): continue
			var anchor := Vector3(box.get_center().x, box.position.y, box.get_center().z)
			# Cutout fans can have transparent mesh below an off-centre visible stem.
			if entry.has("ground_anchor"): anchor = Vector3(entry.ground_anchor[0], entry.ground_anchor[1], entry.ground_anchor[2])
			weight += float(entry.weight)
			models.append({"mesh": mesh.mesh, "name": str(entry.node), "sway": bool(entry.get("sway", false)), "height": box.size.y, "size": float(entry.size), "weight": weight, "width": width,
				"upright": bool(entry.get("upright", entry.get("sway", false))),
				"ground_clearance": float(entry.get("ground_clearance", 0.0)),
				"base": anchor})
		var poses: Array[Dictionary] = []
		var settings: Dictionary = pack.scenery.duplicate()
		# Zero preserves the original fixed layout for saves without a campaign seed.
		settings.seed = (int(settings.seed) ^ session_seed) & 0x7fffffff
		templates.append({"id":pack.id,"name":pack.name,"settings":pack.scenery.duplicate(),"models":models,"weight":weight})
		if not models.is_empty(): poses = await _placements(world, settings, models, weight, exclusions, tree, MAX_TOTAL - total)
		layout.update(var_to_bytes([pack.id, poses]))
		var group := Node3D.new(); group.name = str(pack.id); parent.add_child(group)
		group.set_meta("asset_mod", pack.name)
		await _batch(group, models, poses, tree)
		group.set_meta("decoration_count", poses.size())
		total += poses.size()
		template.free()
	parent.set_meta("decoration_count", total)
	parent.set_meta("scenery_seed", session_seed)
	parent.set_meta("layout_digest", layout.finish().hex_encode())
	world.set_meta("scenery_templates",templates)
	world.set_meta("scenery_exclusions",exclusions)

static func reroll(world: Node3D, tree: SceneTree, session_seed: int, progress: Callable = Callable()) -> Node3D:
	var previous := world.get_node_or_null("ModScenery")
	if previous == null or int(previous.get_meta("scenery_seed",0)) == session_seed: return null
	var parent := Node3D.new(); parent.name = "PendingScenery"; parent.hide(); world.add_child(parent)
	var total := 0
	var exclusions: Array[AABB] = world.get_meta("scenery_exclusions")
	var layout := HashingContext.new(); layout.start(HashingContext.HASH_SHA256)
	for template in world.get_meta("scenery_templates",[]):
		if total >= MAX_TOTAL: break
		var settings: Dictionary = template.settings.duplicate()
		settings.seed = (int(settings.seed)^session_seed)&0x7fffffff
		var models: Array[Dictionary] = template.models
		var poses: Array[Dictionary] = []
		if not models.is_empty(): poses = await _placements(world,settings,models,float(template.weight),exclusions,tree,MAX_TOTAL-total,progress)
		layout.update(var_to_bytes([template.id, poses]))
		var group := Node3D.new(); group.name = str(template.id); parent.add_child(group)
		group.set_meta("asset_mod",template.name); await _batch(group,models,poses,tree)
		group.set_meta("decoration_count",poses.size()); total += poses.size()
	parent.set_meta("decoration_count",total); parent.set_meta("scenery_seed",session_seed)
	parent.set_meta("layout_digest", layout.finish().hex_encode())
	previous.free(); parent.name = "ModScenery"
	# Caller reconnects the existing lighting/sway materials before revealing it.
	return parent

static func _placements(world: Node3D, settings: Dictionary, models: Array[Dictionary], weight: float, exclusions: Array[AABB], tree: SceneTree, remaining: int, progress: Callable = Callable()) -> Array[Dictionary]:
	var poses: Array[Dictionary] = []
	# Mod-file multiplier; absent preserves existing packs and saved layouts.
	var count := mini(roundi(float(settings.count) * float(settings.get("density",1.0))),remaining)
	if count <= 0: return poses
	var rng := RandomNumberGenerator.new(); rng.seed = int(settings.seed)
	var bounds: AABB = world.get_meta("bounds")
	var surface := float(world.get_meta("surface_height"))
	var space := world.get_world_3d().direct_space_state
	var terrain := world.get_node_or_null("WorldCollision")
	# Ground against BSP terrain only. Authored objects have separate clearance
	# bounds, while their live collision poses can change during a saved reroll.
	var ray_exclusions: Array[RID] = []
	for body in world.find_children("*", "PhysicsBody3D", true, false):
		if body != terrain and (body.collision_layer & 1) != 0: ray_exclusions.append(body.get_rid())
	var exclusion_grid := _index_exclusions(exclusions)
	var patch := Vector2.ZERO
	var index := 0
	var attempts := count * 12
	var slice_start := Time.get_ticks_usec()
	for attempt in range(attempts):
		if attempt % 64 == 0 and Time.get_ticks_usec() - slice_start >= WORK_SLICE_USEC:
			if progress.is_valid(): progress.call(float(poses.size()) / float(count))
			await tree.process_frame
			slice_start = Time.get_ticks_usec()
		if poses.size() >= count: break
		if attempt % 96 == 0:
			patch = Vector2(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(bounds.position.z, bounds.end.z))
			# Same-species colonies look natural and share a render batch.
			var choice := rng.randf() * weight
			index = 0
			while index < models.size() - 1 and choice > float(models[index].weight): index += 1
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * float(settings.patch_radius)
		var point := patch + Vector2(cos(angle), sin(angle)) * radius
		if point.x < bounds.position.x or point.x > bounds.end.x or point.y < bounds.position.z or point.y > bounds.end.z: continue
		var model := models[index]
		var scale := float(model.size) * rng.randf_range(0.7, 1.3) / float(model.width)
		var footprint := float(model.width) * scale * 0.55
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, surface - 0.05, point.y), Vector3(point.x, bounds.position.y - 1.0, point.y), 1, ray_exclusions)
		query.hit_back_faces = true
		var hit := space.intersect_ray(query)
		if not _natural_hit(hit, terrain): continue
		var up: Vector3 = hit.normal
		if up.y < 0.0: up = -up
		if up.y < 0.7 or hit.position.y > surface - 0.5: continue
		var origin: Vector3 = hit.position
		var clearance := float(model.get("ground_clearance", 0.0))
		if origin.y + clearance + float(model.get("height", 0.0)) * scale > surface - 0.2: continue
		if not _clear_indexed(origin, footprint, exclusion_grid): continue
		# Reject sharp ledges and uneven roots rather than letting wide coral float.
		var grounded := true
		for delta in [Vector2(footprint, 0), Vector2(-footprint, 0), Vector2(0, footprint), Vector2(0, -footprint)]:
			query.from = origin + Vector3(delta.x, footprint + 0.2, delta.y)
			query.to = origin + Vector3(delta.x, -footprint - 0.2, delta.y)
			var edge := space.intersect_ray(query)
			if not _natural_hit(edge, terrain) or absf((Vector3(edge.position) - origin).dot(up)) > maxf(0.08, footprint * 0.25):
				grounded = false; break
		if not grounded: continue
		var forward := Vector3.FORWARD.slide(up).normalized()
		if forward.length_squared() < 0.1: forward = Vector3.RIGHT.slide(up).normalized()
		var basis := Basis(up.cross(forward).normalized(), up, forward).rotated(up, rng.randf() * TAU).scaled(Vector3.ONE * scale)
		if bool(model.get("upright", model.get("sway", false))):
			# Reuse the same yaw without tipping the growth axis with the seabed.
			var yaw := atan2(basis.z.x, basis.z.z)
			basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
		# Shallow dish corals have a depressed centre at the mesh's minimum Y.
		# Keep that surface above the ground instead of using ordinary root burial.
		var root_offset := clearance if clearance > 0.0 else -minf(0.035, footprint * 0.06)
		var pose := Transform3D(basis, origin + up * root_offset - basis * Vector3(model.base))
		poses.append({"model": index, "pose": pose})
	return poses

static func _natural_hit(hit: Dictionary, terrain: Node) -> bool:
	if hit.is_empty() or hit.collider != terrain: return false
	# Unclassified synthetic terrain remains usable; real BSP collision carries
	# one material classification per face, including buildings baked into it.
	if not terrain.has_meta("plantable_faces"): return true
	var shapes: Array = terrain.get_meta("plantable_faces")
	var shape := int(hit.get("shape", -1)); var face := int(hit.get("face_index", -1))
	return shape >= 0 and shape < shapes.size() and face >= 0 and face < shapes[shape].size() and shapes[shape][face] == 1

static func _index_exclusions(exclusions: Array[AABB]) -> Dictionary:
	var result := {}
	for box in exclusions:
		for x in range(floori(box.position.x / CELL_SIZE), floori(box.end.x / CELL_SIZE) + 1):
			for z in range(floori(box.position.z / CELL_SIZE), floori(box.end.z / CELL_SIZE) + 1):
				var cell := Vector2i(x, z)
				if not result.has(cell):
					var boxes: Array[AABB] = []; result[cell] = boxes
				result[cell].append(box)
	return result

static func _clear_indexed(point: Vector3, radius: float, grid: Dictionary) -> bool:
	for x in range(floori((point.x - radius) / CELL_SIZE), floori((point.x + radius) / CELL_SIZE) + 1):
		for z in range(floori((point.z - radius) / CELL_SIZE), floori((point.z + radius) / CELL_SIZE) + 1):
			var cell := Vector2i(x, z)
			if grid.has(cell) and not clear_of_exclusions(point, radius, grid[cell]): return false
	return true

static func clear_of_exclusions(point: Vector3, radius: float, exclusions: Array[AABB]) -> bool:
	for box in exclusions:
		if box.grow(radius).has_point(point): return false
	return true

static func _exclusions(world: Node3D, folder: String) -> Array[AABB]:
	var boxes := _authored_exclusions(world)
	var offset: Vector3 = world.get_meta("database_offset", Vector3.ZERO)
	var tables := Scenery.read_database(folder.path_join("DATA/SCEN1.DDB"))
	var rendered := {}
	var scenery := world.get_node_or_null("Scenery")
	if scenery != null:
		for node in scenery.get_children():
			if node.has_node("SceneryCollision"):
				rendered[str(node.get_meta("entity_id", ""))] = true
	# Existing buildings use their actual mesh bounds, rather than a second,
	# wider database-marker box. Keep unrendered gameplay/mission markers clear.
	for row in tables.get("Objects", []):
		if int(row.get("ObjectID", -1)) in [26, 27]: continue
		var identity := preload("res://entity_identity.gd").authored("original/objects", int(row.index))
		if rendered.has(identity): continue
		var point := Scenery.placement(row, offset).origin
		if not point.is_finite(): continue
		boxes.append(AABB(point - Vector3.ONE * 4.0, Vector3.ONE * 8.0))
	return boxes

static func _authored_exclusions(world: Node3D) -> Array[AABB]:
	var boxes: Array[AABB] = []
	var spawn: Vector3 = world.get_meta("player_spawn", Vector3.ZERO)
	boxes.append(AABB(spawn - Vector3.ONE * 8.0, Vector3.ONE * 16.0))
	# Honor the final authored transforms, including moved/added scenery.
	for branch in [world.get_node_or_null("Scenery"), world.get_node_or_null("Added")]:
		if branch == null: continue
		for node in branch.find_children("*", "Node3D", true, false):
			if node.has_meta("editor_dropoff"):
				boxes.append(AABB(node.global_position - Vector3.ONE * 2.5, Vector3.ONE * 5.0))
			if not node is MeshInstance3D or node.mesh == null: continue
			# Searchlight beams sweep while the level loads and do not occupy
			# space. Excluding their changing bounds makes saved layouts repeatable.
			if node.name == "SoftBeam":
				var grandparent: Node = node.get_parent().get_parent() if node.get_parent() != null else null
				if grandparent != null and grandparent.get_script() == preload("res://searchlight.gd"): continue
			var owner: Node = node.get_parent()
			if owner != null and (owner.has_meta("approximate_scatter") or str(owner.name).begins_with("Plant")): continue
			boxes.append((node.global_transform * node.mesh.get_aabb()).grow(BUILDING_MARGIN))
	return boxes

static func _batch(parent: Node3D, models: Array[Dictionary], poses: Array[Dictionary], tree: SceneTree = null) -> void:
	var batches := {}
	var slice_start := Time.get_ticks_usec()
	for item in poses:
		var pose: Transform3D = item.pose
		var cell := Vector2i(floori(pose.origin.x / CELL_SIZE), floori(pose.origin.z / CELL_SIZE))
		var key := "%d:%d:%d" % [item.model, cell.x, cell.y]
		if not batches.has(key): batches[key] = {"model": int(item.model), "cell": cell, "poses": []}
		batches[key].poses.append(pose)
	for batch in batches.values():
		var multi := MultiMesh.new(); multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = models[batch.model].mesh
		multi.instance_count = batch.poses.size()
		var anchor := Vector3(batch.cell.x * CELL_SIZE, 0, batch.cell.y * CELL_SIZE)
		for index in batch.poses.size():
			var pose: Transform3D = batch.poses[index]; pose.origin -= anchor
			multi.set_instance_transform(index, pose)
		var node := MultiMeshInstance3D.new(); node.multimesh = multi
		node.set_meta("scenery_model", str(models[batch.model].get("name", "")))
		node.set_meta("marine_plant", bool(models[batch.model].get("sway", false)))
		node.position = anchor
		node.visibility_range_end = 100.0; node.visibility_range_end_margin = 12.0
		# Reuse the existing lights and Graphics shadow quality/distance limits.
		# The spatial batches remain culled at their normal visibility range.
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(node)
		if tree != null and Time.get_ticks_usec() - slice_start >= WORK_SLICE_USEC:
			await tree.process_frame
			slice_start = Time.get_ticks_usec()
