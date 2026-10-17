extends "res://tests/test_scene_tree.gd"
const Trader = preload("res://trader_submarine.gd")
class OpenWater extends "res://submarine_traffic.gd":
	func segment_clear(_a: Vector3,_b: Vector3) -> bool: return true
	func choose_city(_agent: Node3D) -> int: return 0
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-vessel-fixes-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	preload("res://mod_registry.gd").initialize(false); call_deferred("run")
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var traffic := OpenWater.new(); world.add_child(traffic); traffic.navigation_ready = true
	traffic.bubbles = preload("res://propeller_bubbles.gd").new(); world.add_child(traffic.bubbles); traffic.bubbles.set_physics_process(false)
	for id: String in ["TRAD2","PRISON","TRADSHUT"]:
		var model := preload("res://clump_loader.gd").load_clump("../Original Sub Culture/CLUMPS/"+id+".DFF"); world.add_child(model)
		var agent := Trader.install(model,{}); agent.system = traffic; agent.running = true; agent.set_physics_process(false); agent.reset(); agent.wait = 0
		check(agent.propellers.size() == (1 if id == "TRADSHUT" else 2),"All original rotor frames registered for "+id)
		agent.speed = 2; agent._propulsion(0.031)
		check(agent.propellers.all(func(rotor: Dictionary) -> bool: return not rotor.node.basis.is_equal_approx(rotor.rest)),"Every rotor animates independently on "+id)
		traffic.bubbles.clear(); agent._propulsion(1.0)
		check(traffic.bubbles.credits.size() == agent.propellers.size(),"Each propeller has an independent bubble emitter on " + id)
		for rotor in agent.propellers:
			var outlet: Vector3 = rotor.node.global_position - model.global_basis.z.normalized() * 0.04
			check(traffic.bubbles.particles.any(func(particle: Dictionary) -> bool: return particle.position.distance_to(outlet) < 0.071),"Wake particles originate at each actual propeller on " + id)
		for rotor in agent.propellers:
			var mesh: MeshInstance3D = rotor.node.find_child("Mesh*",true,false)
			var material: StandardMaterial3D = mesh.get_active_material(0)
			var picture: Image = material.albedo_texture.get_image(); var transparent := 0; var solid := 0
			for y in range(picture.get_height()):
				for x in range(picture.get_width()):
					if picture.get_pixel(x,y).a < 0.1: transparent += 1
					if picture.get_pixel(x,y).a > 0.9: solid += 1
			check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and transparent > 100 and solid > 100,"Rotor retains blades and cuts out the background on "+id)
		model.free()
	var model := preload("res://clump_loader.gd").load_clump("../Original Sub Culture/CLUMPS/TECHSHUT.DFF"); world.add_child(model)
	var ship := Trader.install(model,{"npc_speed":2.0}); ship.system = traffic; ship.reset(); ship.running = true; ship.set_physics_process(false); ship.wait = 0
	traffic.traders.append(ship)
	ship.speed = 2; ship.motion.velocity = Vector3.RIGHT*2
	ship.path = PackedVector3Array([Vector3(0.4,0,0),Vector3(0,0,8)])
	await physics_frame
	ship.advance(1.0/60.0)
	check(ship.path.size() == 1,"Procha trader captures a close passing waypoint instead of turning back to orbit it")
	for tick in range(600):
		ship.advance(1.0/60.0)
		if tick % 10 == 0: await physics_frame
	check(ship.global_position.distance_to(Vector3(0,0,8)) < 0.4,"Procha trader completes the next leg after entering a rounded corner with sideways momentum")
	if DisplayServer.get_name() != "headless":
		model.hide()
		var preview := preload("res://clump_loader.gd").load_clump("../Original Sub Culture/CLUMPS/TRAD2.DFF"); world.add_child(preview)
		preload("res://natural_light.gd").new().attach(preview)
		for rotor in Trader.rotor_nodes(preview):
			var mesh: MeshInstance3D = rotor.find_child("Mesh*",true,false)
			check(is_equal_approx(mesh.get_active_material(0).get_shader_parameter("alpha_threshold"),0.5),"World lighting preserves the propeller's cutout mask")
		var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.04,0.25,0.32); environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_energy = 0.5; world.add_child(environment)
		var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-35,-20,0); world.add_child(sun)
		var camera := Camera3D.new(); world.add_child(camera); camera.near = 0.02; camera.position = Vector3(0,-0.1,-1.4); camera.look_at(Vector3(0,-0.1,-0.25)); camera.current = true
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/stage-two-bohine-rotors.png")
	world.free(); print("Vessel fixes: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
