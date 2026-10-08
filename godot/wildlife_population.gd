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
var definitions := {}
var model_bounds := {}
var random_groups: Array[Dictionary] = []
var streaming := false
var density := 1.0
var visibility_range := 30.0
var view_camera: Camera3D
var session_seed := -1
var stream_timer := 0.0
var gameplay_catalogue := {}
var death_texture: Texture2D
var death_sound: AudioStream
var death_frames: Array[Texture2D] = []
var death_flesh_texture: Texture2D
var zapper_frames: Array[Texture2D] = []
var zapper_sound: AudioStream
var creature_cells := {}
var cells_frame := -1
const CELL_SIZE := 8.0
func nearby_creatures(point: Vector3, distance: float) -> Array[Node3D]:
	# One shared spatial index per perception tick, rather than a full scan per fish.
	var tick := int(Time.get_ticks_msec() / 200)
	if tick != cells_frame:
		cells_frame = tick; creature_cells.clear()
		for child in get_children():
			if child.dead or not child.get_meta("wildlife_awake",true) or not child.is_physics_processing(): continue
			var cell := Vector3i((child.global_position / CELL_SIZE).floor())
			if not creature_cells.has(cell): creature_cells[cell] = []
			creature_cells[cell].append(child)
	var result: Array[Node3D] = []
	var low := Vector3i(((point - Vector3.ONE * distance) / CELL_SIZE).floor())
	var high := Vector3i(((point + Vector3.ONE * distance) / CELL_SIZE).floor())
	# Iterate occupied cells when a mod chooses an exceptionally large detection range.
	var cells: Array = []
	if (high.x - low.x + 1) * (high.y - low.y + 1) * (high.z - low.z + 1) <= creature_cells.size():
		for x in range(low.x,high.x + 1):
			for y in range(low.y,high.y + 1):
				for z in range(low.z,high.z + 1): cells.append(Vector3i(x,y,z))
	else: cells = creature_cells.keys()
	for cell in cells:
		if cell.x < low.x or cell.x > high.x or cell.y < low.y or cell.y > high.y or cell.z < low.z or cell.z > high.z: continue
		for body in creature_cells.get(cell,[]):
			if is_instance_valid(body) and point.distance_squared_to(body.global_position) <= distance * distance: result.append(body)
	return result
func setup(parent_world: Node3D, game_folder: String, data: Dictionary, stream_near_player: bool = false) -> void:
	world = parent_world
	folder = game_folder
	document = data
	streaming = stream_near_player
	death_texture = preload("res://clump_loader.gd")._load_texture(folder,"BUBBLE","BUBBLEM",{})
	death_sound = preload("res://submarine_weapons.gd")._sound(folder,"audio.creature.death","SPLAT")
	death_frames = preload("res://creature_death.gd").load_gore(folder)
	death_flesh_texture = preload("res://clump_loader.gd")._load_texture(folder,"BEEF2","",{})
	var zapper_cache := {}
	for index in range(1,4):
		var frame := preload("res://clump_loader.gd")._load_texture(folder,"ZAPPER%d" % index,"ZAPPER%dM" % index,zapper_cache)
		if frame != null: zapper_frames.append(frame)
	zapper_sound = preload("res://audio_loop.gd").prepare(preload("res://submarine_weapons.gd")._sound(folder,"audio.weapon.zapper","ELECTRIC"),true,35)
	if session_seed < 0:
		var session := RandomNumberGenerator.new()
		if streaming: session.randomize(); session_seed = session.randi()
		else: session_seed = int(document.get("seed",8675309))
	for body in world.find_children("SceneryCollision", "StaticBody3D", true, false): terrain_exclusions.append(body.get_rid())
	for species in data.species:
		definitions[species.id] = species
		var template := Document.load_model(species.model, folder, true)
		if template != null:
			templates[species.id] = template
			var boxes: Array[AABB] = []
			Creatures._collect_bounds(template,template.transform,boxes)
			var box := AABB(Vector3(-0.25,-0.25,-0.25),Vector3.ONE * 0.5)
			if not boxes.is_empty():
				box = boxes[0]
				for index in range(1,boxes.size()): box = box.merge(boxes[index])
			model_bounds[species.id] = box
		else: push_warning("Wildlife model unavailable: " + str(species.model))
	reroll(false)
