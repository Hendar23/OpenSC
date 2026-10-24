extends "res://tests/test_scene_tree.gd"
const Trader = preload("res://trader_submarine.gd")
const Pirate = preload("res://pirate_submarine.gd")
const Mission = preload("res://mission_vessel.gd")
const Patrol = preload("res://patrol_submarine.gd")
const Traffic = preload("res://submarine_traffic.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func boat(world: Node3D, traffic: Node, model_id: String, kind: String, maximum: float) -> Node3D:
	var model := Node3D.new(); world.add_child(model); model.set_meta("editor_model",model_id)
	model.position.x = traffic.traders.size()*5
	var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); model.add_child(mesh)
	var values := {"npc_health":maximum,"npc_sustain":0.3}
	var agent: Node3D
	match kind:
		"pirate": agent = Pirate.install_pirate(model,values)
		"mission": agent = Mission.install_mission(model,values)
		"patrol": agent = Patrol.install_patrol(model,values)
		_: agent = Trader.install(model,values)
	agent.system = traffic; agent.running = true; agent.reset(); agent.set_physics_process(false); traffic.traders.append(agent)
	return agent
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var traffic := Traffic.new(); world.add_child(traffic); traffic.set_physics_process(false)
	var pirate := boat(world,traffic,"PIRATE","pirate",30)
	check(pirate.health.capacity == 60 and pirate.health.remaining == 60,"Ambient pirates start at double health")
	var custom := boat(world,traffic,"CUSTOM_MOD_HULL","pirate",17)
	check(custom.health.capacity == 34 and custom.tuning.npc_health == 17,"Mod/custom pirate health doubles without editing authored data")
	for model_id in ["TRAD-SUB","TRAD2","TECHNEW","TECH2SUB"]:
		var agent := boat(world,traffic,model_id,"mission",15)
		check(agent.health.capacity == 30,"Mission/friendly attack hull doubles: "+model_id)
		agent.reset(); agent.reset()
		check(agent.health.capacity == 30,"Respawn/reset never compounds multiplier: "+model_id)
		agent.health.hit(10)
		check(is_equal_approx(agent.health.remaining,27),"Damage/sustain unchanged: "+model_id)
	for model_id in ["TRADSHUT","TECHSHUT","PRISON","TRADHERD","TECHHERD","FREIGHT"]:
		var agent := boat(world,traffic,model_id,"mission",15)
		check(agent.health.capacity == 15,"Civilian/mission objective health preserved: "+model_id)
	check(boat(world,traffic,"TECH2SUB","patrol",10).health.capacity == 20,"Patrol attack hull also doubles")
	check(boat(world,traffic,"TRADSHUT","patrol",10).health.capacity == 10,"Patrol civilian hull stays unchanged")
	var identity: String = preload("res://entity_identity.gd").of(pirate)
	var saved: Dictionary = traffic.snapshot()
	check(Traffic.valid_snapshot(saved),"New health/capacity snapshots validate")
	traffic.restore(saved)
	check(pirate.health.remaining == 60,"Full attack health survives save/load without old-cap truncation")
	saved = traffic.snapshot(); saved[identity].erase("health_capacity"); saved[identity].health = 12.0
	check(Traffic.valid_snapshot(saved),"Published beta snapshots without capacity remain supported")
	traffic.restore(saved)
	check(is_equal_approx(pirate.health.remaining,24),"Old beta keeps its 40-percent health when capacity doubles")
	saved = traffic.snapshot(); traffic.restore(saved); traffic.restore(saved)
	check(is_equal_approx(pirate.health.remaining,24),"Repeated new-save loads never double health again")
	saved[identity].health_capacity = -1
	check(not Traffic.valid_snapshot(saved),"Invalid saved capacity is rejected")
	var head := preload("res://mission_walker_body.gd").new(); world.add_child(head); head.detached = true
	head.set_towing_attached(true)
	check(head.mass == 37.5 and head.raw_impact_mass == 0.75,"Head towing mass halved while fragility stays unchanged")
	head.set_towing_attached(false)
	check(head.mass == 3750.0 and head.raw_impact_mass == 75,"Released head is also half its previous weight")
	world.free(); await process_frame
	print("Attack-sub balance: %d checks; %d failures" % [checks,failures]); quit(1 if failures else 0)
