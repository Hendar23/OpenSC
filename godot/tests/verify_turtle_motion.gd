extends SceneTree
const Wildlife = preload("res://wildlife_population.gd")
const Creatures = preload("res://creature_loader.gd")
const Paths = preload("res://asset_paths.gd")
const Fish = preload("res://fish_controller.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func _run() -> void:
	Mods.initialize(false)
	var world := Node3D.new(); root.add_child(world)
	world.set_meta("bounds", AABB(Vector3(-100, 0, -100), Vector3(200, 80, 200)))
	world.set_meta("surface_height", 80.0)
	var pop := Wildlife.new(); pop.simulating = false; world.add_child(pop)
	pop.setup(world, Paths.find_game_folder(), {"seed": 42, "species": [{"id": "turtle", "model": "TURTLE", "name": "Turtle", "mobility": "swimming", "group_behaviour": "solitary", "response": "ignore", "speed": 1.3, "detection": 8.0, "scale_min": 100, "scale_max": 100}], "groups": [{"id": "turtles", "name": "Turtles", "species": "turtle", "position": [0, 40, 0], "radius": 10.0, "chance": 100, "count_min": 1, "count_max": 1}]})
	check(pop.get_child_count() == 1, "Turtle spawns with unchanged map properties")
	var turtle: CharacterBody3D = pop.get_child(0)
	check(turtle.animation.parts.size() == 5 and turtle.animation.meshes.is_empty(), "Original turtle uses five rigid animation parts rather than missing morph poses")
	var flipper: Node3D = turtle.animation.parts[0].node
	var rest: Basis = turtle.animation.parts[0].rest
	turtle.animation.apply(0.0); check(flipper.basis.is_equal_approx(rest), "Procedural flipper cycle starts from its supplied pivot")
	turtle.animation.apply(0.3); check(not flipper.basis.is_equal_approx(rest), "Turtle flipper moves during its swim cycle")
	var pivot := flipper.position
	turtle.animation.apply(0.7); check(flipper.position.is_equal_approx(pivot), "Animation retains each flipper's original pivot")
	var visual: Node3D = turtle.get_child(1)
	var boxes: Array[AABB] = []
	Creatures._collect_bounds(visual, visual.transform, boxes)
	var box := boxes[0]
	for i in range(1, boxes.size()): box = box.merge(boxes[i])
	check(box.get_center().length() < 0.2, "Offset turtle model is centered on its movement and collision body")
	var delta := 1.0 / 60.0
	var max_step := 0.0
	for target in [Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD]:
		for frame in range(180):
			var previous: Vector3 = turtle.direction
			turtle._steer(target, delta); turtle._update_orientation()
			max_step = maxf(max_step, previous.angle_to(turtle.direction))
			if absf(turtle.direction.y) > sin(deg_to_rad(25.0)) + 0.0001: check(false, "Pitch remains bounded for vertical and reversing goals"); break
			if turtle.basis.y.y < cos(deg_to_rad(25.0)) - 0.0001: check(false, "Turtle remains upright during turns"); break
	check(max_step <= deg_to_rad(60.0) * delta * 1.2, "Turns stay bounded rather than taking an arbitrary vertical 180-degree path")
	turtle.mobility = "crawling"; turtle._steer(Vector3.UP, delta)
	check(is_zero_approx(turtle.direction.y), "Crawlers steer horizontally")
	# A real collision must redirect the goal without snapping the displayed pose.
	var wall := StaticBody3D.new(); world.add_child(wall)
	var wall_shape := CollisionShape3D.new(); var wall_box := BoxShape3D.new(); wall_box.size = Vector3(10, 10, 1)
	wall_shape.shape = wall_box; wall.add_child(wall_shape); wall.position = Vector3(20, 40, -1)
	var probe := Fish.new(); var probe_visual := Node3D.new()
	probe.setup(probe_visual, Vector3(20, 40, 0), world.get_meta("bounds"), 80, 0.25, 1)
	world.add_child(probe); probe.goal = Vector3(20, 40, -20); probe.home = Vector3(20, 40, 0); probe.swim_speed = 1.3; probe.turn_timer = 10
	var contacted := false; var biggest_rotation := 0.0
	for frame in range(90):
		var previous_pose := probe.basis.get_rotation_quaternion()
		await physics_frame
		biggest_rotation = maxf(biggest_rotation, previous_pose.angle_to(probe.basis.get_rotation_quaternion()))
		if probe.get_slide_collision_count() > 0: contacted = true
	check(contacted and biggest_rotation < deg_to_rad(2.0), "Obstacle contact changes course gradually without snapping the hull")
	world.queue_free(); await process_frame
	print("Turtle motion verification: %d checks, %d failures; maximum steering step=%.3f degrees" % [checks, failures, rad_to_deg(max_step)])
	quit(1 if failures else 0)
