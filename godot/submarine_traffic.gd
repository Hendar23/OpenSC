extends Node
const Identity = preload("res://entity_identity.gd")
const Survivors = preload("res://mission_survivors.gd")
var events: RefCounted
var prepare_visual: Callable
var asset_folder := ""
## One water navigation graph shared by all civilian vessels.
signal pirate_defeated(position: Vector3)
var roaming_population: Node3D
const Trader = preload("res://trader_submarine.gd")
const Access = preload("res://dock_access.gd")
const STEP := 2.0
const CLEARANCE := 1.05
const FOOTPRINT := [Vector2.ZERO,Vector2(-CLEARANCE,0),Vector2(CLEARANCE,0),Vector2(0,-CLEARANCE),Vector2(0,CLEARANCE),Vector2(-CLEARANCE,-CLEARANCE),Vector2(CLEARANCE,-CLEARANCE),Vector2(-CLEARANCE,CLEARANCE),Vector2(CLEARANCE,CLEARANCE)]
const SMOOTHING_BUDGET_USEC := 2000
var route_water := {}
var routing := false
var traders: Array[Node3D] = []
var ports: Array[Dictionary] = []
var player: Node3D
var map: RefCounted
var graph := AStar3D.new()
var cells := {}
var obstacles: Array[AABB] = []
var navigation_ready := false
var simulating := true
var bubbles: Node3D
var bubble_texture: Texture2D
var explosion_frames: Array[Texture2D] = []
var explosion_sound: AudioStream
var width := 0
var depth := 0
var cursor := 0
var cruise := 0.0
var space: PhysicsDirectSpaceState3D
var probe := SphereShape3D.new()
var navigation_cache_key := ""

func setup(world: Node3D, folder: String, dock_ports: Array[Dictionary], terrain_map: RefCounted, observer: Node3D = null, alert: Callable = Callable()) -> void:
	asset_folder = folder
	space = world.get_world_3d().direct_space_state; probe.radius = 0.9
	ports = dock_ports; map = terrain_map; player = observer
	cruise = map.surface_height - 2.0
	width = int(ceil(map.bounds.size.x / STEP)); depth = int(ceil(map.bounds.size.z / STEP))
	# Static scenery joins the terrain height map as solid navigation obstacles.
	for collider in world.find_children("SceneryCollision","StaticBody3D",true,false):
		var model := collider.get_parent() as Node3D
		var boxes: Array[AABB] = []
		preload("res://docking_controller.gd")._bounds(model,model.global_transform,boxes)
		if boxes.is_empty(): continue
		var box := boxes[0]
		for other in boxes: box = box.merge(other)
		if box.position.y - CLEARANCE < cruise and box.end.y + CLEARANCE > cruise: obstacles.append(box.grow(CLEARANCE))
	bubble_texture = preload("res://clump_loader.gd")._load_texture(folder,"BUBBLE","BUBBLEM",{})
	bubbles = preload("res://propeller_bubbles.gd").new(); add_child(bubbles); bubbles.configure(bubble_texture); bubbles.surface_height = map.surface_height
	explosion_frames = preload("res://mine_explosion.gd").load_frames(folder)
	explosion_sound = preload("res://submarine_weapons.gd")._sound(folder,"audio.object.mine.explosion","EXPLODE1")
	for agent in world.find_children("Trader","Node3D",true,false):
		if not agent is Trader: continue
		register_vessel(agent,world,folder,alert)
	_prepare_navigation_cache(world)

func register_vessel(agent: Node3D, world: Node3D, folder: String, alert: Callable = Callable()) -> void:
	if prepare_visual.is_valid(): prepare_visual.call(agent.get_parent())
	agent.system = self; traders.append(agent)
	if events != null: agent.destroyed.connect(events.entity_destroyed.emit)
	if agent.has_method("configure_resources"): agent.configure_resources(folder)
	if not is_instance_valid(agent.dock_audio) and is_instance_valid(player) and player.get("submarine_audio") != null:
		agent.dock_audio = preload("res://docking_audio.gd").new(); agent.add_child(agent.dock_audio)
		agent.dock_audio.setup(player.submarine_audio,folder,agent.get_parent())
	agent.smoke = preload("res://submarine_damage_smoke.gd").new(); world.add_child(agent.smoke); agent.smoke.setup(agent.get_parent(),folder)
	if alert.is_valid(): agent.attacked.connect(alert)
	agent.reset(); agent.running = simulating
	agent.get_parent().physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON if simulating else Node.PHYSICS_INTERPOLATION_MODE_OFF
	if map.get("actor_markers") != null: map.actor_markers.append(agent.body)

