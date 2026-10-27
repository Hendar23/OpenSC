extends RefCounted
## Retail side jobs: 00424220, 0040cc80, 004258b0, 0044e960, 00480e60.
const ListeningProbe = preload("res://listening_probe.gd")
var jobs: Node3D
var family := ""
var enemies: Array[Node3D] = []
var eel_helpers: Array[Node3D] = []
var recon_reinforcements: Array[Node3D] = []
var scheduled: Array[Dictionary] = []
var ship: Node3D
var cargo: Node3D
var creature: Node3D
var structure: Node3D
var turrets: Array[Node3D] = []
var poses: Array[Transform3D] = []
var flags := {}
var rescuer: Node3D
var rescue_pod: Node3D
var rescue_cable: MeshInstance3D
var recon_cable: MeshInstance3D
var transfer := 0.0
var elapsed := 0.0
var wave := 3
var dialogue := 0
var scan := 0.0

func start() -> void:
	family = "spy" if jobs.id.begins_with("spytech") else "escort" if jobs.id.begins_with("escort") else "recon" if jobs.id.begins_with("recontech") else jobs.id
	jobs.phase = family
	match family:
		"spy": _start_spy()
		"escort": _start_escort()
		"tagtech": _start_tag()
		"eel": _start_eel()
		"recon": _start_recon()

func clear() -> void:
	_end_boarding()
	_end_recon_link()
	# Live attackers can outlast this mission. Their old signal closures must
	# not resolve a different mission when one is attacked or destroyed later.
	var sources: Array = Array(jobs.vessels)+Array(enemies)+[ship,cargo,creature,structure,rescuer]
	for source in sources:
		if not is_instance_valid(source): continue
		for signal_info in source.get_signal_list():
			for connection in source.get_signal_connection_list(signal_info.name):
				if connection.callable.get_object() == self: source.disconnect(signal_info.name,connection.callable)
	scheduled.clear(); enemies.clear(); eel_helpers.clear(); recon_reinforcements.clear(); turrets.clear(); poses.clear()
	ship = null; cargo = null; creature = null; structure = null; rescuer = null; rescue_pod = null

func later(seconds: float, event: String) -> void:
	scheduled.append({"time":seconds,"event":event})

func radio(code: String, terminal: bool = false) -> void:
	jobs.radio(code,terminal)

func finish(success: bool, score: float = 1.0, response: int = 1) -> void:
	jobs._resolve(success,score,response)

func target_body() -> CollisionObject3D:
	var actor: Node3D
	match family:
		"spy": actor = cargo if is_instance_valid(cargo) else ship
		"escort": actor = rescuer if flags.get("escaped",false) and is_instance_valid(rescuer) else ship
		"tagtech": actor = cargo if flags.get("found",false) or flags.get("collected",false) else creature
		"eel": actor = structure if flags.get("huge_dead",false) else creature
		"recon": actor = structure
	if not is_instance_valid(actor) or actor.get("dead") == true: return null
	return actor if actor is CollisionObject3D else actor.get("body")

func step(delta: float) -> void:
	elapsed += delta
	for event in scheduled.duplicate():
		event.time -= delta
		if event.time <= 0:
			scheduled.erase(event); _event(str(event.event))
			if jobs.id.is_empty(): return
	match family:
		"spy": _step_spy(delta)
		"escort": _step_escort(delta)
		"tagtech": _step_tag()
		"eel": _step_eel(delta)
		"recon": _step_recon(delta)

func _mark(actor: Node3D, faction: int = 0) -> void:
	var body: Node3D = actor if actor is CollisionObject3D else actor.body
	# Fish.bounds is the entire playable world, whereas vessel.bounds is its
	# local hull. Collision objects already carry their own local target centre.
	if not actor is CollisionObject3D and actor.get("bounds") is AABB: body.set_meta("mission_target_center",actor.bounds.get_center())
	body.set_meta("mission_marker",true); body.set_meta("faction",faction)
	if not jobs.game.cockpit_hud.map_data.actor_markers.has(body): jobs.game.cockpit_hud.map_data.actor_markers.append(body)

func _boat(model: String, pose: Transform3D, faction: int, health: float, speed: float = 2.0, separate_vessels: bool = false) -> Node3D:
	var agent: Node3D = jobs._boat(model,pose,faction,health,speed)
	if agent == null: return null
	jobs._place_vessel_clear(agent,separate_vessels); _mark(agent,faction)
	return agent

func _hostile(agent: Node3D) -> void:
	if not is_instance_valid(agent) or agent.dead: return
	agent.follow = null; agent.combat_target = null; agent.engage_player = true
	agent.pursue_offscreen = true; agent.tuning.npc_detection = 1000.0
	agent.path.clear(); agent.replan = 0

