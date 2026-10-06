extends Node3D

# Separate menu actors reuse loaded visuals and the normal fish controller.
const Fish = preload("res://fish_controller.gd")
const Creatures = preload("res://creature_loader.gd")
const Bubbles = preload("res://propeller_bubbles.gd")
var game: Node3D
var view: Camera3D
var actors: Array[Dictionary] = []
var menu_population: Node3D
var group_count := 0
var generation := 0
var hidden: Array[Dictionary] = []
var submarine: Node3D
var wake: Node3D
var propeller_audio: AudioStreamPlayer3D
var daylight := preload("res://day_night_cycle.gd").new()
var active := false
var time := 0.0
var pass_time := -1.0
var next_pass := 4.0
var pass_direction := 1.0
var pass_depth := 4.0
var random := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	random.randomize()
	daylight.hour = 12.0
	view = Camera3D.new(); view.fov = 65; add_child(view)
	hide()

func setup(owner_game: Node3D) -> void:
	game = owner_game
	menu_population = preload("res://wildlife_population.gd").new()
	menu_population.world = game.world_root
	if game.wildlife != null: menu_population.terrain_exclusions = game.wildlife.terrain_exclusions.duplicate()
	add_child(menu_population)
	_position_camera()
	submarine = Node3D.new(); submarine.name = "MenuSubmarine"; add_child(submarine)
	var visual: Node3D = game.model.duplicate(0); submarine.add_child(visual)
	wake = Bubbles.new(); add_child(wake); wake.set_physics_process(false)
	wake.configure(game.pilot.bubbles.material.albedo_texture)
	wake.surface_height = game.pilot.surface_height
	propeller_audio = AudioStreamPlayer3D.new()
	propeller_audio.name = "MenuPropellerAudio"
	var original: AudioStreamPlayer = game.pilot.submarine_audio.players.get("main_propeller")
	if original != null:
		propeller_audio.stream = original.stream
		propeller_audio.bus = original.bus
	propeller_audio.unit_size = 6.0
	propeller_audio.max_distance = 30.0
	propeller_audio.volume_db = -80.0
	submarine.add_child(propeller_audio)
	submarine.hide()
	_add_plants()

func _position_camera() -> void:
	var document := preload("res://map_document.gd").load_active() if game.use_map_overrides else {}
	if document.has("menu_camera"):
		view.transform = preload("res://map_document.gd").decode(document.menu_camera.transform)
		view.fov = float(document.menu_camera.fov); view.far = game.camera.far
		return
	# Scenic framing is independent of the editable New Game spawn.
	var config: Dictionary = game.front_end.menu_config
	var anchor := Vector3(config.camera_anchor[0],config.camera_anchor[1],config.camera_anchor[2])
	view.position = anchor + Vector3(config.camera_offset[0],config.camera_offset[1],config.camera_offset[2])
	view.position.y = minf(view.position.y,game.pilot.surface_height - 0.4)
	view.look_at(anchor + Vector3(config.look_offset[0],config.look_offset[1],config.look_offset[2]))
	view.far = game.camera.far

func _add_plants() -> void:
	var templates: Array[Node3D] = []
	for node in game.world_root.find_children("*","Node3D",true,false):
		if str(node.get_meta("editor_model","")).to_upper() in ["BUSH1","BUSH2","BUSH3","BUSH4"]:
			templates.append(node)
			if templates.size() == 3: break
	for index in templates.size():
		var point := view.global_position - view.global_basis.z * (6.0 + index * 2)
		point += view.global_basis.x * (-4.0 if index % 2 == 0 else 4.0)
		var query := PhysicsRayQueryParameters3D.create(point,point + Vector3.DOWN * 30,1)
		var floor_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
		if floor_hit.is_empty(): continue
		var plant := templates[index].duplicate(0) as Node3D
		_remove_collisions(plant)
		add_child(plant); plant.global_position = floor_hit.position

