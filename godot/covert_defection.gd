extends RefCounted
## Retail defect/defect2 00452e90, boarding orders 00453de0, CARAVAN 00432160.
var jobs: Node
var ship: Node3D
var boarder: Node3D
var enemies: Array[Node3D] = []
var mines: Array[Node3D] = []
var pod: Node3D
var cable: MeshInstance3D
var elapsed := 0.0
var attached := false
var transfer := 0.0
var received := false
var operational := false
var bridge_clock := -1.0
var encounter_clock := -1.0
var approach_clock := 12.0
var recognition := false
var weak_signal := false
var bearing_clock := 0.0
var poll_clock := 0.0
var boarding_clock := -1.0
var boarding_warned := false
var captured := false
var safe := false
var outcome_clock := -1.0
var outcome_response := 0
var pending: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

func start() -> void:
	jobs.phase = "rendezvous"; rng.randomize()
	for row in jobs._rows(54):
		var pose: Transform3D = jobs._pose(row)
		if int(row.ObjectID) == 1:
			ship = jobs._boat("CARAVAN",pose,2,15,1.5,preload("res://defector_submarine.gd"))
			if ship == null: continue
			ship.combat_enabled = false; ship.tuning.npc_sustain = 0.1; ship.health.sustain = 0.1
			ship.body.set_meta("damage_sustain",0.1); jobs.target = ship
			jobs._place_vessel_clear(ship)
			ship.destroyed.connect(_destroyed)
		elif int(row.ObjectID) == 2:
			# Ten original random offsets per authored field. Clip obstructed rays
			# halfway before the hit, then verify the complete mine is in water.
			for index in range(10):
				var point := pose.origin+Vector3(rng.randi_range(-512,511),rng.randi_range(-512,511),rng.randi_range(-512,511))*(4.0/512.0)
				var hit: Dictionary = jobs.game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pose.origin,point,1))
				if not hit.is_empty(): point = pose.origin.lerp(hit.position,0.5)
				_mine(point)
	pending.append({"time":12.0,"code":"bb23"})

func _mine(point: Vector3) -> void:
	var shape := SphereShape3D.new(); shape.radius = 0.5
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape; query.transform.origin = point; query.collision_mask = 1
	if point.y >= jobs.game.pilot.surface_height-0.5 or not jobs.game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return
	var definition: Dictionary = preload("res://object_definitions.gd").FLOATING_MINE.duplicate(true)
	definition.merge({"appearance":"model","model":"MINE"},true)
	var population: Node3D = jobs.game.object_population
	var visual: Node3D = population.appearance(definition,jobs.game.game_folder)
	if visual == null: return
	var mine := preload("res://floating_mine.gd").new()
	mine.setup(definition,visual,preload("res://submarine_weapons.gd")._sound(jobs.game.game_folder,"audio.object.mine.explosion","EXPLODE1"),true)
	jobs.game.world_root.add_child(mine); mine.global_position = point; mine.home = point
	mine.player = jobs.game.pilot; mine.explosion_frames.assign(population.explosion_frames)
	mine.set_meta("mission_owner",jobs.id); jobs.actors.append(mine); mines.append(mine)
	mine.exploded.connect(population._exploded.bind(600.0))
	jobs.game.natural_light.attach(mine); jobs.game.water_visuals.attach(mine)

func target_body() -> CollisionObject3D:
	return ship.body if is_instance_valid(ship) and not ship.dead and not captured and not safe else null

func can_attach_pod(body: Node3D) -> bool:
	return is_instance_valid(ship) and not ship.dead and not received and not captured and boarding_clock < 0 and body == ship.body and not jobs.game.equipment.support_tools.passengers