func _structure(pose: Transform3D, health: float) -> Node3D:
	var model: Node3D = jobs.Document.load_model("OUTPOST",jobs.game.game_folder)
	if model == null: return null
	var body := preload("res://mission_structure.gd").new(); jobs.game.world_root.add_child(body)
	body.global_transform = pose; body.setup(model,jobs.game,health); jobs.actors.append(body)
	body.set_meta("mission_owner",jobs.id); _mark(body,1)
	jobs.game.natural_light.attach(model); jobs.game.water_visuals.attach(model)
	return body

func _fish(model: String, point: Vector3, health: float, sustain: float, map_marker: bool = true, controller: Script = null) -> Node3D:
	var visual: Node3D = jobs.Document.load_model(model,jobs.game.game_folder,true)
	if visual == null: return null
	var body: Node3D = (controller if controller != null else preload("res://mission_creature.gd")).new()
	var meshes := preload("res://submarine_equipment.gd")._meshes(visual,Transform3D.IDENTITY)
	var bounds := preload("res://submarine_equipment.gd")._bounds(meshes)
	# Retail creature clumps retain their authoring offset. As with ambient
	# wildlife, centre the visible mesh before fitting its physical hull.
	visual.position -= bounds.get_center()
	var radius := maxf(0.15,minf(bounds.size.x,bounds.size.y)*0.35)
	body.setup(visual,point,jobs.game.world_root.get_meta("bounds"),jobs.game.pilot.surface_height,radius,hash(jobs.id+model))
	body.mission_owner = jobs.id; body.set_meta("mission_owner",jobs.id)
	body.configure_health(health); body.damage_sustain = sustain
	body.population = jobs.game.wildlife; body.response = "attack"; body.attack_range = 4
	body.configure_combat({"model":model.to_lower(),"food_role":"predator","has_zapper":model in ["MUTANT","MJACK"],"attack_range":4})
	body.death_texture = jobs.game.wildlife.death_texture; body.death_sound = jobs.game.wildlife.death_sound; body.death_frames = jobs.game.wildlife.death_frames
	body.death_flesh_texture = jobs.game.wildlife.death_flesh_texture
	if model == "BIGEEL": body.death_particle_scale = clampf(bounds.size.length()/2.0,1.0,4.0)
	jobs.game.world_root.add_child(body); jobs.actors.append(body)
	body.set_meta("mission_target_center",Vector3.ZERO)
	jobs.game.natural_light.attach(visual); jobs.game.water_visuals.attach(visual)
	if map_marker: _mark(body)
	return body

func _start_spy() -> void:
	var waypoints := {}
	for row in jobs._rows(31):
		if int(row.ObjectID) == 1: waypoints[int(row.param1)] = jobs._pose(row).origin
		elif int(row.ObjectID) == 2: poses.append(jobs._pose(row))
	if not waypoints.has(0) or not waypoints.has(1): return
	ship = _boat("TRADSHUT",Transform3D(Basis.IDENTITY,waypoints[0]),1,10,1.5)
	if ship == null: return
	ship.combat_enabled = false; ship.loop_route = true; ship.waypoints = PackedVector3Array([waypoints[1],waypoints[0]])
	ship.destroyed.connect(_spy_shuttle_destroyed)
	ship.player_attacked.connect(func() -> void:
		if not flags.get("hit_shuttle",false): flags["hit_shuttle"] = true; radio("ae12"))
	jobs.target = ship; scan = 4.0

func _spy_shuttle_destroyed(_id: String, _attacker: String) -> void:
	# 00424220 case 10 cancels scans, intercepted speech and pending warnings,
	# and removes the attached listening device even if the freighter is live.
	scheduled.assign(scheduled.filter(func(event: Dictionary) -> bool: return event.event not in ["spy_warning","spy_failed"]))
	var tools: Node3D = jobs.game.equipment.support_tools
	for probe in tools.projectiles.duplicate():
		if is_instance_valid(probe) and probe is ListeningProbe and probe.attached and probe.designated_target == ship.body:
			tools.projectiles.erase(probe); probe.queue_free()
	if not is_instance_valid(cargo): radio("miss2",true); finish(false,0,2)

func attach_listening(body: Node3D) -> bool:
	if family != "spy" or jobs.tapped or not is_instance_valid(ship) or ship.dead or ship.body != body or flags.get("failed",false): return false
	jobs.tapped = true; transfer = 0; radio("ae1")
	return true

