extends "res://pirate_submarine.gd"
## Mission routes reuse traffic steering/avoidance without civilian destination picks.
signal arrived
signal player_attacked
signal hull_damaged(attacker: Node3D)
var combat_enabled := true
var dormant := false
var waypoints := PackedVector3Array()
var waypoint := 0
var loop_route := false
var engage_player := false
var combat_target: Node3D
var pursue_offscreen := false
var follow: Node3D
var formation := Vector3.ZERO
var arrival_reported := false
var dock_destination := 0
var route_mines: Array[Node3D] = []
var route_retry := 0.0
var level_when_idle := false
var travel_height := INF
var pursuit_target := Vector3.INF
var retiring := false
var freighter_guns := false
var staged_destruction := false
var boarding := false
var boarding_pod: Node3D

func health_multiplier() -> float:
	# Mission vessels also include civilian shuttles, fishing boats and freighters.
	return model_health_multiplier(get_parent())

func _physics_process(delta: float) -> void:
	if not dormant: super._physics_process(delta)

func boarding_goal() -> Vector3:
	var goal: Vector3 = follow.get_parent().to_global(formation)
	# The retail formation is above the host; our navigation envelope can be
	# lower than that when the prison ship cruises near the water surface.
	goal.y = minf(goal.y,system.map.surface_height-system.CLEARANCE-0.1)
	return goal

func _advance_boarding(delta: float) -> void:
	var goal := boarding_goal()
	var host_velocity: Vector3 = follow.body.velocity
	var offset := goal-global_position
	var cruise := float(tuning.npc_speed)
	var intercept := goal+host_velocity*clampf(offset.length()/maxf(0.1,cruise),0,2.0)
	intercept.y = minf(intercept.y,system.map.surface_height-system.CLEARANCE-0.1)
	var direct := false
	replan -= delta
	if replan <= 0:
		replan = 0.25
		set_meta("boarding_direct",system.segment_clear(global_position,intercept))
		if not get_meta("boarding_direct",false) and (path.is_empty() or pursuit_target.distance_to(intercept) > 2.0):
			path = system.route(global_position,intercept); pursuit_target = intercept
	direct = get_meta("boarding_direct",false)
	var direction := offset.normalized()
	var desired_speed := cruise
	if direct:
		path.clear()
		# Feed-forward host motion keeps station over a moving hull rather than
		# repeatedly stopping at a stale waypoint behind it.
		var desired_velocity := (host_velocity+offset*1.8).limit_length(cruise)
		direction = desired_velocity.normalized(); desired_speed = desired_velocity.length()
	else:
		direction = _route_direction(delta)
		if path.is_empty(): _coast(delta); return
	if offset.length() > 4.0:
		avoidance_clock -= delta
		if avoidance_clock <= 0:
			avoidance_clock = 0.15
			var decision: Dictionary = system.avoidance(self,direction)
			avoidance = decision.direction; traffic_speed = decision.speed
		direction = (direction+avoidance*0.5).normalized()
		desired_speed *= maxf(0.75,traffic_speed)
	var aim: Vector3 = follow.get_parent().global_basis.z if offset.length() < 4 else direction
	var hit := _flow_move(delta,direction,desired_speed,aim)
	if hit != null: replan = 0; path.clear()

func _precise_motion() -> bool:
	return (boarding and is_instance_valid(follow) and global_position.distance_to(boarding_goal()) < 4.0) or super._precise_motion()

func arm_freighter(folder: String) -> void:
	# FREIGHT 00456560/00455f90: fixed ship, fore/aft homing launchers,
	# ten-unit range and 125 simulation ticks between shots.
	freighter_guns = true; staged_destruction = true; cooldown = 5.0
	if is_instance_valid(missile_template): missile_template.free()
	missile_template = preload("res://clump_loader.gd").load_clump(folder.path_join("CLUMPS/HMISSILE.DFF"))
	if missile_template != null: add_child(missile_template); missile_template.hide()

