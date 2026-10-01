extends CharacterBody3D

const MorphAnimation = preload("res://morph_animation.gd")
const ANIMATION_SPEED := 0.5

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
	MorphAnimation.collect(visual, meshes)
	_choose_goal()
	MorphAnimation.apply(meshes, animation_time)

func _choose_goal() -> void:
	goal = home + Vector3(rng.randf_range(-10.0, 10.0), rng.randf_range(-2.0, 2.0), rng.randf_range(-10.0, 10.0))
	goal.x = clampf(goal.x, bounds.position.x + radius, bounds.end.x - radius)
	goal.z = clampf(goal.z, bounds.position.z + radius, bounds.end.z - radius)
	goal.y = clampf(goal.y, bounds.position.y + radius, surface_height - radius - 0.2)
	turn_timer = rng.randf_range(3.0, 7.0)

func _physics_process(delta: float) -> void:
	animation_time += delta * ANIMATION_SPEED
	MorphAnimation.apply(meshes, animation_time)
	turn_timer -= delta
	if turn_timer <= 0.0 or position.distance_to(goal) < radius + 1.0: _choose_goal()
	var desired := (goal - position).normalized()
	direction = direction.lerp(desired, minf(1.0, delta * 1.5)).normalized()
	if direction.length_squared() < 0.01: direction = Vector3.FORWARD
	velocity = direction * swim_speed
	move_and_slide()
	if get_slide_collision_count() > 0:
		var normal := get_slide_collision(0).get_normal()
		direction = (direction + normal * 2.0).normalized()
		goal = position + direction * 6.0
		turn_timer = 2.0
	# The collider enforces the surface; this clamp also covers oversized steps.
	position.y = minf(position.y, surface_height - radius - safe_margin)
	if absf(direction.y) < 0.99:
		# Original fish face +Z; Godot's default look_at faces -Z.
		look_at(global_position + direction, Vector3.UP, true)
