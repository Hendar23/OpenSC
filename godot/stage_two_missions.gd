extends Node3D
## SC.EXE 004857d0 (Bacau), 0045d0a0 (prisoners), 00490640 (Bohine covert).
const Document = preload("res://map_document.gd")
const Vessel = preload("res://mission_vessel.gd")
const Mine = preload("res://floating_mine.gd")
var runtime: Node
var game: Node
var id := ""
var phase := ""
var age := 0.0
var clock := 0.0
var actors: Array[Node] = []
var vessels: Array[Node3D] = []
var escorts: Array[Node3D] = []
var target: Node3D
var vents: Array[Node3D] = []
var base_poses: Array[Transform3D] = []
var door_poses: Array[Transform3D] = []
var base_defences: Array[Dictionary] = []
var warned := false
var convinced := false
var warning := 0
var delivered_city := 0
var passengers := false
var transfer := 0.0
var tapped := false
var dialogue := 0
var interception_instruction := false
var interception_cancelled := false
var armour_clock := 0.0
var base_guidance := false
var base_instruction_clock := -1.0
var reinforcements := false
var reinforcement_radio_clock := -1.0
var missile_template: Node3D
var bubble_trail: Node3D
var hitbox: CollisionObject3D
var fishing: RefCounted
var genocide: RefCounted
var remaining: RefCounted
var terrorists: RefCounted
var stage_three_remaining: RefCounted
var stage_three: RefCounted
var volcano: StaticBody3D
var defection: RefCounted

func _exit_tree() -> void:
	if defection != null: defection.clear(); defection = null
	if is_instance_valid(volcano): volcano.clear(); volcano = null
	if stage_three_remaining != null: stage_three_remaining.clear(); stage_three_remaining = null
	if stage_three != null: stage_three.clear(); stage_three = null
	if terrorists != null: terrorists.clear(); terrorists = null
	if genocide != null: genocide.clear(); genocide = null
	if fishing != null: fishing.clear(); fishing = null
	if remaining != null: remaining.clear(); remaining = null

func start(mission_id: String) -> void:
	clear(); id = mission_id; age = 0; clock = 0; transfer = 0; warning = 0; delivered_city = 0
	passengers = false; tapped = false; warned = false; convinced = false; dialogue = 0; interception_instruction = false; interception_cancelled = false
	base_guidance = false; base_instruction_clock = -1.0; reinforcements = false; armour_clock = 0
	reinforcement_radio_clock = -1.0
	if id in ["miners","miners2","bomb","aliens","aliens2"]:
		stage_three_remaining = preload("res://stage_three_remaining.gd").new(); stage_three_remaining.jobs = self; stage_three_remaining.start()
	elif id in ["defect","defect2"]:
		defection = preload("res://covert_defection.gd").new(); defection.jobs = self; defection.start()
	elif id in ["fumehole","fumehole2"]:
		volcano = preload("res://volcanic_disaster.gd").new(); game.world_root.add_child(volcano); actors.append(volcano); volcano.setup(self)
	elif id in ["disperse","rovrtn"]:
		stage_three = preload("res://stage_three_missions.gd").new(); stage_three.jobs = self; stage_three.start()
	elif id == "minefield":
		terrorists = preload("res://thwart_terrorists.gd").new(); terrorists.jobs = self; terrorists.start()
	elif id in runtime.Rules.CORE.values():
		genocide = preload("res://genocide_weapon.gd").new(); genocide.jobs = self; genocide.start()
	elif id == "stranded": _start_stranded()
	elif id in ["breakout","breakout2"]: _start_breakout()
	elif id in ["fishing","bigherd"]:
		fishing = preload("res://fishing_missions.gd").new(); fishing.jobs = self; fishing.start()
	elif id in ["spytech","spytech2","escort","escort2","tagtech","eel","recontech","recontech2"]:
		remaining = preload("res://stage_two_remaining.gd").new(); remaining.jobs = self; remaining.start()
	else: _start_covert()

