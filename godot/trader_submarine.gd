extends Node3D
signal attacked(faction: int)
signal destroyed(entity_id: String, attacker_id: String)
var mission_owner := ""
var local_simulation := true
var abstract_clock := 0.0
var damage_attacker: Node3D
const MODELS := ["TRADSHUT","TECHSHUT"]
const DEFAULTS := {"npc_speed":2.0,"npc_wait_min":15.0,"npc_wait_max":40.0,"npc_health":10.0,"npc_sustain":0.3,"npc_respawn":true,"npc_respawn_delay":120.0,"npc_faction":1}
const LIMITS := {"npc_speed":[0.1,8.0],"npc_wait_min":[0.0,300.0],"npc_wait_max":[0.0,300.0],"npc_health":[0.1,10000.0],"npc_sustain":[0.0,100.0],"npc_respawn_delay":[1.0,3600.0],"npc_faction":[1,2]}
const Access = preload("res://dock_access.gd")
var tuning := DEFAULTS.duplicate()
var health = preload("res://npc_health.gd").new()
var body: CharacterBody3D
var bounds := AABB()
var home := Transform3D.IDENTITY
var system: Node
var running := false
var dead := false
var stage := "travel"
var port: Dictionary = {}
var destination := 0
var last_city := 0
var path := PackedVector3Array()
var elapsed := 0.0
var wait := 0.0
var flee := 0.0
var attacker := Vector3.ZERO
var last_obstacle := ""
var blocked := 0.0
var respawn := 0.0
var clock := 0.0
var speed := 0.0
var motion = preload("res://npc_sub_motion.gd").new()
var steering := Vector3.ZERO
var avoidance_clock := 0.0
var avoidance := Vector3.ZERO
var traffic_speed := 1.0
var progress_goal := Vector3.INF
var progress_best := INF
var progress_stalled := 0.0
var journey_count := 0
var transit_start := Vector3.ZERO
var random := RandomNumberGenerator.new()
var dock_audio: Node
var smoke: Node3D
var propeller: Node3D
var propellers: Array[Dictionary] = []
var propeller_rest := Basis.IDENTITY
var propeller_angle := 0.0
var propeller_power := 0.0
var twin_exhaust := false
var report_player_attack := true

static func install(model: Node3D, values: Dictionary, controller: Script = null) -> Node3D:
	var agent := model.get_node_or_null("Trader")
	if agent == null:
		agent = (controller if controller != null else load("res://trader_submarine.gd")).new(); agent.name = "Trader"; model.add_child(agent)
		var boxes: Array[AABB] = []
		preload("res://docking_controller.gd")._bounds(model,Transform3D.IDENTITY,boxes)
		if not boxes.is_empty():
			agent.bounds = boxes[0]
			for box in boxes: agent.bounds = agent.bounds.merge(box)
		var old := model.get_node_or_null("SceneryCollision")
		if old != null: old.free()
		var hull := preload("res://trader_body.gd").new(); hull.name = "SceneryCollision"; model.add_child(hull)
		var shape := CollisionShape3D.new(); var box := BoxShape3D.new()
		box.size = (agent.bounds.size * 0.8).max(Vector3.ONE * 0.1)
		shape.shape = box; shape.position = agent.bounds.get_center(); hull.add_child(shape)
		agent.body = hull; hull.add_to_group("npc_submarines")
	for key in DEFAULTS: agent.tuning[key] = values.get(key,DEFAULTS[key])
	agent.body.collision_layer = 10; agent.body.collision_mask = 1 | 2 | 8
	agent.body.set_meta("damage_sustain",float(agent.tuning.npc_sustain)); agent.body.set_meta("contact_inflict",0.5)
	agent.body.set_meta("faction",int(agent.tuning.npc_faction))
	for rotor in rotor_nodes(model): agent.propellers.append({"node":rotor,"rest":rotor.get_meta("rest_basis",rotor.basis)})
	agent.propeller = agent.propellers[0].node if not agent.propellers.is_empty() else null
	if agent.propeller != null: agent.propeller_rest = agent.propeller.get_meta("rest_basis",agent.propeller.basis)
	var source := str(model.get_meta("asset_id",model.get_meta("asset_source",""))).to_upper()
	agent.twin_exhaust = source.contains("TECHSHUT")
	agent.home = model.global_transform
	preload("res://entity_identity.gd").actor(model,agent,agent.body)
	agent.random.seed = hash(str(model.get_path()))
	return agent

