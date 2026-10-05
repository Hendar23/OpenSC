extends SceneTree
const Game = preload("res://game.gd")
const Mods = preload("res://mod_registry.gd")
const Document = preload("res://map_document.gd")
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Mods.initialize(false)
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	if not game.startup_complete: quit(1); return
	game.set_process(false); game.set_physics_process(false)
	var pop: Node3D = game.wildlife; pop.streaming = false; pop.player = null
	for species in pop.document.species: species.random_spawn = false
	var crab_species: Dictionary = pop.document.species.filter(func(entry: Dictionary) -> bool: return entry.model == "CRAB")[0]
	var random := RandomNumberGenerator.new(); random.seed = 11371
	pop.document.groups = []
	for index in range(24):
		var home: Vector3 = pop._random_home(crab_species,random)
		if home.is_finite(): pop.document.groups.append({"id":"crab_walk_%d" % index,"species":crab_species.id,"position":Document.array(home),"chance":100.0,"count_min":1,"count_max":1,"radius":8.0})
	pop.reroll(false)
	var crabs := pop.get_children(); var travelled := {}; var positions := {}
	if crabs.size() < 20:
		failures += 1; push_error("Expected at least twenty actual-world crabs for the movement regression")
	for crab in crabs:
		crab.set_physics_process(false); travelled[crab] = 0.0; positions[crab] = crab.global_position
	for frame in range(600):
		for crab in crabs:
			crab._physics_process(1.0 / 60.0)
			travelled[crab] += Vector2(crab.global_position.x,crab.global_position.z).distance_to(Vector2(positions[crab].x,positions[crab].z))
			positions[crab] = crab.global_position
	for crab in crabs:
		if travelled[crab] < crab.swim_speed * 2.0:
			failures += 1
			var contact: Dictionary = crab._crawler_contact(crab.global_position)
			var query := PhysicsShapeQueryParameters3D.new(); query.shape = crab.get_child(0).shape; query.transform = crab.global_transform; query.collision_mask = 5
			var hits: Array = crab.get_world_3d().direct_space_state.intersect_shape(query,8)
			var names := []
			for hit in hits: names.append(str(hit.collider.get_path()))
			print("STUCK ",crab.name," travelled=",travelled[crab]," speed=",crab.swim_speed," position=",crab.global_position," contact=",contact," body=",query.shape.size," hits=",names)
	print("Actual-world crabs: ",crabs.size()," tested; ",failures," failed to walk")
	game.queue_free(); await process_frame
	quit(1 if failures else 0)
