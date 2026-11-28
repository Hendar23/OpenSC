extends "res://tests/test_scene_tree.gd"
const Pirate = preload("res://pirate_submarine.gd")
const Vessel = preload("res://mission_vessel.gd")
var checks := 0
var failures := 0
class Target extends CharacterBody3D:
	var received := 0.0
	var dead := false
	func take_damage(_amount: float, _point: Vector3 = Vector3.ZERO) -> void: pass
	func take_weapon_damage_from(amount: float, _point: Vector3, _owner: Node3D) -> void: received += amount
class ConfinedWater extends "res://submarine_traffic.gd":
	var raised_firing_point := false
	func water_clear(point: Vector3) -> bool:
		return point.z <= player.global_position.z
	func segment_clear(a: Vector3, b: Vector3) -> bool:
		return water_clear(a) and water_clear(b)
	func route(start: Vector3, finish: Vector3) -> PackedVector3Array:
		if not segment_clear(start,finish) or (raised_firing_point and finish.y <= 0): return PackedVector3Array()
		return PackedVector3Array([finish])
func _initialize() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-pirate-weapons-fixtures"
	preload("res://mod_registry.gd").initialize(false,"res://tests/cache-pirate-weapons-fixtures/Mods")
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var traffic := ConfinedWater.new(); world.add_child(traffic); traffic.set_physics_process(false)
	var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(5,3,-4); camera.look_at(Vector3(0,0,2)); camera.current = true
	var target := Target.new(); world.add_child(target); target.position.z = 2.0; target.collision_layer = 2
	var shape := CollisionShape3D.new(); shape.shape = SphereShape3D.new(); shape.shape.radius = 0.3; target.add_child(shape)
	traffic.player = target
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	var model := preload("res://map_document.gd").load_model("PIRATE",folder); world.add_child(model)
	var agent := Pirate.install_pirate(model,{}); agent.system = traffic; traffic.traders.append(agent); agent.reset(); agent.set_physics_process(false)
	agent.configure_resources(folder)
	var mission_model := preload("res://map_document.gd").load_model("TECH-SUB",folder); world.add_child(mission_model); mission_model.position.x = 15.0
	var mission := Vessel.install_mission(mission_model,{})
	mission.system = traffic; traffic.traders.append(mission); mission.configure_resources(folder)
	mission.roll_weapon(95)
	check(mission.armament.weapon_id == "zapperup","Scripted standard attack subs use the same loadout pool")
	traffic.set_random_npc_weapons(false)
	check(mission.armament.weapon_id == "missile","Off immediately restores a scripted sub's torpedoes")
	mission.roll_weapon(95)
	check(mission.armament.weapon_id == "missile","A scripted sub that spawns while Off keeps its torpedoes")
	traffic.set_random_npc_weapons(true)
	check(mission.armament.weapon_id == "missile","Turning On keeps an existing spawn's loadout")
	await physics_frame
	for kind in ["zapper","zapperup"]:
		agent.armament.select_weapon(kind); target.received = 0
		agent.armament.begin_frame(0.04); agent.armament.attack(0.04,target)
		check(is_equal_approx(target.received,0.1875 if kind == "zapper" else 0.375),kind+" damages the real hit body at the tuned 25 Hz strength")
		check(agent.armament.arcs[0].firing and agent.armament.arcs[1].firing == (kind == "zapperup"),kind+" uses the corresponding single/double arc")
		for tick in range(30):
			agent.armament.begin_frame(1.0/60.0); agent.armament.attack(1.0/60.0,target)
		check(is_equal_approx(target.received,1.875 if kind == "zapper" else 3.75),kind+" delivers exactly the intended burst damage and stops during cooldown")
	check(agent.player_attack_announced,"Alternative weapons trigger pirate engagement feedback")
	var wall := StaticBody3D.new(); wall.position.z = 1.4; world.add_child(wall)
	var block := CollisionShape3D.new(); block.shape = BoxShape3D.new(); block.shape.size = Vector3(2,2,0.1); wall.add_child(block)
	await physics_frame
	agent.armament.select_weapon("zapper"); target.received = 0; agent.armament.attack(0.04,target)
	check(is_zero_approx(target.received),"Solid scenery blocks zapper damage")
	wall.free(); await physics_frame
	model.rotation.y = PI; agent.armament.attack(0.04,target)
	check(is_zero_approx(target.received),"Pirates cannot zap backwards")
	model.rotation.y = 0; target.position.z = 4.0; await physics_frame
	agent.armament.attack(0.04,target)
	check(is_zero_approx(target.received),"Standard zapper respects its short range")
	agent.armament.select_weapon("zapperup"); agent.armament.attack(0.04,target)
	check(target.received > 0,"Upgraded zapper reaches farther")
	for tick in range(10): agent.armament.begin_frame(0.04)
	agent.armament.attack(0.04,target)
	check(is_equal_approx(target.received,0.375),"Ticks without a target expire rather than being banked")
	target.position = Vector3.ZERO
	agent.home.origin = Vector3(0,0,-5.5)
	for kind in ["zapper","zapperup"]:
		agent.reset()
		agent.armament.select_weapon(kind)
		target.received = 0
		await physics_frame
		for tick in range(240):
			agent.advance(0.04)
			if target.received > 0: break
			await physics_frame
		check(agent.attack_run.passes > 0 and target.received > 0,kind+" closes from torpedo standoff and fires when the usual pass is blocked")
		agent.reset()
		agent.armament.select_weapon(kind)
		traffic.raised_firing_point = true
		var raised_route: PackedVector3Array = agent._attack_route(target.global_position)
		if raised_route.is_empty(): raised_route = agent._attack_route(target.global_position)
		check(not raised_route.is_empty() and raised_route[-1].y > 0 and raised_route[-1].distance_to(target.global_position) < agent.armament.weapon_range(),kind+" keeps elevated fallback positions within firing range")
		traffic.raised_firing_point = false
	agent.armament.select_weapon("missile")
	var torpedo_route: PackedVector3Array = agent._attack_route(target.global_position)
	check(not torpedo_route.is_empty() and is_equal_approx(torpedo_route[-1].length(),5.5),"Torpedo fallback keeps its usual standoff distance")
	agent.armament.select_weapon("electro")
	check(agent.armament.weapon_id == "missile","Legacy NPC Electro Bolt loadouts fall back to torpedoes")
	target.position = model.global_position + Vector3.BACK * 4.0
	await physics_frame
	agent.armament.select_weapon("zapperup"); agent.armament.attack(0.04,target)
	agent.dead = true; agent.armament._process(0)
	check(agent.armament.arcs.all(func(arc: Node3D) -> bool: return not arc.firing) and not agent.armament.zap_audio.playing,"Death stops zapper visuals and loop audio")
	world.queue_free(); await process_frame
	print("Pirate weapons: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