func _step_spy(delta: float) -> void:
	if not is_instance_valid(ship): return
	scan -= delta
	if scan <= 0 and not ship.dead and not flags.get("detected",false):
		scan = 2.4
		var offset: Vector3 = jobs.game.pilot.global_position-ship.global_position
		if offset.length() < 8 and (2.0-ship.get_parent().global_basis.z.dot(offset.normalized()))*offset.length() < 6:
			var ray := PhysicsRayQueryParameters3D.create(ship.global_position,jobs.game.pilot.global_position,1)
			if jobs.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				if not flags.get("seen",false): flags["seen"] = true
				else:
					flags["detected"] = true
					if jobs.tapped: radio("ae8")
					if is_instance_valid(cargo): _spy_guards(true)
					else: flags["failed"] = true
					later(7 if jobs.tapped else 1,"spy_warning")
	if jobs.tapped and not flags.get("detected",false):
		transfer += delta
		while dialogue < 5 and transfer >= (dialogue+1)*8.0:
			radio(["ae3","ae4","ae5","ae6","ae7"][dialogue]); dialogue += 1
			if dialogue == 5: _spawn_freighter(); later(8,"ae9"); later(16,"ae10")

func _spawn_freighter() -> void:
	if poses.is_empty(): return
	cargo = _boat("FREIGHT",poses[0],1,60,0.6)
	if cargo == null: return
	cargo.tuning.npc_sustain = 0.5; cargo.health.configure(60,0.5); cargo.body.set_meta("damage_sustain",0.5)
	cargo.combat_enabled = false; cargo.set_meta("mission_target_center",cargo.bounds.get_center()); jobs.target = cargo
	cargo.arm_freighter(jobs.game.game_folder)
	cargo.destroyed.connect(func(_id: String,_attacker: String) -> void: later(2,"spy_success"))
	cargo.hull_damaged.connect(func(_attacker: Node3D) -> void: _spy_guards(false))
	later(8,"cargo_warning")
	for index in range(4):
		var offset := Vector3(-2 if index%2 == 0 else 2,1,-2 if index < 2 else 2)
		var guard := _boat("TRAD-SUB",Transform3D(Basis.IDENTITY,cargo.global_position+offset),1,10)
		if guard == null: continue
		guard.follow = cargo; guard.formation = offset; enemies.append(guard)
		guard.hull_damaged.connect(func(_attacker: Node3D) -> void: _spy_guards(false))

func _spy_guards(reinforce: bool) -> void:
	if reinforce and not flags.get("reinforced",false):
		flags["reinforced"] = true
		for index in range(4):
			var guard := _boat("TRAD2",Transform3D(Basis.IDENTITY,cargo.global_position+Vector3((index%2)*3-1.5,2,(index/2)*3-1.5)),1,10)
			if guard != null: enemies.append(guard)
	for agent in enemies: _hostile(agent)

func _start_escort() -> void:
	for row in jobs._rows(27):
		ship = _boat("PRISON",jobs._pose(row),1,20,0.5)
	if ship == null: return
	ship.combat_enabled = false; jobs.target = ship
	ship.destroyed.connect(func(_id: String,_attacker: String) -> void:
		if not flags.get("escaped",false): radio("aa2"); later(3,"aa3"); later(6,"escort_dead"))
	ship.arrived.connect(_prison_arrived)

func _step_escort(delta: float) -> void:
	if not is_instance_valid(ship): return
	if not flags.get("started",false) and not ship.dead and ship.global_position.distance_to(jobs.game.pilot.global_position) < 5:
		flags["started"] = true; ship.waypoint = 0; ship.arrival_reported = false
		ship.waypoints = PackedVector3Array([_port_goal(5,ship.global_position)]); ship.dock_destination = 5
		later(2,"aa1"); later(20,"escort_wave")
	if flags.get("escaped",false):
		if not flags.get("escape_reported",false) and is_instance_valid(rescuer) and not rescuer.dead and rescuer.stage == "berth" and rescuer.last_city == 2:
			radio("aa6"); later(6,"escort_escape"); flags["escape_reported"] = true
		return
	if ship.dead: return
	if flags.get("started",false) and ship.stage == "berth" and ship.last_city == 5:
		_prison_arrived(); return
	if not is_instance_valid(rescuer) or rescuer.dead:
		_end_boarding()
		transfer = 0
		for agent in enemies:
			if not agent.dead and agent.get_meta("pod_rescuer",false):
				rescuer = agent; agent.engage_player = false; agent.combat_target = null; agent.victim = null
				agent.boarding = true; agent.follow = ship
				agent.formation = Vector3(-0.3,2,-0.1) if agent.get_meta("pod_slot",1) == 0 else Vector3(0,2,-0.4)
				agent.path.clear(); agent.replan = 0; agent.wait = 0; agent.flee = 0
				# This deliberate boarding formation must not invoke the ships'
				# ordinary collision/traffic separation against its own host.
				agent.body.add_collision_exception_with(ship.body); ship.body.add_collision_exception_with(agent.body)
				break
	if is_instance_valid(rescuer) and not rescuer.dead:
		if rescuer.global_position.distance_to(rescuer.boarding_goal()) <= 0.7:
			if transfer == 0: _rescue_visual(); later(2,"escort_boarding")
			_update_rescue_visual(delta)
			transfer += delta
			if transfer >= 16:
				flags["escaped"] = true; radio("aa8"); ship.tuning.npc_speed = 1.5
				_end_boarding()
				rescuer.follow = null; rescuer.path.clear(); rescuer.waypoint = 0; rescuer.waypoints = PackedVector3Array([_port_goal(2,rescuer.global_position)])
				rescuer.dock_destination = 2; rescuer.combat_enabled = false; rescuer.arrival_reported = false
		else:
			transfer = 0
			_stow_rescue_pod()

