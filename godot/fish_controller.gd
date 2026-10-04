extends CharacterBody3D

const ANIMATION_SPEED := 0.5
const CreatureAnimation = preload("res://creature_animation.gd")
var animation: RefCounted
var turn_speed := 60.0
var pitch_limit := 25.0
var avoidance := Vector3.ZERO
var avoidance_timer := 0.0

var meshes: Array[MeshInstance3D] = []
var home := Vector3.ZERO
var goal := Vector3.ZERO
var bounds := AABB()
var surface_height := 0.0
var radius := 0.5
var swim_speed := 1.3
var animation_time := 0.0
var direction := Vector3.FORWARD
var turn_timer := 0.0
var rng := RandomNumberGenerator.new()
var roam_radius := 10.0
var group_behaviour := "solitary"
var response := "ignore"
var detection_distance := 8.0
var mobility := "swimming"
var population: Node3D
var group_members: Array[Node3D] = []
var defense_timer := 0.0
var startle_duration := 0.3
var startle_speed_multiplier := 2.8
var startle_turn_speed := 720.0
var startle_timer := 0.0
var startle_cooldown := 0.0
var startle_direction := Vector3.ZERO
var fleeing := false
var ground_normal := Vector3.UP
var ground_clearance := 0.1
var walking_animation_rate := 1.0
var ground_span := Vector2(0.2,0.2)
var crawl_stuck_time := 0.0
var crawl_turn_sign := 1.0
var crawl_probe_timer := 0.0
var playback_rate := ANIMATION_SPEED
var ground_initialized := false

func _ready() -> void:
	# Bind playback to the live instance after its visual enters the scene.
	animation = CreatureAnimation.new(get_child(1))
	meshes = animation.meshes
	animation.apply(animation_time)

func _process(_delta: float) -> void:
	if animation == null or not is_physics_processing(): return
	var between_ticks := Engine.get_physics_interpolation_fraction() / float(Engine.physics_ticks_per_second)
	animation.apply(animation_time + between_ticks * playback_rate)

func configure_crawler(size: Vector3) -> void:
	ground_clearance = size.y * 0.5 + 0.02
	ground_span = Vector2(size.x,size.z) * 0.35
	var box := BoxShape3D.new()
	# Legs can straddle small stones without the entire footprint snagging.
	box.size = (size * Vector3(0.6,0.8,0.6)).max(Vector3.ONE * 0.02)
	(get_child(0) as CollisionShape3D).shape = box
	crawl_turn_sign = -1.0 if rng.randf() < 0.5 else 1.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	# A complete stored walking cycle every two seconds at normal speed.
	for mesh in meshes: walking_animation_rate = maxf(walking_animation_rate,(mesh.mesh.get_blend_shape_count() + 1) / 4.0)

func _ground_on_terrain(delta: float) -> void:
	if population == null: return
	var contact := _crawler_contact(global_position)
	if contact.is_empty(): return
	ground_normal = ground_normal.lerp(Vector3(contact.normal),1.0 - exp(-8.0 * delta)).normalized()
	# Offset vertically: offsetting along the normal also pushes a stationary
	# crawler sideways on every tick, causing drift and triangle-edge jitter.
	global_position.y = float(contact.height) + ground_clearance / maxf(0.3,ground_normal.y)
	ground_initialized = true
	_update_orientation()

func _crawler_contact(point: Vector3) -> Dictionary:
	var center: Dictionary = population.floor_contact(point)
	if center.is_empty(): return {}
	var normal := Vector3(center.normal)
	var height := float(center.position.y)
	var forward := Vector3(direction.x,0,direction.z).normalized()
	var side := Vector3(forward.z,0,-forward.x)
	var contacts := 1
	for offset in [forward * ground_span.y,-forward * ground_span.y,side * ground_span.x,-side * ground_span.x]:
		var hit: Dictionary = population.floor_contact(point + offset)
		if hit.is_empty() or Vector3(hit.normal).y < 0.4 or absf(float(hit.position.y) - float(center.position.y)) > 0.5: continue
		normal += Vector3(hit.normal); contacts += 1
		# Extrapolate each foot's supporting plane to the body centre.
		var n := Vector3(hit.normal)
		height = maxf(height,float(hit.position.y) + (n.x * offset.x + n.z * offset.z) / maxf(n.y,0.3))
	normal = normal.normalized()
	return {"height":height,"normal":normal}

func _crawler_step(point: Vector3) -> Dictionary:
	var contact := _crawler_contact(point)
	if contact.is_empty() or Vector3(contact.normal).y < cos(deg_to_rad(55.0)): return {}
	var horizontal := Vector2(point.x - global_position.x,point.z - global_position.z).length()
	var height: float = float(contact.height) + ground_clearance / maxf(Vector3(contact.normal).y,0.3)
	if absf(height - global_position.y) > maxf(0.25,horizontal * 1.5): return {}
	point.y = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = (get_child(0) as CollisionShape3D).shape
	var forward := direction.slide(contact.normal).normalized()
	query.transform = Transform3D(Basis(Vector3(contact.normal).cross(forward).normalized(),contact.normal,forward),point)
	query.collision_mask = 5
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return {}
	contact.position = point
	return contact

