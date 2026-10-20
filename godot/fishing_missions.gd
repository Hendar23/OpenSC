extends RefCounted
## Retail fishing 00452050, bigherd 00430910, herder 0047c680/0047c4a0.
const QUOTA := 12
var jobs: Node3D
var herders: Array[Dictionary] = []
var enemies: Array[Node3D] = []
var fish: Array[Node3D] = []
var pulling: Array[Dictionary] = []
var fish_template: Node3D
var greeted := false
var first_wave := false
var second_wave := false
var delivered := 0
var failed_clock := -1.0
var scheduled: Array[Dictionary] = []
var field := Vector3.ZERO
var school := Vector3.ZERO
var random := RandomNumberGenerator.new()
var capture_clock := 0.0

func start() -> void:
	random.seed = hash(jobs.id)
	jobs.phase = "fishing"
	for row in jobs._rows(21 if jobs.id == "fishing" else 22):
		var pose: Transform3D = jobs._pose(row)
		match int(row.get("ObjectID",0)):
			1:
				var agent: Node3D = jobs._boat("TECHHERD" if jobs.id == "fishing" else "TRADHERD",pose,2 if jobs.id == "fishing" else 1,30,1.2)
				if agent == null: continue
				agent.get_parent().global_basis = preload("res://docking_controller.gd").upright_basis(agent.get_parent().global_basis)
				jobs._place_vessel_clear(agent)
				agent.combat_enabled = false; agent.level_when_idle = true
				agent.travel_height = agent.global_position.y
				var state := {"agent":agent,"count":0,"returning":false,"resolved":false,"under_attack":false,"player_warning":false,"low_health":false,"cone":_cone(agent)}
				herders.append(state)
				agent.arrived.connect(_arrived.bind(state))
				agent.destroyed.connect(func(_id: String,_attacker: String) -> void: _lost(state))
				agent.player_attacked.connect(_player_hit.bind(state))
				agent.hull_damaged.connect(_herder_hit.bind(state))
			2:
				field = pose.origin
			3: school = pose.origin
	if herders.is_empty(): return
	jobs.target = herders[0].agent
	if jobs.id == "fishing":
		field.y = herders[0].agent.travel_height
		herders[0].agent.waypoints = PackedVector3Array([field])
	else:
		school = herders[1].agent.global_position + Vector3.DOWN*3.0
	fish_template = jobs.Document.load_model("SILVER",jobs.game.game_folder,true)
	_spawn_school(20 if jobs.id == "fishing" else 50,school,10.4 if jobs.id == "fishing" else 0.8)

func clear() -> void:
	for entry in pulling:
		if is_instance_valid(entry.fish): entry.fish.herding_target = null; entry.fish.mission_owner = entry.owner
	pulling.clear()
	if is_instance_valid(fish_template): fish_template.free()
	fish_template = null
	herders.clear(); enemies.clear(); fish.clear(); scheduled.clear()

func target_body() -> CollisionObject3D:
	for state in herders:
		if not state.resolved and not state.agent.dead and not state.returning: return state.agent.body
	for state in herders:
		if not state.resolved and not state.agent.dead: return state.agent.body
	return null

func _cone(agent: Node3D) -> MeshInstance3D:
	var cone := MeshInstance3D.new(); cone.name = "FishingStunField"
	cone.set_meta("exclude_from_debris",true)
	var mesh := CylinderMesh.new(); mesh.top_radius = 0.05; mesh.bottom_radius = 1.0; mesh.height = 1.5; mesh.radial_segments = 24
	cone.mesh = mesh; cone.position.y = -0.9
	var material := StandardMaterial3D.new(); material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = Color(0.15,0.8,1,0.08)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED; cone.material_override = material
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	agent.get_parent().add_child(cone); cone.visible = jobs.id == "fishing"
	return cone

