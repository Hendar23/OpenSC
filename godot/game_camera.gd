extends RefCounted
## Third-person boom and cockpit camera positioning.

var game: Node3D

func _init(context: Node3D) -> void:
	game = context

const SUB_RENDER_LAYER := 2

func _update_follow_camera(delta: float, snap: bool = false) -> void:
	game.camera.cull_mask |= preload("res://remote_vehicle.gd").RENDER_LAYER
	var pose: Transform3D = game.pilot.global_transform if snap else game.pilot.get_global_transform_interpolated()
	if game.first_person:
		game.camera.global_transform = pose * Transform3D(Basis.IDENTITY,game.cockpit_camera_offset)
		return
	var target: Vector3 = pose.origin + Vector3.UP * 0.35
	var forward: Vector3 = -pose.basis.z
	var heading := atan2(-forward.x, -forward.z)
	var distance := float(game.pilot.movement.settings.camera_distance)
	var tool: Node3D = game.equipment.towing_tool() if game.equipment != null else null
	if tool != null and is_instance_valid(tool.target) and not tool.target.is_queued_for_deletion():
		var cargo: Node3D = tool.target
		var extent: float = pose.origin.distance_to(cargo.global_position)
		if cargo.get("stats") is Dictionary: extent += float(cargo.stats.get("size",0.5)) * 0.5
		distance = game.camera_follow.cargo_distance(distance,extent)
	var desired: Vector3 = game.camera_follow.desired_position(target, heading, game.pilot.velocity, forward,
		float(game.pilot.movement.settings.forward_speed), distance, delta, snap)
	var exclusions: Array[RID] = [game.pilot.get_rid()]
	if tool != null:
		if is_instance_valid(tool.target) and tool.target is CollisionObject3D: exclusions.append(tool.target.get_rid())
		if is_instance_valid(tool.head): exclusions.append(tool.head.get_rid())
	# Solve the full boom before smoothing. Sampling only the already shortened
	# camera position made its own obstruction appear/disappear every frame.
	var offset: Vector3 = desired - target
	var query := PhysicsRayQueryParameters3D.create(target,desired,1,exclusions)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(query)
	var allowed: float = maxf(0.02,target.distance_to(hit.position) - 0.08) if not hit.is_empty() else offset.length()
	var boom: float = game.camera_follow.clear_distance(offset.length(),allowed,delta,snap)
	var limited: Vector3 = target + offset.normalized() * boom
	var next: Vector3 = limited if snap else game.camera.global_position.lerp(limited,1.0-exp(-7.0*delta))
	query.to = next
	hit = game.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): next = target + (next-target).normalized() * maxf(0.02,target.distance_to(hit.position)-0.05)
	next.y = minf(next.y, game.pilot.surface_height - 0.2)
	game.camera.global_position = next
	if next.distance_to(target) > 0.01: game.camera.look_at(target, Vector3.UP)

func _set_camera_mode(cockpit: bool) -> void:
	if game.pilot == null: return
	if game.pilot.dead: cockpit = false
	game.first_person = cockpit
	if cockpit: game.camera.cull_mask &= ~SUB_RENDER_LAYER
	else: game.camera.cull_mask |= SUB_RENDER_LAYER
	game._update_follow_camera(0.0,true)
	if is_instance_valid(game.first_person_cockpit): game.first_person_cockpit.refresh()
