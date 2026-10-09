extends SceneTree
const Population = preload("res://object_population.gd")
const Document = preload("res://map_document.gd")
const Definitions = preload("res://object_definitions.gd")
const Clam = preload("res://clam.gd")
const Pearl = preload("res://pearl_body.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	preload("res://mod_registry.gd").initialize(false)
	var document := Document.load_path("res://../Maps/scen1.json")
	check(not document.is_empty(),"Authored map remains valid")
	var groups: Array = document.object_groups.filter(func(group: Dictionary) -> bool: return group.type in ["clam","pearl"])
	check(groups.size() == 9,"Six original clams and three refinery pearls")
	for index in range(6):
		var original := Document.decode(document.entities["Scenery/CLAM_" + str(index)].transform)
		var group: Dictionary = groups[index]
		check(Document.vector(group.position).is_equal_approx(original.origin) and Basis.from_euler(Document.vector(group.rotation) * PI / 180.0).is_equal_approx(original.basis.orthonormalized()),"Original clam placement and orientation %d" % index)
	check(groups.filter(func(group: Dictionary) -> bool: return group.type == "clam").map(func(group: Dictionary) -> float: return group.initial_delay) == [0.0,0.0,1800.0,3600.0,5400.0,7200.0],"Recovered staggered first pearl delays")
	var world := Node3D.new(); root.add_child(world); world.set_meta("surface_height",10.0)
	var population := Population.new(); world.add_child(population)
	var folder := preload("res://asset_paths.gd").find_game_folder()
	var sample := Document.empty(); Definitions.ensure(sample)
	sample.object_groups = [{"id":"test_clam","name":"Clam","type":"clam","position":[0,0,0],"rotation":[0,0,0],"count":1,"radius":0,"initial_delay":0}]
	population.setup(folder,sample,true); population.set_physics_process(false)
	var clam: Clam = population.get_children().filter(func(node: Node) -> bool: return node is Clam)[0]
	clam.set_physics_process(false)
	check(clam.lid != null and clam.colliders.size() == 2,"Original articulated shell and separate collisions loaded")
	check(is_instance_valid(clam.pearl) and clam.pearl.freeze,"First pearl starts secured inside shell")
	check(clam.pearl.pickup_item().is_empty(),"Closed pearl cannot be vacuumed")
	clam._physics_process(1.0); check(is_equal_approx(clam.angle,75),"Recovered opening speed")
	clam._physics_process(1.0); check(clam.fully_open() and clam.pearl.pickup_item() == "pearls","Open pearl available to SOM")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(800,600)
		var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(1.4,1.3,1.7); camera.look_at(Vector3(0,0.25,0)); camera.current = true
		var light := DirectionalLight3D.new(); world.add_child(light); light.rotation_degrees = Vector3(-50,-30,0); light.light_energy = 2
		var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color(0.08,0.15,0.2)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color.WHITE; environment.environment.ambient_light_energy = 0.8; world.add_child(environment)
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/clam-open.png")
	var pilot := preload("res://submarine_controller.gd").new(); pilot.remember_settings = false; world.add_child(pilot); pilot.freeze = true; pilot.set_physics_process(false)
	pilot.position = Vector3(0,0.5,0); clam.player = pilot
	clam._physics_process(0.2); check(is_equal_approx(clam.angle,10),"Approaching player scares shell shut")
	pilot.position = Vector3(0,2,0); clam._physics_process(2)
	var vacuum := preload("res://suck_o_matic.gd").new(); world.add_child(vacuum); vacuum.setup(pilot,folder); vacuum.population = population; vacuum.position = Vector3(0,1.2,0); vacuum.set_physics_process(false)
	pilot.active = true; pilot.controls_enabled = true; vacuum.enabled = true
	await physics_frame; await physics_frame
	for tick in range(180):
		vacuum._physics_process(1.0 / 60.0); await physics_frame
	check(vacuum.storage == ["pearls"] and not vacuum.enabled,"SOM extracts pearl through open shell and switches off")
	check(not is_instance_valid(clam.pearl) and clam.remaining == 7200,"Harvest starts recovered two-hour regrowth timer")
	await process_frame
	clam._physics_process(12)
	var snapshot: Array = JSON.parse_string(JSON.stringify(population.snapshot()))
	check(Population.valid_snapshot(snapshot) and snapshot.size() == 1,"Harvested clam saves once without duplicate pearl")
	population.restore_snapshot(snapshot)
	clam = population.get_children().filter(func(node: Node) -> bool: return node is Clam)[0]; clam.set_physics_process(false)
	check(is_equal_approx(clam.remaining,7188) and not is_instance_valid(clam.pearl),"Save restore preserves regrowth progress")
	clam._physics_process(7188); check(is_instance_valid(clam.pearl),"Pearl regrows when timer expires")
	clam.pearl.pull_towards(clam.global_position + Vector3.UP * 0.6,1,0.2)
	snapshot = JSON.parse_string(JSON.stringify(population.snapshot())); population.restore_snapshot(snapshot)
	clam = population.get_children().filter(func(node: Node) -> bool: return node is Clam)[0]; clam.set_physics_process(false)
	check(is_instance_valid(clam.pearl) and is_equal_approx(clam.pearl.position.y,0.4),"Partially extracted pearl survives save restore")
	clam.pearl.pull_towards(Vector3.UP * 2,2,1)
	check(not is_instance_valid(clam.pearl) and population.snapshot().size() == 2,"Extracted pearl becomes independent physical object")
	snapshot = JSON.parse_string(JSON.stringify(population.snapshot())); population.restore_snapshot(snapshot)
	check(population.get_children().filter(func(node: Node) -> bool: return node is Pearl).size() == 1,"Loose pearl survives save restore")
	population.reset_population()
	clam = population.get_children().filter(func(node: Node) -> bool: return node is Clam)[0]; clam.set_physics_process(false)
	check(is_instance_valid(clam.pearl) and clam.remaining == 0,"New game restores initial pearl")
	var bad := population.snapshot(); bad[0].clam_state.remaining = -1
	check(not Population.valid_snapshot(bad),"Invalid clam timer rejected")
	var cargo := {}; vacuum.transfer_to(cargo); check(cargo.get("pearls",0) == 1,"Docking transfers pearl into commodity hold")
	population._create_thorium(Definitions.PEARL,0,Transform3D(Basis.IDENTITY,Vector3(5,1,0)))
	population.initial_thorium = population.snapshot()
	population.restore_snapshot([])
	check(population.get_children().filter(func(node: Node) -> bool: return node is Clam).size() == 1 and population.get_children().filter(func(node: Node) -> bool: return node is Pearl).size() == 2,"Older saves receive authored clams and loose pearls")
	for body in population.get_children():
		if body is Pearl and not is_instance_valid(body.clam): body.free()
	population.restore_snapshot(population.snapshot())
	check(population.get_children().filter(func(node: Node) -> bool: return node is Pearl).size() == 1,"New saves do not respawn already collected loose pearls")
	world.free()
	print("Clams and pearls: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
