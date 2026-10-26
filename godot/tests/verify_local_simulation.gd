extends SceneTree
const Fish = preload("res://fish_controller.gd")
const Population = preload("res://wildlife_population.gd")
const Traffic = preload("res://submarine_traffic.gd")
const Identity = preload("res://entity_identity.gd")
var checks := 0
var failures := 0
class Observer extends Node3D:
	var dead := false
	var active := true
	var controls_enabled := true
class QueryCounter extends Traffic:
	var queries := 0
	func segment_clear(_a: Vector3, _b: Vector3) -> bool:
		queries += 1; return true
	func water_clear(_point: Vector3) -> bool:
		queries += 1; return true
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	world.set_meta("bounds",AABB(Vector3.ONE * -200,Vector3.ONE * 400)); world.set_meta("surface_height",100.0)
	var observer := Observer.new(); world.add_child(observer)
	var camera := Camera3D.new(); world.add_child(camera); camera.far = 20
	var activity := preload("res://actor_activity.gd").new(); world.add_child(activity); activity.set_physics_process(false)
	activity.cameras.append(camera); activity.refresh_views()
	check(activity.in_sight(Vector3(0,0,-10)) and not activity.in_sight(Vector3(0,0,10)),"Ground visibility uses the camera frustum")
	var rear := Camera3D.new(); world.add_child(rear); rear.far = 20; rear.rotation.y = PI
	activity.cameras.append(rear); activity.refresh_views()
	check(activity.in_sight(Vector3(0,0,10)),"An active rear camera keeps actors in sight")
	check(not activity.nearby(Vector3(100,0,0)),"Cameras never activate distant actors")
	var turret_system := preload("res://turret_system.gd").new(); world.add_child(turret_system)
	var turret_model := Node3D.new(); world.add_child(turret_model); turret_model.position = Vector3(100,0,0)
	var turret := preload("res://gun_turret.gd").install(turret_model)
	turret_system.turrets.append(turret); activity.turrets = turret_system
	turret.cooldown = 4; turret.retaliation = 8
	activity.update_actors(1)
	turret._physics_process(1)
	check(not turret.local_simulation and not turret.is_physics_processing() and turret.cooldown == 4 and turret.retaliation == 8,"Distant turrets freeze targeting and combat timers")
	turret_model.position = Vector3(0,0,10); activity.update_actors(0)
	check(turret.local_simulation and turret.is_physics_processing(),"Turrets resume within rear camera range")
	activity.cameras.erase(rear); activity.refresh_views(); activity.update_actors(0)
	check(turret.local_simulation,"Nearby turrets remain active behind the main camera")
	turret_model.position = Vector3(100,0,0); activity.update_actors(0)
	check(not turret.local_simulation,"Leaving camera range freezes the turret again")
	var traffic := QueryCounter.new(); world.add_child(traffic); traffic.set_physics_process(false)
	traffic.player = observer; traffic.navigation_ready = true
	traffic.graph.add_point(1,Vector3(100,0,0)); traffic.graph.add_point(2,Vector3(110,0,0)); traffic.graph.connect_points(1,2)
	var dock := Node3D.new(); world.add_child(dock); dock.set_meta("city_id",1)
	traffic.ports.append({"node":dock,"race":1,"entry":Vector3(110,0,0),"inside":Vector3(110,-2,0),"meshes":[]})
	var model := Node3D.new(); world.add_child(model); model.position.x = 100
	Identity.assign_id(model,"fixture/submarine")
	var agent := preload("res://trader_submarine.gd").install(model,{})
	agent.system = traffic; traffic.traders.append(agent); agent.reset(); agent.wait = 0; agent.running = true
	activity.submarines = traffic; activity.update_actors(1.0)
	check(not agent.local_simulation and not agent.is_physics_processing() and agent.body.collision_layer == 0 and agent.body.collision_mask == 0,"Distant submarines have no callbacks or collisions")
	check(is_equal_approx(agent.global_position.x,102.0) and traffic.queries == 0,"Abstract travel advances at the configured speed without physics queries")
	var health: float = agent.health.remaining; agent.take_weapon_damage_from(1,Vector3.ZERO,observer)
	check(agent.health.remaining == health,"Abstract NPCs cannot participate in combat")
	agent.mission_owner = "escort"; var saved := traffic.snapshot()
	traffic.restore(saved); agent.set_local_simulation(false)
	check(Traffic.valid_snapshot(saved) and agent.mission_owner == "escort" and is_equal_approx(agent.global_position.x,102.0),"Abstract travel and mission state survive save restoration")
	var invalid := saved.duplicate(true); invalid["fixture/submarine"].route[0][0] = NAN
	check(not Traffic.valid_snapshot(invalid),"Non-finite abstract route state is rejected")
	agent.wait = 0; agent.advance_abstract(5)
	check(agent.stage == "berth" and agent.journey_count == 1 and traffic.queries == 0,"Hidden arrivals complete without collisions or dock animation")
	model.position = Vector3(0,0,-10); agent.stage = "travel"; agent.destination = 0; agent.port = {}; agent.path.clear()
	activity.update_actors(0)
	await physics_frame
	check(agent.local_simulation and agent.body.collision_layer == 10 and not agent.body.get_child(0).disabled,"Entering viewing range restores physical representation")
	agent.set_physics_process(false); traffic.traders.clear()
	var vehicle_model := Node3D.new(); world.add_child(vehicle_model); vehicle_model.position = Vector3(0,0,30)
	var vehicle := preload("res://ground_vehicle.gd").install(vehicle_model)
	vehicle.running = true; vehicle.waiting = 5; vehicle.respawn_remaining = 3
	var ground := preload("res://ground_traffic.gd").new(); world.add_child(ground); ground.vehicles.append(vehicle); activity.ground = ground
	activity.update_actors(0)
	var pose := vehicle_model.transform; var probes: int = vehicle.probes
	vehicle._physics_process(100)
	check(not vehicle.local_simulation and vehicle_model.transform == pose and vehicle.probes == probes and vehicle.waiting == 5 and vehicle.respawn_remaining == 3,"Unseen ground vehicles freeze movement, probes and timers completely")
	vehicle_model.position.z = -10; activity.update_actors(0)
	check(vehicle.local_simulation and vehicle.body.collision_layer == 9,"Ground vehicles resume when a camera sees them")
	vehicle.set_physics_process(false)
	var pop := Population.new(); world.add_child(pop); pop.world = world; pop.player = observer; pop.streaming = true; pop.set_physics_process(false)
	pop.view_camera = camera; pop.visibility_range = 20; pop.activity = activity
	var species := {"id":"fixture","model":"fixture","scale_min":100,"scale_max":100,"speed":1.0,"group_behaviour":"schooling","response":"ignore","mobility":"swimming","health":10.0}
	pop.definitions.fixture = species; pop.templates.fixture = Node3D.new(); pop.model_bounds.fixture = AABB(Vector3.ONE * -0.1,Vector3.ONE * 0.2)
	var group := {"id":"local","species":"fixture","position":[0,0,-15],"count_min":1,"count_max":1,"radius":5.0}
	pop.spawn_budget = 1; var rng := RandomNumberGenerator.new(); rng.seed = 42
	var first: Node3D = pop._spawn_group(group,rng)[0]; first.set_physics_process(false)
	first.position = Vector3(100,0,0); first.health = 1; first.combat.target = agent.body; first.defense_timer = 3
	pop._stream_update()
	check(pop.get_child_count() == 0 and pop.pooled_count == 1 and not first.is_inside_tree(),"Distant wildlife leaves no individual or physics body in the world")
	check(first.health == first.max_health and first.position == Vector3.ZERO and first.combat.target == null and first.defense_timer == 0,"Pooled wildlife retains resources but no previous creature history")
	pop.spawn_budget = 1; var second: Node3D = pop._spawn_group(group,rng)[0]
	check(first == second and pop.pooled_count == 0 and second.visible and second.health == 10,"Local spawning reuses a clean pooled representation")
	second.set_physics_process(false); second.position = Vector3(0,0,-16)
	check(pop.detailed(second),"Nearby wildlife retains detailed movement")
	second.position = Vector3(0,0,-pop.smooth_range()+1)
	check(pop.detailed(second),"Wildlife keeps smooth movement through the expanded detailed range")
	var far_z := -pop.smooth_range()-8.0
	second.position = Vector3(0,0,far_z); second.direction = Vector3.RIGHT; second.goal = Vector3(0,0,-100); second.turn_timer = 100
	check(not pop.detailed(second),"Far wildlife still uses simplified movement")
	second.combat.scan_timer = 7; second._physics_process(1.0 / 60.0)
	check(second.combat.scan_timer == 7 and second.animation_time > 0,"Distant wildlife uses movement and animation without perception or combat")
	check(second.basis.z.normalized().dot(second.velocity.normalized()) > 0.999,"Simplified fish face their travel direction after steering")
	second.direction = Vector3.FORWARD
	var wall := StaticBody3D.new(); world.add_child(wall); wall.position = Vector3(0,0,far_z-7)
	var wall_shape := CollisionShape3D.new(); wall_shape.shape = BoxShape3D.new(); wall_shape.shape.size = Vector3(20,10,0.2); wall.add_child(wall_shape)
	second.swim_speed = 6; second.ambient_clock = 0
	await physics_frame
	for tick in range(180): second._physics_process(1.0 / 60.0)
	check(second.position.z > wall.position.z,"Cosmetic swimming stops and turns before a wall without continuous body motion tests")
	second.mission_owner = "objective"; second.position.x = 100; pop._stream_update()
	check(second.get_parent() == pop and second.mission_owner == "objective","Mission-owned wildlife is retained explicitly")
	pop.document = {"groups":[],"species":[]}; pop.reroll()
	check(second.get_parent() == pop and second.mission_owner == "objective","Ambient rerolls preserve mission-owned creatures")
	world.free()
	print("Local simulation: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