func clear(reset_rover: bool = false) -> void:
	if defection != null: defection.clear(); defection = null
	if is_instance_valid(volcano): volcano.clear(); volcano = null
	if stage_three_remaining != null: stage_three_remaining.clear(); stage_three_remaining = null
	if stage_three != null: stage_three.clear(); stage_three = null
	if terrorists != null: terrorists.clear(); terrorists = null
	if genocide != null: genocide.clear(); genocide = null
	if fishing != null: fishing.clear(); fishing = null
	if remaining != null: remaining.clear(); remaining = null
	id = ""; phase = ""
	if game == null: return
	if game.equipment != null and game.equipment.support_tools != null: game.equipment.support_tools.reset(reset_rover)
	for agent in vessels:
		if not is_instance_valid(agent): continue
		agent.running = false; agent.set_physics_process(false); agent.get_parent().hide()
		game.submarine_traffic.traders.erase(agent)
		game.cockpit_hud.map_data.actor_markers.erase(agent.body)
		if is_instance_valid(agent.smoke): agent.smoke.free(); agent.smoke = null
		if agent.body == hitbox: hitbox = null
	for node in actors:
		if is_instance_valid(node): game.cockpit_hud.map_data.actor_markers.erase(node)
		if is_instance_valid(node): node.queue_free()
	actors.clear(); vessels.clear(); escorts.clear(); vents.clear(); base_poses.clear(); door_poses.clear(); base_defences.clear()
	target = null; missile_template = null; hitbox = null

func radio(code: String, terminal: bool = false) -> void:
	if id.is_empty(): return
	var row: Dictionary = game.gameplay_catalogue.tables.get("radio_messages",{}).get("records",{}).get(code,{})
	runtime._radio(code,str(row.get("portrait","ship")),terminal)

func _rows(mission_id: int) -> Array:
	return game.gameplay_catalogue.tables.get("database.objects",{}).get("records",{}).values().filter(func(row: Dictionary) -> bool: return int(row.get("MissionID",0)) == mission_id)

func _pose(row: Dictionary) -> Transform3D:
	return preload("res://scenery_loader.gd").placement(row,game.world_root.get_meta("database_offset",Vector3.ZERO))

func _boat(model_id: String, pose: Transform3D, faction: int, health: float, speed: float = 2.0, controller: Script = null) -> Node3D:
	var model := Document.load_model(model_id,game.game_folder)
	if model == null: return null
	game.world_root.add_child(model); model.global_transform = pose; actors.append(model)
	model.set_meta("editor_model",model_id); model.set_meta("mission_owner",id)
	preload("res://entity_identity.gd").assign_id(model,"mission/" + id + "/vessel/" + str(vessels.size()))
	var agent: Node3D = Vessel.install_mission(model,{"npc_faction":faction,"npc_health":health,"npc_speed":speed,"npc_sustain":0.1 if model_id == "FREIGHT" and id == "minefield" else 0.3},controller)
	agent.mission_owner = id
	game.submarine_traffic.register_vessel(agent,game.world_root,game.game_folder)
	agent.report_player_attack = false; vessels.append(agent)
	game.natural_light.attach(model); game.water_visuals.attach(model)
	return agent

func _city(id_value: int) -> Vector3:
	return game.submarine_traffic.port_by_id(id_value).get("entry",Vector3.ZERO)

func _place_vessel_clear(agent: Node3D, separate_vessels: bool = false) -> void:
	# Source markers may overlap our larger hull/navigation footprint. Find
	# nearby water before activating a ship, including base reinforcements.
	var model := agent.get_parent() as Node3D
	var origin := model.global_position
	var shape: CollisionShape3D = agent.body.get_child(0)
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = shape.shape; query.collision_mask = 1
	var occupied: Array[AABB] = []
	if separate_vessels:
		# New bodies may not have reached the physics broadphase yet. Check
		# existing hull bounds too, so a wave cannot start interpenetrating.
		for other in game.submarine_traffic.traders:
			if other != agent and not other.dead and other.running and other.stage == "travel":
				occupied.append(other.get_parent().global_transform*other.bounds.grow(0.25))
	if separate_vessels:
		for lift in [0.0,0.5,1.0,1.5,3.0,-0.5,-1.0,-2.0,5.0]:
			for radius in [0.0,2.0,4.0,6.0]:
				for direction in (1 if radius == 0 else 8):
					var angle := float(direction)*TAU/8.0
					var point := origin+Vector3(cos(angle)*radius,lift,sin(angle)*radius)
					point.y = minf(point.y,game.pilot.surface_height-game.submarine_traffic.CLEARANCE-0.05)
					var hull: AABB = Transform3D(model.global_basis,point)*agent.bounds.grow(0.25)
					if occupied.any(func(other: AABB) -> bool: return hull.intersects(other)): continue
					if not game.submarine_traffic.segment_clear(point,point): continue
					query.transform = Transform3D(model.global_basis,point)*shape.transform
					if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
					model.global_position = point; agent.home = model.global_transform; model.reset_physics_interpolation(); return
	for radius in [0.0,2.0,4.0,6.0]:
		for direction in (1 if radius == 0 else 8):
			var angle := float(direction)*TAU/8.0
			for lift in [0.0,0.25,0.5,0.75,1.0,1.5,3.0,5.0,-0.5,-1.0,-2.0]:
				var point := origin+Vector3(cos(angle)*radius,lift,sin(angle)*radius)
				point.y = minf(point.y,game.pilot.surface_height-game.submarine_traffic.CLEARANCE-0.05)
				if not game.submarine_traffic.segment_clear(point,point): continue
				query.transform = Transform3D(model.global_basis,point)*shape.transform
				if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
				model.global_position = point; agent.home = model.global_transform; model.reset_physics_interpolation(); return