func _exit_tree() -> void:
	for template in templates.values(): template.free()
func reroll(advance: bool = true) -> void:
	if advance: generation += 1
	for child in get_children(): child.free()
	spawned_groups.clear()
	creature_cells.clear(); cells_frame = -1
	random_groups.clear()
	var random := RandomNumberGenerator.new()
	random.seed = session_seed + generation * 104729
	for group in document.groups:
		var roll := random.randf() * 100.0
		if float(group.chance) <= 0.0 or (float(group.chance) < 100.0 and roll >= float(group.chance)): continue
		_spawn_group(group,random)
	for species in document.species:
		if not species.get("random_spawn",false) or not templates.has(species.id): continue
		var amount := random.randi_range(int(species.get("groups_min",3)),int(species.get("groups_max",8)))
		var scaled := amount * density
		amount = int(floorf(scaled)) + (1 if random.randf() < scaled - floorf(scaled) else 0)
		for index in range(amount):
			if random.randf() * 100.0 >= float(species.get("spawn_chance",100.0)): continue
			var home := _random_home(species,random)
			if not home.is_finite(): continue
			var group := {"id": "random_%s_%d" % [species.id,index], "species": species.id,"position": Document.array(home),"count_min": species.get("count_min",1),"count_max": species.get("count_max",10),"radius": species.get("roam_radius",10.0)}
			random_groups.append({"group": group,"seed": random.randi(),"members": [],"attempted": false})
	_stream_update(true)
	world.set_meta("ambient_fish_count",active_count())

func _random_home(species: Dictionary, random: RandomNumberGenerator) -> Vector3:
	var bounds: AABB = world.get_meta("bounds")
	var box: AABB = model_bounds[species.id]
	var radius := maxf(0.08,box.size.length() * 0.5 * float(species.scale_max) / 100.0)
	var surface := float(world.get_meta("surface_height"))
	for attempt in range(80):
		var point := Vector3(random.randf_range(bounds.position.x + radius,bounds.end.x - radius),0,random.randf_range(bounds.position.z + radius,bounds.end.z - radius))
		point = floor_point(point,radius)
		if not point.is_finite() or point.y >= surface - radius - 0.2: continue
		if species.mobility != "crawling": point.y = random.randf_range(point.y,surface - radius - 0.2)
		# Weapon-only wildlife collisions let different groups share water.
		if Creatures._clear(world,point,radius): return point
	return Vector3(INF,INF,INF)

func set_density(value: float) -> void:
	var next := clampf(value,0.0,3.0)
	if is_equal_approx(next,density): return
	density = next
	if world != null: reroll(false)

func _physics_process(delta: float) -> void:
	if not streaming: return
	stream_timer -= delta
	if stream_timer <= 0.0:
		stream_timer = 0.1
		_stream_update()

func _visible_spawn(point: Vector3, center: Vector3, body_radius: float = 0.0) -> bool:
	var viewer := view_camera.global_position if is_instance_valid(view_camera) else center
	if viewer.distance_to(point) > visibility_range + body_radius + 0.75: return false
	if not is_instance_valid(view_camera): return true
	if not view_camera.is_position_in_frustum(point): return false
	var query := PhysicsRayQueryParameters3D.create(view_camera.global_position,point,1)
	query.hit_back_faces = true
	return world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _activation_margin() -> float:
	return 4.0 + player.global_position.distance_to(view_camera.global_position) if is_instance_valid(player) and is_instance_valid(view_camera) else 4.0

