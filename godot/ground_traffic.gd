extends Node
const Identity = preload("res://entity_identity.gd")
var events: RefCounted
const Vehicle = preload("res://ground_vehicle.gd")
var vehicles: Array[Node3D] = []
var bubbles: Node3D
var simulating := true
func setup(world: Node3D, folder: String, player: Node3D = null, alert: Callable = Callable()) -> void:
	bubbles = preload("res://propeller_bubbles.gd").new(); bubbles.name = "TrafficBubbles"; add_child(bubbles)
	var texture := preload("res://clump_loader.gd")._load_texture(folder,"BUBBLE","BUBBLEM",{})
	bubbles.configure(texture)
	bubbles.surface_height = float(world.get_meta("surface_height",INF))
	var frames := preload("res://mine_explosion.gd").load_frames(folder)
	var sound := preload("res://submarine_weapons.gd")._sound(folder,"audio.object.mine.explosion","EXPLODE1")
	for node in world.find_children("GroundVehicle","Node3D",true,false):
		if not node is Vehicle: continue
		node.player = player; node.bubble_trail = bubbles; node.explosion_frames = frames; node.explosion_sound = sound
		node.bubble_texture = texture
		if alert.is_valid(): node.attacked.connect(alert)
		vehicles.append(node)
		if events != null: node.destroyed.connect(events.entity_destroyed.emit)
	var exclusions: Array[RID] = []
	for vehicle in vehicles: exclusions.append(vehicle.body.get_rid())
	for vehicle in vehicles:
		vehicle.navigation_exclusions = exclusions; vehicle.reset(); vehicle.running = simulating
func set_simulating(value: bool) -> void:
	simulating = value
	for vehicle in vehicles: vehicle.running = value
func reset() -> void:
	for wreck in get_tree().get_nodes_in_group("ground_vehicle_wrecks"):
		if get_parent().is_ancestor_of(wreck): wreck.free()
	if bubbles != null: bubbles.clear()
	for vehicle in vehicles:
		vehicle.mission_owner = ""
		vehicle.reset()
func snapshot() -> Dictionary:
	var result := {}
	for vehicle in vehicles:
		result[Identity.of(vehicle)] = {"mission_owner":vehicle.mission_owner,"pose":preload("res://map_document.gd").encode(vehicle.get_parent().global_transform),"health":vehicle.health.remaining,"wait":vehicle.waiting,"respawn":vehicle.respawn_remaining,"rng":str(vehicle.random.state),"goal":[vehicle.destination.x,vehicle.destination.y,vehicle.destination.z] if vehicle.destination.is_finite() else []}
	return result
static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 2000: return false
	for key in value:
		if not Identity.valid(key) or not value[key] is Dictionary: return false
		if not value[key].get("mission_owner","") is String or value[key].get("mission_owner","").length() > 256: return false
		var entry: Dictionary = value[key]
		for property in ["health","wait","respawn"]:
			var amount: Variant = entry.get(property)
			if not (amount is float or amount is int) or not is_finite(amount) or amount < 0 or amount > 10000: return false
		for field in ["pose","goal"]:
			var array: Variant = entry.get(field)
			if not array is Array or array.size() not in ([12] if field == "pose" else [0,3]): return false
			for number in array:
				if not (number is float or number is int) or not is_finite(number) or absf(number) > 100000: return false
		if absf(preload("res://map_document.gd").decode(entry.pose).basis.determinant()) < 0.00001: return false
		if not entry.get("rng") is String or not entry.rng.is_valid_int(): return false
	return true
func restore(value: Dictionary) -> void:
	for vehicle in vehicles:
		var saved: Dictionary = value.get(Identity.of(vehicle),{})
		if saved.is_empty(): continue
		vehicle.set_local_simulation(true)
		vehicle.mission_owner = saved.get("mission_owner","")
		var pose := preload("res://map_document.gd").decode(saved.pose)
		if Vector2(pose.origin.x - vehicle.home.origin.x,pose.origin.z - vehicle.home.origin.z).length() <= float(vehicle.tuning.npc_radius) + 1:
			vehicle.get_parent().global_transform = pose
			vehicle.grounded = true
		vehicle.health.remaining = minf(float(saved.health),float(vehicle.tuning.npc_health)); vehicle.dead = vehicle.health.remaining <= 0
		vehicle.get_parent().visible = not vehicle.dead; vehicle.body.collision_layer = 0 if vehicle.dead else 9
		vehicle.waiting = float(saved.wait); vehicle.respawn_remaining = float(saved.respawn); vehicle.random.state = int(saved.rng)
		if saved.goal.size() == 3: vehicle.destination = Vector3(saved.goal[0],saved.goal[1],saved.goal[2])
