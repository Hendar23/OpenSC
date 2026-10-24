extends RefCounted
## Retail minefield callback 00427640, FREIGHT 00456560 / 00455f90.
const Mine = preload("res://floating_mine.gd")
const Hull = preload("res://runaway_freighter.gd")
const Survivors = preload("res://mission_survivors.gd")
const SPHERES := [Vector4(0,0,2.6,0.45),Vector4(0,-0.1,2,0.6),Vector4(0,-0.05,1.1,0.7),Vector4(0,0.05,0.3,0.6),Vector4(-0.8,0.15,0.8,0.5),Vector4(0.8,0.15,0.8,0.5),Vector4(-1.05,0.15,0.35,0.4),Vector4(1.05,0.15,0.35,0.4),Vector4(0,0.4,-0.4,0.4),Vector4(0,0.45,-1.1,0.4),Vector4(0,0.45,-1.8,0.4),Vector4(0,0.4,-2.5,0.4)]
var jobs: Node
var ship: Node3D
var mines: Array[Node3D] = []
var points: Array[Transform3D] = []
var elapsed := 0.0
var attached := false
var inside := false
var ready := false
var crew_found := false
var failed_attempts := 0
var transfer := -1.0
var search := -1.0
var result_clock := -1.0
var crash_clock := -1.0
var city_hit := false
var won := false
var lost := false
var returned := false
var warning_clock := -1.0
var damage_warnings := 0
var contact_clock := 0.0

func start() -> void:
	jobs.phase = "boarding"
	points.resize(9)
	for row in jobs._rows(18):
		if int(row.ObjectID) == 1: points[clampi(int(row.get("param1",0)),0,8)] = jobs._pose(row)
	ship = jobs._boat("FREIGHT",points[0],1,3.0,1.5,Hull)
	if ship == null: return
	jobs.target = ship; ship.combat_enabled = false; ship.staged_destruction = true
	ship.body.set_meta("mission_target_center",ship.bounds.get_center())
	# Retail's twelve hull spheres avoid an enclosing box across empty wing/tail
	# space. Pod seating still uses the visible mesh's actual surface.
	for child in ship.body.get_children(): child.free()
	for value in SPHERES:
		var shape := CollisionShape3D.new(); var sphere := SphereShape3D.new(); sphere.radius = value.w
		shape.shape = sphere; shape.position = Vector3(value.x,value.y,value.z); ship.body.add_child(shape)
	ship.body.collision_mask = 1 | 2 # Mine contact is handled below, without wedging in a static mine.
	for index in range(1,9): ship.waypoints.append(points[index].origin)
	ship.destroyed.connect(_destroyed); ship.arrived.connect(_city_collision)
	jobs.game.equipment.support_tools.passengers = true
	_spawn_mines()

func _spawn_mines() -> void:
	var population: Node = jobs.game.object_population
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var templates: Array[Node3D] = []
	var definitions: Array[Dictionary] = []
	for hard in [false,true]:
		var stats: Dictionary = preload("res://object_definitions.gd").FLOATING_MINE.duplicate(true)
		stats.merge({"appearance":"model","model":"HARDMINE" if hard else "MINE","health":1.5 if hard else 0.5,"damage":21.0 if hard else 17.5,"trigger_on_contact":false},true)
		definitions.append(stats); templates.append(population.appearance(stats,jobs.game.game_folder))
	var sound: AudioStream = preload("res://submarine_weapons.gd")._sound(jobs.game.game_folder,"audio.object.mine.explosion","EXPLODE1")
	# Source loop: 20 mines around each of four segment midpoints. Increasing
	# 6/64, 12/64, 24/64, 36/64 odds select the tougher HARDMINE model.
	for segment in [1,2,4,6]:
		var center := (points[segment].origin+points[segment+1].origin)*0.5
		for index in range(20):
			var point := center+Vector3(rng.randf_range(-4,4),rng.randf_range(-4,4),rng.randf_range(-4,4))
			var query := PhysicsRayQueryParameters3D.create(center,point,1); query.hit_back_faces = true
			var hit: Dictionary = jobs.game.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty(): point = center.lerp(point,float(hit.position.distance_to(center)/maxf(0.001,center.distance_to(point)))*0.5)
			var hard := 1 if rng.randi_range(0,63) < segment*6 else 0
			if templates[hard] == null: continue
			var mine := Mine.new(); mine.setup(definitions[hard],templates[hard].duplicate(),sound,true)
			jobs.game.world_root.add_child(mine); jobs.actors.append(mine); mines.append(mine)
			mine.set_meta("mission_owner",jobs.id); mine.home = point; mine.position = point; mine.phase = rng.randf()*TAU
			mine.explosion_frames.assign(population.explosion_frames)
			mine.exploded.connect(population._exploded.bind(600.0))
			jobs.game.natural_light.attach(mine); jobs.game.water_visuals.attach(mine)
	for template in templates:
		if template != null: template.free()

func target_body() -> CollisionObject3D:
	return ship.body if is_instance_valid(ship) and not ship.dead else null

