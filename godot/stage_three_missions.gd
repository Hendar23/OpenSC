extends RefCounted
## Released disperse 0044fdb0 and rovrtn 0043c3e0; original text/assets only.
const Jelly = preload("res://mission_jellyfish.gd")
const Minelayer = preload("res://disabled_minelayer.gd")
const Survivors = preload("res://mission_survivors.gd")
var jobs: Node
var fish: Array[Node3D] = []
var mines: Array[Node3D] = []
var enemies: Array[Node3D] = []
var pirate_poses: Array[Transform3D] = []
var ship: RigidBody3D
var elapsed := 0.0
var kills := 0
var rescued := false
var failed := false
var attached := false
var transfer := -1.0
var safe := false
var rov_seen := false
var blast := false
var breach_clock := -1.0
var breach_stage := 0
var fail_clock := -1.0
var poll_clock := 0.0
var radio_stage := 0
var damaged_dock: Dictionary = {}
var dock_smoke: Node3D
var progress_clock := 0.0
var attack_site := Vector3.ZERO
var attack_smoke: Node3D

func start() -> void:
	if jobs.id == "disperse": _start_fish()
	else: _start_minelayers()

func _start_fish() -> void:
	jobs.phase = "defend"
	damaged_dock = jobs.game.submarine_traffic.port_by_id(4)
	if not damaged_dock.is_empty():
		damaged_dock.node.set_meta("mission_dock_disabled",true)
		dock_smoke = _smoke_at(damaged_dock.node.global_position + Vector3.UP*2.0)
	var utility := preload("res://stage_two_remaining.gd").new(); utility.jobs = jobs
	for row in jobs._rows(12):
		if int(row.ObjectID) != 1: continue
		attack_site = jobs._pose(row).origin
		var center: Vector3 = attack_site-Vector3.UP*2
		for index in range(10):
			var point := center+Vector3(randi_range(0,3),0,randi_range(0,3))
			var actor: Node3D = utility._fish("BADJELLY",point,10,0.3,false,Jelly)
			if actor == null: continue
			actor.combat.settings.has_zapper = true; actor.combat.settings.bite_damage = 4.0
			actor.navigation = jobs.game.submarine_traffic
			actor.city_target = actor.above_seabed(center); actor.player = jobs.game.pilot; actor.city_attacker = index >= 6
			actor.global_position = actor.above_seabed(point); actor.home = actor.global_position
			actor.ignore_wildlife = true; actor.swim_speed = 1.0; actor.turn_speed = 70
			actor.animation_time = index*2.0
			actor.died.connect(_fish_died); fish.append(actor)
	var cluster := preload("res://wildlife_shoal.gd").new()
	for actor in fish:
		actor.group_members = fish; actor.shoal = cluster

func _fish_died() -> void:
	if jobs.id != "disperse" or jobs.phase == "finished": return
	# Retail checks one defeat flag per creature as well as its dialogue counter.
	# Reconcile actual tracked actors: missed/duplicate signals cannot leave a
	# dead invisible creature owing a kill, or count the same death twice.
	var defeated := 0
	for actor in fish:
		if not is_instance_valid(actor) or actor.dead or actor.health <= 0: defeated += 1
	if defeated <= kills: return
	var previous := kills; kills = defeated
	var lines := {1:"l9",2:"l8",4:"l7",6:"l6",8:"l5"}
	for count in range(previous+1,kills+1):
		if lines.has(count): jobs.radio(lines[count])
	if kills >= 8:
		for actor in fish:
			if is_instance_valid(actor) and not actor.dead: actor.pursue_player = true
	if kills == 10:
		jobs.radio("l3",true); jobs._resolve(true,1.0,1)

func _start_minelayers() -> void:
	jobs.phase = "rescue"
	for row in jobs._rows(48):
		var pose: Transform3D = jobs._pose(row)
		match int(row.ObjectID):
			1: pirate_poses.append(pose)
			2,4: _mine(pose,int(row.ObjectID) == 4)
			3:
				var visual: Node3D = jobs.Document.load_model("MINING",jobs.game.game_folder)
				if visual == null: continue
				var definition: Dictionary = preload("res://object_definitions.gd").SALVAGE.duplicate(true)
				definition.merge({"id":"rescued_minelayer","name":"Minelayer","model":"MINING","health":5.0,"mass":0.2,"magnet_compatible":false},true)
				ship = Minelayer.new(); ship.game = jobs.game
				ship.setup(definition,visual,0,jobs.game.pilot.surface_height,true)
				ship.mass = 2000.0
				jobs.game.object_population.add_child(ship); ship.global_transform = pose
				_place_minelayer_clear()
				ship.set_meta("mission_owner",jobs.id); jobs.actors.append(ship); jobs.target = ship
				preload("res://entity_identity.gd").assign_id(ship)
				ship.smoke = preload("res://submarine_damage_smoke.gd").new(); ship.add_child(ship.smoke)
				ship.smoke.setup(visual,jobs.game.game_folder); ship.smoke.damaged = true; ship.smoke.enabled = true
				ship.destroyed.connect(_ship_destroyed)
				jobs.game.natural_light.attach(visual); jobs.game.water_visuals.attach(visual)
	poll_clock = 2.0

