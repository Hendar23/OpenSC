extends RefCounted
## SC.EXE 00401730: four sequential recoveries from placement group 19.
const Survivors = preload("res://mission_survivors.gd")
const PIRATES := [3,0,4,2]
const GUARD_DELAY := [8.0,0.0,4.0,8.0]
const HOSTILE_RANGE := 20.0
var jobs: Node
var leg := 0
var filter_body: RigidBody3D
var poses := {}
var cities: Array[int] = []
var enemies: Array[Node3D] = []
var guards: Array[Node3D] = []
var walkers: Array[Node3D] = []
var boss: Node3D
var guns: Array[Node3D] = []
var builder: RefCounted
var poll := 0.0
var clue_scheduled := false
var elapsed := 0.0
var pending: Array[Dictionary] = []

func start() -> void:
	builder = preload("res://student_rescue.gd").new()
	builder.jobs = jobs
	for row in jobs._rows(19):
		var key := int(row.ObjectID)
		if not poses.has(key): poses[key] = []
		poses[key].append(jobs._pose(row))
	_spawn_leg()

func _spawn_leg() -> void:
	jobs.phase = "recover"
	guards.clear()
	poll = GUARD_DELAY[leg] if PIRATES[leg] > 0 else -1.0
	if leg < 3: _later("s%d" % (11+leg))
	clue_scheduled = false
	filter_body = builder.prop("PURIFIER",poses[leg+1][0],1.0,0.1,0.5,true)
	if filter_body == null: return
	builder.place_clear(filter_body)
	filter_body.set_meta("mission_delivery",true)
	filter_body.set_meta("mission_marker",true)
	filter_body.set_meta("faction",0)
	filter_body.destroyed.connect(_filter_lost)
	jobs.game.cockpit_hud.map_data.actor_markers.append(filter_body)
	jobs.target = filter_body
	if leg == 1:
		for pose in poses[6]: _walker(pose)
	if leg == 3: _battleship(poses[8][0])
	if PIRATES[leg] == 0: return
	var pose: Transform3D = poses[[5,6,7,9][leg]][0]
	for index in PIRATES[leg]:
		var pirate: Node3D = jobs._boat("PIRATE",pose,3,30,2.5)
		if pirate == null: continue
		if leg == 0: _place_cave_guard(pirate,pose.origin)
		else: jobs._place_vessel_clear(pirate,true)
		pirate.dormant = true
		pirate.player_attacked.connect(_alert_guards)
		guards.append(pirate); enemies.append(pirate)