func _port_goal(city: int, from: Vector3) -> Vector3:
	var traffic: Node = jobs.game.submarine_traffic
	var center: Vector3 = jobs._city(city)
	if city == 5:
		var port: Dictionary = traffic.port_by_id(city)
		if not port.is_empty():
			# Choose the reachable side we are approaching from, rather than the
			# graph point nearest the building's centre on the far side.
			var best := INF; var goal := Vector3.INF
			for point_id in traffic.graph.get_point_ids():
				var point: Vector3 = traffic.graph.get_point_position(point_id)
				if point.distance_to(port.entry) >= 8 or not traffic.segment_clear(point,point): continue
				var route: PackedVector3Array = traffic.abstract_route(from,point)
				if route.is_empty(): continue
				var distance: float = point.distance_to(port.entry); var previous := from
				for step in route: distance += previous.distance_to(step); previous = step
				if distance < best: best = distance; goal = point
			if goal.is_finite(): return goal
	var options: Array = []
	for point_id in traffic.graph.get_point_ids():
		var point: Vector3 = traffic.graph.get_point_position(point_id)
		if point.distance_to(center) < 8: options.append([point.distance_squared_to(center),point])
	options.sort_custom(func(a: Array,b: Array) -> bool: return a[0] < b[0])
	for option in options:
		if not traffic.abstract_route(from,option[1]).is_empty(): return option[1]
	return center

func _escort_wave() -> void:
	if wave < 0: return
	var traffic: Node = jobs.game.submarine_traffic
	var launch: Vector3 = jobs._city(2)
	var nearest := INF
	for point_id in traffic.graph.get_point_ids():
		var point: Vector3 = traffic.graph.get_point_position(point_id)
		var distance := point.distance_squared_to(jobs._city(2))
		if distance > 144.0 or distance >= nearest or not traffic.water_clear(point): continue
		var occupied := false
		for other in traffic.traders:
			if not other.dead and other.stage == "travel" and other.global_position.distance_to(point) < maxf(2.5,other.bounds.size.length()+0.5): occupied = true; break
		if not occupied: launch = point; nearest = distance
	var agent := _boat("TECH2SUB" if wave >= 2 else "TECHNEW",Transform3D(Basis.IDENTITY,launch),2,15,3.5 if wave < 2 else 2.0)
	if agent != null:
		enemies.append(agent); _hostile(agent); agent.set_meta("pod_rescuer",wave < 2)
		if wave < 2:
			agent.set_meta("pod_slot",wave)
			var pod: Node3D = jobs.Document.load_model("ESCAPE",jobs.game.game_folder)
			if pod != null:
				agent.get_parent().add_child(pod); pod.position = Vector3(0,-0.3,0)
				pod.set_meta("exclude_from_debris",true); agent.boarding_pod = pod; jobs.actors.append(pod)
				jobs.game.natural_light.attach(pod); jobs.game.water_visuals.attach(pod)
		agent.destroyed.connect(func(_id: String,_attacker: String) -> void:
			if agent == rescuer:
				if is_instance_valid(rescue_pod): rescue_pod.queue_free(); rescue_pod = null
				if flags.get("escaped",false): radio("aa10",true); finish(true,0.5,2))
	wave -= 1
	if wave >= 0: later(8,"escort_wave")

