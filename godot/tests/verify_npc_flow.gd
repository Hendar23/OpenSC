extends "res://tests/test_scene_tree.gd"
class OpenWater extends "res://submarine_traffic.gd":
	var probes := 0
	var routes := 0
	func segment_clear(_a: Vector3,_b: Vector3) -> bool: probes += 1; return true
	func water_clear(_point: Vector3) -> bool: return true
	func route(_from: Vector3,goal: Vector3) -> PackedVector3Array: routes += 1; return PackedVector3Array([goal])
	func choose_city(_agent: Node3D) -> int: return 0
class Target extends CharacterBody3D:
	var active := true
	var dead := false
class BlockedWater extends OpenWater:
	func route(_from: Vector3,_goal: Vector3) -> PackedVector3Array: routes += 1; return PackedVector3Array()
class ShoreWater extends OpenWater:
	func water_clear(point: Vector3) -> bool: return point.x <= 0
	func segment_clear(a: Vector3,b: Vector3) -> bool: probes += 1; return water_clear(a) and water_clear(b)
var checks := 0
var failures := 0
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func boat(world: Node3D,traffic: Node,point: Vector3,combat: bool) -> Node3D:
	var model := Node3D.new(); world.add_child(model); model.position = point
	var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); mesh.mesh.size = Vector3(0.6,0.6,1); model.add_child(mesh)
	var agent: Node3D = preload("res://pirate_submarine.gd").install_pirate(model,{"npc_speed":2.5}) if combat else preload("res://mission_vessel.gd").install_mission(model,{"npc_speed":2.0})
	agent.system = traffic; agent.running = true; agent.reset(); agent.set_physics_process(false); traffic.traders.append(agent)
	return agent
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var traffic := OpenWater.new(); world.add_child(traffic); traffic.navigation_ready = true; traffic.set_physics_process(false)
	traffic.space = world.get_world_3d().direct_space_state
	var cruise := boat(world,traffic,Vector3.ZERO,false)
	cruise.combat_enabled = false; cruise.loop_route = true
	cruise.waypoints = PackedVector3Array([Vector3(0,0,10),Vector3(10,0,10),Vector3(10,0,0),Vector3.ZERO])
	var stationary := boat(world,traffic,Vector3(30,0,0),false); stationary.combat_enabled = false; stationary.level_when_idle = true; stationary.travel_height = 0
	var target := Target.new(); world.add_child(target); target.position = Vector3(60,0,0); traffic.player = target
	var attack := boat(world,traffic,Vector3(60,0,-12),true)
	var phases := {}; var minimum := INF; var minimum_cruise := INF; var moving := 0; var max_step := 0.0
	var visited := {}
	await physics_frame
	for tick in range(1500):
		var previous: Vector3 = cruise.global_position
		cruise.advance(0.04); stationary.advance(0.04); attack.advance(0.04)
		if tick > 100:
			minimum_cruise = minf(minimum_cruise,cruise.speed)
			if attack.speed > 0.3: moving += 1
		phases[attack.attack_run.phase] = true; visited[cruise.waypoint] = true
		minimum = minf(minimum,attack.global_position.distance_to(target.global_position))
		max_step = maxf(max_step,cruise.global_position.distance_to(previous))
		await physics_frame
	check(visited.size() == 4,"Patrol traverses every leg of its loop")
	check(minimum_cruise > 0.65,"Patrol keeps forward speed through every corner and route transition")
	check(max_step <= 0.081,"Continuous patrol never teleports or batches its movement")
	check(stationary.global_position.is_equal_approx(Vector3(30,0,0)),"Working fishing/stationary mission ship remains at its station and height")
	check(phases.size() == 4 and attack.attack_run.passes >= 2,"Combat cycles through approach, firing pass, extension and rejoin repeatedly")
	check(float(moving)/1399 > 0.95,"Combat ship keeps moving rather than parking beside its target")
	check(minimum > 1.2,"Firing passes clear the target hull rather than ramming it")
	check(traffic.routes < 130,"Combat route generation is bounded across a sixty-second encounter")
	check(traffic.probes < 2500,"Look-ahead and avoidance queries remain throttled")
	# Emerging from a tunnel must invalidate a pass aimed at the old position.
	for phase in ["pass","extend","rejoin"]:
		attack.attack_run.phase = phase; attack.attack_run.target_point = target.global_position
		attack.attack_run.goal = target.global_position; attack.attack_run.decision_clock = 0
		var old_goal: Vector3 = attack.attack_run.goal
		target.position += Vector3.RIGHT*20
		attack.attack_run.advance(attack,target,0.04)
		check(attack.attack_run.phase == "approach" and attack.attack_run.goal.distance_to(old_goal) > 10,"Moving target replaces obsolete %s destination promptly" % phase)
	var blocked := BlockedWater.new(); world.add_child(blocked); blocked.navigation_ready = true; blocked.set_physics_process(false); blocked.player = target
	var trapped := boat(world,blocked,Vector3(60,0,-12),true)
	for tick in range(300): trapped.advance(1.0/60.0)
	check(blocked.routes <= 40,"Impossible combat routes have a small search budget rather than a per-frame angle sweep")
	check(trapped.global_position.is_equal_approx(Vector3(60,0,-12)),"No valid route means holding safely rather than driving through scenery")
	var shore := ShoreWater.new(); world.add_child(shore); shore.set_physics_process(false)
	var turning := boat(world,shore,Vector3(-0.01,0,-30),true)
	turning.victim = target; turning.motion.velocity = Vector3.RIGHT*2.5
	turning._flow_move(0.04,Vector3.FORWARD,2.5)
	check(shore.water_clear(turning.global_position),"Turning inertia cannot leave navigable water and invalidate future pursuit routes")
	check(turning.global_position.z < -30 and turning.speed > 0,"Combat hull redirects along the clear route instead of becoming stranded at its boundary")
	print("Flow metrics: cruise minimum ",minimum_cruise," target separation ",minimum," moving ",float(moving)/1399," passes ",attack.attack_run.passes," routes ",traffic.routes," probes ",traffic.probes)
	world.free(); print("NPC continuous flow: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
