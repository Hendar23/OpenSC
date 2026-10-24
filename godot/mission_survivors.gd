extends RefCounted
## Surviving encounter ships can outlast their mission without retaining callbacks.
const MODELS := {"TRAD2":1,"TRAD-SUB":1,"TECHNEW":2,"TECH2SUB":2,"TRADSHUT":1,"FREIGHT":1,"PIRATE":3}
const TAG := "fishing_survivor"

static func depart(jobs: Node, agent: Node3D) -> void:
	if not is_instance_valid(agent) or agent.dead: return
	var traffic: Node = jobs.game.submarine_traffic
	var city := 0; var shortest := INF
	var fallback := 0; var nearest := INF
	for candidate in traffic.ports:
		if int(candidate.race) != int(agent.tuning.npc_faction): continue
		if int(candidate.node.get_meta("city_id")) not in traffic.destinations(int(agent.tuning.npc_faction)): continue
		var direct: float = agent.global_position.distance_squared_to(candidate.entry)
		if direct < nearest: nearest = direct; fallback = int(candidate.node.get_meta("city_id"))
		var route: PackedVector3Array = traffic.abstract_route(agent.global_position,candidate.entry)
		if route.is_empty(): continue
		var distance := 0.0; var previous: Vector3 = agent.global_position
		for point in route: distance += previous.distance_to(point); previous = point
		if distance < shortest: shortest = distance; city = int(candidate.node.get_meta("city_id"))
	# A very early dev-triggered failure can precede navigation graph completion.
	# Keep the ship and let normal traffic routing retry once navigation is ready.
	if city == 0: city = fallback
	if city == 0: return
	var model: Node3D = agent.get_parent()
	agent.set_meta(TAG,str(model.get_meta("editor_model"))); agent.mission_owner = ""
	model.remove_meta("mission_owner")
	preload("res://entity_identity.gd").assign_id(model)
	preload("res://entity_identity.gd").actor(model,agent,agent.body)
	agent.body.remove_meta("mission_marker")
	agent.follow = null; agent.combat_target = null; agent.victim = null
	agent.combat_enabled = false; agent.engage_player = false; agent.retiring = true
	agent.loop_route = false; agent.waypoints.clear(); agent.path.clear()
	agent.destination = city; agent.dock_destination = city; agent.port = traffic.port_by_id(city)
	agent.wait = 0; agent.flee = 0
	jobs.vessels.erase(agent); jobs.actors.erase(model)

static func release(jobs: Node, enemies: Array[Node3D]) -> void:
	for agent in enemies:
		if not is_instance_valid(agent) or agent.dead: continue
		var model: Node3D = agent.get_parent()
		var model_id := str(model.get_meta("editor_model",""))
		if not MODELS.has(model_id): continue
		agent.set_meta(TAG,model_id); agent.mission_owner = ""
		model.remove_meta("mission_owner")
		preload("res://entity_identity.gd").assign_id(model)
		preload("res://entity_identity.gd").actor(model,agent,agent.body)
		# Mission-local targets are about to disappear. Preserve the independent
		# ships and release formations, without making passive guards hostile.
		agent.follow = null; agent.combat_enabled = true; agent.dormant = false
		agent.engage_player = agent.engage_player or is_instance_valid(agent.combat_target)
		agent.combat_target = null; agent.victim = null
		agent.waypoints.clear(); agent.dock_destination = 0
		agent.path.clear(); agent.replan = 0; agent.pursuit_target = Vector3.INF
		jobs.vessels.erase(agent); jobs.actors.erase(model)

static func clear(traffic: Node) -> void:
	for agent in traffic.traders.duplicate():
		if not agent.has_meta(TAG): continue
		traffic.traders.erase(agent)
		if traffic.map != null and traffic.map.get("actor_markers") != null: traffic.map.actor_markers.erase(agent.body)
		agent.release_port()
		if is_instance_valid(agent.smoke): agent.smoke.free(); agent.smoke = null
		agent.get_parent().free()

static func restore(traffic: Node, entries: Dictionary) -> void:
	clear(traffic)
	for identity in entries:
		var entry: Dictionary = entries[identity]
		if not entry.has(TAG): continue
		var model_id := str(entry[TAG])
		if not MODELS.has(model_id): continue
		var model := preload("res://map_document.gd").load_model(model_id,traffic.asset_folder)
		if model == null: continue
		traffic.get_parent().add_child(model)
		model.global_transform = preload("res://map_document.gd").decode(entry.pose)
		model.set_meta("editor_model",model_id)
		preload("res://entity_identity.gd").assign_id(model,identity)
		var agent: Node3D = preload("res://mission_vessel.gd").install_mission(model,{"npc_faction":MODELS[model_id],"npc_health":3.0 if model_id == "FREIGHT" else 30.0 if model_id == "PIRATE" else 10.0 if MODELS[model_id] == 1 else 15.0,"npc_speed":1.5 if model_id in ["TRADSHUT","FREIGHT"] else 2.5 if model_id == "PIRATE" else 2.0,"npc_sustain":0.1 if model_id == "FREIGHT" else 0.3,"npc_detection":1000.0})
		agent.set_meta(TAG,model_id); agent.engage_player = entry.get("survivor_hostile",true); agent.pursue_offscreen = true
		agent.retiring = entry.get("survivor_retiring",false); agent.combat_enabled = not agent.retiring
		if agent.retiring: agent.dock_destination = int(entry.get("destination",0))
		agent.report_player_attack = false
		traffic.register_vessel(agent,traffic.get_parent(),traffic.asset_folder)