func _crawler_steering(desired: Vector3, delta: float) -> Vector3:
	crawl_probe_timer -= delta
	if crawl_probe_timer > 0.0 or population == null: return desired
	crawl_probe_timer = 0.15
	var heading := direction * maxf(0.3,ground_span.y + 0.15)
	if not _crawler_step(global_position + heading).is_empty(): return desired
	for degrees in [45.0,80.0,120.0,160.0]:
		for sign_value in [crawl_turn_sign,-crawl_turn_sign]:
			var next := direction.rotated(Vector3.UP,deg_to_rad(degrees) * sign_value)
			if not _crawler_step(global_position + next * heading.length()).is_empty():
				avoidance = next; avoidance_timer = 0.8
				return next
	return -direction

func _move_crawler(delta: float, speed: float) -> void:
	if population == null: velocity = Vector3.ZERO; return
	var step := _crawler_step(global_position + direction * speed * delta)
	if step.is_empty():
		velocity = Vector3.ZERO; crawl_stuck_time += delta
		if crawl_stuck_time > 0.4:
			avoidance = direction.rotated(Vector3.UP,deg_to_rad(110.0) * crawl_turn_sign)
			avoidance_timer = 1.2; goal = position + avoidance * 3.0; turn_timer = 2.0
			crawl_stuck_time = 0.0; crawl_probe_timer = 0.0
		return
	crawl_stuck_time = 0.0
	velocity = (Vector3(step.position) - global_position) / maxf(delta,0.001)
	global_position = step.position
	ground_normal = ground_normal.lerp(Vector3(step.normal),1.0 - exp(-8.0 * delta)).normalized()
	_update_orientation()

func setup(visual: Node3D, point: Vector3, world_bounds: AABB, surface: float, body_radius: float, seed_value: int) -> void:
	position = point
	home = point
	bounds = world_bounds
	surface_height = surface
	radius = body_radius
	rng.seed = seed_value
	swim_speed = rng.randf_range(0.8, 1.6)
	animation_time = rng.randf_range(0.0, 8.0)
	collision_layer = 0
	collision_mask = 5
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := SphereShape3D.new()
	shape.radius = radius
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	add_child(visual)
	animation = CreatureAnimation.new(visual)
	meshes = animation.meshes
	_choose_goal()
	animation.apply(animation_time)
	_update_orientation()

func _choose_goal() -> void:
	var angle := rng.randf() * TAU
	var spread := sqrt(rng.randf()) * roam_radius
	goal = home + Vector3(cos(angle) * spread, rng.randf_range(-minf(2.0, roam_radius), minf(2.0, roam_radius)), sin(angle) * spread)
	goal.x = clampf(goal.x, bounds.position.x + radius, bounds.end.x - radius)
	goal.z = clampf(goal.z, bounds.position.z + radius, bounds.end.z - radius)
	goal.y = clampf(goal.y, bounds.position.y + radius, surface_height - radius - 0.2)
	turn_timer = rng.randf_range(3.0, 7.0)