func _start_stranded() -> void:
	phase = "tow"
	for row in _rows(24):
		var pose := _pose(row)
		match int(row.get("ObjectID",0)):
			1:
				var visual := Document.load_model("TECHSHUT",game.game_folder)
				if visual == null: continue
				target = preload("res://mission_cargo.gd").new(); game.world_root.add_child(target)
				target.name = "BacauShuttle"; target.global_transform = pose; target.add_child(visual); actors.append(target)
				target.set_meta("mission_owner",id); target.surface_height = game.pilot.surface_height
				preload("res://entity_identity.gd").assign_id(target,"mission/stranded/bacau")
				var boxes: Array[AABB] = []; preload("res://docking_controller.gd")._bounds(visual,Transform3D.IDENTITY,boxes)
				var box := boxes[0] if not boxes.is_empty() else AABB(Vector3.ONE * -0.3,Vector3.ONE * 0.6)
				for other in boxes: box = box.merge(other)
				target.set_meta("mission_target_center",box.get_center())
				var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = box.size; collision.shape = shape; collision.position = box.get_center(); target.add_child(collision)
				var ground: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pose.origin + Vector3.UP * 3,pose.origin + Vector3.DOWN * 8,1,[target.get_rid()]))
				if not ground.is_empty(): target.global_position.y = maxf(target.global_position.y,ground.position.y - box.position.y + 0.03)
				# A centre ray alone misses a sloping floor under the bow/stern.
				# Resolve the complete hull before its first visible physics frame.
				var clearance := PhysicsShapeQueryParameters3D.new(); clearance.shape = shape; clearance.collision_mask = 1; clearance.margin = 0.02
				clearance.exclude = [target.get_rid()]
				for attempt in range(120):
					clearance.transform = target.global_transform * collision.transform
					if game.get_world_3d().direct_space_state.intersect_shape(clearance,1).is_empty(): break
					target.global_position.y += 0.05
				game.natural_light.attach(visual); game.water_visuals.attach(visual)
				target.setup_damage_smoke(visual,game.game_folder)
				target.destroyed.connect(_bacau_destroyed)
			2:
				var agent := _boat("TECHNEW",pose,2,15)
				if agent != null: escorts.append(agent)
			# ObjectID 3 is a surveillance craft left in the source database.
			# Retail gameplay checked by the user contains only the two guards.
	for index in escorts.size():
		# SC.EXE 004f01a8: the rescue guards wait above and behind the shuttle.
		# A lower approximate formation can put hidden guards into the volcano,
		# preventing ActorActivity from reactivating them when the player arrives.
		escorts[index].follow = target
		escorts[index].formation = Vector3(1.5,3.3,-2) if index == 0 else Vector3(-1.5,2.7,-2)

func _start_breakout() -> void:
	phase = "convoy"
	var start := _city(1); start.y = game.pilot.surface_height - 3
	target = _boat("PRISON",Transform3D(Basis.IDENTITY,start),1,40,1.2)
	if target == null: return
	target.combat_enabled = false
	for body in game.world_root.find_children("*","StaticBody3D",true,false):
		if body is Mine: target.route_mines.append(body)
	target.player_attacked.connect(_prison_attacked)
	target.destroyed.connect(func(_entity: String,_attacker: String) -> void:
		if not passengers: radio("y4",true); _resolve(false,0,2))
	# Retail waits until the player comes within 12 units before departure.
	for index in range(4):
		var offset: Vector3 = [Vector3(0,0,4),Vector3(-4,0,0),Vector3(4,0,0),Vector3(0,0,-4)][index]
		var agent := _boat("TRAD2",Transform3D(Basis.IDENTITY,start + offset),1,10)
		if agent != null:
			agent.follow = target; agent.formation = offset; escorts.append(agent)
			agent.player_attacked.connect(_prison_attacked)

