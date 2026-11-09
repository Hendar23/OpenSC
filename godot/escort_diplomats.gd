extends RefCounted
## Retail diptrad family: 0043b540; battleship 0043a290 / 00439620.
var jobs: Node
var ship: Node3D
var pirate: Node3D
var boss: Node3D
var guns: Array[Node3D] = []
var points := {}
var boss_pose := Transform3D.IDENTITY
var elapsed := 0.0
var pending: Array[Dictionary] = []
var disabled := false
var captured := false
var freed := false
var lost := false
var arrived := false
var seen_waypoint := 0
var rescue_clock := 0.0
var approach_reported := false
var capture_visual: RefCounted

func start() -> void:
	jobs.phase = "rendezvous"
	for row in jobs._rows(8):
		if float(row.get("param2",0)) != 1.0: continue
		if int(row.ObjectID) == 1: points[int(row.param1)] = jobs._pose(row)
		elif int(row.ObjectID) == 2: boss_pose = jobs._pose(row)
	if points.size() != 7: return
	ship = jobs._boat("TRADSHUT",points[0],1,10,1.5)
	if ship == null: return
	ship.combat_enabled = false; ship.dormant = true
	ship.destroyed.connect(_ship_lost)
	jobs.target = ship
	later(0.2,"h12"); later(10.2,"h13")

func later(delay: float, code: String) -> void:
	pending.append({"time":elapsed+delay,"code":code})

func target_body() -> CollisionObject3D:
	return ship.body if is_instance_valid(ship) and not ship.dead and not arrived else null

func clear() -> void:
	if capture_visual != null: capture_visual.clear(); capture_visual = null
	_restore_controls()
	for actor in [ship,pirate]:
		if not is_instance_valid(actor): continue
		for connection in actor.get_signal_connection_list("destroyed"):
			if connection.callable.get_object() == self: actor.disconnect("destroyed",connection.callable)
	pending.clear()

func _route(first: int, last: int) -> void:
	ship.dormant = false; ship.path.clear(); ship.waypoints.clear(); ship.waypoint = 0
	ship.arrival_reported = false
	for index in range(first,last+1):
		# Retail markers can sit above our water ceiling; the last marker is
		# inside Tryton's dock. Navigate through water, then let docking descend.
		var point: Vector3 = jobs._city(4) if index == 6 else points[index].origin
		point.y = minf(point.y,jobs.game.submarine_traffic.map.surface_height-jobs.game.submarine_traffic.CLEARANCE-0.1)
		ship.waypoints.append(point)

func step(delta: float) -> void:
	elapsed += delta
	for event in pending.duplicate():
		if event.time > elapsed: continue
		pending.erase(event)
		match event.code:
			"win": jobs._resolve(true,1,0); return
			"loss":
				_restore_controls(); jobs.radio("h17",true)
				jobs.game.pilot.controls_enabled = true
				jobs.game.pilot.take_damage(1000000)
				jobs._resolve(false,0,0); return
			_: jobs.radio(event.code)
	if lost or not is_instance_valid(ship) or ship.dead: return
	if jobs.phase == "rendezvous":
		if jobs.game.pilot.global_position.distance_to(ship.global_position) < 10:
			jobs.phase = "escort"; _route(1,3)
		return
	if jobs.phase == "escort":
		if ship.waypoint >= 1 and seen_waypoint == 0:
			seen_waypoint = 1
			pirate = jobs._boat("PIRATE",Transform3D(Basis.IDENTITY,points[0].origin),3,30)
			if pirate != null: pirate.engage_player = true; pirate.pursue_offscreen = true
			if jobs.game.pilot.global_position.distance_to(points[3].origin) > 10:
				_disable(); later(8,"h14"); later(16,"h15"); later(24,"h5"); later(32,"h16")
		if ship.waypoint >= 3:
			if disabled: _capture()
			else:
				jobs.phase = "return"; freed = true; _route(4,6); ship.dock_destination = 4
	elif captured and not freed:
		rescue_clock += delta
		if capture_visual != null: capture_visual.step(delta)
		if not approach_reported and jobs.game.pilot.global_position.distance_to(boss.global_position) < 8:
			approach_reported = true; jobs.radio("h6")
		if guns.size() == 2 and guns.all(func(gun: Node3D) -> bool: return gun.dead):
			freed = true; captured = false; pending.clear()
			jobs.radio("h2"); jobs.phase = "release"; ship.dock_destination = 4
			capture_visual.release(float(ship.tuning.npc_speed))
		elif rescue_clock >= 168:
			ship.take_weapon_damage_from(1000000,ship.global_position,null)
	elif jobs.phase == "release":
		capture_visual.step(delta)
		if capture_visual.released:
			jobs.phase = "return"; _route(4,6)
			if is_instance_valid(boss):
				var effect := preload("res://base_destruction.gd").new(); jobs.game.world_root.add_child(effect)
				effect.setup([boss],[],jobs.game.submarine_traffic); jobs.actors.erase(boss)
	elif freed and not arrived and ship.stage == "berth":
		arrived = true; jobs.radio("h18",true); later(6,"win")

func _disable() -> void:
	disabled = true; jobs.radio("h1")
	jobs.game.pilot.set_meta("diplomat_system_failure",true)
	jobs.game.pilot.angular_velocity = Vector3.ZERO
	jobs.game.pilot.global_basis = (jobs.game.pilot.global_basis*Basis(Vector3.FORWARD,PI*0.5)).orthonormalized()
	jobs.game.pilot.reset_physics_interpolation()

func _restore_controls() -> void:
	if jobs == null or not is_instance_valid(jobs.game.pilot): return
	jobs.game.pilot.remove_meta("diplomat_system_failure")
	if disabled: jobs.game.pilot.angular_velocity = Vector3.ZERO
	disabled = false

func _capture() -> void:
	pending = pending.filter(func(event: Dictionary) -> bool: return event.code not in ["h14","h15","h5","h16"])
	_restore_controls(); jobs.radio("h3")
	captured = true; jobs.phase = "rescue"; ship.dormant = true
	boss = jobs.Document.load_model("BOSS",jobs.game.game_folder)
	if boss == null: return
	jobs.game.world_root.add_child(boss); boss.global_transform = boss_pose; jobs.actors.append(boss)
	jobs.game.natural_light.attach(boss); jobs.game.water_visuals.attach(boss)
	capture_visual = preload("res://diplomat_capture.gd").new()
	capture_visual.setup(boss,ship)
	guns = preload("res://pirate_battleship.gd").install(jobs,boss)
	for item in [{"time":6,"code":"h4"},{"time":12,"code":"h7"},{"time":30,"code":"h8"},{"time":66,"code":"h9"},{"time":114,"code":"h10"},{"time":162,"code":"h11"}]: later(item.time,item.code)

func _ship_lost(_entity_id: String, _attacker_id: String) -> void:
	if lost or arrived: return
	lost = true; pending.clear(); later(8,"loss")