func step(delta: float) -> void:
	if jobs.id.is_empty() or jobs.phase == "finished": return
	elapsed += delta
	for index in range(pending.size()-1,-1,-1):
		if pending[index].time <= elapsed:
			jobs.radio(pending[index].code); pending.remove_at(index)
	if not is_instance_valid(ship): return
	if outcome_clock >= 0:
		outcome_clock = maxf(0,outcome_clock-delta)
		if outcome_clock <= 0 and (not safe or (ship.stage == "berth" and ship.last_city == 3)):
			jobs.radio("bb25" if safe else "bb24" if captured else "bb22",true)
			jobs._resolve(safe,1.0 if safe else 0.0,outcome_response)
		return
	if ship.dead: return
	approach_clock -= delta
	if not recognition and approach_clock <= 0:
		approach_clock = 2.0
		if ship.global_position.distance_to(jobs.game.pilot.global_position) < 8: recognition = true; jobs.radio("bb1")
	if encounter_clock >= 0:
		encounter_clock -= delta
		if encounter_clock <= 0:
			encounter_clock = -1; _wave()
	_update_transfer(delta)
	if operational and not safe and not captured:
		_update_bearing(delta)
		poll_clock -= delta
		if poll_clock <= 0:
			poll_clock = 2.0
			if ship.global_position.distance_to(jobs._city(3)) < 8: _safe(); return
	_update_boarding(delta)

func _update_transfer(delta: float) -> void:
	var touching: bool = jobs.game.equipment.support_tools.pod_target == ship.body
	if touching != attached:
		attached = touching
		if not received and boarding_clock < 0:
			if touching: transfer = 0; jobs.radio("bb5"); jobs.phase = "supplies"
			else: transfer = 0; jobs.radio("bb7"); jobs.phase = "rendezvous"
		_orders()
	if attached and not received and boarding_clock < 0:
		transfer += delta
		if transfer+0.00001 >= 16:
			received = true; jobs.radio("bb6"); bridge_clock = 8.0
			return
	if bridge_clock >= 0:
		bridge_clock -= delta
		if bridge_clock <= 0:
			bridge_clock = -1; operational = true; ship.tracking = true
			weak_signal = true
			jobs.phase = "lead"; jobs.radio("bb8"); encounter_clock = 8.0
			_orders()

func _update_bearing(delta: float) -> void:
	var offset: Vector3 = jobs.game.pilot.global_position-ship.global_position
	if offset.length() < 15: weak_signal = false; bearing_clock = 0; return
	bearing_clock -= delta
	if bearing_clock > 0: return
	if not weak_signal: weak_signal = true; bearing_clock = 6.0; jobs.radio("bb13")
	else:
		bearing_clock = 18.0
		# Original rotates the vector 22.5 degrees then quantises16 bearings/2.
		var bearing := posmod(int(floor((atan2(offset.x,-offset.z)+PI/8)/(PI/4))),8)
		jobs.radio("bb%d" % (14+bearing))

func _wave() -> void:
	if ship.dead or safe or captured: return
	var count := enemies.filter(func(agent: Node3D) -> bool: return is_instance_valid(agent) and not agent.dead).size()
	if count >= 4: encounter_clock = 2.0; return
	var player: Vector3 = jobs.game.pilot.global_position
	# The original chooses the farther of its two Procha city markers.
	var city := 2 if player.distance_to(jobs._city(2)) > player.distance_to(jobs._city(4)) else 4
	var origin: Vector3 = jobs._city(city)+Vector3.UP*3
	for index in range(rng.randi_range(1,2)):
		var guard: Node3D = jobs._boat("TECHNEW",Transform3D(Basis.IDENTITY,origin),2,15,2.5)
		if guard == null: continue
		jobs._place_vessel_clear(guard,true); guard.engage_player = true; guard.pursue_offscreen = true; enemies.append(guard)
	boarder = jobs._boat("TECH2SUB",Transform3D(Basis.IDENTITY,origin),2,15,3.5)
	if boarder == null: encounter_clock = 2; return
	jobs._place_vessel_clear(boarder,true); boarder.tuning.npc_sustain = 0.6; boarder.health.sustain = 0.6; boarder.body.set_meta("damage_sustain",0.6)
	boarder.pursue_offscreen = true; boarder.destroyed.connect(_boarder_destroyed)
	pod = jobs.Document.load_model("ESCAPE",jobs.game.game_folder)
	if pod != null:
		boarder.get_parent().add_child(pod); pod.position = Vector3(0,-0.3,0)
		pod.set_meta("exclude_from_debris",true); jobs.actors.append(pod)
		jobs.game.natural_light.attach(pod); jobs.game.water_visuals.attach(pod)
	_orders()
	pending.append({"time":elapsed+maxf(0.04,floor(player.distance_to(jobs._city(city)))*4.0/25.0),"code":"bb10"})