func _prison_attacked() -> void:
	if id not in ["breakout","breakout2"] or phase == "finished": return
	if not warned: warned = true; radio("y1")
	_engage_prison_guards()

func _engage_prison_guards(all_guards: bool = false) -> void:
	# 0045cf90(1) sends half the surviving escorts; pod attachment uses (0)
	# to send all four. The prison transport itself continues toward Aquatraz.
	if id not in ["breakout","breakout2"] or phase == "finished": return
	var alive: Array = escorts.filter(func(agent: Node3D) -> bool: return is_instance_valid(agent) and not agent.dead)
	var count := alive.size() if all_guards else maxi(1,alive.size()/2)
	for index in mini(count,alive.size()): alive[index].engage_player = true

func _start_covert() -> void:
	phase = "tag"
	var points: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO]
	base_poses.resize(3); door_poses.resize(3)
	for row in _rows(32):
		var pose := _pose(row); var index := clampi(int(row.get("param1",0)),0,2)
		match int(row.get("ObjectID",0)):
			1: points[mini(index,1)] = pose.origin
			2: base_poses[index] = pose
			3: door_poses[index] = pose
	target = _boat("TECHSHUT",Transform3D(Basis.IDENTITY,points[0]),2,10,1.5)
	if target != null:
		target.loop_route = true; target.waypoints = PackedVector3Array([points[1],points[0]])
		target.destroyed.connect(func(_entity: String,_attacker: String) -> void:
			interception_cancelled = true
			# Original case 10 fails only before the base exists (counter -1).
			if phase in ["tag","listen"] and vents.is_empty(): radio("miss2",true); _resolve(false,0,2))
	clock = 4.0

func _physics_process(delta: float) -> void:
	if id.is_empty() or phase == "finished" or runtime.active().is_empty() or not game.pilot.active: return
	age += delta; clock -= delta; armour_clock = maxf(0,armour_clock - delta)
	if defection != null: defection.step(delta)
	elif is_instance_valid(volcano): volcano.step(delta)
	elif stage_three_remaining != null: stage_three_remaining.step(delta)
	elif stage_three != null: stage_three.step(delta)
	elif terrorists != null: terrorists.step(delta)
	elif genocide != null: genocide.step(delta)
	elif id == "stranded": _step_stranded()
	elif id in ["breakout","breakout2"]: _step_breakout(delta)
	elif fishing != null: fishing.step(delta)
	elif remaining != null: remaining.step(delta)
	else: _step_covert(delta)

func _step_stranded() -> void:
	if not is_instance_valid(target) or target.dead: return
	if delivered_city == 0:
		var times := [12.0,92.0,172.0,252.0,332.0,356.0]
		if warning < times.size() and age >= times[warning]:
			radio(["x3","x23","x4","x18","x24","x25"][warning]); warning += 1
		if age >= 359.6: target.take_weapon_damage(1000); return
		if not convinced and target.global_position.distance_to(game.pilot.global_position) < 9.5:
			convinced = true; radio("x11")
		# Taking the shuttle toward a Bohine city while the Procha team is alive
		# reveals the deception and eventually provokes the team.
		var towing: Node = game.equipment.magnet
		var near_bohine := target.global_position.distance_to(_city(1)) < 20 or target.global_position.distance_to(_city(3)) < 20
		if towing.target == target and not warned and near_bohine:
			warned = true; radio("x15")
			for agent in escorts: agent.engage_player = true