func _freighter_fire(delta: float) -> void:
	var player: Node3D = system.player
	if not is_instance_valid(player) or player.get("dead") == true or player.get("active") == false or player.get_meta("bubble_screened",false): return
	cooldown -= delta
	var offset := player.global_position-global_position
	if cooldown > 0 or offset.length() >= 10 or missile_template == null: return
	var front: bool = get_parent().global_basis.z.dot(offset) >= 0
	var socket := Vector3(0,0,3.2) if front else Vector3(0,-0.2,-0.6)
	var heading: Vector3 = (get_parent().global_basis*socket).normalized()
	var missile := preload("res://turret_missile.gd").new(); system.get_parent().add_child(missile)
	missile.setup(self,missile_template,get_parent().to_global(socket),heading,player,true)
	missile.get_child(0).show(); cooldown = 5.0

func _retire_if_docked() -> void:
	if stage != "berth" or not running: return
	running = false; set_physics_process(false)
	call_deferred("_finish_retirement")

func _finish_retirement() -> void:
	system.traders.erase(self)
	if system.map != null and system.map.get("actor_markers") != null: system.map.actor_markers.erase(body)
	release_port()
	if is_instance_valid(smoke): smoke.queue_free(); smoke = null
	get_parent().queue_free()

func prepare_abstract_route() -> bool:
	if not retiring and not (dock_destination > 0 and waypoint >= waypoints.size()): return super.prepare_abstract_route()
	if destination == 0: destination = dock_destination
	port = system.port_by_id(destination)
	if port.is_empty(): wait = 2; return false
	path = system.abstract_route(global_position,port.entry)
	if path.is_empty(): wait = 2
	return not path.is_empty()

func _destroy_visuals() -> void:
	if not staged_destruction: super._destroy_visuals(); return
	var effect := preload("res://base_destruction.gd").new(); system.get_parent().add_child(effect)
	effect.setup_vessel(get_parent(),system)

static func install_mission(model: Node3D, values: Dictionary, controller: Script = null) -> Node3D:
	var agent = preload("res://trader_submarine.gd").install(model,values,controller if controller != null else load("res://mission_vessel.gd"))
	agent.tuning = preload("res://trader_submarine.gd").DEFAULTS.merged(PIRATE_DEFAULTS,true).merged(values,true)
	agent.tuning.npc_respawn = false
	agent.body.set_meta("faction",int(values.get("npc_faction",2)))
	agent.hitbox = agent.body
	return agent

func _valid_target(target: Node3D) -> bool:
	return combat_enabled and system != null and target == (system.player if engage_player else combat_target) and super._valid_target(target)

func _nearest_target() -> Node3D:
	var target: Node3D = system.player if engage_player else combat_target
	return target if _valid_target(target) else null

func _advance_motion(delta: float) -> void:
	if dead: return
	if retiring:
		if destination == 0: destination = dock_destination
		if stage != "berth": _travel_without_target(delta)
		_retire_if_docked(); return
	if freighter_guns:
		_freighter_fire(delta); _coast(delta); return
	if boarding and is_instance_valid(follow) and not follow.dead:
		_advance_boarding(delta); return
	route_retry = maxf(0,route_retry-delta)
	if stage != "travel":
		if stage != "berth" or dock_destination == 0: _travel_without_target(delta)
		if stage == "berth" and not arrival_reported: arrival_reported = true; arrived.emit()
		return
	if combat_enabled and (engage_player or is_instance_valid(combat_target)):
		super._advance_motion(delta); return
	if is_instance_valid(follow):
		replan -= delta
		if replan <= 0:
			replan = 1.0; path = system.route(global_position,follow.global_position + formation)
	elif path.is_empty():
		var reach := maxf(0.3,speed*0.9) if _continuous_route() else 0.2
		if waypoint < waypoints.size() and global_position.distance_to(waypoints[waypoint]) < reach: waypoint += 1
		if waypoint >= waypoints.size():
			if loop_route and not waypoints.is_empty(): waypoint = 0
			else:
				if dock_destination > 0:
					destination = dock_destination; port = system.port_by_id(destination)
					# A closed entrance can block the final navigation probe.
					# Reserve/open it from the approach, then move over the hatch.
					if not port.is_empty() and global_position.distance_to(port.entry) < 8 and preload("res://dock_access.gd").acquire(port,self):
						_phase("open"); return
					_travel_without_target(delta); return
				_coast(delta)
				if not waypoints.is_empty() and not arrival_reported: arrival_reported = true; arrived.emit()
				return
		if route_retry > 0: _coast(delta); return
		path = _mission_route(waypoints[waypoint])
		if path.is_empty(): route_retry = 0.75
	if not path.is_empty(): _travel_without_target(delta)
	else: _coast(delta)