func enable_roaming_pirates(folder: String, document: Dictionary) -> void:
	if is_instance_valid(roaming_population): return
	roaming_population = preload("res://pirate_population.gd").new(); roaming_population.name = "RoamingPirates"
	get_parent().add_child(roaming_population); roaming_population.setup(self,folder,document)

func replenish_docked(delta: float) -> void:
	# Game calls this only once the player's docked UI hides the outside world.
	if not navigation_ready or not simulating: return
	for agent in traders:
		if not agent.dead or not agent.mission_owner.is_empty(): continue
		if agent.has_meta(Survivors.TAG): continue
		if is_instance_valid(roaming_population) and roaming_population.ships.has(agent): continue
		agent.reset()
	if is_instance_valid(roaming_population): roaming_population.replenish_docked(delta)

func _exit_tree() -> void:
	for agent in traders:
		if is_instance_valid(agent):
			agent.release_port(); agent.running = false; agent.system = null
			if is_instance_valid(agent.dock_audio): agent.dock_audio.queue_free(); agent.dock_audio = null
			if is_instance_valid(agent.smoke): agent.smoke.queue_free(); agent.smoke = null

func _physics_process(_delta: float) -> void:
	if not navigation_ready: build_graph(128)

func build_graph(budget: int) -> void:
	var started := Time.get_ticks_usec()
	while cursor < width * depth and budget > 0 and Time.get_ticks_usec() - started < 2000:
		var cell := Vector2i(cursor % width,cursor / width)
		var point: Vector3 = map.bounds.position + Vector3((cell.x + 0.5) * STEP,0,(cell.y + 0.5) * STEP); point.y = cruise
		if water_clear(point):
			cells[cell] = cursor; graph.add_point(cursor,point)
			for offset in [Vector2i(-1,0),Vector2i(0,-1),Vector2i(-1,-1),Vector2i(1,-1)]:
				var other: Vector2i = cell + offset
				if cells.has(other) and segment_clear(point,graph.get_point_position(cells[other])):
					graph.connect_points(cursor,cells[other])
		cursor += 1; budget -= 1
	var completed := cursor >= width * depth
	if completed and not navigation_ready and not navigation_cache_key.is_empty():
		var points: Array = []
		for id in graph.get_point_ids(): points.append([id, graph.get_point_position(id), graph.get_point_connections(id)])
		preload("res://asset_cache.gd").save_data(navigation_cache_key, {"points":points, "cells":cells})
	navigation_ready = completed

func _prepare_navigation_cache(world: Node3D) -> void:
	var cache := preload("res://asset_cache.gd")
	if not cache.enabled: return
	var signature := preload("res://world_cache.gd").collision_signature(world, 1)
	if signature.is_empty(): return
	navigation_cache_key = cache.key("world-navigation", [], [signature, preload("res://world_cache.gd").digest(map.height_samples), map.bounds, map.surface_height, map.RESOLUTION, obstacles, STEP, CLEARANCE, probe.radius, cruise, width, depth])
	var data := cache.load_data(navigation_cache_key)
	if not data.get("points") is Array or not data.get("cells") is Dictionary: return
	var ids := {}
	for point in data.points:
		if not point is Array or point.size() != 3 or not point[0] is int or point[0] < 0 or point[0] >= width * depth or ids.has(point[0]) or not point[1] is Vector3 or not point[1].is_finite() or not point[2] is PackedInt64Array: return
		ids[point[0]] = true
	if data.cells.size() != ids.size(): return
	for cell in data.cells:
		if not cell is Vector2i or cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= depth or data.cells[cell] != cell.y * width + cell.x or not ids.has(data.cells[cell]): return
	for point in data.points:
		for other in point[2]:
			if not ids.has(other) or other == point[0]: return
	for point in data.points: graph.add_point(point[0], point[1])
	# Each list preserves the original neighbour order, including both directions.
	for point in data.points:
		for other in point[2]: graph.connect_points(point[0], other, false)
	cells = data.cells; cursor = width * depth; navigation_ready = true