func _stream_update(initial: bool = false) -> void:
	var center: Vector3 = player.global_position if is_instance_valid(player) else world.get_meta("player_spawn",world.get_meta("bounds").get_center())
	# A small band outside the fog prepares creatures before they are visible.
	# Park individual fish, so one nearby member cannot retain a distant shoal.
	var activation := visibility_range + _activation_margin()
	var retirement := activation + 2.0
	var budget := 2 if not initial and streaming else 100000
	var viewer := view_camera.global_position if is_instance_valid(view_camera) else center
	var planes: Array = view_camera.get_frustum() if is_instance_valid(view_camera) else []
	if streaming:
		for fish in get_children():
			if fish.dead: continue
			var distance: float = fish.global_position.distance_to(center)
			if distance > retirement + fish.radius: _set_awake(fish,false)
			elif not bool(fish.get_meta("wildlife_awake",true)) and distance <= activation and (initial or not _visible_spawn(fish.global_position,center,fish.radius)):
				_set_awake(fish,true)
			_update_activity(fish,viewer,planes)
	for state in random_groups:
		var group: Dictionary = state.group
		var home := Document.vector(group.position)
		var members: Array = state.members
		if not members.is_empty():
			# Random populations need no retained offscreen bodies. Recreate
			# members on return, before they become visible, using a fresh roll.
			if streaming and home.distance_to(center) > retirement and members.all(func(fish: Node3D) -> bool: return fish.dead or fish.global_position.distance_to(center) > retirement + fish.radius):
				for fish in members: fish.free()
				members.clear(); state.attempted = false
				state.seed = int(state.seed) + 104729
				spawned_groups.erase(group.id)
			continue
		if state.attempted or budget <= 0: continue
		if streaming and (home.distance_to(center) > activation or (not initial and _visible_spawn(home,center))): continue
		var random := RandomNumberGenerator.new(); random.seed = int(state.seed)
		state.members = _spawn_group(group,random,streaming and not initial,streaming)
		state.attempted = true; budget -= 1
	world.set_meta("ambient_fish_count",active_count())

func active_count() -> int:
	var count := 0
	for fish in get_children():
		if not fish.dead and fish.get_meta("wildlife_awake",true): count += 1
	return count

func _set_awake(fish: Node3D, awake: bool) -> void:
	if fish.dead: return
	if bool(fish.get_meta("wildlife_awake",true)) == awake: return
	fish.set_meta("wildlife_awake",awake)
	if not awake and fish.combat != null: fish.combat._stop_weapon()
	# Disable the whole dormant subtree, including any mod-provided animation
	# players or scripts, rather than only the creature controller callbacks.
	fish.process_mode = Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED
	fish.visible = awake
	fish.set_physics_process(awake and simulating)
	fish.set_process(awake and simulating)
	fish.collision_mask = 7 if awake else 0
	var collider := fish.get_child(0) as CollisionShape3D
	if collider != null: collider.set_deferred("disabled",not awake)
	if awake: fish.reset_physics_interpolation()

func _update_activity(fish: Node3D, viewer: Vector3, planes: Array) -> void:
	var awake: bool = not fish.dead and bool(fish.get_meta("wildlife_awake",true))
	var in_range := viewer.distance_squared_to(fish.global_position) <= pow(visibility_range + fish.radius,2)
	var on_screen := in_range
	for plane in planes:
		if plane.distance_to(fish.global_position) > fish.radius: on_screen = false; break
	fish.visual_animation_enabled = awake and on_screen
	# Keep nearby AI operating behind the player; creatures in the preparation
	# band beyond the absolute view distance need neither AI nor pose uploads.
	fish.set_physics_process(simulating and awake and in_range)
	fish.set_process(simulating and awake and on_screen)

