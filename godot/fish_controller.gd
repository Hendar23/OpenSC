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
	turn_timer -= delta
	# Arrival belongs to the goal's centre, not the collision sphere size.
	# Large creatures otherwise replace nearby goals every tick.
	var arrival_distance := clampf(roam_radius * 0.15, 0.2, 1.0)
	if turn_timer <= 0.0 or position.distance_to(goal) < arrival_distance: _choose_goal()
	var desired := (goal - position).normalized()
	if group_behaviour != "solitary" and not group_members.is_empty():
		var center := Vector3.ZERO
		var alignment := Vector3.ZERO
		var separation := Vector3.ZERO
		for other in group_members:
			center += other.position
			alignment += other.direction
			var away: Vector3 = position - other.position
			if away.length_squared() > 0.001 and away.length() < radius * 3.0: separation += away.normalized()
		center /= group_members.size()
		var shared_goal: Vector3 = group_members[0].goal
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
	_steer(desired, delta, maxf(turn_speed, startle_turn_speed) if startle_timer > 0.0 else turn_speed)
	animation_time += delta * ANIMATION_SPEED * (speed / maxf(swim_speed, 0.001) if escaping else 1.0)
	if animation != null: animation.apply(animation_time)
	velocity = direction * speed
	move_and_slide()
	if mobility == "crawling" and population != null:
		var grounded: Vector3 = population.floor_point(position, radius)
		if grounded.is_finite(): position.y = grounded.y
	if get_slide_collision_count() > 0:
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
	# +Z is the legacy model's nose. Bounded pitch keeps the up axis stable,
	# avoiding look_at's vertical singularity and unexpected roll flips.
	rotation = Vector3(-asin(clampf(direction.y, -1.0, 1.0)), atan2(direction.x, direction.z), 0.0)