func water_clear(point: Vector3) -> bool:
	if routing and route_water.has(point): return route_water[point]
	var clear := _water_clear(point)
	if routing: route_water[point] = clear
	return clear

func _water_clear(point: Vector3) -> bool:
	var uv: Vector2 = map.uv(point)
	if uv.x < 0 or uv.y < 0 or uv.x > 1 or uv.y > 1 or point.y > map.surface_height - CLEARANCE: return false
	var resolution: int = map.RESOLUTION
	var heights: PackedFloat32Array = map.height_samples
	# Probe the footprint, not only its centre, to avoid cutting ridge corners.
	for offset: Vector2 in FOOTPRINT:
		var sample: Vector2 = map.uv(point + Vector3(offset.x,0,offset.y)) * (resolution - 1)
		var x := clampi(int(sample.x),0,resolution - 1); var y := clampi(int(sample.y),0,resolution - 1)
		for row in range(y,mini(y + 2,resolution)):
			for column in range(x,mini(x + 2,resolution)):
				var terrain: float = heights[row * resolution + column]
				if not is_finite(terrain) or terrain + 0.6 > point.y: return false
	for box in obstacles:
		if box.has_point(point): return false
	return true

func segment_clear(a: Vector3, b: Vector3) -> bool:
	# Reject impossible endpoints before sampling the whole leg.
	if not water_clear(a) or not water_clear(b): return false
	var steps := maxi(1,int(ceil(a.distance_to(b) / 0.4)))
	for index in range(1,steps):
		if not water_clear(a.lerp(b,float(index) / steps)): return false
	if space != null:
		var query := PhysicsShapeQueryParameters3D.new(); query.shape = probe
		query.transform.origin = a; query.motion = b - a; query.collision_mask = 1
		if not space.intersect_shape(query,1).is_empty(): return false
		if a == b: return true
		var fraction := space.cast_motion(query)
		if not fraction.is_empty() and fraction[0] < 0.999: return false
	return true

func anchor(point: Vector3) -> int:
	var best := -1; var distance := INF
	# Closest graph point may lie across a cliff. Require a clear connection.
	var candidates: Array = []
	var cell := Vector2i(int((point.x - map.bounds.position.x) / STEP),int((point.z - map.bounds.position.z) / STEP))
	for y in range(cell.y - 6,cell.y + 7):
		for x in range(cell.x - 6,cell.x + 7):
			if not cells.has(Vector2i(x,y)): continue
			var id: int = cells[Vector2i(x,y)]
			var squared := point.distance_squared_to(graph.get_point_position(id))
			if squared < 144: candidates.append([squared,id])
	candidates.sort_custom(func(a: Array,b: Array) -> bool: return a[0] < b[0])
	for candidate in candidates:
		if candidate[0] >= distance: break
		if segment_clear(point,graph.get_point_position(candidate[1])): best = candidate[1]; distance = candidate[0]; break
	return best

func abstract_route(start: Vector3, finish: Vector3) -> PackedVector3Array:
	# The graph was checked at load time. Hidden travel performs no physics queries.
	if not navigation_ready or graph.get_point_count() == 0: return PackedVector3Array()
	var first := graph.get_closest_point(start)
	var last := graph.get_closest_point(finish)
	var result := graph.get_point_path(first,last)
	if not result.is_empty(): result.append(finish)
	return result

func can_activate(agent: Node3D) -> bool:
	if space == null or agent.dead or agent.stage != "travel": return true
	for collider in agent.body.get_children():
		if not collider is CollisionShape3D: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = collider.shape; query.transform = collider.global_transform
		query.collision_mask = 1; query.exclude = [agent.body.get_rid()]
		if not space.intersect_shape(query,1).is_empty(): return false
	return true

