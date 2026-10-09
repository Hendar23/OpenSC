extends SceneTree
const Population = preload("res://object_population.gd")
const Document = preload("res://map_document.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	preload("res://mod_registry.gd").initialize(false)
	var world := Node3D.new(); root.add_child(world)
	world.set_meta("bounds",AABB(Vector3(-200,-30,-200),Vector3(400,60,400))); world.set_meta("surface_height",0.0)
	var floor_body := StaticBody3D.new(); floor_body.position.y = -21; world.add_child(floor_body)
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(400,2,400); shape.shape = box; floor_body.add_child(shape)
	var document := Document.empty()
	for type in document.object_types:
		if type.get("behavior","") in ["thorium","salvage"]: type.spawn_chance = 0; type.maximum_population = 0
	var population := Population.new(); world.add_child(population); population.setup(preload("res://asset_paths.gd").find_game_folder(),document,true); population.set_physics_process(false)
	population.random.seed = 42
	await physics_frame; await physics_frame
	population.populate_startup()
	check(population.get_child_count() == 72,"Twelve startup attempts per each of six types on unobstructed terrain")
	for definition in population.thorium_types.values() + population.salvage_types.values():
		var items: Array = population.get_children().filter(func(body: Node) -> bool: return body.stats.id == definition.id)
		check(items.size() == 12,"Startup ignores later cap and chance: " + str(definition.id))
		if definition.behavior == "thorium":
			check(items.all(func(body: Node3D) -> bool: return is_equal_approx(body.position.y,-19.47)),"Crystals start resting on terrain: " + str(definition.id))
		else:
			check(items.any(func(body: Node3D) -> bool: return body.position.y > -19) and items.all(func(body: Node3D) -> bool: return is_equal_approx(body.position.y,-19.47) or (body.position.y >= -14.471 and body.position.y <= -10.719)),"Other salvage uses terrain or recovered height range: " + str(definition.id))
	check(population.get_children().any(func(body: Node3D) -> bool: return Vector2(body.position.x,body.position.z).length() > 100),"Startup covers distant map areas")
	var saved: Array = JSON.parse_string(JSON.stringify(population.snapshot())); population.restore_snapshot(saved)
	check(population.snapshot().size() == 72,"Save/load restores startup population without generating another batch")
	population.restore_snapshot([])
	population.world_bounds = AABB(Vector3(100,-30,100),Vector3(99,60,99))
	var crystal: Dictionary = population.thorium_types.thorium; crystal.maximum_population = 6
	population._random_drop(crystal); population._random_drop(crystal); population._random_drop(crystal)
	check(population.get_child_count() == 2,"Later drops respect crystal and shard reservation limit")
	check(population.get_children().all(func(body: Node3D) -> bool: return body.position.x >= 100 and body.position.z >= 100 and body.position.y == 5),"Later drops use distant map-wide positions above water without a nearby player")
	population.restore_snapshot([])
	population.dock_spawn_exclusions = [{"center":Vector2(150,150),"radius":200.0}]
	population.populate_startup(); population._random_drop(crystal)
	check(population.get_child_count() == 0,"Startup and ongoing drops preserve dock exclusion")
	population.dock_spawn_exclusions.clear(); floor_body.free(); await physics_frame; await physics_frame
	population.populate_startup(); population._random_drop(crystal)
	check(population.get_child_count() == 0,"Failed terrain placement never creates unsafe items")
	world.free()
	print("Salvage startup and map-wide drops: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