func _step_breakout(delta: float) -> void:
	if not is_instance_valid(target) or target.dead: return
	var distance: float = target.global_position.distance_to(game.pilot.global_position)
	if phase == "convoy" and target.waypoints.is_empty() and distance < 12:
		var goal := _prison_route_goal()
		if goal.is_finite():
			target.arrival_reported = false
			# The hatch centre sits inside Aquatraz's navigation exclusion. Arrival
			# is at its surrounding water, not an impossible civilian hatch route.
			target.waypoints = PackedVector3Array([goal])
			if not target.arrived.is_connected(_prison_arrived): target.arrived.connect(_prison_arrived)
	if not passengers and distance < 8 and warning < 3 and clock <= 0 and escorts.any(func(agent: Node3D) -> bool: return not agent.dead):
		radio(["y5","y6","y7"][warning]); warning += 1; clock = 6
		if warning == 3:
			_engage_prison_guards()
	var attached: Node3D = game.equipment.support_tools.pod_target
	if not passengers and attached == target.body:
		if transfer == 0:
			radio("y2")
			_engage_prison_guards(true)
		transfer += delta
		if transfer >= 16:
			passengers = true; phase = "return"; radio("y8")
			game.equipment.support_tools.passengers = true
			# 0045d0a0 calls the success animation at transfer completion. The
			# city return still selects the response/score and pays the reward.
			runtime.active()["outcome_shown"] = true
			runtime.outcome.play(game.game_folder,true)
	elif not passengers and transfer > 0:
		transfer = 0; radio("y3")

func _prison_route_goal() -> Vector3:
	var traffic: Node = game.submarine_traffic
	if not traffic.navigation_ready or traffic.graph.get_point_count() == 0: return Vector3.INF
	var destination := _city(5)
	var candidates: Array = []
	for point_id in traffic.graph.get_point_ids():
		var point: Vector3 = traffic.graph.get_point_position(point_id)
		var distance := point.distance_squared_to(destination)
		if distance < 64.0: candidates.append([distance,point])
	candidates.sort_custom(func(a: Array,b: Array) -> bool: return a[0] < b[0])
	for candidate in candidates:
		if not traffic.route(target.global_position,candidate[1]).is_empty(): return candidate[1]
	return Vector3.INF

func _prison_arrived() -> void:
	if id.is_empty() or phase == "finished": return
	if not passengers: radio("y9",true); _resolve(false,0,2)

func _step_covert(delta: float) -> void:
	if reinforcement_radio_clock >= 0:
		reinforcement_radio_clock -= delta
		if reinforcement_radio_clock <= 0:
			reinforcement_radio_clock = -1; radio("af6")
	if phase in ["tag","listen","base"] and not reinforcements and is_instance_valid(target) and not target.dead and clock <= 0:
		clock = 3.6
		var offset: Vector3 = game.pilot.global_position - target.global_position
		var distance := offset.length()
		var forward: Vector3 = target.get_parent().global_basis.z.normalized()
		if distance < 8 and (2.0 - forward.dot(offset.normalized())) * distance < 6:
			var query := PhysicsRayQueryParameters3D.create(target.global_position,game.pilot.global_position,1)
			if game.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				if warned:
					if tapped and not vents.is_empty():
						radio("af5"); _reinforce_base()
					else: radio("af14",true); _resolve(false,0,2); return
				# Retail latches the first sighting, then reacts if spotted again.
				warned = true
	if tapped and phase in ["listen","base"]:
		transfer += delta
		while not interception_cancelled and dialogue < 5 and transfer >= float(dialogue + 1) * 8.0:
			radio(["af7","af8","af9","af10","af11"][dialogue]); dialogue += 1
			if dialogue == 4: _spawn_base()
		# 00490640 schedules AF12 400 ticks after line four (tick 800).
		if not interception_instruction and transfer >= 48.0:
			interception_instruction = true; radio("af12"); phase = "base"
	if not vents.is_empty():
		if base_instruction_clock >= 0.0:
			base_instruction_clock -= delta
			if base_instruction_clock <= 0.0:
				base_instruction_clock = -1.0
				var equipped: Dictionary = preload("res://equipment_shop.gd").installed(game.equipment,game.weapons)
				radio("af17" if "depthl" in equipped.values() and int(game.player_progress.hold.get("depth",0)) > 0 else "af16")
		if not base_guidance and game.pilot.global_position.distance_to(base_poses[0].origin) < 9:
			base_guidance = true; radio("af15")
			base_instruction_clock = 6.0 # Original case 0xb follows 0xc by 150 ticks.
		for vent in vents:
			if not vent.dead: vent.open = fposmod(transfer,9.6) >= 4.8
		_step_base_defences(delta)
		if vents.all(func(vent: Node3D) -> bool: return vent.dead):
			_destroy_base(); radio("af3",true); _resolve(true,1,1)