func route(start: Vector3, finish: Vector3) -> PackedVector3Array:
	# Endpoint and shortcut probes revisit many identical samples. Their
	# validity is shared within this request only, never across world changes.
	routing = true; route_water.clear()
	var result := _route(start,finish)
	routing = false; route_water.clear()
	return result

func _route(start: Vector3, finish: Vector3) -> PackedVector3Array:
	if not navigation_ready: return PackedVector3Array()
	# Every possible anchor connection includes its endpoint. If the hull
	# already overlaps scenery, trying scores of anchors cannot succeed.
	if not segment_clear(start,start) or not segment_clear(finish,finish): return PackedVector3Array()
	if segment_clear(start,finish): return PackedVector3Array([finish])
	var first := anchor(start); var last := anchor(finish)
	if first < 0 or last < 0: return PackedVector3Array()
	var result := graph.get_point_path(first,last)
	if result.is_empty(): return result
	result.append(finish)
	# Visibility shortcuts remove staircase routes and connect hatch departures
	# diagonally to cruising water whenever terrain permits.
	var smooth := PackedVector3Array()
	var previous := start
	var index := 0
	var deadline := Time.get_ticks_usec()+SMOOTHING_BUDGET_USEC
	while index < result.size():
		var next := index
		for candidate in range(mini(index + 23,result.size() - 1),index,-1):
			if Time.get_ticks_usec() >= deadline:
				# Remaining graph edges were already clearance-checked. Keep
				# their safe route instead of blocking a frame on more shortcuts.
				smooth.append_array(result.slice(index)); return smooth
			if segment_clear(previous,result[candidate]):
				next = candidate; break
		smooth.append(result[next]); previous = result[next]; index = next + 1
	return smooth

func avoidance(agent: Node3D, forward: Vector3) -> Dictionary:
	var steer := Vector3.ZERO
	var pace := 1.0
	var actors: Array[Node3D] = []
	var exceptions: Array[PhysicsBody3D] = agent.body.get_collision_exceptions()
	for other in traders:
		if other != agent and other.running and not other.dead and other.stage == "travel" and not exceptions.has(other.body): actors.append(other.body)
	var tether: WeakRef = agent.body.get_meta("rescue_pod_pilot") if agent.body.has_meta("rescue_pod_pilot") else null
	if is_instance_valid(player) and (tether == null or tether.get_ref() != player): actors.append(player)
	var velocity: Vector3 = forward * maxf(agent.speed,float(agent.tuning.npc_speed) * 0.6)
	var right := Vector3(forward.z,0,-forward.x).normalized()
	for other in actors:
		var offset: Vector3 = other.global_position - agent.global_position
		if offset.length_squared() > 144 or offset.dot(forward) < -1.0: continue
		var relative: Vector3 = velocity - other.velocity
		var time := clampf(offset.dot(relative) / maxf(0.01,relative.length_squared()),0,3.0)
		var separation := (offset - relative * time).length()
		if separation > 2.2 or time >= 3.0: continue
		# Both head-on vessels pass to their own right, rather than making
		# contradictory random decisions after their hulls touch.
		var urgency := (1.0 - time / 3.0) * (1.0 - separation / 2.2)
		steer += right * maxf(0.4,urgency * 1.8)
		pace = minf(pace,lerpf(0.35,0.85,clampf(offset.length() / 6.0,0,1)))
	if not steer.is_zero_approx() and not segment_clear(agent.global_position,agent.global_position + (forward + steer).normalized() * 2.5):
		steer = Vector3.ZERO; pace = 0.15
	return {"direction":steer,"speed":pace}

func port_by_id(id: int) -> Dictionary:
	for port in ports:
		if int(port.node.get_meta("city_id")) == id: return port
	return {}

func destinations(faction: int) -> Array[int]:
	var result: Array[int] = []
	for port in ports:
		var id := int(port.node.get_meta("city_id"))
		if id != 5 and int(port.race) in [faction,4]: result.append(id)
	return result

func choose_city(agent: Node3D) -> int:
	var options := destinations(int(agent.tuning.npc_faction))
	options.erase(agent.last_city)
	return options[agent.random.randi_range(0,options.size() - 1)] if not options.is_empty() else 0

