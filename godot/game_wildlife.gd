extends RefCounted
## Wildlife resets at docks and density control.

var game: Node3D

func _init(context: Node3D) -> void:
	game = context

const Creatures = preload("res://creature_loader.gd")
const Wildlife = preload("res://wildlife_population.gd")

func _reset_docked_wildlife() -> void:
	# Cover the world before changing populations, after the doors finish closing.
	game._set_map_open(false)
	if game.docked_screen != null: game.docked_screen.visible = true
	if game.wildlife != null:
		game.wildlife.reroll()
	else:
		# Until a map is authored, reroll the provisional population as well.
		game._reset_provisional_wildlife()

func _reset_provisional_wildlife() -> void:
	game.world_root.set_meta("wildlife_generation", int(game.world_root.get_meta("wildlife_generation", 0)) + 1)
	var population: Node = game.world_root.get_node_or_null("AmbientFish")
	if population == null: return
	var random := RandomNumberGenerator.new()
	random.seed = 8675309 + int(game.world_root.get_meta("wildlife_generation")) * 104729
	for fish in population.get_children():
		fish.health = fish.max_health
		if fish.dead:
			fish.dead = false; fish.health = fish.max_health; fish.visible = true; fish.collision_layer = 8; fish.collision_mask = 7
			fish.get_child(0).set_deferred("disabled",false); fish.set_physics_process(true); fish.set_process(true)
		for attempt in range(24):
			var point: Vector3 = fish.home + Vector3(random.randf_range(-3, 3), random.randf_range(-0.5, 0.5), random.randf_range(-3, 3))
			if point.y + fish.radius >= game.pilot.surface_height or not Creatures._clear(game.world_root, point, fish.radius): continue
			fish.position = point
			fish.rng.seed = random.randi()
			fish._choose_goal()
			fish.reset_physics_interpolation()
			break

func _update_wildlife_density() -> void:
	game.wildlife_density_label.text = "Wildlife density: %.0f%%" % game.wildlife_density_slider.value
	if game.wildlife != null: game.wildlife.set_density(game.wildlife_density_slider.value / 100.0)