func _place_cave_guard(pirate: Node3D, origin: Vector3) -> void:
	var shape: CollisionShape3D = pirate.body.get_child(0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape; query.collision_mask = 1; query.exclude = [pirate.body.get_rid()]
	var offsets: Array[Vector3] = []
	for lift in [0.0,-0.5,0.5,-1.0,1.0,-2.0,2.0]:
		for radius in [0.0,0.5,1.0,1.5,2.0,3.0,4.0]:
			for direction in (1 if radius == 0 else 12):
				offsets.append(Vector3(cos(direction*TAU/12)*radius,lift,sin(direction*TAU/12)*radius))
	offsets.sort_custom(func(a: Vector3,b: Vector3) -> bool: return a.length_squared()<b.length_squared())
	var model: Node3D = pirate.get_parent()
	var space: PhysicsDirectSpaceState3D = jobs.game.get_world_3d().direct_space_state
	for offset in offsets:
		var point := origin+offset
		var roof := PhysicsRayQueryParameters3D.create(point,point+Vector3.UP*20,1)
		roof.hit_back_faces = false
		var ceiling: Dictionary = space.intersect_ray(roof)
		if ceiling.is_empty() or ceiling.normal.y >= -0.1: continue
		query.transform = Transform3D(model.global_basis,point)*shape.transform
		if not space.intersect_shape(query,1).is_empty(): continue
		var box: AABB = Transform3D(model.global_basis,point)*pirate.bounds.grow(0.1)
		if guards.any(func(other: Node3D) -> bool: return box.intersects(other.get_parent().global_transform*other.bounds.grow(0.1))): continue
		model.global_position = point; pirate.home = model.global_transform
		model.reset_physics_interpolation()
		return
	push_error("No clear interior position for the Touka filter guard")

func _alert_guards() -> void:
	poll = -1.0
	for pirate in guards:
		if is_instance_valid(pirate) and not pirate.dead:
			pirate.dormant = false; pirate.engage_player = true; pirate.pursue_offscreen = true

func _walker(pose: Transform3D) -> void:
	# WALKER callback 00463410 starts the emplacement at 20 health, .1 sustain.
	var walker: RigidBody3D = builder.prop("WALKER",pose,20,0.1,1,false)
	if walker == null: return
	walker.freeze = true
	# The retail marker is the chassis centre, not the underside of its feet.
	var shape: CollisionShape3D = walker.get_child(1)
	var bottom: float = (Transform3D(walker.global_basis,Vector3.ZERO)*shape.shape.get_debug_mesh().get_aabb()).position.y
	var floor_ray := PhysicsRayQueryParameters3D.create(pose.origin+Vector3.UP*0.5,pose.origin+Vector3.DOWN*5,1,[walker.get_rid()])
	floor_ray.hit_back_faces = true
	var floor_hit: Dictionary = jobs.game.get_world_3d().direct_space_state.intersect_ray(floor_ray)
	if not floor_hit.is_empty(): walker.global_position.y = maxf(walker.global_position.y,floor_hit.position.y-bottom+0.03)
	var armament := preload("res://walker_armament.gd").new()
	walker.add_child(armament); armament.setup(walker,jobs.game,null,walker.get_child(0))
	walker.destroyed.connect(_walker_destroyed.bind(walker))
	walkers.append(walker)

func _walker_destroyed(walker: RigidBody3D) -> void:
	jobs.burst(walker.global_position,2.5)
	jobs.runtime._retained_prop_destroyed(walker)

func _battleship(pose: Transform3D) -> void:
	boss = jobs.Document.load_model("BOSS",jobs.game.game_folder)
	if boss == null: return
	jobs.game.world_root.add_child(boss); boss.global_transform = pose; jobs.actors.append(boss)
	jobs.game.natural_light.attach(boss); jobs.game.water_visuals.attach(boss)
	guns = preload("res://pirate_battleship.gd").install(jobs,boss)
	var watch := preload("res://filter_battleship_destruction.gd").new()
	boss.add_child(watch)
	watch.guns.assign(guns)
	watch.traffic = jobs.game.submarine_traffic
	watch.runtime = jobs.runtime
	watch.destroyed.connect(_boss_destroyed)

func _boss_destroyed() -> void:
	jobs.actors.erase(boss)
	boss = null

func _later(code: String) -> void:
	pending.append({"at":elapsed+40.0,"code":code})

func step(delta: float) -> void:
	if not is_instance_valid(filter_body) or filter_body.dead: return
	elapsed += delta
	for item in pending.duplicate():
		if elapsed >= item.at:
			jobs.radio(item.code)
			pending.erase(item)
	var towing: bool = jobs.game.equipment.magnet.target == filter_body
	if towing and not clue_scheduled and leg < 3:
		_later("s%d" % (14+leg))
		clue_scheduled = true
	if poll >= 0.0:
		poll -= delta
		if poll > 0.0: return
		if not guards.any(func(pirate: Node3D) -> bool: return is_instance_valid(pirate) and not pirate.dead and jobs.game.pilot.global_position.distance_squared_to(pirate.global_position) < HOSTILE_RANGE*HOSTILE_RANGE):
			poll = 0.25; return
		poll = -1.0
		var attacking := false
		for pirate in guards:
			if not is_instance_valid(pirate) or pirate.dead: continue
			pirate.dormant = false; pirate.engage_player = true; pirate.pursue_offscreen = true
			attacking = true
		if attacking: jobs.radio("s6")

func target_body() -> CollisionObject3D:
	return filter_body if is_instance_valid(filter_body) and not filter_body.dead else null

func delivery_cities(body: Node3D) -> Variant:
	if body != filter_body: return null
	return [1,2,3,4].filter(func(city: int) -> bool: return city not in cities) if not filter_body.dead else []

func delivery(body: Node3D, city: int) -> bool:
	if body != filter_body or filter_body.dead: return false
	var magnet: Node3D = jobs.game.equipment.magnet
	# Each city gets one prototype. No new dialogue for repeat deliveries.
	if city not in delivery_cities(body):
		magnet.decline_delivery(); return true
	cities.append(city)
	body.delivered = true; body.set_meta("delivery_city",city)
	magnet.set_enabled(false)
	jobs.game.cockpit_hud.map_data.actor_markers.erase(body)
	jobs.actors.erase(body); body.hide(); body.queue_free()
	filter_body = null
	if leg < 3 and not clue_scheduled: _later("s%d" % (14+leg))
	leg += 1
	jobs.radio("s%d" % (leg+(6 if city in [2,4] else 0)),leg == 4)
	if leg == 4:
		jobs.runtime.active()["resolved_city"] = city
		jobs._resolve(true,1,1)
	else: _spawn_leg()
	return true

func _filter_lost() -> void:
	if jobs.game.equipment.magnet.target == filter_body: jobs.game.equipment.magnet.set_enabled(false)
	filter_body.hide()
	jobs.radio("s5",true)
	jobs._resolve(false,0,0)

func release_survivors() -> void:
	Survivors.release(jobs,enemies)
	for walker in walkers:
		if not is_instance_valid(walker) or walker.dead: continue
		walker.destroyed.disconnect(_walker_destroyed.bind(walker))
		jobs.actors.erase(walker)
		jobs.runtime.retain_prop_until_docking(walker)
	if is_instance_valid(boss):
		jobs.actors.erase(boss)
		jobs.runtime.retain_scene_until_docking(boss)

func clear() -> void:
	for pirate in enemies:
		if is_instance_valid(pirate) and pirate.player_attacked.is_connected(_alert_guards): pirate.player_attacked.disconnect(_alert_guards)
	if is_instance_valid(filter_body) and jobs.game.equipment.magnet.target == filter_body:
		jobs.game.equipment.magnet.set_enabled(false)
	if is_instance_valid(boss):
		var watch := boss.get_node_or_null("FilterBattleshipDestruction")
		if watch != null and watch.destroyed.is_connected(_boss_destroyed): watch.destroyed.disconnect(_boss_destroyed)