func _rescue_visual() -> void:
	if is_instance_valid(rescue_pod): return
	rescue_pod = rescuer.boarding_pod
	if not is_instance_valid(rescue_pod): return
	rescue_pod.reparent(ship.get_parent(),true)
	rescue_cable = MeshInstance3D.new(); var cable := CylinderMesh.new()
	cable.top_radius = 0.004; cable.bottom_radius = 0.004; cable.height = 1.0; cable.radial_segments = 6
	rescue_cable.mesh = cable
	var material := StandardMaterial3D.new(); material.albedo_color = Color(0.3,0.35,0.36)
	rescue_cable.material_override = material; rescue_cable.set_meta("exclude_from_debris",true)
	jobs.game.world_root.add_child(rescue_cable); jobs.actors.append(rescue_cable)

func _update_rescue_visual(delta: float) -> void:
	if not is_instance_valid(rescue_pod): return
	rescue_pod.position = rescue_pod.position.move_toward(Vector3(rescuer.formation.x,0.4,rescuer.formation.z),delta*3.0)
	var start: Vector3 = rescuer.get_parent().to_global(Vector3(0,-0.2,0))
	var span: Vector3 = rescue_pod.global_position-start
	if not is_instance_valid(rescue_cable): return
	rescue_cable.visible = span.length() > 0.005
	rescue_cable.global_position = start+span*0.5
	if rescue_cable.visible: rescue_cable.global_basis = Basis(Quaternion(Vector3.UP,span.normalized())).scaled(Vector3(1,span.length(),1))

func _stow_rescue_pod() -> void:
	if is_instance_valid(rescue_pod):
		if is_instance_valid(rescuer) and not rescuer.dead:
			rescue_pod.reparent(rescuer.get_parent(),true); rescue_pod.transform = Transform3D(Basis.IDENTITY,Vector3(0,-0.3,0))
		else: rescue_pod.queue_free()
	rescue_pod = null
	if is_instance_valid(rescue_cable): rescue_cable.queue_free()
	rescue_cable = null

func _end_boarding() -> void:
	_stow_rescue_pod()
	if not is_instance_valid(rescuer): return
	rescuer.boarding = false; rescuer.follow = null
	if is_instance_valid(ship) and is_instance_valid(ship.body) and is_instance_valid(rescuer.body):
		rescuer.body.remove_collision_exception_with(ship.body); ship.body.remove_collision_exception_with(rescuer.body)

func _prison_arrived() -> void:
	if jobs.id.is_empty() or jobs.phase == "finished" or ship.dead: return
	# 0040cc80 orders docking with message 0x31 and resolves on the docked
	# notification (0x1e), rather than deleting the transport on approach.
	if not flags.get("started",false) or ship.stage != "berth" or ship.last_city != 5: return
	if not flags.get("escaped",false): radio("aa9",true); finish(true,1,1)

func _start_tag() -> void:
	var points := {}
	var start := Vector3.ZERO
	var deposit := Vector3.ZERO
	for row in jobs._rows(9):
		match int(row.ObjectID):
			2: start = jobs._pose(row).origin
			3: points[int(row.param2)] = jobs._pose(row).origin
			4: deposit = jobs._pose(row).origin
	creature = _fish("LIONFISH",start,10,0.25)
	if creature != null:
		creature.swim_speed = 0.8; creature.roam_radius = 0.2
		creature.ignore_wildlife = true
		for index in range(17):
			if points.has(index): creature.route.append(points[index])
		creature.died.connect(func() -> void:
			if not flags.get("found",false): radio("ii1",true); finish(false,0,2))
	# 004258b0 creates five untagged mutants with the specimen, then four
	# mutant lionfish and four thorium crystals at the pollution source.
	var random := RandomNumberGenerator.new(); random.seed = hash(jobs.id)
	for index in range(5):
		var variant := random.randi_range(0,3)
		var model: String = ["MUTANT","MUTANT","MSILVER","BABY"][variant]
		var companion := _fish(model,start+Vector3(random.randf_range(-2,2),0,random.randf_range(-2,2)),10,[0.25,0.5,1.25,0.25][variant],false)
		if companion != null: companion.roam_radius = 4
	for index in range(4):
		var offset := Vector3(cos(index*TAU/4)*0.8,0.2,sin(index*TAU/4)*0.8)
		_fish("MUTANT",deposit+offset,10,0.25,false)
		# Retail spawns these as independent world resources, not mission actors.
		jobs.game.object_population._create_thorium(preload("res://object_definitions.gd").THORIUM,0,Transform3D(Basis.IDENTITY,deposit+offset))
	var visual: Node3D = jobs.Document.load_model("CANISTER",jobs.game.game_folder)
	if visual == null: return
	cargo = preload("res://mission_cargo.gd").new(); jobs.game.world_root.add_child(cargo)
	cargo.global_position = deposit; cargo.add_child(visual); cargo.mass = 1.5; cargo.health = 5; cargo.surface_height = jobs.game.pilot.surface_height
	cargo.damage_sustain = 0.1; cargo.set_meta("damage_sustain",0.1)
	cargo.stats = {"delivery_commodity":"Radioactive canister","delivery_quantity":1}; cargo.set_meta("mission_owner",jobs.id)
	# CANISTER callback 004260f0 overrides inflict to 0.05, within four units.
	cargo.stats.merge({"radiation_range":4.0,"radiation_strength":preload("res://original_damage.gd").radiation_strength(0.05)})
	cargo.add_to_group("mission_radiation_sources")
	var box := preload("res://submarine_equipment.gd")._bounds(preload("res://submarine_equipment.gd")._meshes(visual,Transform3D.IDENTITY))
	var shape := CollisionShape3D.new(); shape.shape = BoxShape3D.new(); shape.shape.size = box.size; shape.position = box.get_center(); cargo.add_child(shape)
	cargo.set_meta("mission_target_center",box.get_center()); jobs.actors.append(cargo)
	jobs.game.natural_light.attach(visual); jobs.game.water_visuals.attach(visual)
	cargo.destroyed.connect(_canister_destroyed)
	jobs.target = creature

