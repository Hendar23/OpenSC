extends Node3D
## Local ground journeys. Original TRADCAR/TECHTRUCK shields and models retained.
signal attacked(faction: int)
signal destroyed(entity_id: String, attacker_id: String)
var mission_owner := ""
var local_simulation := true
var damage_attacker: Node3D
var report_player_attack := true
const MODELS := ["TRADCAR","TECHTRUK"]
const GRID_SPACING := 0.8
const DEFAULTS := {"npc_speed":0.4,"npc_radius":8.0,"npc_wait_min":2.0,"npc_wait_max":6.0,"npc_health":4.0,"npc_sustain":0.1,"npc_respawn":true,"npc_respawn_delay":120.0,"npc_faction":1}
const LIMITS := {"npc_speed":[0.05,3.0],"npc_radius":[2.0,30.0],"npc_wait_min":[0.0,300.0],"npc_wait_max":[0.0,300.0],"npc_health":[0.1,10000.0],"npc_sustain":[0.0,100.0],"npc_respawn_delay":[1.0,3600.0],"npc_faction":[0,5]}
var tuning := DEFAULTS.duplicate()
var health = preload("res://npc_health.gd").new()
var dead := false
var running := false
var body: CharacterBody3D
var bounds := AABB()
var home := Transform3D.IDENTITY
var graph := AStar3D.new()
var cells := {}
var grid_cursor := 0
var grid_width := 0
var graph_ready := false
var grounded := false
var path := PackedVector3Array()
var destination := Vector3.INF
var waiting := 0.0
var speed := 0.0
var blocked := 0.0
var reversing := 0.0
var respawn_remaining := 0.0
var clock := 0.0
var probes := 0
var journeys := 0
var player: Node3D
var random := RandomNumberGenerator.new()
var bubble_trail: Node3D
var bubble_texture: Texture2D
var explosion_frames: Array[Texture2D] = []
var explosion_sound: AudioStream
var navigation_exclusions: Array[RID] = []

static func install(model: Node3D, values: Dictionary = {}) -> Node3D:
	var agent := model.get_node_or_null("GroundVehicle")
	if agent == null:
		agent = load("res://ground_vehicle.gd").new(); agent.name = "GroundVehicle"; model.add_child(agent)
	var collision := model.get_node_or_null("SceneryCollision")
	if not collision is CharacterBody3D:
		if collision != null: collision.free()
		collision = preload("res://ground_vehicle_body.gd").new(); collision.name = "SceneryCollision"; model.add_child(collision)
		var faces := PackedVector3Array()
		preload("res://scenery_loader.gd")._collect_faces(model,Transform3D.IDENTITY,faces)
		var box := AABB(faces[0],Vector3.ZERO) if not faces.is_empty() else AABB(Vector3(-0.2,0,-0.3),Vector3(0.4,0.3,0.6))
		for vertex in faces: box = box.expand(vertex)
		agent.bounds = box
		# Keep the chassis solid without boxing in the empty space below it.
		# Wheel contact follows the terrain probes instead of catching triangle edges.
		var shape := CollisionShape3D.new(); var hull := BoxShape3D.new(); hull.size = (box.size * Vector3(1,0.65,1)).max(Vector3.ONE * 0.02)
		shape.shape = hull; shape.position = box.get_center() + Vector3.UP * box.size.y * 0.175; collision.add_child(shape)
	if agent.body != collision:
		agent.health = load("res://npc_health.gd").new(); agent.graph = AStar3D.new(); agent.cells = {}; agent.path = PackedVector3Array()
	agent.home = model.global_transform
	agent.body = collision; collision.collision_layer = 9; collision.collision_mask = 3 | 8
	agent.configure(values)
	preload("res://entity_identity.gd").actor(model,agent,agent.body)
	return agent

func configure(values: Dictionary) -> void:
	for key in DEFAULTS: tuning[key] = values.get(key,tuning[key])
	if not has_meta("initialized"):
		home = get_parent().global_transform
		random.seed = hash(str(get_parent().get_path()))
		health.configure(float(tuning.npc_health),float(tuning.npc_sustain)); set_meta("initialized",true)
	body.set_meta("damage_sustain",float(tuning.npc_sustain)); body.set_meta("contact_inflict",0.1)