func _destroy_base() -> void:
	var models: Array[Node3D] = []
	var smoke: Array[Node] = []
	for defence in base_defences:
		if is_instance_valid(defence.model): models.append(defence.model); actors.erase(defence.model)
		for plume in defence.smoke:
			if is_instance_valid(plume): smoke.append(plume); actors.erase(plume)
	if models.is_empty(): return
	var effect := preload("res://base_destruction.gd").new(); game.world_root.add_child(effect)
	effect.setup(models,smoke,game.submarine_traffic)

func _reinforce_base() -> void:
	reinforcements = true; interception_cancelled = true; reinforcement_radio_clock = 7.0
	for index in range(4):
		var angle := float(index) * TAU / 4.0
		var position := base_poses[0].origin + Vector3(cos(angle) * 5.0,2.0,sin(angle) * 5.0)
		var agent := _boat("TECHNEW" if index % 2 == 0 else "TECH2SUB",Transform3D(Basis.IDENTITY,position),2,15)
		if agent != null:
			_place_vessel_clear(agent)
			agent.engage_player = true; agent.pursue_offscreen = true; agent.tuning.npc_detection = 1000.0

func attach_listening_device(body: Node3D) -> bool:
	if remaining != null: return remaining.attach_listening(body)
	if id not in ["spytrad","spytrad2"] or phase != "tag" or not is_instance_valid(target) or target.dead or body != target.body: return false
	tapped = true; phase = "listen"; transfer = 0; dialogue = 0; radio("af1")
	return true

func can_attach_pod(body: Node3D) -> bool:
	if defection != null: return defection.can_attach_pod(body)
	if stage_three != null: return stage_three.can_attach_pod(body)
	if terrorists != null: return terrorists.can_attach_pod(body)
	if remaining != null: return remaining.can_attach_pod(body)
	return id in ["breakout","breakout2"] and not passengers and is_instance_valid(target) and not target.dead and body == target.body

func delivery(body: Node3D, city: int) -> bool:
	if stage_three_remaining != null: return stage_three_remaining.delivery(body,city)
	if genocide != null: return genocide.delivery(body,city)
	if remaining != null: return remaining.delivery(body,city)
	if id != "stranded" or body != target or city not in [1,2,3,4] or delivered_city != 0: return false
	delivered_city = city; target.delivered = true; target.set_meta("delivery_city",city)
	target.set_meta("metal_tow_target",false); game.equipment.magnet.set_enabled(false)
	runtime.active()["resolved_city"] = city
	var guards_dead := escorts.all(func(agent: Node3D) -> bool: return agent.dead)
	if city in [1,3]:
		radio("x1"); _resolve(true,1,1)
	elif guards_dead:
		radio("x21"); _resolve(false,0.8,5)
	else:
		radio("x12"); _resolve(true,0.9 if convinced else 0.8,3 if convinced else 4)
	return true

func completes_on_docking(city: int) -> bool:
	if stage_three != null: return id == "rovrtn" and stage_three.rescued and not stage_three.failed and city in [1,2,3,4]
	if terrorists != null: return terrorists.won and not terrorists.lost
	if remaining != null:
		return (remaining.family == "eel" and remaining.flags.get("miners_aboard",false)) or (remaining.family == "recon" and remaining.flags.get("recorded",false))
	return id in ["breakout","breakout2"] and passengers and city in [1,2,3,4]

func docked(city: int) -> void:
	if stage_three != null: stage_three.docked(city); return
	if terrorists != null: terrorists.docked(city); return
	if remaining != null: remaining.docked(city); return
	if id in ["breakout","breakout2"] and passengers and city in [1,2,3,4]:
		runtime.active()["resolved_city"] = city
		# Retail keeps the rescue success flag for the alternate Bohine return,
		# but selects response 3 and a reduced bulletin score (0045d0a0).
		_resolve(true,1.0 if city in [2,4] else 0.5,1 if city in [2,4] else 3)

func _resolve(success: bool, score: float, response: int) -> void:
	if phase == "finished" or id.is_empty(): return
	phase = "finished"
	runtime.finish(success,score,response)

func _bacau_destroyed() -> void:
	if id != "stranded": return
	var wreck := preload("res://submarine_death.gd").new(); game.world_root.add_child(wreck); wreck.global_position = target.global_position
	wreck.setup_machine(target,target.appearance,game.submarine_traffic.bubble_texture,[],target.linear_velocity)
	_burst(target.global_position,1.0); radio("x5",true); _resolve(false,0,2)