func _canister_destroyed() -> void:
	jobs.burst(cargo.to_global(cargo.get_meta("mission_target_center",Vector3.ZERO)),1.5)
	radio("ii2",true); finish(false,0,2)

func _step_tag() -> void:
	if not is_instance_valid(cargo) or cargo.dead: return
	if not flags.get("found",false) and jobs.game.pilot.global_position.distance_to(cargo.global_position) < 8:
		flags["found"] = true; radio("ii7" if is_instance_valid(creature) and creature.route_index >= 7 else "ii8"); _mark(cargo)
	if not flags.get("collected",false) and jobs.game.equipment.magnet.target == cargo:
		flags["found"] = true; flags["collected"] = true; radio("ii3"); _mark(cargo)

func delivery(body: Node3D, city: int) -> bool:
	if family != "tagtech" or body != cargo: return false
	if city not in [2,4]:
		radio("ii6" if city == 6 else "ii5"); jobs.game.equipment.magnet.decline_delivery(); return true
	cargo.delivered = true; jobs.game.equipment.magnet.set_enabled(false); jobs.runtime.active()["resolved_city"] = city
	radio("ii4",true); finish(true); return true

func _start_eel() -> void:
	for row in jobs._rows(3):
		if int(row.ObjectID) == 1: structure = _structure(jobs._pose(row),10)
		elif int(row.ObjectID) == 2: poses.append(jobs._pose(row))
	if structure == null: return
	structure.start_smoke(); structure.destroyed.connect(func() -> void: radio("c7"); later(6,"eel_failed"))
	creature = _fish("MEEL",structure.global_position+Vector3(0,3.8,0),10,0.25)
	if creature != null:
		creature.home = structure.global_position+Vector3.UP*2; creature.roam_radius = 3; creature.swim_speed = 1.2
		creature.contact_victim = structure
		creature.died.connect(func() -> void: radio("c9"); later(6,"huge_eel"))
	for index in range(3):
		var helper := _boat("TRAD-SUB",Transform3D(Basis.IDENTITY,structure.global_position+Vector3(index*1.5-1.5,4,5)),1,10)
		if helper != null:
			helper.combat_enabled = false; helper.running = false; eel_helpers.append(helper)
	jobs.target = structure

func can_attach_pod(body: Node3D) -> bool:
	if family != "eel" or body != structure or structure.dead: return false
	if not flags.get("huge_dead",false):
		if not flags.get("refused",false): radio("c3"); flags["refused"] = true
		return false
	return true

func _step_eel(delta: float) -> void:
	if flags.get("miners_aboard",false): return
	if not is_instance_valid(structure) or structure.dead: return
	if not flags.get("help",false) and elapsed >= 8 and jobs.game.pilot.global_position.distance_to(structure.global_position) < 9:
		flags["help"] = true; radio("c6")
		for helper in eel_helpers:
			if is_instance_valid(helper) and not helper.dead:
				helper.waypoints = PackedVector3Array([_port_goal(int(jobs.runtime.active().city),helper.global_position)]); helper.dock_destination = int(jobs.runtime.active().city); helper.running = true
	if jobs.game.equipment.support_tools.pod_target == structure:
		if transfer == 0: radio("c2")
		transfer += delta
		if transfer >= 12:
			flags["miners_aboard"] = true; jobs.phase = "return"
			jobs.game.equipment.support_tools.passengers = true
			jobs.game.equipment.support_tools._detach_pod()
			jobs.game.cockpit_hud.map_data.actor_markers.erase(structure)
			jobs.actors.erase(structure); structure.remove_meta("mission_owner"); structure.demolish_after(3.0)
			radio("c5")
	elif transfer > 0: transfer = 0; radio("c4")

