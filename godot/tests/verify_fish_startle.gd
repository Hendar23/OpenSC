extends SceneTree
const Fish = preload("res://fish_controller.gd")
const Wildlife = preload("res://wildlife_population.gd")
const Document = preload("res://map_document.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _run() -> void:
	var world := Node3D.new(); root.add_child(world)
	world.set_meta("bounds", AABB(Vector3(-100, 0, -100), Vector3(200, 80, 200)))
	world.set_meta("surface_height", 80.0)
	var player := Node3D.new(); world.add_child(player)
	var pop := Wildlife.new(); world.add_child(pop); pop.player = player; pop.world = world
	var fish := Fish.new()
	fish.setup(Node3D.new(), Vector3(0, 40, 0), AABB(Vector3(-100, 0, -100), Vector3(200, 80, 200)), 80, 0.2, 42)
	world.add_child(fish); fish.set_physics_process(false)
	fish.population = pop; fish.response = "flee"; fish.swim_speed = 1.0; fish.roam_radius = 1.0
	fish.direction = Vector3.FORWARD; fish.goal = fish.position + Vector3.FORWARD * 20; fish.turn_timer = 100
	player.position = fish.position + Vector3.FORWARD * 3
	await physics_frame
	var previous := fish.direction
	var previous_animation := fish.animation_time
	fish._physics_process(1.0 / 60.0)
	check(fish.startle_timer > 0.0 and fish.fleeing, "Entering detection range triggers a startle")
	check(rad_to_deg(previous.angle_to(fish.direction)) > 5.0 and rad_to_deg(previous.angle_to(fish.direction)) <= 12.1, "Startle turns sharply without instantaneous rotation")
	check(is_equal_approx(fish.velocity.length(), 2.8), "Startle has a brief burst of speed")
	check(fish.animation_time - previous_animation > 1.0 / 60.0, "Swim animation accelerates with the dart")
	var max_step := 0.0
	for frame in range(24):
		player.position = fish.position + Vector3.FORWARD * 3
		previous = fish.direction; fish._physics_process(1.0 / 60.0)
		max_step = maxf(max_step, previous.angle_to(fish.direction))
	check(fish.direction.dot(Vector3.BACK) > 0.8, "Fish quickly faces away from threat")
	check(fish.startle_timer == 0.0 and is_equal_approx(fish.velocity.length(), 1.6), "Burst settles into normal fleeing speed")
	check(max_step < deg_to_rad(13.0) and fish.basis.y.y >= cos(deg_to_rad(25.0)), "Startled fish keeps upright, bounded turns")
	for frame in range(180):
		player.position = fish.position + Vector3.FORWARD * 3
		fish._physics_process(1.0 / 60.0)
	check(fish.startle_timer == 0.0, "Nearby sub does not cause repeated startle jitter")
	fish.home = fish.position + Vector3.FORWARD * 20
	player.position = fish.position + Vector3.FORWARD * 3
	fish._physics_process(0.1)
	check(fish.direction.dot(Vector3.BACK) > 0.8, "Fleeing overrides returning home outside roaming area")
	player.position = fish.position + Vector3.FORWARD * 8.5; fish._physics_process(0.01)
	check(fish.fleeing, "Detection hysteresis avoids flicker near boundary")
	player.position = fish.position + Vector3.FORWARD * 11; fish._physics_process(0.01)
	check(not fish.fleeing, "Fish calms once submarine leaves")
	player.position = fish.position + Vector3.FORWARD * 3; fish._physics_process(0.01)
	check(fish.startle_timer > 0.0, "Returning submarine can startle fish again")
	player.position = fish.position + Vector3.FORWARD * 11; fish._physics_process(0.05)
	player.position = fish.position + Vector3.FORWARD * 3; fish._physics_process(0.05)
	check(fish.startle_timer < fish.startle_duration, "Cooldown prevents immediate re-entry retrigger")
	fish.response = "ignore"; fish._physics_process(0.01)
	check(fish.startle_timer == 0.0 and not fish.fleeing and is_equal_approx(fish.velocity.length(), 1.0), "Other responses retain normal movement")
	fish.response = "flee"; fish.startle_duration = 0.0; fish.startle_cooldown = 0.0; fish._physics_process(0.01)
	check(fish.fleeing and fish.startle_timer == 0.0 and is_equal_approx(fish.velocity.length(), 1.6), "Zero duration disables startle and keeps normal flee")
	fish.response = "ignore"; fish._physics_process(0.01)
	fish.response = "flee"; fish.mobility = "crawling"; fish.startle_duration = 0.3; fish._physics_process(0.01)
	check(fish.startle_timer == 0.0 and is_zero_approx(fish.direction.y), "Crawlers retain grounded movement")
	var data := Document.load_active()
	check(Document.valid(data), "Existing saved map needs no migration")
	data.species[0].startle_duration = 0.2; data.species[0].startle_speed_multiplier = 3.0; data.species[0].startle_turn_speed = 900.0
	check(Document.valid(JSON.parse_string(JSON.stringify(data))), "Custom species startle settings round trip as JSON")
	data.species[0].startle_duration = -0.1; check(not Document.valid(data), "Invalid startle settings rejected")
	world.queue_free(); await process_frame
	print("Fish startle verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
