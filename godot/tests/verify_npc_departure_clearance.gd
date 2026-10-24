extends "res://tests/test_scene_tree.gd"
const Access = preload("res://dock_access.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func settle() -> void:
	await physics_frame; await physics_frame
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var traffic := preload("res://submarine_traffic.gd").new(); world.add_child(traffic)
	traffic.set_physics_process(false); traffic.navigation_ready = true
	traffic.space = world.get_world_3d().direct_space_state
	var player := RigidBody3D.new(); player.freeze = true; player.collision_layer = 2; world.add_child(player)
	var hull := CollisionShape3D.new(); hull.shape = BoxShape3D.new(); hull.shape.size = Vector3(0.6,0.6,1)
	player.add_child(hull); traffic.player = player
	var dock := Node3D.new(); world.add_child(dock)
	var hatch := StaticBody3D.new(); dock.add_child(hatch)
	var port := {"node":dock,"entry":Vector3(0,1,0),"inside":Vector3(0,-3,0),"meshes":[],"collision":hatch}
	var model := Node3D.new(); world.add_child(model)
	var mesh := MeshInstance3D.new(); mesh.mesh = BoxMesh.new(); mesh.mesh.size = Vector3(0.8,0.6,1.2); model.add_child(mesh)
	var agent: Node3D = preload("res://trader_submarine.gd").install(model,{})
	agent.system = traffic; agent.running = true; agent.set_physics_process(false)
	agent.port = port; agent.destination = 1; agent.stage = "berth"; agent.wait = 0; agent.body.collision_layer = 0
	model.position = port.inside; model.hide()
	player.position = port.entry; await settle()
	for tick in range(20): agent._dock_step(0.1)
	check(agent.stage == "berth" and not model.visible,"NPC stays hidden in its berth while the player is over the hatch")
	check(Access.owner(port) == null and hatch.collision_layer == 1,"Waiting departure leaves the closed hatch unreserved for player docking")
	player.position = port.entry+Vector3(4,0,0); await settle()
	agent._dock_step(0.3)
	check(agent.stage == "exit_open" and model.visible and Access.owner(port) == agent,"Departure starts normally after the player clears the exit")
	agent._dock_step(0.6)
	player.position = port.entry; await settle()
	var elapsed: float = agent.elapsed
	for tick in range(10): agent._dock_step(0.1)
	check(agent.stage == "exit_open" and agent.elapsed == elapsed,"Player returning during hatch opening pauses departure")
	player.position = port.entry+Vector3(4,0,0); await settle()
	agent._dock_step(0.7)
	check(agent.stage == "ascend","Clear exit resumes the hatch sequence")
	agent._dock_step(0.4)
	var position: Vector3 = model.global_position
	player.position = port.entry; await settle()
	for tick in range(20): agent._dock_step(0.1)
	check(agent.stage == "ascend" and model.global_position == position,"Ascending NPC stops before moving through a player blocking its path")
	agent.set_local_simulation(false)
	check(agent.local_simulation and agent.stage == "ascend" and model.global_position == position,"Offscreen activity cannot skip an occupied ascent")
	player.position = port.entry+Vector3(4,0,0); await settle()
	for tick in range(40):
		if agent.stage == "travel": break
		agent._dock_step(0.1)
	check(agent.stage == "travel" and Access.owner(port) == null and agent.body.collision_layer == 10,"Clear exit completes departure and restores ordinary hull collision")
	# Clearance follows collision shapes, not just the player's centre point.
	agent.port = port
	var pod := CollisionShape3D.new(); pod.shape = SphereShape3D.new(); pod.shape.radius = 0.2; pod.position.x = -1
	player.add_child(pod); player.position = port.entry+Vector3(1.3,0,0); await settle()
	check(not agent._departure_clear(),"Player side pod overlapping the exit blocks departure even with its centre outside")
	player.position = port.entry+Vector3(0,0,2); player.rotation.y = PI/2; await settle()
	check(not agent._departure_clear(),"Rotated player hull near the first departure leg blocks the exit")
	player.position = port.entry+Vector3(0,5,0); await settle()
	check(agent._departure_clear(),"Player safely above the rising hull does not indefinitely block the dock")
	agent.stage = "berth"; agent.local_simulation = false; agent.wait = 0; model.position = port.inside
	player.position = port.entry; await settle()
	agent.advance_abstract(0.3)
	check(agent.stage == "berth" and model.global_position == port.inside,"Abstract traffic also waits instead of spawning through the player")
	player.collision_layer = 0; await settle()
	check(agent._departure_clear(),"A player already removed from outside collision does not block departures")
	player.collision_layer = 2; player.position = port.entry+Vector3(4,0,0); await settle()
	agent.advance_abstract(0.3)
	check(agent.stage == "travel","Abstract departure resumes once the player moves clear")
	world.free(); print("NPC departure clearance: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