func _spawn_group(group: Dictionary, random: RandomNumberGenerator, avoid_visible: bool = false, limit_to_visible_range: bool = false) -> Array[Node3D]:
	var members: Array[Node3D] = []
	if not templates.has(group.species): return members
	var species: Dictionary = definitions[group.species].duplicate(true)
	species.merge(group.get("overrides",{}),true)
	var template: Node3D = templates[group.species]
	var box: AABB = model_bounds[group.species]
	var home := Document.vector(group.position)
	var player_position: Vector3 = player.global_position if is_instance_valid(player) else world.get_meta("player_spawn",home)
	for member in range(random.randi_range(int(group.count_min),int(group.count_max))):
		var size := random.randf_range(float(species.scale_min), float(species.scale_max)) / 100.0
		var radius := maxf(0.08, box.size.length() * 0.5 * size)
		var point := Vector3(INF, INF, INF)
		for attempt in range(24):
			var spread := minf(float(group.radius) * 0.4, 5.0)
			var candidate := home + Vector3(random.randf_range(-spread, spread), random.randf_range(-0.5, 0.5), random.randf_range(-spread, spread))
			if species.mobility == "crawling": candidate = floor_point(candidate, radius)
			if limit_to_visible_range and candidate.distance_to(player_position) > visibility_range + _activation_margin(): continue
			if avoid_visible and candidate.is_finite() and _visible_spawn(candidate,player_position,radius): continue
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
		fish.animation_speed = float(species.get("animation_speed",1.0))
		fish.pitch_limit = float(species.get("pitch_limit", 25.0))
		fish.startle_duration = float(species.get("startle_duration", 0.3))
		fish.startle_speed_multiplier = float(species.get("startle_speed_multiplier", 2.8))
		fish.startle_turn_speed = float(species.get("startle_turn_speed", 720.0))
		fish.group_behaviour = species.group_behaviour
		fish.response = species.response
		fish.detection_distance = float(species.detection)
		fish.mobility = species.mobility
		fish.configure_health(Document.creature_health(species,gameplay_catalogue))
		fish.configure_combat(species)
		fish.death_texture = death_texture; fish.death_sound = death_sound; fish.death_frames = death_frames
		fish.death_flesh_texture = death_flesh_texture
		if fish.mobility == "crawling": fish.configure_crawler(box.size * size)
		fish.population = self
		fish.group_members = members
		fish._choose_goal()
		add_child(fish)
		if fish.mobility == "crawling": fish._ground_on_terrain(1.0)
		fish.set_physics_process(simulating)
		fish.set_process(simulating)
		members.append(fish)
	if not members.is_empty(): spawned_groups.append(group.id)
	return members
func floor_point(point: Vector3, radius: float) -> Vector3:
	var hit := floor_contact(point)
	return Vector3(hit.position) + Vector3.UP * (radius + 0.15) if not hit.is_empty() else Vector3(INF, INF, INF)

func floor_contact(point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, float(world.get_meta("surface_height")) - 0.1, point.z), Vector3(point.x, world.get_meta("bounds").position.y - 1.0, point.z), 1)
	query.exclude = terrain_exclusions
	query.hit_back_faces = true
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	# Legacy terrain contains triangles with both winding directions. A ground
	# probe always needs the upward-facing normal, including back-face hits.
	if not hit.is_empty() and Vector3(hit.normal).y < 0.0: hit.normal = -Vector3(hit.normal)
	return hit
func set_simulating(on: bool) -> void:
	simulating = on
	var center: Vector3 = player.global_position if is_instance_valid(player) else world.get_meta("player_spawn",Vector3.ZERO)
	var viewer := view_camera.global_position if is_instance_valid(view_camera) else center
	var planes: Array = view_camera.get_frustum() if is_instance_valid(view_camera) else []
	for child in get_children():
		if not on and child.combat != null: child.combat._stop_weapon()
		if streaming: _update_activity(child,viewer,planes)
		else:
			var running: bool = on and not child.dead and bool(child.get_meta("wildlife_awake",true))
			child.set_physics_process(running); child.set_process(running)