static func rotor_nodes(model: Node3D, model_id: String = "") -> Array[Node3D]:
	var result: Array[Node3D] = []
	var parts: Dictionary = model.get_meta("submarine_parts",{})
	for role in parts:
		if not str(role).ends_with("propeller"): continue
		var rotor := model.get_node_or_null(NodePath(str(parts[role]))) as Node3D
		if rotor != null and not result.has(rotor): result.append(rotor)
	for rotor: Node3D in model.find_children("*Propeller","Node3D",true,false):
		if not result.has(rotor): result.append(rotor)
	if not model.get_meta("modern_model",false):
		if model_id.is_empty(): model_id = str(model.get_meta("editor_model",str(model.get_meta("asset_source","")).get_file().get_basename())).to_upper()
		var count := 2 if model_id in ["TRAD2","PRISON"] else 1 if model_id in ["TRADSHUT","TRAD-SUB"] else 0
		for index in range(1,count+1):
			var rotor := model.get_node_or_null("Frame_0/Frame_"+str(index)) as Node3D
			if rotor != null and not result.has(rotor): result.append(rotor)
	return result

func reset() -> void:
	set_local_simulation(true)
	release_port()
	get_parent().global_transform = home; body.transform = Transform3D.IDENTITY; get_parent().reset_physics_interpolation()
	health.configure(float(tuning.npc_health),float(tuning.npc_sustain))
	propeller_power = 0; propeller_angle = 0
	if is_instance_valid(propeller): propeller.basis = propeller_rest
	for rotor in propellers:
		if is_instance_valid(rotor.node): rotor.node.basis = rotor.rest
	dead = false; stage = "travel"; path.clear(); destination = 0; last_city = 0
	elapsed = 0; wait = random.randf_range(0,3); flee = 0; blocked = 0; respawn = 0; clock = 0; speed = 0; steering = Vector3.ZERO; avoidance = Vector3.ZERO; avoidance_clock = 0; journey_count = 0
	motion.velocity = Vector3.ZERO; motion.bank = 0.0
	progress_goal = Vector3.INF; progress_best = INF; progress_stalled = 0.0
	body.collision_layer = 10; get_parent().show()
	if smoke != null: smoke.set_health(health.remaining * 10)

func release_port() -> void:
	if is_instance_valid(dock_audio): dock_audio.stop()
	if Access.owner(port) == self:
		Access.open(port,0); port.collision.collision_layer = 1; Access.release(port,self)
	port = {}

func _exit_tree() -> void:
	release_port()

func _physics_process(delta: float) -> void:
	if not running or not local_simulation or system == null or not system.navigation_ready: return
	advance(delta)

func set_local_simulation(on: bool) -> void:
	if local_simulation == on: return
	local_simulation = on
	if not on:
		# Complete hidden hatch transitions without animating or reserving a dock.
		var saved_port := port
		release_port(); port = saved_port
		if stage in ["open","descend","close"]:
			last_city = destination; journey_count += 1; stage = "berth"
			if not port.is_empty(): get_parent().global_position = port.inside + Vector3.UP * maxf(0,-bounds.position.y - 0.25)
			wait = random.randf_range(float(tuning.npc_wait_min),float(tuning.npc_wait_max))
		elif stage in ["exit_open","ascend","exit_close"]:
			if not port.is_empty(): get_parent().global_position = port.entry
			stage = "travel"; destination = 0; port = {}; path.clear()
		body.velocity = Vector3.ZERO
	get_parent().visible = on and not dead and stage != "berth"
	get_parent().process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	set_physics_process(on)
	body.collision_layer = 10 if on and not dead and stage == "travel" else 0
	body.collision_mask = (1 | 2 | 8) if on else 0
	for shape in body.get_children():
		if shape is CollisionShape3D: shape.set_deferred("disabled",not on or dead)
	if is_instance_valid(smoke): smoke.set_process(on)
	if on:
		abstract_clock = 0; avoidance_clock = 0; blocked = 0
		get_parent().reset_physics_interpolation()

