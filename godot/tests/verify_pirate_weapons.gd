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
func _initialize() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-pirate-weapons-fixtures"
	preload("res://mod_registry.gd").initialize(false,"res://tests/cache-pirate-weapons-fixtures/Mods")
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var traffic := preload("res://submarine_traffic.gd").new(); world.add_child(traffic); traffic.set_physics_process(false)
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
		check(is_equal_approx(target.received,0.375 if kind == "zapper" else 0.75),kind+" damages the real hit body at the tuned 25 Hz strength")
		check(agent.armament.arcs[0].firing and agent.armament.arcs[1].firing == (kind == "zapperup"),kind+" uses the corresponding single/double arc")
		for tick in range(30):
			agent.armament.begin_frame(1.0/60.0); agent.armament.attack(1.0/60.0,target)
		check(is_equal_approx(target.received,3.75 if kind == "zapper" else 7.5),kind+" delivers exactly the intended burst damage and stops during cooldown")
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
	check(is_equal_approx(target.received,0.75),"Ticks without a target expire rather than being banked")
	agent.armament.select_weapon("electro")
	check(agent.armament.weapon_id == "missile","Legacy NPC Electro Bolt loadouts fall back to torpedoes")
	agent.armament.select_weapon("zapperup"); agent.armament.attack(0.04,target)
	agent.dead = true; agent.armament._process(0)
	check(agent.armament.arcs.all(func(arc: Node3D) -> bool: return not arc.firing) and not agent.armament.zap_audio.playing,"Death stops zapper visuals and loop audio")
	world.queue_free(); await process_frame
	print("Pirate weapons: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
