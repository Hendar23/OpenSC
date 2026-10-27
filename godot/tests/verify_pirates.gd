extends "res://tests/test_scene_tree.gd"
const Pirate = preload("res://pirate_submarine.gd")
const Document = preload("res://map_document.gd")
var checks := 0
var failures := 0
class OpenWater extends "res://submarine_traffic.gd":
	func water_clear(_point: Vector3) -> bool: return true
	func segment_clear(_a: Vector3,_b: Vector3) -> bool: return true
	func route(a: Vector3,b: Vector3) -> PackedVector3Array: return PackedVector3Array([b]) if a.distance_to(b) > 0.1 else PackedVector3Array()
	func choose_city(_agent: Node3D) -> int:
		push_error("Pirates must never choose trader docks"); return 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-traffic-fixtures"
	call_deferred("run")
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var traffic := OpenWater.new(); world.add_child(traffic); traffic.navigation_ready = true; traffic.set_physics_process(false)
	var target := CharacterBody3D.new(); world.add_child(target); target.position = Vector3(0,0,10); target.collision_layer = 2
	var shape := CollisionShape3D.new(); shape.shape = SphereShape3D.new(); target.add_child(shape); traffic.player = target
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var agents: Array[Node3D] = []
	for id in Pirate.PIRATE_MODELS:
		var model := Document.load_model(id,folder); world.add_child(model)
		var agent := Pirate.install_pirate(model,{})
		agent.system = traffic; agent.running = true; agent.set_physics_process(false); traffic.traders.append(agent)
		agent.reset(); agent.set_physics_process(false); agents.append(agent)
		check(agent.health.remaining == 30 and agent.body.get_meta("faction") == 3,"Original pirate health and affiliation")
		check(not agent.tuning.npc_respawn,"Placed pirates do not automatically replenish")
	for i in range(1,agents.size()): agents[i].running = false; agents[i].body.collision_layer = 0; agents[i].get_parent().position.x = 100
	var pirate = agents[0]
	pirate.configure_resources(folder)
	check(pirate.missile_template != null,"Original pirate missile model loads")
	await physics_frame
	pirate._physics_process(0.1)
	check(pirate.victim == target and pirate.global_position.z > 0,"Pirate acquires and pursues nearby player")
	check(pirate.destination == 0 and pirate.port.is_empty(),"Combat never occupies a city dock")
	check(get_nodes_in_group("turret_missiles").size() == 1,"Aimed pirate fires a missile")
	var missile = get_nodes_in_group("turret_missiles")[0]
	check(missile.inflict == 2.5 and not missile.homing,"Pirate uses original TMISSILE strength")
	pirate._physics_process(0.1)
	check(get_nodes_in_group("turret_missiles").size() == 1,"Shot cooldown prevents repeated immediate fire")
	for node in get_nodes_in_group("turret_missiles"): node.free()
	pirate.cooldown = 0; pirate.get_parent().basis = Basis(Vector3.UP,PI); pirate.path.clear(); pirate.replan = 0
	pirate._physics_process(0.01)
	check(get_nodes_in_group("turret_missiles").is_empty(),"Pirate cannot fire backwards")
	pirate.take_weapon_damage(1,target.global_position)
	check(pirate.health.remaining < 30 and pirate.flee == 0,"Damaged pirate fights instead of civilian fleeing")
	var snapshot := traffic.snapshot()
	check(traffic.valid_snapshot(snapshot),"Pirate state saves with other vessels")
	traffic.restore(snapshot)
	pirate.set_physics_process(false)
	check(pirate.health.remaining < 30,"Pirate health restored")
	target.position = Vector3(0,0,200); pirate.victim = null
	pirate._physics_process(1)
	check(pirate.victim == null and pirate.body.velocity == Vector3.ZERO,"No pursuit outside detection range")
	pirate.reset()
	target.position = Vector3(0,0,10)
	pirate.set_physics_process(false)
	var wall := StaticBody3D.new(); world.add_child(wall); wall.position = Vector3(0,0,4); wall.collision_layer = 1
	var block := CollisionShape3D.new(); block.shape = BoxShape3D.new(); block.shape.size = Vector3(5,5,1); wall.add_child(block)
	await physics_frame
	pirate._physics_process(0.1)
	check(get_nodes_in_group("turret_missiles").is_empty(),"Scenery blocks pirate fire")
	wall.free()
	pirate.take_weapon_damage(10000,target.global_position)
	check(pirate.dead and not pirate.get_parent().visible and pirate.body.collision_layer == 0,"Destroyed pirate disables hull")
	check(get_nodes_in_group("trader_wrecks").size() == 1,"Pirate destruction uses shared submarine debris")
	pirate.reset()
	check(pirate.health.remaining == 30 and pirate.victim == null,"New game resets placed pirate")
	for script in ["res://pirate_submarine.gd","res://tests/verify_pirates.gd"]:
		if not FileAccess.file_exists(script + ".uid"):
			var file := FileAccess.open(script + ".uid",FileAccess.WRITE); file.store_string(ResourceUID.id_to_text(ResourceUID.create_id()) + "\n")
	world.free()
	print("Pirates: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