func advance_abstract(delta: float) -> void:
	if local_simulation or not running or dead or system == null or not system.navigation_ready: return
	abstract_clock += delta
	if abstract_clock < 0.25: return
	var step := abstract_clock; abstract_clock = 0.0
	flee = 0; wait = maxf(0,wait - step)
	if wait > 0: return
	if stage == "berth":
		if not port.is_empty(): get_parent().global_position = port.entry
		stage = "travel"; destination = 0; port = {}; path.clear()
	if path.is_empty() and not prepare_abstract_route(): return
	var remaining := float(tuning.npc_speed) * step
	while remaining > 0 and not path.is_empty():
		var offset := path[0] - global_position
		var distance := offset.length()
		if distance > 0.001:
			var direction := offset / distance
			get_parent().global_position += direction * minf(remaining,distance)
			if absf(direction.y) < 0.98: get_parent().global_basis = Basis.looking_at(-direction,Vector3.UP).scaled_local(home.basis.get_scale())
		remaining -= distance
		if remaining >= 0: path.remove_at(0)
	if path.is_empty() and destination != 0 and not port.is_empty():
		last_city = destination; journey_count += 1; stage = "berth"
		get_parent().global_position = port.inside + Vector3.UP * maxf(0,-bounds.position.y - 0.25)
		wait = random.randf_range(float(tuning.npc_wait_min),float(tuning.npc_wait_max))
	body.transform = Transform3D.IDENTITY

func prepare_abstract_route() -> bool:
	if destination == 0: destination = system.choose_city(self)
	port = system.port_by_id(destination)
	if port.is_empty(): wait = 2; return false
	path = system.abstract_route(global_position,port.entry)
	if path.is_empty(): destination = 0; wait = 2
	return not path.is_empty()

func advance(delta: float) -> void:
	_advance_motion(delta)
	_propulsion(delta)

func _advance_motion(delta: float) -> void:
	if dead:
		# The traffic manager replaces destroyed subs only behind the docked UI.
		return
	if stage != "travel": _dock_step(delta); return
	if wait > 0: wait = maxf(0,wait - delta); _coast(delta); return
	if flee > 0:
		flee = maxf(0,flee - delta)
		if path.is_empty():
			var away := (global_position - attacker).normalized()
			if away.is_zero_approx(): away = get_parent().global_basis.z.normalized()
			path = system.route(global_position,global_position + away * 18)
		if flee == 0: path.clear(); destination = 0
	elif path.is_empty():
		if destination != 0:
			port = system.port_by_id(destination)
			if not port.is_empty() and global_position.distance_to(port.entry) < 0.2:
				if Access.acquire(port,self):
					body.collision_layer = 0; _phase("open"); return
				wait = 0.5; return
			if port.is_empty(): destination = 0
		if destination == 0: destination = system.choose_city(self)
		if destination == 0: wait = 2; return
		port = system.port_by_id(destination)
		path = system.route(global_position,port.entry)
		if path.is_empty(): destination = 0; wait = 2
		return
	while not path.is_empty():
		var reach := 0.15
		var distance := global_position.distance_to(path[0])
		# Capture a passing corner before rounded steering can orbit it. Only
		# shortcut when the next leg is actually clear of terrain/scenery.
		var corner_reach := clampf(speed*0.6,0.2,0.75)
		if path.size() > 1 and distance < corner_reach and system.segment_clear(global_position,path[1]): reach = corner_reach
		if distance >= reach: break
		path.remove_at(0)
	if path.is_empty(): _coast(delta); return
	if flee <= 0 and not port.is_empty() and global_position.distance_to(port.entry) < 4:
		if Access.owner(port) != null and Access.owner(port) != self:
			wait = 0.5; return
		if global_position.distance_to(port.entry) < 3: Access.acquire(port,self)
	var offset := path[0] - global_position
	if progress_goal != path[0]:
		progress_goal = path[0]; progress_best = offset.length(); progress_stalled = 0.0
	elif offset.length() < progress_best - 0.05:
		progress_best = offset.length(); progress_stalled = 0.0
	else: progress_stalled += delta
	if progress_stalled > 3.0:
		# Brake and request a fresh route instead of endlessly circling a close
		# waypoint or repeatedly adding detours around an occupied point.
		path.clear(); steering = Vector3.ZERO; progress_goal = Vector3.INF
		wait = 0.4; _coast(delta); return
	var direction := offset.normalized()
	avoidance_clock -= delta
	if avoidance_clock <= 0:
		avoidance_clock = 0.12
		var decision: Dictionary = system.avoidance(self,direction)
		avoidance = decision.direction; traffic_speed = decision.speed
	var desired := (direction + avoidance * clampf(offset.length()/1.5,0,1)).normalized()
	if steering.is_zero_approx(): steering = direction
	steering = steering.lerp(desired,1.0 - exp(-3.5 * delta)).normalized()
	# Keep turns rounded, but finish precisely over the hatch.
	if path.size() == 1 and offset.length() < 0.6: steering = direction
	direction = steering
	var model := get_parent() as Node3D
	var desired_speed := float(tuning.npc_speed) * (1.5 if flee > 0 else 1.0) * traffic_speed
	if path.size() == 1: desired_speed = minf(desired_speed,sqrt(maxf(0.0,2.0 * maxf(1.0,float(tuning.npc_speed)*0.85) * offset.length())))
	var hit := _flow_move(delta,direction,desired_speed)
	if hit != null:
		last_obstacle = str(hit.get_collider().get_path())
		blocked += delta
		# Replan around a newly occupied entrance or another vessel, keeping the
		# submarine in the water rather than teleporting through the obstacle.
		if blocked > 0.4:
			var side := Vector3(-direction.z,0,direction.x).normalized()
			var detour := model.global_position + side * 2.2
			if system.segment_clear(model.global_position,detour): path.insert(0,detour)
			else:
				detour = model.global_position - side * 2.2
				if system.segment_clear(model.global_position,detour): path.insert(0,detour)
				else: path.clear()
			wait = random.randf_range(0.2,0.5); blocked = 0
	else: blocked = 0

