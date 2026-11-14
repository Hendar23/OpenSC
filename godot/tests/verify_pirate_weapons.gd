extends "res://tests/test_scene_tree.gd"
const Pirate = preload("res://pirate_submarine.gd")
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
	check(agent.armament == null,"Placed/scripted pirates do not acquire random armaments")
	agent.armament = preload("res://pirate_armament.gd").new(); agent.add_child(agent.armament); agent.armament.setup(agent,folder)
	await physics_frame
	for kind in ["zapper","zapperup"]:
		agent.armament.select_weapon(kind); target.received = 0
		agent.armament.begin_frame(0.04); agent.armament.attack(0.04,target)
		check(is_equal_approx(target.received,2.5 if kind == "zapper" else 5.0),kind+" damages the real hit body at the original 25 Hz strength")
		check(agent.armament.arcs[0].firing and agent.armament.arcs[1].firing == (kind == "zapperup"),kind+" uses the corresponding single/double arc")
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
	target.received = 0; target.position.z = 6.0; await physics_frame
	agent.armament.select_weapon("electro"); agent.armament.attack(0.04,target)
	check(agent.armament.shots.size() == 1,"Electro pirate launches the real Electro Bolt projectile")
	var bolt: Node3D = agent.armament.shots[0]; bolt.set_physics_process(false)
	agent.armament.attack(0.04,target)
	check(agent.armament.shots.size() == 1,"Electro Bolt has a firing cooldown")
	for tick in range(100):
		if bolt.spent or bolt.bursting: break
		bolt.advance(0.04)
	check(bolt.bursting and target.received > 0,"NPC Electro Bolt travels, collides and discharges against the player")
	check(agent.health.remaining == agent.health.capacity,"Electro discharge excludes the launching hull")
	agent.dead = true; agent.armament._process(0)
	check(agent.armament.arcs.all(func(arc: Node3D) -> bool: return not arc.firing) and not agent.armament.zap_audio.playing,"Death stops zapper visuals and loop audio")
	world.queue_free(); await process_frame
	print("Pirate weapons: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
