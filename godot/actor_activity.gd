extends Node
## One visibility snapshot for ambient actors and all active gameplay cameras.
var game: Node
var cameras: Array[Camera3D] = []
var views: Array[Dictionary] = []
var submarines: Node
var ground: Node
var turrets: Node
var clock := 0.0

func _physics_process(delta: float) -> void:
	clock += delta
	if clock < 0.1: return
	var step := clock; clock = 0.0
	refresh_views()
	update_actors(step)

func refresh_views() -> void:
	if is_instance_valid(game):
		cameras.clear()
		if is_instance_valid(game.camera): cameras.append(game.camera)
		var hud: Node = game.cockpit_hud
		if is_instance_valid(hud) and is_instance_valid(hud.bottom_view) and hud.bottom_view.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			var feed: Camera3D = hud.bottom_view.get_camera_3d()
			if feed != null: cameras.append(feed)
	views.clear()
	for camera in cameras:
		if is_instance_valid(camera): views.append({"origin":camera.global_position,"range":camera.far,"planes":camera.get_frustum()})

func nearby(point: Vector3, radius: float = 0.0, margin: float = 0.0) -> bool:
	for view in views:
		if point.distance_squared_to(view.origin) <= pow(float(view.range) + radius + margin,2): return true
	return false

func in_sight(point: Vector3, radius: float = 0.0) -> bool:
	for view in views:
		if point.distance_squared_to(view.origin) > pow(float(view.range) + radius,2): continue
		var inside := true
		for plane: Plane in view.planes:
			if plane.distance_to(point) > radius: inside = false; break
		if inside: return true
	return false

func update_actors(delta: float) -> void:
	if views.is_empty(): return
	if is_instance_valid(turrets):
		for turret in turrets.turrets:
			turret.set_local_simulation(nearby(turret.global_position,turret.visibility_radius,2.0))
	if is_instance_valid(ground):
		for vehicle in ground.vehicles:
			vehicle.set_local_simulation(in_sight(vehicle.global_position,vehicle.bounds.size.length() * 0.5))
	if is_instance_valid(submarines):
		for agent in submarines.traders:
			# Keep nearby water continuous when turning the camera. No distant combat.
			var local := nearby(agent.global_position,agent.bounds.size.length() * 0.5,2.0)
			if local and not agent.local_simulation: local = submarines.can_activate(agent)
			agent.set_local_simulation(local)
			if not local and submarines.simulating: agent.advance_abstract(delta)