func set_simulating(value: bool) -> void:
	simulating = value
	for agent in traders:
		agent.running = value
		agent.get_parent().physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON if value else Node.PHYSICS_INTERPOLATION_MODE_OFF
		agent.get_parent().reset_physics_interpolation()

func reset() -> void:
	Survivors.clear(self)
	for wreck in get_tree().get_nodes_in_group("trader_wrecks"):
		if get_parent().is_ancestor_of(wreck): wreck.free()
	if bubbles != null: bubbles.clear()
	for agent in traders:
		agent.mission_owner = ""
		agent.reset()
	if is_instance_valid(roaming_population): roaming_population.reset_population()

func snapshot() -> Dictionary:
	var result := {}
	for agent in traders:
		result[Identity.of(agent)] = {"mission_owner":agent.mission_owner,"pose":preload("res://map_document.gd").encode(agent.get_parent().global_transform),"health":agent.health.remaining,"stage":agent.stage,"destination":agent.destination,"last_city":agent.last_city,"elapsed":agent.elapsed,"wait":agent.wait,"flee":agent.flee,"attacker":[agent.attacker.x,agent.attacker.y,agent.attacker.z],"respawn":agent.respawn,"rng":str(agent.random.state),"start":[agent.transit_start.x,agent.transit_start.y,agent.transit_start.z]}
		result[Identity.of(agent)].route = Array(agent.path).map(func(point: Vector3) -> Array: return [point.x,point.y,point.z])
		result[Identity.of(agent)].health_capacity = agent.health.capacity
		if agent.get("player_attack_announced") is bool: result[Identity.of(agent)]["player_attack_announced"] = agent.player_attack_announced
		if agent.has_meta(Survivors.TAG):
			result[Identity.of(agent)][Survivors.TAG] = agent.get_meta(Survivors.TAG)
			result[Identity.of(agent)]["survivor_hostile"] = agent.engage_player
			if agent.retiring:
				result[Identity.of(agent)]["survivor_retiring"] = true
				result[Identity.of(agent)].destination = agent.dock_destination
	return result

static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 2000: return false
	for key in value:
		if not Identity.valid(key) or not value[key] is Dictionary: return false
		if not value[key].get("mission_owner","") is String or value[key].get("mission_owner","").length() > 256: return false
		var entry: Dictionary = value[key]
		if entry.has("health_capacity"):
			var capacity: Variant = entry.health_capacity
			if not (capacity is float or capacity is int) or not is_finite(capacity) or capacity <= 0 or capacity > 20000: return false
		if entry.has("player_attack_announced") and not entry.player_attack_announced is bool: return false
		if entry.has(Survivors.TAG) and entry[Survivors.TAG] not in Survivors.MODELS: return false
		if entry.has("survivor_hostile") and not entry.survivor_hostile is bool: return false
		if entry.has("survivor_retiring") and not entry.survivor_retiring is bool: return false
		var route_points: Variant = entry.get("route",[])
		if not route_points is Array or route_points.size() > 8192: return false
		for point in route_points:
			if not point is Array or point.size() != 3: return false
			for coordinate in point:
				if not (coordinate is float or coordinate is int) or not is_finite(coordinate) or absf(coordinate) > 100000: return false
		if entry.get("stage") not in ["travel","open","descend","close","berth","exit_open","ascend","exit_close"]: return false
		for field in ["health","elapsed","wait","flee","respawn","destination","last_city"]:
			var number: Variant = entry.get(field)
			if not (number is float or number is int) or not is_finite(number) or number < 0 or number > (20000 if field == "health" else 10000): return false
		for field in ["destination","last_city"]:
			if entry[field] != floorf(entry[field]) or int(entry[field]) not in [0,1,2,3,4,6]: return false
		if entry.stage != "travel" and int(entry.destination) == 0: return false
		for field in ["pose","attacker","start"]:
			var array: Variant = entry.get(field)
			if not array is Array or array.size() != (12 if field == "pose" else 3): return false
			for number in array:
				if not (number is float or number is int) or not is_finite(number) or absf(number) > 100000: return false
		if absf(preload("res://map_document.gd").decode(entry.pose).basis.determinant()) < 0.00001: return false
		if not entry.get("rng") is String or not entry.rng.is_valid_int(): return false
	return true