func _place_minelayer_clear() -> void:
	# Retail used a sphere; the recovered mesh's convex hull can intersect the
	# sloped cave floor at that same marker. Resolve before exposing it to ROV.
	var origin := ship.global_position
	var collider: CollisionShape3D = ship.get_child(1)
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = collider.shape
	query.collision_mask = 1; query.exclude = [ship.get_rid()]; query.margin = 0.02
	var offsets: Array[Vector3] = []
	for lift in [0.0,0.15,0.3,0.5,0.75,1.0,1.5,2.0,-0.15,-0.3,-0.5]:
		for radius in [0.0,0.25,0.5,1.0,1.5,2.0]:
			for side in (1 if radius == 0 else 8):
				var angle := side*TAU/8.0
				offsets.append(Vector3(cos(angle)*radius,lift,sin(angle)*radius))
	offsets.sort_custom(func(a: Vector3,b: Vector3) -> bool: return a.length_squared() < b.length_squared())
	for offset in offsets:
		query.transform = Transform3D(ship.global_basis,origin+offset)*collider.transform
		if not jobs.game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
		ship.global_position = origin+offset; ship.reset_physics_interpolation(); return

func _mine(pose: Transform3D, hard: bool) -> void:
	var population: Node = jobs.game.object_population
	var definition: Dictionary = preload("res://object_definitions.gd").FLOATING_MINE.duplicate(true)
	definition.merge({"appearance":"model","model":"HARDMINE" if hard else "MINE","health":1.5 if hard else 0.5,"damage":21.0 if hard else 17.5},true)
	var visual: Node3D = population.appearance(definition,jobs.game.game_folder)
	if visual == null: return
	var mine := preload("res://floating_mine.gd").new()
	var sound: AudioStream = preload("res://submarine_weapons.gd")._sound(jobs.game.game_folder,"audio.object.mine.explosion","EXPLODE1")
	mine.setup(definition,visual,sound,true); mine.player = jobs.game.pilot
	jobs.game.world_root.add_child(mine); mine.global_transform = pose; mine.home = pose.origin
	mine.set_meta("mission_owner",jobs.id); jobs.actors.append(mine); mines.append(mine)
	mine.explosion_frames.assign(population.explosion_frames)
	mine.exploded.connect(_mine_blast); mine.exploded.connect(population._exploded.bind(600.0))
	jobs.game.natural_light.attach(mine); jobs.game.water_visuals.attach(mine)

func target_body() -> CollisionObject3D:
	if jobs.id == "disperse":
		for actor in fish:
			if is_instance_valid(actor) and not actor.dead: return actor
	elif is_instance_valid(ship) and not ship.dead and not rescued: return ship
	return null

func can_attach_pod(body: Node3D) -> bool:
	return jobs.id == "rovrtn" and not failed and is_instance_valid(ship) and not ship.dead and body == ship and (rescued or not jobs.game.equipment.support_tools.passengers)