func _spawn_school(count: int, center: Vector3, spread: float) -> void:
	if fish_template == null: return
	var bounds: AABB = jobs.game.world_root.get_meta("bounds")
	for index in count:
		var visual := fish_template.duplicate() as Node3D
		var point := center + Vector3(random.randf_range(-spread,spread),random.randf_range(-0.5,0.5),random.randf_range(-spread,spread))
		if jobs.id == "fishing" and index >= 16: point.y += 3
		var floor_query := PhysicsRayQueryParameters3D.create(Vector3(point.x,jobs.game.pilot.surface_height-0.1,point.z),Vector3(point.x,bounds.position.y-1,point.z),1)
		floor_query.hit_back_faces = true
		var floor_hit := jobs.get_world_3d().direct_space_state.intersect_ray(floor_query)
		if not floor_hit.is_empty(): point.y = maxf(point.y,float(floor_hit.position.y)+0.4)
		point.y = minf(point.y,jobs.game.pilot.surface_height-0.4)
		# The retail spread uses discrete diagonal offsets; a wider independent
		# distribution keeps the shoal from spawning inside itself in Godot.
		var body := preload("res://fish_controller.gd").new()
		body.name = "FishingSilverback"; body.set_meta("species","silver"); body.set_meta("mission_owner",jobs.id)
		body.mission_owner = jobs.id; body.group_behaviour = "shoaling"; body.response = "flee"
		body.setup(visual,point,bounds,jobs.game.pilot.surface_height,0.15,random.randi())
		body.home = center; body.roam_radius = 5; body.swim_speed = 0.8; body.flee_range = 3.5
		body.configure_health(10); body.damage_sustain = 2.5
		body.population = jobs.game.wildlife
		body.death_texture = jobs.game.submarine_traffic.bubble_texture
		jobs.game.world_root.add_child(body); fish.append(body); jobs.actors.append(body)
		jobs.game.natural_light.attach(visual); jobs.game.water_visuals.attach(visual)
	for body in fish:
		if is_instance_valid(body) and not body.dead: body.group_members = fish

func step(delta: float) -> void:
	if failed_clock >= 0:
		failed_clock -= delta
		if failed_clock <= 0: jobs.radio("u11",true); jobs._resolve(false,0,2)
		return
	for entry in scheduled.duplicate():
		entry.remaining -= delta
		if entry.remaining <= 0: scheduled.erase(entry); jobs.radio(entry.code)
	if not greeted and jobs.age >= (2.0 if jobs.id == "fishing" else 10.0) and jobs.game.pilot.global_position.distance_to(herders[0].agent.global_position) < (8.0 if jobs.id == "fishing" else 9.0):
		greeted = true
		if jobs.id == "fishing": _later("u2",20)
		else:
			jobs.radio("v2"); first_wave = true; _wave(3,1); _later("v4",12)
			for state in herders: state.cone.show()
	capture_clock -= delta
	if capture_clock <= 0:
		capture_clock = 0.04
		for state in herders:
			var agent: Node3D = state.agent
			if state.resolved or agent.dead: continue
			if not state.low_health and agent.health.remaining < 15:
				state.low_health = true; jobs.radio("u7" if jobs.id == "fishing" else "v6")
			if state.returning or (jobs.id == "bigherd" and not greeted): continue
			var center: Vector3 = agent.get_parent().to_global(Vector3(0,-1.5,0))
			for body in jobs.get_tree().get_nodes_in_group("attractable_fish"):
				if body.dead or is_instance_valid(body.herding_target) or body.get_world_3d() != jobs.get_world_3d(): continue
				if center.distance_to(body.global_position) > 1.0: continue
				pulling.append({"fish":body,"state":state,"owner":body.mission_owner})
				body.mission_owner = jobs.id; body.herding_target = agent
	for entry in pulling.duplicate():
		var body: Node3D = entry.fish; var state: Dictionary = entry.state
		if not is_instance_valid(body) or body.dead: pulling.erase(entry); continue
		if state.resolved or state.returning or state.agent.dead:
			body.herding_target = null; body.mission_owner = entry.owner; pulling.erase(entry); continue
		var point: Vector3 = state.agent.global_position
		body.global_position = body.global_position.move_toward(point,delta*2.0)
		if body.global_position.distance_to(point) >= 0.9: continue
		pulling.erase(entry); body.dead = true; body.collision_layer = 0; body.hide(); body.set_physics_process(false)
		body.group_members.erase(body)
		if body.population != null:
			for population_state in body.population.random_groups: population_state.members.erase(body)
		body.queue_free(); _caught(state)
		if jobs.id.is_empty(): return
	_retarget()