func can_attach_pod(body: Node3D) -> bool:
	return not lost and not won and is_instance_valid(ship) and not ship.dead and body == ship.body

func step(delta: float) -> void:
	if jobs.phase == "finished" or jobs.id.is_empty() or not is_instance_valid(ship): return
	elapsed += delta
	if result_clock >= 0:
		result_clock -= delta
		if result_clock <= 0:
			jobs.radio("r18",true); jobs._resolve(false,0.0,2 if city_hit else 3)
			return
	if warning_clock >= 0:
		warning_clock -= delta
		if warning_clock <= 0:
			warning_clock = -1
			if not city_hit and not ship.dead: jobs.radio("r16")
	if ship.dead: return
	if crash_clock >= 0:
		crash_clock -= delta
		if crash_clock <= 0: ship.take_weapon_damage(1000); return
	contact_clock -= delta
	if contact_clock <= 0:
		contact_clock = 0.1; _contacts()
	if ship.dead: return
	_damage_radio()
	var tools: Node3D = jobs.game.equipment.support_tools
	var touching: bool = tools.pod_target == ship.body
	if touching != attached:
		attached = touching
		if attached:
			if inside:
				if ready: jobs.radio("r5"); transfer = 8.0
			else: returned = false; jobs.radio("r4"); transfer = 8.0
		else:
			transfer = -1
			if inside: jobs.radio("r7")
			elif not ready and not returned: jobs.radio("r6")
	# Keep transfers distinct from the search clock: attaching partway through
	# a search does not reset it, and leaving strands the team inside.
	if transfer >= 0:
		transfer -= delta
		if transfer <= 0:
			transfer = -1
			if inside: _return_team()
			else: _enter_ship()
			return
	if search >= 0:
		search -= delta
		if search <= 0:
			search = -1; ready = true
			if crew_found: jobs.radio("r12")
			else:
				jobs.radio("r%d" % (9+failed_attempts)); failed_attempts += 1
			if attached: transfer = 12.0 if crew_found else 8.0

func _enter_ship() -> void:
	inside = true; ready = false; jobs.game.equipment.support_tools.passengers = false
	jobs.radio("r8")
	# Recovered callback uses progress/time, not which mesh the pod touches.
	crew_found = ship.waypoint >= 6 or elapsed >= 216.0 or failed_attempts >= 3
	search = 16.0 if crew_found else 24.0

func _return_team() -> void:
	inside = false; ready = false; returned = true; jobs.game.equipment.support_tools.passengers = true
	if crew_found:
		won = true; jobs.phase = "return"; jobs.radio("r14",true); warning_clock = 8.0
		# The crew leaves with SWAT. The empty runaway still threatens Beluga:
		# R16 asks the player to destroy it; reaching the city reduces the score.
	else: jobs.radio("r13")

func docked(_city: int) -> void:
	if won and not lost: jobs._resolve(true,0.5 if city_hit else 1.0,3 if city_hit else 1)

func _damage_radio() -> void:
	var damage: float = ship.health.capacity-ship.health.remaining
	for index in range(3):
		if damage > [0.5,1.0,2.4][index] and damage_warnings <= index:
			damage_warnings = index+1; jobs.radio(["r20","r19","r15"][index])

func _contacts() -> void:
	# Query two hulls every 0.1 s instead of eighty per-frame player probes.
	# Use the actual freighter spheres and player collider, not distance
	# to the ship origin (which misses the wings/tail).
	for body: CollisionObject3D in [ship.body,jobs.game.pilot]:
		for child in body.get_children():
			if not child is CollisionShape3D or child.disabled: continue
			var query := PhysicsShapeQueryParameters3D.new(); query.shape = child.shape; query.transform = child.global_transform
			query.collision_mask = 8; query.exclude = [body.get_rid()]
			for hit in jobs.game.get_world_3d().direct_space_state.intersect_shape(query,64):
				if hit.collider is Mine and not hit.collider.dead: hit.collider.detonate()

func _city_collision() -> void:
	if lost or city_hit: return
	city_hit = true; crash_clock = 5.0
	if won: jobs.radio("r17")

func _destroyed(_entity: String, _attacker: String) -> void:
	if lost: return
	warning_clock = -1
	if won: return # Empty freighter can be destroyed safely after the rescue.
	lost = true; won = false; result_clock = 9.2
	jobs.radio("r2" if inside else "r1",true)
	jobs.game.equipment.support_tools.passengers = false
	jobs.game.equipment.support_tools._detach_pod()

func release_survivor() -> void:
	if is_instance_valid(ship) and not ship.dead:
		if ship.arrived.is_connected(_city_collision): ship.arrived.disconnect(_city_collision)
		if ship.destroyed.is_connected(_destroyed): ship.destroyed.disconnect(_destroyed)
		Survivors.depart(jobs,ship)

func clear() -> void:
	if is_instance_valid(ship):
		if ship.arrived.is_connected(_city_collision): ship.arrived.disconnect(_city_collision)
		if ship.destroyed.is_connected(_destroyed): ship.destroyed.disconnect(_destroyed)