func _spawn_base() -> void:
	if not vents.is_empty(): return
	for index in range(3):
		var model := Document.load_model("TECHPOST",game.game_folder)
		if model == null: continue
		game.world_root.add_child(model); model.global_transform = base_poses[index]; actors.append(model)
		model.set_meta("mission_owner",id)
		preload("res://scenery_loader.gd")._add_prop_collision(model)
		game.natural_light.attach(model); game.water_visuals.attach(model)
		var vent := preload("res://mission_vent.gd").new(); game.world_root.add_child(vent)
		vent.global_position = door_poses[index].origin; vent.collision_layer = 1 | 4; vent.collision_mask = 0; actors.append(vent); vents.append(vent)
		vent.shell = model.get_node_or_null("SceneryCollision")
		var defence := {"model":model,"vent":vent,"clock":float(randi_range(0,255))/25.0,"smoke":[]}
		base_defences.append(defence)
		vent.set_meta("mission_owner",id)
		var shape := CollisionShape3D.new(); var sphere := SphereShape3D.new(); sphere.radius = 0.65; shape.shape = sphere; vent.add_child(shape)
		var door := Document.load_model("TESTDOOR",game.game_folder,true)
		if door != null:
			vent.add_child(door); door.global_transform = door_poses[index]; vent.door = door; vent.shut_pose = door.transform
			game.natural_light.attach(door); game.water_visuals.attach(door)
		vent.armour_hit.connect(func() -> void:
			if armour_clock <= 0: armour_clock = 6; radio("af2"))
		vent.disabled.connect(_disable_base.bind(defence))
	missile_template = preload("res://clump_loader.gd").load_clump(game.game_folder.path_join("CLUMPS/TMISSILE.DFF"))
	if missile_template != null: add_child(missile_template); missile_template.hide(); actors.append(missile_template)
	bubble_trail = game.submarine_traffic.bubbles; hitbox = null

func _disable_base(defence: Dictionary) -> void:
	if not defence.smoke.is_empty(): return
	# Covert mission 00490640 creates SMOKE at the building (+0.9 Y)
	# and at its separate vent when the internal target is destroyed.
	var building: Node3D = defence.model
	var vent: Node3D = defence.vent
	for point in [building.global_position + Vector3.UP * 0.9,vent.global_position]:
		var smoke := preload("res://smoke_emitter.gd").new()
		game.world_root.add_child(smoke); smoke.global_position = point
		smoke.configure(game.game_folder,{})
		actors.append(smoke); defence.smoke.append(smoke)
	_burst(vent.global_position,1.2); radio("af4")

func _step_base_defences(delta: float) -> void:
	for defence in base_defences:
		if not is_instance_valid(defence.model) or not is_instance_valid(defence.vent) or defence.vent.dead: continue
		defence.clock -= delta
		if float(defence.clock) >= 0.0: continue
		# TECHOUTPOST 00431dc0: independent 64..127-tick reloads.
		defence.clock = float(randi_range(64,127))/25.0
		_fire_base(defence)

func _fire_base(defence: Dictionary) -> Node3D:
	if missile_template == null or defence.vent.dead or game.pilot.dead: return null
	var building: Node3D = defence.model
	var aim: Vector3 = preload("res://gun_turret.gd").intercept(game.pilot.global_position-building.global_position,game.pilot.velocity)
	# Original firing matrix is at the building origin + one unit along aim;
	# the remote vent/door placement is not a weapon mount.
	if aim.length() < 0.01 or aim.length() >= 11.0: return null
	var direction := aim.normalized()
	var point := building.global_position + direction
	var exclusions: Array[RID] = []
	var shell: CollisionObject3D = defence.vent.shell
	if is_instance_valid(shell): exclusions.append(shell.get_rid())
	var query := PhysicsRayQueryParameters3D.create(point,game.pilot.global_position,1,exclusions)
	if not game.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return null
	var missile := preload("res://turret_missile.gd").new(); game.world_root.add_child(missile); actors.append(missile)
	missile.source_exclusions = exclusions
	missile.setup(self,missile_template,point,direction,game.pilot,false)
	missile.get_child(0).show()
	return missile

func burst(point: Vector3, size: float) -> void: _burst(point,size)

func _burst(point: Vector3, size: float) -> void:
	var effect := preload("res://mine_explosion.gd").new(); game.world_root.add_child(effect); effect.global_position = point
	effect.setup(game.submarine_traffic.explosion_frames,size,game.submarine_traffic.explosion_sound)

func _detach_walker_head() -> void:
	if genocide != null: genocide.detach_head()