func reset() -> void:
	set_local_simulation(true)
	get_parent().global_transform = home; body.transform = Transform3D.IDENTITY
	health.configure(float(tuning.npc_health),float(tuning.npc_sustain)); dead = false
	body.collision_layer = 9; get_parent().show(); speed = 0; blocked = 0; reversing = 0; clock = 0
	path.clear(); destination = Vector3.INF; waiting = random.randf_range(0,2); respawn_remaining = 0; journeys = 0
	graph.clear(); cells.clear(); grid_cursor = 0; graph_ready = false; grounded = false
	grid_width = int(ceil(float(tuning.npc_radius) / GRID_SPACING)) * 2 + 1
	seat_on_ground()

func ground(point: Vector3) -> Dictionary:
	probes += 1
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x,home.origin.y + 0.75,point.z),Vector3(point.x,home.origin.y - 4.0,point.z),1,navigation_exclusions)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.75 or hit.collider.name != "WorldCollision": return {}
	return hit

func _root_at(hit: Dictionary) -> Vector3:
	return hit.position + hit.normal * (-bounds.position.y * home.basis.get_scale().y + 0.06)

func _clear(point: Vector3, normal: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body.get_child(0).shape
	var basis := heading_basis(home.basis.z,normal).scaled_local(home.basis.get_scale())
	query.transform = Transform3D(basis,point) * body.get_child(0).transform
	query.collision_mask = 1; query.exclude = navigation_exclusions
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

static func heading_basis(forward: Vector3, normal: Vector3) -> Basis:
	var heading := forward.slide(normal).normalized()
	if heading.is_zero_approx(): heading = Vector3.BACK.slide(normal).normalized()
	return Basis.looking_at(heading,normal,true)

func _build_graph() -> void:
	# Bounded incremental work: four terrain samples per vehicle per frame.
	var centre := grid_width / 2
	for iteration in range(4):
		if grid_cursor >= grid_width * grid_width:
			graph_ready = true; return
		var cell := Vector2i(grid_cursor % grid_width,int(grid_cursor / grid_width)); grid_cursor += 1
		var point := home.origin + Vector3(cell.x - centre,0,cell.y - centre) * GRID_SPACING
		if Vector2(point.x - home.origin.x,point.z - home.origin.z).length() > float(tuning.npc_radius): continue
		var hit := ground(point)
		if hit.is_empty(): continue
		point = _root_at(hit)
		if not _clear(point,hit.normal): continue
		var id := graph.get_available_point_id(); graph.add_point(id,point); cells[cell] = id
		for neighbour in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
			if not cells.has(cell + neighbour): continue
			var other: int = cells[cell + neighbour]; var previous := graph.get_point_position(other)
			if absf(previous.y - point.y) > 0.5: continue
			var mid := ground((previous + point) * 0.5)
			if mid.is_empty() or not _clear(_root_at(mid),mid.normal): continue
			var ray := PhysicsRayQueryParameters3D.create(previous + Vector3.UP * 0.2,point + Vector3.UP * 0.2,1,navigation_exclusions)
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): graph.connect_points(id,other)

func _plan() -> void:
	if graph.get_point_count() < 2: waiting = 5; return
	var start := graph.get_closest_point(get_parent().global_position)
	var ids := graph.get_point_ids()
	for attempt in range(12):
		var finish: int = ids[random.randi_range(0,ids.size() - 1)]
		if destination.is_finite(): finish = graph.get_closest_point(destination)
		var route := graph.get_point_path(start,finish)
		if route.size() > 2:
			path = route; destination = route[-1]; return
		destination = Vector3.INF
	waiting = 3

func _physics_process(delta: float) -> void:
	if not running or not local_simulation: return
	if dead:
		if bool(tuning.npc_respawn) and mission_owner.is_empty():
			respawn_remaining -= delta
			if respawn_remaining <= 0 and _can_respawn(): reset()
		return
	if not grounded: seat_on_ground()
	if not graph_ready: _build_graph(); return
	clock += delta
	var distant := is_instance_valid(player) and player.global_position.distance_squared_to(global_position) > 1600
	if clock < (0.2 if distant else 0.05): return
	var step := minf(clock,0.25); clock = 0
	advance(step)

func set_local_simulation(on: bool) -> void:
	if local_simulation == on: return
	local_simulation = on
	get_parent().process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	set_physics_process(on)
	body.collision_layer = 9 if on and not dead else 0
	body.collision_mask = (3 | 8) if on else 0
	for shape in body.get_children():
		if shape is CollisionShape3D: shape.set_deferred("disabled",not on or dead)
	if on: get_parent().reset_physics_interpolation()

func _can_respawn() -> bool:
	if not is_instance_valid(player): return true
	if player.global_position.distance_to(home.origin) <= 12: return false
	var camera := get_viewport().get_camera_3d()
	return camera == null or not camera.is_position_in_frustum(home.origin)

