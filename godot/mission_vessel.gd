extends "res://pirate_submarine.gd"
## Mission routes reuse traffic steering/avoidance without civilian destination picks.
signal arrived
signal player_attacked
var combat_enabled := true
var waypoints := PackedVector3Array()
var waypoint := 0
var loop_route := false
var engage_player := false
var follow: Node3D
var formation := Vector3.ZERO
var arrival_reported := false
var dock_destination := 0
var route_mines: Array[Node3D] = []

static func install_mission(model: Node3D, values: Dictionary) -> Node3D:
	var agent = preload("res://trader_submarine.gd").install(model,values,load("res://mission_vessel.gd"))
	agent.tuning = PIRATE_DEFAULTS.merged(values,true)
	agent.tuning.npc_respawn = false
	agent.body.set_meta("faction",int(values.get("npc_faction",2)))
	agent.hitbox = agent.body
	return agent

func _valid_target(target: Node3D) -> bool:
	return combat_enabled and engage_player and system != null and target == system.player and super._valid_target(target)

func _nearest_target() -> Node3D:
	return system.player if engage_player and _valid_target(system.player) else null

func _advance_motion(delta: float) -> void:
	if dead: return
	if stage != "travel":
		_travel_without_target(delta)
		if stage == "berth" and not arrival_reported: arrival_reported = true; arrived.emit()
		return
	if combat_enabled and engage_player:
		super._advance_motion(delta); return
	if is_instance_valid(follow):
		replan -= delta
		if replan <= 0:
			replan = 1.0; path = system.route(global_position,follow.global_position + formation)
	elif path.is_empty():
		if waypoint < waypoints.size() and global_position.distance_to(waypoints[waypoint]) < 0.2: waypoint += 1
		if waypoint >= waypoints.size():
			if loop_route and not waypoints.is_empty(): waypoint = 0
			else:
				if dock_destination > 0:
					destination = dock_destination; port = system.port_by_id(destination)
					_travel_without_target(delta); return
				_coast(delta)
				if not arrival_reported: arrival_reported = true; arrived.emit()
				return
		path = _mission_route(waypoints[waypoint])
	if not path.is_empty(): _travel_without_target(delta)
	else: _coast(delta)

func _mission_route(goal: Vector3) -> PackedVector3Array:
	var result: PackedVector3Array = system.route(global_position,goal)
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
	if local_simulation or dead or not running or not system.navigation_ready: return
	if is_instance_valid(follow):
		get_parent().global_position = follow.global_position + formation; return
	if (combat_enabled and engage_player) or waypoints.is_empty(): return
	if path.is_empty():
		if waypoint < waypoints.size() and global_position.distance_to(waypoints[waypoint]) < 0.2: waypoint += 1
		if waypoint >= waypoints.size():
			if loop_route: waypoint = 0
			else:
				if dock_destination > 0:
					stage = "berth"; get_parent().hide(); body.collision_layer = 0
				if not arrival_reported: arrival_reported = true; arrived.emit()
				return
		path = system.abstract_route(global_position,waypoints[waypoint])
	var remaining := float(tuning.npc_speed) * delta
	while remaining > 0 and not path.is_empty():
		var distance := global_position.distance_to(path[0])
		get_parent().global_position = global_position.move_toward(path[0],remaining)
		remaining -= distance
		if remaining >= 0: path.remove_at(0)

func take_weapon_damage_from(strength: float, source: Vector3, owner_body: Node3D) -> void:
	# Mission combat ships never pay roaming-pirate bounties.
	apply_attributed_damage(strength,source,owner_body)
	if not combat_enabled: flee = 0.0
	if system != null and owner_body == system.player:
		if combat_enabled and not dead: engage_player = true
		player_attacked.emit()