func _orders() -> void:
	if not is_instance_valid(boarder) or boarder.dead: return
	var boarding: bool = not attached and not captured and not safe and not ship.dead
	boarder.boarding = boarding; boarder.engage_player = not boarding
	boarder.follow = ship if boarding else null; boarder.formation = Vector3(0,2,0)
	boarder.combat_target = null; boarder.victim = null; boarder.path.clear(); boarder.replan = 0; boarder.wait = 0; boarder.flee = 0
	if boarding:
		boarder.body.add_collision_exception_with(ship.body); ship.body.add_collision_exception_with(boarder.body)
	else:
		boarder.body.remove_collision_exception_with(ship.body); ship.body.remove_collision_exception_with(boarder.body)

func _update_boarding(delta: float) -> void:
	if not is_instance_valid(boarder) or boarder.dead or not boarder.boarding: return
	if boarding_clock < 0:
		if boarder.global_position.distance_to(boarder.boarding_goal()) >= 1.0: return
		boarding_clock = 0.0; boarding_warned = false; ship.held_by_boarders = true; jobs.phase = "boarding"
		if is_instance_valid(pod): pod.reparent(ship.get_parent(),true)
		cable = MeshInstance3D.new(); var mesh := CylinderMesh.new()
		mesh.top_radius = 0.004; mesh.bottom_radius = 0.004; mesh.height = 1.0; mesh.radial_segments = 6; cable.mesh = mesh
		var material := StandardMaterial3D.new(); material.albedo_color = Color(0.3,0.35,0.36); cable.material_override = material
		cable.set_meta("exclude_from_debris",true); jobs.game.world_root.add_child(cable); jobs.actors.append(cable)
	boarding_clock += delta
	if is_instance_valid(pod):
		pod.position = pod.position.move_toward(Vector3(0,0.35,0),delta*3.0)
		var start: Vector3 = boarder.get_parent().to_global(Vector3(0,-0.2,0))
		var span: Vector3 = pod.global_position-start
		cable.visible = span.length() > 0.005; cable.global_position = start+span*0.5
		if cable.visible: cable.global_basis = Basis(Quaternion(Vector3.UP,span.normalized())).scaled(Vector3(1,span.length(),1))
	if boarding_clock >= 4 and not boarding_warned: boarding_warned = true; jobs.radio("bb11")
	if boarding_clock >= 40:
		captured = true; ship.tracking = false; jobs.phase = "captured"; jobs.radio("bb4")
		_end_boarding(); _orders(); outcome_clock = 8.0; outcome_response = 3

func _end_boarding() -> void:
	ship.held_by_boarders = false; boarding_clock = -1; boarding_warned = false
	if is_instance_valid(cable): cable.queue_free()
	cable = null
	if is_instance_valid(pod):
		if is_instance_valid(boarder) and not boarder.dead:
			pod.reparent(boarder.get_parent(),true); pod.transform = Transform3D(Basis.IDENTITY,Vector3(0,-0.3,0))
		else: pod.queue_free(); pod = null

func _boarder_destroyed(_id: String, _attacker: String) -> void:
	if jobs.id.is_empty(): return
	if boarding_clock >= 0: jobs.radio("bb12")
	pending = pending.filter(func(event: Dictionary) -> bool: return event.code not in ["bb10","bb11"])
	_end_boarding(); boarder = null
	if not safe and not captured and not ship.dead: encounter_clock = 108.0; jobs.phase = "lead" if operational else "rendezvous"

func _destroyed(_id: String, _attacker: String) -> void:
	if jobs.id.is_empty() or safe: return
	pending.clear(); _end_boarding(); _orders()
	jobs.radio("bb3"); jobs.phase = "destroyed"; outcome_clock = 6.0; outcome_response = 2

func _safe() -> void:
	safe = true; jobs.phase = "dock"; jobs.radio("bb9")
	ship.tracking = false; ship.secured = true; ship.health.sustain = 0; ship.body.set_meta("damage_sustain",0.0)
	ship.waypoints.clear(); ship.waypoint = 0; ship.dock_destination = 3; ship.path.clear(); ship.arrival_reported = false
	jobs.game.equipment.support_tools._detach_pod()
	_end_boarding(); _orders(); outcome_clock = 10.0; outcome_response = 1

func clear() -> void:
	if is_instance_valid(ship): _end_boarding()
	pending.clear(); enemies.clear(); mines.clear()
	ship = null; boarder = null; pod = null; cable = null