func step(delta: float) -> void:
	if jobs.id.is_empty() or jobs.phase == "finished": return
	elapsed += delta; poll_clock -= delta
	if jobs.id == "disperse":
		progress_clock -= delta
		if progress_clock <= 0:
			progress_clock = 0.2; _fish_died()
			if jobs.id != "disperse" or jobs.phase == "finished": return
		var deadlines := [20.0,32.0,200.0]
		var lines := ["l1","l4","l2"]
		while radio_stage < deadlines.size() and elapsed >= deadlines[radio_stage]:
			jobs.radio(lines[radio_stage])
			if radio_stage == 2: attack_smoke = _smoke_at(attack_site)
			radio_stage += 1
		return
	if fail_clock >= 0:
		fail_clock -= delta
		if fail_clock <= 0:
			if is_instance_valid(ship) and not ship.dead: ship.take_weapon_damage(1000)
			jobs.radio("av11",true); jobs._resolve(false,0,2)
		return
	if not is_instance_valid(ship) or ship.dead: return
	var tools: Node3D = jobs.game.equipment.support_tools
	if poll_clock <= 0:
		poll_clock = 2.0
		if not rov_seen and is_instance_valid(tools.rover) and tools.rover.launched and ship.global_position.distance_squared_to(tools.rover.global_position) < 25:
			rov_seen = true; ship.movable = true; ship.mass = 0.2; ship.stats.mass = 0.2; jobs.radio("av4")
		var clear := mines.all(func(mine: Node3D) -> bool: return not is_instance_valid(mine) or mine.dead or mine.global_position.distance_squared_to(ship.global_position) >= 36)
		if clear != safe:
			safe = clear; jobs.radio("av6" if safe else "av7")
	var touching: bool = tools.pod_target == ship
	if touching != attached:
		attached = touching
		if touching:
			if rescued: jobs.radio("av1")
			elif not failed: transfer = 10.0; jobs.radio("av2")
		else:
			if transfer >= 0 and not rescued and not failed: jobs.radio("av3")
			transfer = -1
	if transfer >= 0 and attached and not failed:
		transfer -= delta
		if transfer <= 0:
			transfer = -1; rescued = true; tools.passengers = true; jobs.phase = "return"
			jobs.radio("av5",true); _spawn_pirates()
	if breach_clock >= 0:
		breach_clock -= delta
		if breach_clock <= 0:
			breach_stage += 1
			if breach_stage == 1:
				if not rescued and not attached: jobs.radio("av8")
				breach_clock = 18.4
			elif breach_stage == 2:
				if not rescued and not attached: jobs.radio("av9")
				breach_clock = 18.4
			elif breach_stage == 3:
				if not rescued and not attached:
					failed = true; transfer = -1; jobs.radio("av10",true)
					fail_clock = 9.2; breach_clock = -1; return
				breach_clock = 9.2
			else:
				breach_clock = -1; ship.take_weapon_damage(1000)

func _mine_blast(_point: Vector3, _damage: float, _radius: float) -> void:
	if blast or not is_instance_valid(ship) or ship.dead: return
	blast = true
	# Evaluate the live geometry on the blast frame, including the detonating
	# mine, rather than relying on the previous two-second advisory scan.
	safe = _point.distance_squared_to(ship.global_position) >= 36 and mines.all(func(mine: Node3D) -> bool: return not is_instance_valid(mine) or mine.dead or mine.global_position.distance_squared_to(ship.global_position) >= 36)
	# The callback turns the entire dense payload into a chain reaction, not
	# just whichever mines happen to overlap a renderer/physics query limit.
	for mine in mines:
		if is_instance_valid(mine) and not mine.dead: mine.detonate.call_deferred()
	if not safe: ship.take_weapon_damage(1000)
	else: breach_clock = 1.2

func _ship_destroyed() -> void:
	if rescued or failed or jobs.id.is_empty(): return
	failed = true; transfer = -1; jobs.game.equipment.support_tools._detach_pod(false)
	jobs.radio("av12",true); fail_clock = 2.4

func _spawn_pirates() -> void:
	for pose in pirate_poses:
		var agent: Node3D = jobs._boat("PIRATE",pose,3,30,2.5)
		if agent == null: continue
		jobs._place_vessel_clear(agent,true)
		agent.engage_player = true; agent.pursue_offscreen = true; agent.tuning.npc_detection = 1000.0
		enemies.append(agent)

func docked(city: int) -> void:
	if jobs.id == "rovrtn" and rescued and not failed and city in [1,2,3,4]:
		jobs.runtime.active()["resolved_city"] = city; jobs._resolve(true,1.0,1)

func release_survivors() -> void:
	Survivors.release(jobs,enemies)
	if is_instance_valid(ship) and not ship.dead:
		# Preserve the empty disabled hull in ordinary object snapshots. It does
		# not acquire a working engine or vanish when the crew reaches home.
		ship.mass = 0.2; ship.remove_meta("mission_owner"); jobs.actors.erase(ship)

func clear() -> void:
	if not damaged_dock.is_empty() and is_instance_valid(damaged_dock.node): damaged_dock.node.remove_meta("mission_dock_disabled")
	if is_instance_valid(dock_smoke): dock_smoke.enabled = false
	if is_instance_valid(attack_smoke): attack_smoke.enabled = false
	damaged_dock = {}
	for actor in Array(fish)+Array(mines)+[ship]:
		if not is_instance_valid(actor): continue
		for info in actor.get_signal_list():
			for connection in actor.get_signal_connection_list(info.name):
				if connection.callable.get_object() == self: actor.disconnect(info.name,connection.callable)

func _smoke_at(point: Vector3) -> Node3D:
	var effect := preload("res://smoke_emitter.gd").new()
	jobs.game.world_root.add_child(effect); jobs.actors.append(effect)
	effect.global_position = point; effect.configure(jobs.game.game_folder,{})
	return effect
