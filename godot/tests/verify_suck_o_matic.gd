extends SceneTree
const Equipment = preload("res://submarine_equipment.gd")
const Pilot = preload("res://submarine_controller.gd")
const Thorium = preload("res://thorium_body.gd")
const Game = preload("res://game.gd")
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	preload("res://mod_registry.gd").initialize(false)
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var world := Node3D.new(); root.add_child(world)
	var pilot := Pilot.new(); pilot.remember_settings = false; world.add_child(pilot); pilot.set_physics_process(false)
	pilot.visual = preload("res://clump_loader.gd").load_submarine(folder.path_join("CLUMPS/SUB.DFF")); pilot.add_child(pilot.visual)
	pilot.visual.scale *= Pilot.VISUAL_SCALE; pilot.visual.rotation.y = PI; pilot.active = true; pilot.freeze = true
	var equipment := Equipment.new(); pilot.add_child(equipment); equipment.setup(pilot,folder)
	check(equipment.mounted.size() == 2 and equipment.mounted[1].id == "suckomat","Installed alongside lights at game start")
	check(equipment.mounted[1].mount.position.y < 0,"Mounted below hull")
	check(equipment.vacuum.audio.stream != null and equipment.mounted[1].icons[0] != null,"Original vacuum sound and HUD icon loaded")
	check(equipment.counter_digits.size() == 10 and equipment.counter_digits[5] != null,"Original counter digits loaded")
	equipment.cycle(1); equipment.toggle_selected(); check(equipment.vacuum.enabled,"Equipment binding toggles suction")
	var population := Node3D.new(); world.add_child(population); equipment.vacuum.population = population
	var collected: Array[String] = []
	equipment.vacuum.item_collected.connect(func(item: String) -> void: collected.append(item))
	for index in range(6):
		var body := Thorium.new(); population.add_child(body)
		var visual := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3.ONE * 0.05; visual.mesh = box
		body.setup(preload("res://object_definitions.gd").THORIUM,visual,1,10,true); body.freeze = true
		body.global_position = equipment.vacuum.global_position + Vector3(0,-0.1,0)
	equipment.vacuum._physics_process(0.016)
	check(collected.size() == 1 and equipment.cycle_audio.playing,"Captured item triggers SUBCYCLE")
	check(not equipment.vacuum.enabled and not equipment.mounted[1].enabled and not equipment.vacuum.audio.playing,"One pickup switches off suction, HUD state and vacuum sound")
	equipment.vacuum._physics_process(0.016)
	check(collected.size() == 1,"Remaining items require another activation")
	for pickup in range(4):
		equipment.toggle_selected(); equipment.vacuum._physics_process(0.016)
	check(equipment.vacuum.storage.size() == 5,"Captures at most five shards")
	check(population.get_child(5).dead == false,"Sixth item stays in world")
	var cargo := {}; equipment.vacuum.transfer_to(cargo); equipment.vacuum.transfer_to(cargo)
	check(cargo.get("ore",0) == 5 and equipment.vacuum.storage.is_empty(),"Docking transfer happens once into separate cargo")
	equipment.vacuum.enabled = false
	await process_frame
	var crystal := Thorium.new(); crystal.shard = 0
	check(crystal.pickup_item().is_empty(),"Whole crystals cannot be vacuumed"); crystal.free()
	var remaining: RigidBody3D = population.get_child(0)
	remaining.global_position = equipment.vacuum.global_position + Vector3(0,-1,0); remaining.freeze = false
	equipment.settings.som_radius = 0.1; equipment.settings.som_range = 0.5
	equipment.apply_settings(); equipment.toggle_selected()
	equipment.vacuum._physics_process(0.016)
	check(remaining.linear_velocity == Vector3.ZERO and equipment.vacuum.storage.is_empty(),"Item outside configured depth is not drawn in")
	remaining.global_position = equipment.vacuum.global_position + Vector3(0.2,-0.1,0)
	equipment.vacuum._physics_process(0.016)
	check(equipment.vacuum.storage.is_empty(),"Item outside narrow suction radius is not captured")
	equipment.settings.som_radius = 0.25; equipment.settings.som_range = 2.0
	equipment.settings.som_pull_speed = 3.0; equipment.settings.som_pull_strength = 12.0
	equipment.apply_settings()
	check(equipment.vacuum.pull_speed == 3.0 and equipment.vacuum.pull_strength == 12.0,"Live equipment settings tune suction forces")
	remaining.global_position = equipment.vacuum.global_position + Vector3(0,-1,0)
	for tick in range(120): await physics_frame
	check(equipment.vacuum.storage.size() == 1,"Shard is physically pulled up into intake")
	var saved := preload("res://player_progress.gd").restore({"cargo":cargo,"suckomat":["ore"]})
	check(saved.cargo.ore == 5 and saved.suckomat == ["ore"],"Cargo and device storage survive progress restore")
	equipment.vacuum.reset(); check(not equipment.vacuum.enabled and equipment.vacuum.storage.is_empty(),"New game clears device")
	world.free()
	print("Suck-O-Matic: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