func _physics_process(delta: float) -> void:
	if mobility == "crawling" and not ground_initialized: _ground_on_terrain(1.0)
	turn_timer -= delta
	# Arrival belongs to the goal's centre, not the collision sphere size.
	# Large creatures otherwise replace nearby goals every tick.
	var arrival_distance := clampf(roam_radius * 0.15, 0.2, 1.0)
	var goal_distance := Vector2(position.x,position.z).distance_to(Vector2(goal.x,goal.z)) if mobility == "crawling" else position.distance_to(goal)
	if turn_timer <= 0.0 or goal_distance < arrival_distance: _choose_goal()
	var desired := (goal - position).normalized()
	if group_behaviour != "solitary" and not group_members.is_empty():
		var center := Vector3.ZERO
		var alignment := Vector3.ZERO
		var separation := Vector3.ZERO
		var active_members := 0
		var shared_goal := goal
		for other in group_members:
			if not other.get_meta("wildlife_awake",true): continue
			if active_members == 0: shared_goal = other.goal
			active_members += 1
			center += other.position
			alignment += other.direction
			var away: Vector3 = position - other.position
			if away.length_squared() > 0.001 and away.length() < radius * 3.0: separation += away.normalized()
		center /= maxi(1,active_members)
		desired = ((shared_goal - position).normalized() + (center - position).normalized() * 0.6 + separation * 1.5 + alignment.normalized() * (1.0 if group_behaviour == "schooling" else 0.0)).normalized()
	defense_timer = maxf(0.0, defense_timer - delta)
	startle_timer = maxf(0.0, startle_timer - delta)
	startle_cooldown = maxf(0.0, startle_cooldown - delta)
	var speed := swim_speed
	var escaping := false
	if population != null and is_instance_valid(population.player):
		var offset: Vector3 = population.player.global_position - global_position
		if response == "defend" and offset.length() < radius + 0.8: defense_timer = 3.0
		if response == "flee":
			# Hysteresis prevents repeated startles at the detection boundary.
			var threatened := offset.length() < detection_distance * (1.25 if fleeing else 1.0)
			if threatened and not fleeing and startle_cooldown <= 0.0 and mobility == "swimming" and startle_duration > 0.0:
				startle_timer = startle_duration
				startle_cooldown = 2.0
				var away := -offset.normalized() if offset.length_squared() > 0.001 else -direction
				startle_direction = away.rotated(Vector3.UP, deg_to_rad(rng.randf_range(-20.0, 20.0)))
			fleeing = threatened
			if fleeing or startle_timer > 0.0:
				escaping = true
				desired = startle_direction if startle_timer > 0.0 else -offset.normalized()
				speed *= lerpf(1.6, startle_speed_multiplier, smoothstep(0.0, 0.35, startle_timer / maxf(startle_duration, 0.001))) if startle_timer > 0.0 else 1.6
		else:
			fleeing = false; startle_timer = 0.0
		if offset.length() < detection_distance:
			if response == "attack" or (response == "defend" and defense_timer > 0.0): desired = offset.normalized(); speed *= 1.3
	else:
		fleeing = false; startle_timer = 0.0
	# A frightened fish can leave its usual roaming area instead of turning
	# straight back toward the submarine at the group's boundary.
	if not escaping and position.distance_to(home) > roam_radius: desired = (home - position).normalized()
	avoidance_timer = maxf(0.0, avoidance_timer - delta)
	if avoidance_timer > 0.0: desired = avoidance
	if mobility == "crawling": desired.y = 0.0; desired = desired.normalized()
	if mobility == "crawling": desired = _crawler_steering(desired,delta)
	_steer(desired, delta, maxf(turn_speed, startle_turn_speed) if startle_timer > 0.0 else turn_speed)
	playback_rate = (walking_animation_rate if mobility == "crawling" else ANIMATION_SPEED) * (speed / maxf(swim_speed, 0.001) if escaping else 1.0)
	animation_time += delta * playback_rate
	if animation != null: animation.apply(animation_time)
	velocity = direction * speed
	if mobility == "crawling": _move_crawler(delta,speed)
	else: move_and_slide()
	if mobility != "crawling" and get_slide_collision_count() > 0:
		var normal := get_slide_collision(0).get_normal()
		avoidance = (direction + normal * 2.0).normalized()
		avoidance_timer = 1.0
		goal = position + avoidance * 6.0
		turn_timer = 2.0
	# The collider enforces the surface; this clamp also covers oversized steps.
	position.y = minf(position.y, surface_height - radius - safe_margin)
	_update_orientation()

func _steer(desired: Vector3, delta: float, rate: float = -1.0) -> void:
	if direction.length_squared() < 0.01: direction = Vector3.FORWARD
	if desired.length_squared() < 0.0001: desired = direction
	desired = desired.normalized()
	var heading := atan2(direction.x, direction.z)
	var target_heading := atan2(desired.x, desired.z) if Vector2(desired.x, desired.z).length_squared() > 0.0001 else heading
	var step := deg_to_rad(turn_speed if rate < 0.0 else rate) * maxf(0.0, delta)
	heading += clampf(wrapf(target_heading - heading, -PI, PI), -step, step)
	var elevation := asin(clampf(direction.y, -1.0, 1.0))
	var limit := deg_to_rad(pitch_limit) if mobility == "swimming" else 0.0
	var target_elevation := clampf(asin(clampf(desired.y, -1.0, 1.0)), -limit, limit)
	elevation = clampf(move_toward(elevation, target_elevation, step * 0.5), -limit, limit)
	direction = Vector3(sin(heading) * cos(elevation), sin(elevation), cos(heading) * cos(elevation))

func _update_orientation() -> void:
	if mobility == "crawling":
		var forward := direction.slide(ground_normal).normalized()
		if forward.length_squared() > 0.001: basis = Basis(ground_normal.cross(forward).normalized(),ground_normal,forward).orthonormalized()
		return
	# +Z is the legacy model's nose. Bounded pitch keeps the up axis stable,
	# avoiding look_at's vertical singularity and unexpected roll flips.
	rotation = Vector3(-asin(clampf(direction.y, -1.0, 1.0)), atan2(direction.x, direction.z), 0.0)
