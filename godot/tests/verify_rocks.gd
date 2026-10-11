extends SceneTree
const Definitions = preload("res://object_definitions.gd")
const Document = preload("res://map_document.gd")
const Population = preload("res://object_population.gd")
const Rock = preload("res://rock_body.gd")
class Player extends Node3D:
	var active := true
	var controls_enabled := true
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	preload("res://mod_registry.gd").initialize(false)
	var data := Document.empty()
	var rocks := Definitions.rock_types()
	check(Document.valid(data),"Rock types coexist with existing map schema")
	Definitions.ensure(data)
	check(data.object_types.filter(func(entry: Dictionary) -> bool: return entry.get("behavior","") == "rock").size() == 3,"Defaults register exactly three rock types without duplication")
	for index in range(3):
		data.object_groups.append({"id":"rock_test_"+str(index),"name":rocks[index].name,"type":rocks[index].id,"position":[index*4,-2,0],"count":1,"radius":0,"rotation":[0,30,0]})
	var world := Node3D.new(); root.add_child(world)
	world.set_meta("surface_height",0.0)
	var ground := StaticBody3D.new(); ground.position.y = -6
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(100,1,100); shape.shape = box; ground.add_child(shape); world.add_child(ground)
	var pop := Population.new(); world.add_child(pop)
	pop.setup(ProjectSettings.globalize_path("res://../Original Sub Culture"),data)
	check(pop.get_child_count() == 3,"All original rock models instantiate from object groups")
	for index in range(3):
		var body: RigidBody3D = pop.get_child(index)
		check(body is Rock and body.mass == rocks[index].mass,"Original callback mass: " + rocks[index].name)
		check(is_equal_approx(body.get_child(0).get_meta("diameter"),rocks[index].size),"Original model diameter: " + rocks[index].name)
		check(body.get_child(1).shape is ConvexPolygonShape3D and body.collision_layer == 9,"Solid convex collision: " + rocks[index].name)
		check(body.freeze == rocks[index].immovable and not body.get_meta("metal_tow_target") and body.get_meta("grapple_tow_target") == not rocks[index].immovable,"Mobility and towing: " + rocks[index].name)
	for tick in range(100): await physics_frame
	check(pop.get_child(0).position.y < -2 and pop.get_child(1).position.y < -2,"Smaller rocks settle through water")
	check(pop.get_child(2).position.is_equal_approx(Vector3(8,-2,0)),"Large rock remains at its authored position")
	var small: RigidBody3D = pop.get_child(0)
	var old_position := small.position
	small.apply_central_impulse(Vector3(3,0,0))
	for tick in range(15): await physics_frame
	check(small.position.x > old_position.x,"Movable rocks respond to impulses")
	var saved: Array = JSON.parse_string(JSON.stringify(pop.snapshot()))
	check(saved.size() == 3 and Population.valid_snapshot(saved),"Rock state survives JSON save validation")
	pop.restore_snapshot(saved)
	check(pop.snapshot().size() == 3 and pop.get_child(2).freeze,"Restoring rocks preserves fixed large-rock collision")
	check(pop.get_child(0).transform.is_equal_approx(Document.decode(saved[0].pose)) and pop.get_child(0).linear_velocity.is_equal_approx(Document.vector(saved[0].velocity)),"Restore preserves rock pose and motion")
	pop.reset_population()
	check(pop.get_child(0).position.is_equal_approx(Vector3(0,-2,0)),"New game restores authored rocks")
	check(pop.salvage_types.keys().all(func(id: String) -> bool: return not pop.rock_types.has(id)),"Rocks do not silently join salvage random spawning")
	var bad := saved.duplicate(true); bad[0].stats.immovable = "yes"
	check(not Population.valid_snapshot(bad),"Invalid mobility flag is rejected")
	bad = saved.duplicate(true); bad[0].shard = 1
	check(not Population.valid_snapshot(bad),"Rocks cannot become crystal shards")
	# Isolate rocks on a broad flat seabed to exercise actual placement queries.
	pop.restore_snapshot([]); pop.thorium_types.clear(); pop.salvage_types.clear()
	pop.world_bounds = AABB(Vector3(-50,-10,-50),Vector3(100,20,100))
	pop.random.seed = 42
	await physics_frame
	pop.populate_startup()
	var startup := pop.snapshot()
	check(startup.filter(func(entry: Dictionary) -> bool: return entry.stats.id == "small_rock").size() == 12 and startup.filter(func(entry: Dictionary) -> bool: return entry.stats.id == "rock").size() == 12,"New Game places twelve small and twelve medium rocks on clear terrain")
	check(startup.all(func(entry: Dictionary) -> bool: return entry.stats.id != "large_rock"),"Large rocks are excluded from random startup placement")
	check(pop.get_children().all(func(body: RigidBody3D) -> bool: return is_equal_approx(body.position.y,-5.5 + float(body.stats.size)*0.5 + 0.03) and absf(body.position.x) <= 50 and absf(body.position.z) <= 50),"Startup rocks span map bounds and rest at seabed height")
	pop.restore_snapshot(startup)
	check(pop.snapshot().size() == 24,"Loading saved startup rocks preserves their population")
	pop.restore_snapshot([])
	var pilot := Player.new(); world.add_child(pilot); pop.player = pilot
	for minute in range(10): pop._physics_process(60.0)
	check(pop.get_child_count() == 0,"Removed rocks do not replenish after startup")
	pop.simulating = false; pop.populate_startup()
	check(pop.get_child_count() == 0,"Editor previews do not generate random rocks")
	world.free()
	print("Rock checks: %d, failures: %d" % [checks,failures])
	quit(1 if failures else 0)