func _continuous_route() -> bool:
	if is_instance_valid(follow) or retiring or freighter_guns: return false
	return loop_route or waypoint < waypoints.size()-1 or (combat_enabled and (engage_player or is_instance_valid(combat_target)))

func _dock_step(delta: float) -> void:
	if dock_destination > 0 and stage == "open" and preload("res://dock_access.gd").owner(port) == self:
		if elapsed + delta >= 1.2 and global_position.distance_to(port.entry) > 0.15:
			# Keep the hatch open while physically aligning; the ordinary descent
			# starts only after the transport is above the entrance.
			elapsed = 1.2; preload("res://dock_access.gd").open(port,1)
			port.collision.collision_layer = 0
			var offset: Vector3 = port.entry-global_position
			_flow_move(delta,offset.normalized(),minf(float(tuning.npc_speed),offset.length()*2))
			return
	super._dock_step(delta)

func _mission_route(goal: Vector3) -> PackedVector3Array:
	if is_finite(travel_height): goal.y = travel_height
	var result: PackedVector3Array = system.route(global_position,goal)
	if is_finite(travel_height):
		# Fishing ships stay in their working plane. The shared traffic graph
		# may route via a lower cruise depth; never follow that descent.
		var previous := global_position
		for index in result.size():
			result[index].y = travel_height
			if not system.segment_clear(previous,result[index]): return PackedVector3Array()
			previous = result[index]
	# The shared graph covers terrain/scenery. A prison convoy also has to
	# clear solid mines, which otherwise act as permanent unseen roadblocks.
	for attempt in range(16):
		var previous := global_position
		var changed := false
		for index in range(result.size()):
			var next := result[index]
			for mine in route_mines:
				if not is_instance_valid(mine) or mine.dead: continue
				var clearance := bounds.size.length() * 0.5 + float(mine.stats.size) * 0.5 + 0.3
				var nearest := Geometry3D.get_closest_point_to_segment(mine.global_position,previous,next)
				if nearest.distance_to(mine.global_position) >= clearance: continue
				var forward := (next-previous).normalized()
				var side := forward.cross(Vector3.UP).normalized()
				for offset in [Vector3.DOWN,side,-side]:
					var before: Vector3 = nearest - forward * clearance * 1.5 + offset * clearance * 1.5
					var after: Vector3 = nearest + forward * clearance * 1.5 + offset * clearance * 1.5
					if system.segment_clear(previous,before) and system.segment_clear(before,after) and system.segment_clear(after,next):
						result.insert(index,after); result.insert(index,before); changed = true; break
				if changed: break
			if changed: break
			previous = next
		if not changed: break
	return result

func advance_abstract(delta: float) -> void:
	# Mission travel/timers continue outside visual range, but no hidden combat.
	if dormant or local_simulation or dead or not running or not system.navigation_ready: return
	if retiring:
		if stage != "berth": super.advance_abstract(delta)
		_retire_if_docked(); return
	if dock_destination > 0 and waypoint >= waypoints.size() and not loop_route and not is_instance_valid(follow):
		_abstract_dock(delta); return
	route_retry = maxf(0,route_retry-delta)
	if pursue_offscreen and (engage_player or is_instance_valid(combat_target)):
		var target: Node3D = system.player if engage_player else combat_target
		if not is_instance_valid(target) or target.get("dead") == true: return
		if global_position.distance_to(target.global_position) < 6: return
		replan -= delta
		if replan <= 0 and (path.is_empty() or pursuit_target.distance_to(target.global_position) > 4.0):
			replan = 1.0
			var away := (global_position-target.global_position).normalized()
			# Keep the leg already being travelled. Rebuilding from our nearest
			# graph anchor every second can turn us back at each half-way point.
			var next := global_position if path.is_empty() else path[0]
			var goal: Vector3 = target.global_position+away*5.5
			if not system.water_clear(goal): goal = system.graph.get_point_position(system.graph.get_closest_point(goal))
			var route: PackedVector3Array = system.abstract_route(next,goal)
			if not path.is_empty() and not route.is_empty() and route[0] != next: route.insert(0,next)
			path = route; pursuit_target = target.global_position
		var distance_left := float(tuning.npc_speed)*delta
		while distance_left > 0 and not path.is_empty():
			var distance := global_position.distance_to(path[0])
			get_parent().global_position = global_position.move_toward(path[0],distance_left)
			distance_left -= distance
			if distance_left >= 0: path.remove_at(0)
		return # Approach unseen; weapons still require local simulation.
	if is_instance_valid(follow):
		_abstract_follow(delta); return
	if (combat_enabled and (engage_player or is_instance_valid(combat_target))) or waypoints.is_empty(): return
	if path.is_empty():
		if waypoint < waypoints.size() and global_position.distance_to(waypoints[waypoint]) < 0.2: waypoint += 1
		if waypoint >= waypoints.size():
			if loop_route: waypoint = 0
			else:
				if dock_destination > 0:
					_abstract_dock(delta)
				elif not arrival_reported: arrival_reported = true; arrived.emit()
				return
		if route_retry > 0: return
		path = _mission_route(waypoints[waypoint]) if is_finite(travel_height) else system.abstract_route(global_position,waypoints[waypoint])
		if path.is_empty(): route_retry = 0.75
	var remaining := float(tuning.npc_speed) * delta
	while remaining > 0 and not path.is_empty():
		var distance := global_position.distance_to(path[0])
		get_parent().global_position = global_position.move_toward(path[0],remaining)
		remaining -= distance
		if remaining >= 0: path.remove_at(0)