func _caught(state: Dictionary) -> void:
	if state.resolved or state.returning or state.agent.dead: return
	state.count += 1
	if jobs.id == "fishing" and state.count == 6:
		jobs.radio("u3"); first_wave = true; _wave(2,1); _later("u5",8)
	if state.count < QUOTA: return
	state.returning = true; state.cone.hide()
	var agent: Node3D = state.agent
	agent.travel_height = INF
	agent.path.clear(); agent.waypoint = 0; agent.arrival_reported = false
	agent.dock_destination = 2 if jobs.id == "fishing" else 3
	agent.waypoints = PackedVector3Array([jobs._city(agent.dock_destination)])
	jobs.radio("u4" if jobs.id == "fishing" else "v1")
	if not second_wave and herders.all(func(other: Dictionary) -> bool: return other.returning or other.resolved):
		second_wave = true; _wave(2 if jobs.id == "fishing" else 3,2); _later("u6" if jobs.id == "fishing" else "v5",8 if jobs.id == "fishing" else 12)

func _arrived(state: Dictionary) -> void:
	if state.resolved or not state.returning or state.agent.stage != "berth": return
	state.resolved = true; delivered += 1
	if jobs.id == "fishing": jobs.radio("u9",true); jobs._resolve(true,1,1); return
	if herders.all(func(other: Dictionary) -> bool: return other.resolved): jobs.radio("v10",true); jobs._resolve(true,float(delivered)/3.0,1)
	else: jobs.radio("v11")

func _lost(state: Dictionary) -> void:
	if state.resolved or jobs.id.is_empty(): return
	state.resolved = true; state.cone.hide()
	_spawn_school(int(state.count),state.agent.global_position,0.4)
	jobs.radio("u8" if jobs.id == "fishing" else "v7")
	if jobs.id == "fishing": failed_clock = 6; scheduled.clear(); return
	_retarget()
	if herders.all(func(other: Dictionary) -> bool: return other.resolved):
		var attackers_alive := enemies.any(func(enemy: Node3D) -> bool: return is_instance_valid(enemy) and not enemy.dead)
		jobs.radio(("v13" if attackers_alive else "v12") if delivered > 0 else ("v8" if attackers_alive else "v9"),true)
		jobs._resolve(delivered > 0,float(delivered)/3.0,1 if delivered > 0 else 2)

func _player_hit(state: Dictionary) -> void:
	if state.player_warning or state.resolved: return
	state.player_warning = true
	if jobs.id == "fishing": jobs.radio("u10")

func _herder_hit(attacker: Node3D, state: Dictionary) -> void:
	if state.resolved or state.under_attack or attacker == jobs.game.pilot: return
	state.under_attack = true; jobs.radio("u1" if jobs.id == "fishing" else "v3")

func _later(code: String, seconds: float) -> void:
	scheduled.append({"code":code,"remaining":seconds})

func _wave(count: int, wave: int) -> void:
	for index in count:
		var procha: bool = jobs.id == "bigherd"
		var model := ("TECHNEW" if index%2 == 0 else "TECH2SUB") if procha else ("TRAD2" if wave == 1 else "TRAD-SUB")
		var point: Vector3 = jobs._city(4 if procha else 1) + Vector3((index-1)*2,3,index*2)
		var enemy: Node3D = jobs._boat(model,Transform3D(Basis.IDENTITY,point),2 if procha else 1,15 if procha else 10,2.0)
		if enemy == null: continue
		jobs._place_vessel_clear(enemy)
		enemy.pursue_offscreen = true; enemy.tuning.npc_detection = 1000.0
		enemies.append(enemy)
		if not procha and index == 0: enemy.engage_player = true
	_retarget()

func _retarget() -> void:
	var live: Array = herders.filter(func(state: Dictionary) -> bool: return not state.resolved and not state.agent.dead)
	for index in enemies.size():
		var enemy: Node3D = enemies[index]
		if not is_instance_valid(enemy) or enemy.dead or enemy.engage_player: continue
		var target: Node3D = live[index%live.size()].agent.body if not live.is_empty() else jobs.game.pilot
		if enemy.combat_target != target: enemy.combat_target = target; enemy.victim = null; enemy.path.clear(); enemy.replan = 0