func _remove_collisions(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D: child.free()
		else: _remove_collisions(child)


func open() -> void:
	if active: return
	_refresh_wildlife()
	active = true; show(); hidden.clear()
	for node in [game.pilot,game.cockpit_hud,game.canvas,game.particles,game.world_root.get_node_or_null("AmbientFish")]:
		if node != null:
			hidden.append({"node":node,"visible":node.visible}); node.hide()
	if game.docked_screen != null:
		var dock_hud: CanvasLayer = game.docked_screen.get_parent()
		hidden.append({"node":dock_hud,"visible":dock_hud.visible}); dock_hud.hide()
	for node in game.find_children("CreatureBurst*","Node3D",true,false):
		hidden.append({"node":node,"visible":node.visible}); node.hide()
	for actor in actors: actor.node.set_physics_process(true)
	view.make_current()

func close() -> void:
	if not active: return
	active = false; hide(); wake.clear()
	propeller_audio.stop()
	for actor in actors: actor.node.set_physics_process(false)
	for entry in hidden:
		if is_instance_valid(entry.node): entry.node.visible = entry.visible
	hidden.clear()
	if is_instance_valid(game.camera): game.camera.make_current()

func _process(delta: float) -> void:
	if not active: return
	time += delta
	if pass_time < 0:
		next_pass -= delta
		if next_pass <= 0:
			pass_time = 0; pass_direction = -1 if random.randf() < 0.5 else 1
			pass_depth = random.randf_range(3.5,5.0); submarine.show()
	else:
		pass_time += delta
		var direction := view.global_basis.x * pass_direction
		submarine.global_position = view.global_position - view.global_basis.z * pass_depth + direction * (-9.0 + pass_time * 1.2)
		submarine.global_basis = Basis.looking_at(direction)
		_update_propeller_audio()
		for node in submarine.find_children("*Propeller","Node3D",true,false):
			node.basis = node.get_meta("rest_basis",Basis.IDENTITY) * Basis(Vector3.BACK,time * TAU * 5)
		wake.emit_from(0,submarine.global_position - direction * 0.4,-direction,1,16,delta)
		if pass_time > 15:
			pass_time = -1; next_pass = random.randf_range(18,40); submarine.hide()
			propeller_audio.stop()
	wake.advance(delta)

func _spawn_fish_group(candidate: Dictionary, group: int) -> void:
	var members: Array[Node3D] = []
	var species: Dictionary = candidate.species
	var box: AABB = candidate.box
	var home := view.global_position - view.global_basis.z * (7.0 + group * 2.0)
	home += view.global_basis.x * (-3.0 if group % 2 == 0 else 3.0)
	home.y = minf(home.y - 1.0,game.pilot.surface_height - 1.5)
	for member in range(random.randi_range(int(species.get("count_min",3)),int(species.get("count_max",5)))):
		var size := random.randf_range(float(species.get("scale_min",65)),float(species.get("scale_max",95))) / 100.0
		var radius := maxf(0.08,box.size.length() * 0.5 * size)
		var point := Vector3(INF,INF,INF)
		for attempt in range(40):
			var proposed := home + Vector3(random.randf_range(-3,3),random.randf_range(-1,1),random.randf_range(-3,3))
			proposed.y = minf(proposed.y,game.pilot.surface_height - radius - 0.2)
			if species.get("mobility","swimming") == "crawling": proposed = menu_population.floor_point(proposed,radius)
			if proposed.is_finite() and Creatures._clear(game.world_root,proposed,radius): point = proposed; break
		if not point.is_finite(): continue
		var visual: Node3D = candidate.template.duplicate(0)
		visual.scale *= size; visual.position -= box.get_center() * size
		var fish := Fish.new()
		fish.name = "MenuFish_%d_%d" % [group,member]
		fish.setup(visual,point,game.world_root.get_meta("bounds"),game.pilot.surface_height,radius,random.randi())
		# Terrain still blocks these fish, but weapons and player queries cannot see them.
		fish.collision_layer = 0
		fish.home = point if species.get("mobility","") == "crawling" else home
		fish.roam_radius = float(species.get("roam_radius",10.0))
		fish.swim_speed = float(species.get("speed",1.3)) * random.randf_range(0.9,1.1)
		fish.turn_speed = float(species.get("turn_speed",60))
		fish.pitch_limit = float(species.get("pitch_limit",25))
		fish.group_behaviour = str(species.get("group_behaviour","schooling"))
		fish.response = str(species.get("response","ignore"))
		fish.detection_distance = float(species.get("detection",8.0))
		fish.startle_duration = float(species.get("startle_duration",0.3))
		fish.startle_speed_multiplier = float(species.get("startle_speed_multiplier",2.8))
		fish.startle_turn_speed = float(species.get("startle_turn_speed",720.0))
		fish.group_members = members
		fish.population = menu_population
		fish.mobility = str(species.get("mobility","swimming"))
		fish.set_meta("species",species.get("id","ambient"))
		if fish.mobility == "crawling": fish.configure_crawler(box.size * size)
		fish.direction = view.global_basis.x * (-1.0 if group % 2 == 0 else 1.0)
		fish._choose_goal()
		menu_population.add_child(fish)
		if fish.mobility == "crawling": fish._ground_on_terrain(1.0)
		fish.set_physics_process(false)
		members.append(fish); actors.append({"node":fish,"group":group})

func _update_propeller_audio() -> void:
	if propeller_audio.stream == null: return
	var settings: Dictionary = game.pilot.submarine_audio.tuning.settings
	var gain := float(settings.master_volume) + float(settings.main_propeller_volume)
	var fade := minf(clampf(pass_time,0.0,1.0),clampf(15.0 - pass_time,0.0,1.0))
	propeller_audio.volume_db = -80.0 if float(settings.master_volume) <= -60.0 or float(settings.main_propeller_volume) <= -60.0 else gain + linear_to_db(maxf(0.0001,fade * 0.7))
	propeller_audio.pitch_scale = lerpf(float(settings.main_propeller_pitch_min),float(settings.main_propeller_pitch_max),0.7) + float(settings.main_propeller_speed_pitch) * 0.2
	if not propeller_audio.playing: propeller_audio.play()

func _refresh_wildlife() -> void:
	for actor in actors: actor.node.free()
	actors.clear()
	generation += 1
	# Templates have already been imported and assigned their water materials.
	var candidates: Array[Dictionary] = []
	if game.wildlife != null:
		for id in game.wildlife.templates:
			var species: Dictionary = game.wildlife.definitions[id]
			candidates.append({"template":game.wildlife.templates[id],"species":species,"box":game.wildlife.model_bounds[id]})
	else:
		var population: Node3D = game.world_root.get_node_or_null("AmbientFish")
		if population != null:
			var seen := {}
			for fish in population.get_children():
				var id := str(fish.get_meta("species",fish.name))
				if seen.has(id): continue
				seen[id] = true
				for child in fish.get_children():
					if child is Node3D and not child is CollisionShape3D:
						var boxes: Array[AABB] = []
						Creatures._collect_bounds(child,child.transform,boxes)
						var box := AABB(Vector3(-0.2,-0.2,-0.2),Vector3.ONE * 0.4)
						if not boxes.is_empty():
							box = boxes[0]
							for index in range(1,boxes.size()): box = box.merge(boxes[index])
						candidates.append({"template":child,"species":{"id":id,"scale_min":100,"scale_max":100,"count_min":4,"count_max":4,"speed":fish.swim_speed,"roam_radius":fish.roam_radius,"group_behaviour":fish.group_behaviour,"mobility":fish.mobility},"box":box})
						break
	# Choose different species without changing the gameplay population.
	for index in range(candidates.size() - 1,0,-1):
		var other := random.randi_range(0,index)
		var entry := candidates[index]; candidates[index] = candidates[other]; candidates[other] = entry
	group_count = random.randi_range(2,3) if not candidates.is_empty() else 0
	for group in range(group_count):
		_spawn_fish_group(candidates[group % candidates.size()],group)