func seat_on_ground() -> bool:
	var model := get_parent() as Node3D
	var floor_hit := ground(home.origin)
	if floor_hit.is_empty(): return false
	var initial := _root_at(floor_hit)
	var clear := _clear(initial,floor_hit.normal)
	if not clear and graph_ready and graph.get_point_count() > 0:
		initial = graph.get_point_position(graph.get_closest_point(initial)); clear = true
	# Seat before the incremental route grid is ready, including while stopped
	# in the main menu. An obstructed placement can resolve once the grid exists.
	model.global_position = initial
	model.global_basis = heading_basis(home.basis.z,floor_hit.normal).scaled_local(home.basis.get_scale())
	grounded = clear
	return grounded

func advance(delta: float) -> void:
	var model := get_parent() as Node3D
	if not grounded and not seat_on_ground(): waiting = 1; return
	if waiting > 0:
		waiting = maxf(0,waiting - delta); speed = move_toward(speed,0,delta); return
	if path.is_empty(): _plan(); return
	while not path.is_empty() and Vector2(path[0].x - model.global_position.x,path[0].z - model.global_position.z).length() < 0.18: path.remove_at(0)
	if path.is_empty():
		journeys += 1; destination = Vector3.INF; waiting = random.randf_range(float(tuning.npc_wait_min),float(tuning.npc_wait_max)); return
	var offset := path[0] - model.global_position
	var hit := ground(model.global_position)
	if hit.is_empty(): speed = 0; path.clear(); waiting = 1; return
	var desired := Vector3(offset.x,0,offset.z).normalized()
	var basis := heading_basis(desired,hit.normal)
	model.global_basis = model.global_basis.orthonormalized().slerp(basis,1.0 - exp(-2.5 * delta)).scaled_local(home.basis.get_scale())
	var forward := model.global_basis.z.normalized()
	var alignment := forward.dot(desired)
	speed = move_toward(speed,float(tuning.npc_speed) * clampf(alignment,0,1),delta * 0.4)
	var motion := forward * speed * delta
	if reversing > 0: reversing -= delta; motion = -forward * float(tuning.npc_speed) * delta * 0.5
	var next_ground := ground(model.global_position + motion)
	if next_ground.is_empty(): speed = 0; path.clear(); waiting = 1; return
	motion.y = _root_at(next_ground).y - model.global_position.y
	var collision := body.move_and_collide(motion)
	model.global_position = body.global_position; body.transform = Transform3D.IDENTITY
	body.velocity = motion / maxf(0.001,delta)
	if collision != null:
		blocked += delta; speed = 0
		if blocked > 2.0: reversing = 0.6; path.clear(); destination = Vector3.INF; blocked = 0; waiting = 0.3
	else: blocked = maxf(0,blocked - delta)
	if bubble_trail != null and speed > 0.05: bubble_trail.emit_from(0,model.global_position - model.global_basis.z * bounds.size.z * 0.6,Vector3.UP,1,2,delta)

func take_weapon_damage(strength: float, _source: Vector3 = Vector3.ZERO) -> void:
	if not running or not local_simulation or dead or not health.hit(strength): return
	if report_player_attack: attacked.emit(int(tuning.npc_faction))
	if health.remaining > 0: return
	var inherited_velocity := body.velocity
	dead = true; speed = 0; body.velocity = Vector3.ZERO; body.collision_layer = 0; get_parent().hide()
	destroyed.emit(preload("res://entity_identity.gd").of(self),preload("res://entity_identity.gd").of(damage_attacker) if is_instance_valid(damage_attacker) else "")
	var wreck := preload("res://submarine_death.gd").new()
	get_parent().get_parent().add_child(wreck); wreck.global_position = global_position
	wreck.setup_machine(get_parent(),get_parent(),bubble_texture,[],inherited_velocity)
	wreck.name = "VehicleWreck"; wreck.add_to_group("ground_vehicle_wrecks")
	respawn_remaining = float(tuning.npc_respawn_delay)
	var effect := preload("res://mine_explosion.gd").new(); get_parent().get_parent().add_child(effect); effect.global_position = global_position
	effect.setup(explosion_frames,maxf(0.3,bounds.size.length()),explosion_sound)

func take_weapon_damage_from(strength: float, source: Vector3, attacker: Node3D) -> void:
	var previous := report_player_attack
	var previous_attacker := damage_attacker
	damage_attacker = attacker; report_player_attack = is_instance_valid(attacker) and attacker == player
	take_weapon_damage(strength,source)
	report_player_attack = previous; damage_attacker = previous_attacker