func _huge_eel() -> void:
	if not is_instance_valid(structure) or structure.dead or poses.is_empty(): return
	var pose: Transform3D = poses[0]
	if poses.size() > 1 and jobs.game.camera.global_position.distance_to(poses[1].origin) < jobs.game.camera.global_position.distance_to(pose.origin): pose = poses[1]
	radio("c10" if jobs.game.camera.is_position_behind(pose.origin) else "c11")
	creature = _fish("BIGEEL",pose.origin,10,0.125)
	if creature == null: return
	creature.swim_speed = 1.5; creature.home = structure.global_position+Vector3.UP*2; creature.roam_radius = 4
	# HUGEEEL is marked non-solid in OBJECTS.CSV. Retain layer eight so
	# weapons can hit it, without wedging its long hull in the mine/terrain.
	creature.collision_mask = 0; creature.giant_eel = true; creature.giant_player = jobs.game.pilot
	creature.died.connect(func() -> void: flags["huge_dead"] = true; radio("c1"))

func _start_recon() -> void:
	for row in jobs._rows(15):
		match int(row.ObjectID):
			1: structure = _structure(jobs._pose(row),20)
			6: poses.append(jobs._pose(row))
	if structure == null: return
	jobs.target = structure
	structure.attacked.connect(func() -> void:
		if not flags.get("attacked",false): flags["attacked"] = true; radio("o2"); _end_recon_link(); _hostile(ship))
	structure.destroyed.connect(func() -> void:
		_end_recon_link()
		if flags.get("recorded",false): radio("miss1",true); finish(true)
		else: radio("o4",true); finish(false,0,2))
	ship = _boat("TRAD-SUB",Transform3D(Basis.IDENTITY,structure.global_position+Vector3(2,1,0)),1,10)
	if ship != null:
		ship.follow = structure; ship.formation = Vector3(2,1,0); enemies.append(ship)
		ship.player_attacked.connect(func() -> void: _end_recon_link(); _hostile(ship))
		ship.destroyed.connect(func(_id: String,_attacker: String) -> void: _end_recon_link())
		recon_cable = MeshInstance3D.new(); var line := CylinderMesh.new()
		line.top_radius = 0.004; line.bottom_radius = 0.004; line.height = 1.0; line.radial_segments = 6
		recon_cable.mesh = line
		var material := StandardMaterial3D.new(); material.albedo_color = Color(0.3,0.35,0.36)
		recon_cable.material_override = material; recon_cable.set_meta("exclude_from_debris",true)
		jobs.game.world_root.add_child(recon_cable); jobs.actors.append(recon_cable)
		_update_recon_link()
	for row in jobs._rows(15):
		if int(row.ObjectID) == 2: _recon_turret(jobs._pose(row))
		# Released 00480e60 skips the three ObjectID 3 rows entirely.
		elif int(row.ObjectID) == 4:
			var holder := Node3D.new(); jobs.game.world_root.add_child(holder); jobs.actors.append(holder)
			preload("res://scenery_loader.gd")._add_light(holder,jobs._pose(row).origin,0.7,4.0,jobs.game.game_folder,"Recon")
		elif int(row.ObjectID) == 5:
			var beam: Node3D = jobs.Document.load_model("LITEBEEM",jobs.game.game_folder)
			if beam != null:
				jobs.game.world_root.add_child(beam); beam.global_transform = jobs._pose(row); jobs.actors.append(beam)
				beam.set_meta("exclude_from_debris",true)
				jobs.game.water_visuals.attach(beam)

func _update_recon_link() -> void:
	if not is_instance_valid(recon_cable): return
	if not is_instance_valid(structure) or structure.dead or not is_instance_valid(ship) or ship.dead:
		_end_recon_link(); return
	var start: Vector3 = structure.to_global(Vector3(0.7,0.6,0))
	var span: Vector3 = ship.get_parent().to_global(Vector3(0,-0.2,0))-start
	recon_cable.visible = span.length() > 0.005
	recon_cable.global_position = start+span*0.5
	if recon_cable.visible: recon_cable.global_basis = Basis(Quaternion(Vector3.UP,span.normalized())).scaled(Vector3(1,span.length(),1))

