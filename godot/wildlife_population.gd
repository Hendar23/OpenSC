extends Node3D
const Document = preload("res://map_document.gd")
const Fish = preload("res://fish_controller.gd")
const Creatures = preload("res://creature_loader.gd")
var document := {}
var templates := {}
var world: Node3D
var folder := ""
var generation := 0
var player: Node3D
var simulating := true
var spawned_groups: Array[String] = []
var terrain_exclusions: Array[RID] = []
func setup(parent_world: Node3D, game_folder: String, data: Dictionary) -> void:
	world = parent_world
	folder = game_folder
	document = data
	for body in world.find_children("SceneryCollision", "StaticBody3D", true, false): terrain_exclusions.append(body.get_rid())
	for species in data.species:
		var template := Document.load_model(species.model, folder, true)
		if template != null: templates[species.id] = template
		else: push_warning("Wildlife model unavailable: " + str(species.model))
	reroll(false)
func _exit_tree() -> void:
	for template in templates.values(): template.free()
func reroll(advance: bool = true) -> void:
	if advance: generation += 1
	for child in get_children(): child.free()
	spawned_groups.clear()
	var random := RandomNumberGenerator.new()
	random.seed = int(document.get("seed", 8675309)) + generation * 104729
	var definitions := {}
	for species in document.species: definitions[species.id] = species
	var count := 0
	for group in document.groups:
		var roll := random.randf() * 100.0
		if float(group.chance) <= 0.0 or (float(group.chance) < 100.0 and roll >= float(group.chance)): continue
		if not templates.has(group.species): continue
		var species: Dictionary = definitions[group.species].duplicate(true)
		species.merge(group.get("overrides", {}), true)
		var template: Node3D = templates[group.species]
		var boxes: Array[AABB] = []
		Creatures._collect_bounds(template, template.transform, boxes)
		var box := AABB(Vector3(-0.25, -0.25, -0.25), Vector3.ONE * 0.5)
		if not boxes.is_empty():
			box = boxes[0]
			for i in range(1, boxes.size()): box = box.merge(boxes[i])
		var members: Array[Node3D] = []
		var home := Document.vector(group.position)
		for member in range(random.randi_range(int(group.count_min), int(group.count_max))):
			var size := random.randf_range(float(species.scale_min), float(species.scale_max)) / 100.0
			var radius := maxf(0.08, box.size.length() * 0.5 * size)
			var point := Vector3(INF, INF, INF)
			for attempt in range(24):
				var spread := minf(float(group.radius) * 0.4, 5.0)
				var candidate := home + Vector3(random.randf_range(-spread, spread), random.randf_range(-0.5, 0.5), random.randf_range(-spread, spread))
				if species.mobility == "crawling": candidate = floor_point(candidate, radius)
				if candidate.is_finite() and candidate.y + radius < float(world.get_meta("surface_height")) and Creatures._clear(world, candidate, radius): point = candidate; break
			if not point.is_finite(): continue
			var visual := template.duplicate() as Node3D
			visual.scale *= size
			# Turn around the model's body rather than an offset authoring origin.
			visual.position -= box.get_center() * size
			var fish := Fish.new()
			fish.name = "Creature_%s_%d" % [group.id, member]
			fish.set_meta("species", species.id)
			fish.set_meta("spawn_group", group.id)
			fish.set_meta("spawn_position", point)
			fish.setup(visual, point, world.get_meta("bounds"), world.get_meta("surface_height"), radius, random.randi())
			fish.home = home
			fish.roam_radius = float(group.radius)
			fish.swim_speed = float(species.speed) * random.randf_range(0.9, 1.1)
			fish.turn_speed = float(species.get("turn_speed", 60.0))
			fish.pitch_limit = float(species.get("pitch_limit", 25.0))
			fish.startle_duration = float(species.get("startle_duration", 0.3))
			fish.startle_speed_multiplier = float(species.get("startle_speed_multiplier", 2.8))
			fish.startle_turn_speed = float(species.get("startle_turn_speed", 720.0))
			fish.group_behaviour = species.group_behaviour
			fish.response = species.response
			fish.detection_distance = float(species.detection)
			fish.mobility = species.mobility
			fish.population = self
			fish.group_members = members
			fish._choose_goal()
			add_child(fish)
			fish.set_physics_process(simulating)
			members.append(fish)
			count += 1
		if not members.is_empty(): spawned_groups.append(group.id)
	world.set_meta("ambient_fish_count", count)
func floor_point(point: Vector3, radius: float) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, float(world.get_meta("surface_height")) - 0.1, point.z), Vector3(point.x, world.get_meta("bounds").position.y - 1.0, point.z), 1)
	query.exclude = terrain_exclusions
	query.hit_back_faces = true
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	return Vector3(hit.position) + Vector3.UP * (radius + 0.15) if not hit.is_empty() else Vector3(INF, INF, INF)
func set_simulating(on: bool) -> void:
	simulating = on
	for child in get_children(): child.set_physics_process(on)