func restore(value: Dictionary) -> void:
	Survivors.restore(self,value)
	for agent in traders: agent.release_port()
	for agent in traders:
		var entry: Dictionary = value.get(Identity.of(agent),{})
		if entry.is_empty(): continue
		agent.set_local_simulation(true)
		agent.mission_owner = entry.get("mission_owner","")
		if agent.get("player_attack_announced") is bool: agent.player_attack_announced = entry.get("player_attack_announced",false)
		agent.get_parent().global_transform = preload("res://map_document.gd").decode(entry.pose)
		agent.get_parent().reset_physics_interpolation()
		agent.motion.velocity = Vector3.ZERO; agent.motion.bank = 0.0; agent.speed = 0.0; agent.body.velocity = Vector3.ZERO
		agent.progress_goal = Vector3.INF; agent.progress_best = INF; agent.progress_stalled = 0.0
		# Published betas stored health without a capacity. Preserve the damage
		# fraction when applying the balance change, and avoid doubling on reload.
		var old_capacity: float = entry.get("health_capacity",float(agent.tuning.npc_health))
		agent.health.remaining = clampf(float(entry.health)/maxf(0.001,old_capacity),0,1)*agent.health.capacity
		agent.dead = agent.health.remaining <= 0
		agent.stage = entry.stage; agent.destination = int(entry.destination); agent.last_city = int(entry.last_city)
		for field in ["elapsed","wait","flee","respawn"]: agent.set(field,float(entry[field]))
		agent.transit_start = Vector3(entry.start[0],entry.start[1],entry.start[2]); agent.attacker = Vector3(entry.attacker[0],entry.attacker[1],entry.attacker[2])
		agent.random.state = int(entry.rng); agent.path.clear(); agent.port = port_by_id(agent.destination)
		for point in entry.get("route",[]): agent.path.append(Vector3(point[0],point[1],point[2]))
		if agent.destination != 0 and agent.destination not in destinations(int(agent.tuning.npc_faction)):
			agent.destination = 0; agent.stage = "travel"; agent.port = {}
		if agent.stage not in ["travel","berth"]:
			if agent.port.is_empty() or not Access.acquire(agent.port,agent):
				agent.stage = "travel"; agent.destination = 0
			else:
				var fraction := clampf(agent.elapsed / 1.2,0,1)
				Access.open(agent.port,1 - smoothstep(0,1,fraction) if agent.stage in ["close","exit_close"] else smoothstep(0,1,fraction) if agent.stage in ["open","exit_open"] else 1)
				agent.port.collision.collision_layer = 0 if agent.stage in ["descend","close","ascend","exit_close"] else 1
		agent.body.collision_layer = 10 if agent.stage == "travel" and not agent.dead else 0
		agent.get_parent().visible = not agent.dead and agent.stage != "berth"
		agent._update_dock_audio()
		if agent.smoke != null: agent.smoke.set_health(agent.health.remaining * 10)

static func describe_ports(world: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in world.find_children("*","Node3D",true,false):
		if not node.has_meta("city_id"): continue
		var meshes: Array[MeshInstance3D] = []
		preload("res://morph_animation.gd").collect(node,meshes)
		if meshes.is_empty(): continue
		var boxes: Array[AABB] = []
		preload("res://docking_controller.gd")._bounds(node,Transform3D.IDENTITY,boxes)
		var box := boxes[0]
		for other in boxes: box = box.merge(other)
		var centre := box.get_center()
		var floor_height := preload("res://docking_controller.gd")._interior_floor(node,Transform3D.IDENTITY,centre,box.position.y)
		result.append({"node":node,"meshes":meshes,"race":int(node.get_meta("race_id",1)),"entry":node.to_global(Vector3(centre.x,box.end.y,centre.z)) + Vector3.UP * 1.1,"inside":node.to_global(Vector3(centre.x,floor_height,centre.z)) + Vector3.UP * 0.3,"collision":node.get_node("SceneryCollision")})
	return result