func _end_recon_link() -> void:
	if is_instance_valid(recon_cable): recon_cable.queue_free()
	recon_cable = null

func _recon_turret(pose: Transform3D) -> void:
	var model: Node3D = jobs.Document.load_model("TURRET",jobs.game.game_folder)
	if model == null: return
	jobs.game.world_root.add_child(model); model.global_transform = pose; jobs.actors.append(model)
	preload("res://scenery_loader.gd")._add_prop_collision(model)
	var gun := preload("res://gun_turret.gd").install(model,{"turret_health":10.0,"turret_faction":1,"turret_armed":false})
	gun.player = jobs.game.pilot; gun.hostile = func(_faction: int) -> bool: return flags.get("alarm",false)
	gun.report_player_attack = false; gun.mission_owner = jobs.id
	gun.missile_template = jobs.game.turret_system.templates[0]; gun.bubble_trail = jobs.game.turret_system.bubbles
	gun.bubble_texture = jobs.game.submarine_traffic.bubble_texture; gun.explosion_frames = jobs.game.submarine_traffic.explosion_frames; gun.explosion_sound = jobs.game.submarine_traffic.explosion_sound
	turrets.append(gun); jobs.game.natural_light.attach(model); jobs.game.water_visuals.attach(model)

func _step_recon(delta: float) -> void:
	_update_recon_link()
	if not is_instance_valid(structure) or structure.dead: return
	var distance: float = jobs.game.pilot.global_position.distance_to(structure.global_position)
	scan -= delta
	# Original callback polls after eight seconds, then every fifty ticks.
	# Give the warning first, even if the initial approach is already close.
	if elapsed >= 8 and scan <= 0 and not flags.get("alarm",false):
		scan = 2.0
		if distance < 20 and not flags.get("greeted",false): flags["greeted"] = true; radio("o3")
		elif distance < 15 and not flags.get("alarm_pending",false):
			flags["alarm_pending"] = true; later(0.4,"recon_alarm")
	if flags.get("alarm",false):
		for gun in turrets:
			if not gun.dead: gun.retaliation = 5

func _recon_alarm() -> void:
	if flags.get("alarm",false): return
	flags["alarm"] = true; radio("o6")
	_end_recon_link()
	# Keep the cave approach clear. The original alarm creates this wave,
	# after the encounter is underway, rather than parking it outside early.
	for index in poses.size():
		var agent := _boat("TRAD2" if index == 0 else "TRAD-SUB",poses[index],1,10,3.5,true)
		if agent == null: continue
		recon_reinforcements.append(agent); enemies.append(agent)
	for agent in enemies:
		agent.wait = 0; agent.flee = 0
		_hostile(agent)

func rov_recorded(quality: float) -> void:
	if family != "recon" or flags.get("recorded",false): return
	if quality <= 0.05: radio("o5"); return
	flags["recorded"] = true; radio("o7"); later(4,"recon_alarm"); later(10,"o1")
	jobs.runtime.active()["outcome_shown"] = true; jobs.runtime.outcome.play(jobs.game.game_folder,true)

func docked(_city: int) -> void:
	if family == "eel" and flags.get("miners_aboard",false): finish(true)
	if family == "recon":
		if flags.get("recorded",false): finish(true)
		elif flags.get("attacked",false): finish(false,0,3)

func _event(event: String) -> void:
	match event:
		"spy_warning":
			radio("ae2")
			if flags.get("failed",false): later(6,"spy_failed")
		"spy_failed":
			preload("res://mission_survivors.gd").depart(jobs,ship)
			radio("ae11",true); finish(false,0,2)
		"spy_success": radio("miss1",true); finish(true)
		"cargo_warning":
			if not is_instance_valid(cargo) or cargo.dead: return
			if cargo.global_position.distance_to(jobs.game.pilot.global_position) < 8:
				flags["cargo_warning"] = true; radio("ae13"); later(20,"cargo_attack")
			else: later(1.2,"cargo_warning")
		"cargo_attack":
			if is_instance_valid(cargo) and not cargo.dead and cargo.global_position.distance_to(jobs.game.pilot.global_position) < 8: radio("ae14"); _spy_guards(false)
			else: later(1.2,"cargo_attack")
		"escort_wave": _escort_wave()
		"escort_boarding":
			if transfer > 0: radio("aa7")
		"escort_dead": radio("aa4",true); finish(false,0,2)
		"escort_escape": radio("aa5",true); finish(false,0,2)
		"huge_eel": _huge_eel()
		"eel_failed": radio("c8",true); finish(false,0,2)
		"recon_alarm": _recon_alarm()
		_: radio(event)