func _abstract_dock(delta: float) -> void:
	# Completing the approach waypoint is not docking. Continue to the actual
	# hatch through normal traffic, including when the player is far away.
	if stage != "berth":
		destination = dock_destination
		super.advance_abstract(delta)
	if stage == "berth" and not arrival_reported: arrival_reported = true; arrived.emit()

func _abstract_follow(delta: float) -> void:
	var goal := boarding_goal() if boarding else follow.global_position+formation
	if global_position.distance_to(goal) < 0.2: path.clear(); return
	replan -= delta
	if replan <= 0 and (path.is_empty() or pursuit_target.distance_to(goal) > 2):
		replan = 1.0; pursuit_target = goal
		var next := global_position if path.is_empty() else path[0]
		var route: PackedVector3Array = system.abstract_route(next,goal)
		if not path.is_empty() and not route.is_empty() and route[0] != next: route.insert(0,next)
		path = route
	var remaining := float(tuning.npc_speed)*delta
	while remaining > 0 and not path.is_empty():
		var distance := global_position.distance_to(path[0])
		get_parent().global_position = global_position.move_toward(path[0],remaining)
		remaining -= distance
		if remaining >= 0: path.remove_at(0)

func _react_to_damage(source: Vector3) -> void:
	# Passive mission ships keep their fishing/convoy/docking orders. Damage,
	# smoke and radio still apply, without a civilian escape route or port reset.
	if combat_enabled and not boarding: super._react_to_damage(source)

func _coast(delta: float, aim: Vector3 = Vector3.ZERO) -> void:
	if level_when_idle and aim.is_zero_approx():
		aim = get_parent().global_basis.z; aim.y = 0
		if aim.is_zero_approx(): aim = Vector3.BACK
	super._coast(delta,aim)

func _flow_move(delta: float, direction: Vector3, desired_speed: float, aim: Vector3 = Vector3.ZERO) -> KinematicCollision3D:
	if is_finite(travel_height):
		# Avoidance and collision sliding must not turn a nearby hull or rock
		# into a new diving order while the herder is fishing.
		direction.y = 0; aim.y = 0; motion.velocity.y = 0
	var hit := super._flow_move(delta,direction.normalized(),desired_speed,aim)
	if is_finite(travel_height):
		# Contact recovery can also displace a stationary ship vertically.
		get_parent().global_position.y = travel_height
		motion.velocity.y = 0; body.velocity.y = 0
	return hit

func take_weapon_damage_from(strength: float, source: Vector3, owner_body: Node3D) -> void:
	# Mission combat ships never pay roaming-pirate bounties.
	var before: float = health.remaining
	apply_attributed_damage(strength,source,owner_body)
	if health.remaining < before: hull_damaged.emit(owner_body)
	if not combat_enabled: flee = 0.0
	if system != null and owner_body == system.player:
		if combat_enabled and not dead and not boarding: engage_player = true
		player_attacked.emit()