func _flow_move(delta: float, direction: Vector3, desired_speed: float, aim: Vector3 = Vector3.ZERO) -> KinematicCollision3D:
	var model := get_parent() as Node3D
	model.global_basis = motion.step(delta,direction,desired_speed,float(tuning.npc_speed),model.global_basis,aim).scaled_local(home.basis.get_scale())
	var start := model.global_position
	var hit := body.move_and_collide(motion.velocity * delta)
	model.global_position = body.global_position; body.transform = Transform3D.IDENTITY
	body.velocity = (model.global_position-start) / maxf(delta,0.001)
	if hit != null: motion.velocity = motion.velocity.slide(hit.get_normal())
	speed = motion.velocity.length()
	return hit

func _coast(delta: float, aim: Vector3 = Vector3.ZERO) -> void:
	_flow_move(delta,Vector3.ZERO,0.0,aim)

func _propulsion(delta: float) -> void:
	if dead or not running: return
	var target := clampf(speed / maxf(0.1,float(tuning.npc_speed)),0,1.5) if stage == "travel" else 0.35 if stage in ["ascend","descend"] else 0.0
	propeller_power = move_toward(propeller_power,target,delta * 2.5)
	propeller_angle = fmod(propeller_angle + propeller_power * delta * TAU * 5.0,TAU)
	for rotor in propellers:
		if is_instance_valid(rotor.node): rotor.node.basis = rotor.rest * Basis(Vector3.BACK,propeller_angle)
	if system == null or system.bubbles == null or not get_parent().visible or propeller_power < 0.025: return
	var model := get_parent() as Node3D
	var exhaust := -model.global_basis.z.normalized()
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(model.global_position) > pow(camera.far + 8.0,2): return
	# The shared renderer keeps independent fractional credits per ship/outlet.
	var key := int(get_instance_id()) * 3
	if not propellers.is_empty():
		for index in propellers.size():
			var rotor: Node3D = propellers[index].node
			if not is_instance_valid(rotor): continue
			system.bubbles.emit_from(key + index,rotor.global_position + exhaust * 0.04,exhaust,propeller_power,7.0 if propellers.size() > 1 else 10.0,delta)
	elif twin_exhaust:
		for index in range(2):
			var origin := model.to_global(Vector3(-0.3 if index == 0 else 0.3,0,-0.45))
			system.bubbles.emit_from(key + index,origin,exhaust,propeller_power,7.0,delta)
	else:
		var origin := propeller.global_position if is_instance_valid(propeller) else model.to_global(Vector3(0,0,bounds.position.z))
		system.bubbles.emit_from(key,origin + exhaust * 0.04,exhaust,propeller_power,10.0,delta)

func _phase(value: String) -> void:
	var previous := stage
	stage = value; elapsed = 0; transit_start = global_position; speed = 0; steering = Vector3.ZERO; avoidance = Vector3.ZERO; avoidance_clock = 0; body.velocity = Vector3.ZERO
	motion.velocity = Vector3.ZERO; motion.bank = 0.0

	_update_dock_audio(previous)

func _update_dock_audio(previous: String = "") -> void:
	if not is_instance_valid(dock_audio): return
	if not port.is_empty(): dock_audio.spatial_origin = port.node
	var doors := ["open","close","exit_open","exit_close"]
	dock_audio.set_phase(not dead and stage not in ["travel","berth"],stage in doors,previous in doors and stage != previous)

func _dock_step(delta: float) -> void:
	if stage == "berth":
		wait = maxf(0,wait - delta)
		if wait > 0 or not Access.acquire(port,self): return
		get_parent().show(); _phase("exit_open"); return
	if Access.owner(port) != self:
		get_parent().global_position = port.entry; get_parent().show(); body.collision_layer = 10
		port = {}; destination = 0; _phase("travel"); return
	elapsed += delta
	var duration := 1.2 if stage in ["open","close","exit_open","exit_close"] else maxf(1.0,port.entry.distance_to(port.inside) / float(tuning.npc_speed))
	var fraction := clampf(elapsed / duration,0,1)
	var eased := smoothstep(0,1,fraction)
	match stage:
		"open","exit_open":
			Access.open(port,eased)
			var model := get_parent() as Node3D
			var level := preload("res://docking_controller.gd").upright_basis(model.global_basis)
			model.global_basis = model.global_basis.orthonormalized().slerp(level,clampf(delta * 6,0,1)).scaled_local(home.basis.get_scale())
		"close","exit_close": Access.open(port,1 - eased)
		"descend": get_parent().global_position = transit_start.lerp(port.inside + Vector3.UP * maxf(0,-bounds.position.y - 0.25),eased)
		"ascend": get_parent().global_position = transit_start.lerp(port.entry,eased)
	if fraction < 1: return
	match stage:
		"open": port.collision.collision_layer = 0; _phase("descend")
		"descend": _phase("close")
		"close":
			port.collision.collision_layer = 1; Access.release(port,self); get_parent().hide()
			last_city = destination; journey_count += 1
			wait = random.randf_range(float(tuning.npc_wait_min),float(tuning.npc_wait_max)); _phase("berth")
		"exit_open": port.collision.collision_layer = 0; _phase("ascend")
		"ascend": _phase("exit_close")
		"exit_close":
			port.collision.collision_layer = 1; Access.release(port,self); body.collision_layer = 10
			port = {}; path.clear(); destination = 0; _phase("travel")

func take_weapon_damage(strength: float, source: Vector3 = Vector3.ZERO) -> void:
	if not running or not local_simulation or dead or stage != "travel" or not health.hit(strength): return
	if report_player_attack: attacked.emit(int(tuning.npc_faction))
	attacker = source; flee = 8; path.clear(); wait = 0; destination = 0; release_port()
	if smoke != null: smoke.set_health(health.remaining * 10)
	if health.remaining > 0: return
	dead = true; release_port(); get_parent().hide(); body.collision_layer = 0
	destroyed.emit(preload("res://entity_identity.gd").of(self),preload("res://entity_identity.gd").of(damage_attacker) if is_instance_valid(damage_attacker) else "")
	respawn = float(tuning.npc_respawn_delay)
	var wreck := preload("res://submarine_death.gd").new(); system.get_parent().add_child(wreck)
	wreck.global_position = global_position; wreck.setup_machine(get_parent(),get_parent(),system.bubble_texture,[],body.velocity)
	wreck.add_to_group("trader_wrecks")
	var effect := preload("res://mine_explosion.gd").new(); system.get_parent().add_child(effect); effect.global_position = global_position
	effect.setup(system.explosion_frames,maxf(0.4,bounds.size.length()),system.explosion_sound)

func apply_attributed_damage(strength: float, source: Vector3, owner_body: Node3D) -> void:
	# City defence alerts target the player, so NPC combat must not raise them.
	var previous := report_player_attack
	var previous_attacker := damage_attacker
	damage_attacker = owner_body
	report_player_attack = system != null and is_instance_valid(owner_body) and owner_body == system.player
	take_weapon_damage(strength,source)
	report_player_attack = previous
	damage_attacker = previous_attacker

func take_weapon_damage_from(strength: float, source: Vector3, owner_body: Node3D) -> void:
	apply_attributed_damage(strength,source,owner_body)
