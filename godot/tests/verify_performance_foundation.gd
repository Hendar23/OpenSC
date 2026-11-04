extends SceneTree
const Fish = preload("res://fish_controller.gd")
const Population = preload("res://wildlife_population.gd")
const Identity = preload("res://entity_identity.gd")
var checks := 0
var failures := 0
var alerts := 0
var deaths: Array = []
class Observer extends Node3D:
	var dead := false
	var active := false
	var controls_enabled := false
class FlatPopulation extends Population:
	var probes := 0
	func floor_contact(point: Vector3) -> Dictionary:
		probes += 1
		return {"position":Vector3(point.x,0,point.z),"normal":Vector3.UP}
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var map := preload("res://hud_map.gd").new()
	map.bounds = AABB(Vector3(-50,-5,-50),Vector3(100,10,100)); map.initialize_exploration()
	map.height_samples.resize(map.RESOLUTION*map.RESOLUTION); map.height_samples.fill(0)
	# A ridge tests that batching preserves occlusion as well as feathering.
	for y in range(map.RESOLUTION): map.height_samples[y*map.RESOLUTION+260] = 8
	var observer_point := Vector3(-1,2,0)
	map.explore(observer_point)
	var expected: PackedByteArray = map.explored.get_data()
	map.reset_exploration(); map.explore(observer_point,1)
	check(not map._exploration_work.is_empty(),"Exploration yields instead of processing a full sightline batch in one frame")
	var batches := 0
	while not map._exploration_work.is_empty() and batches < 1000:
		map.explore(observer_point,1); batches += 1
	check(map._exploration_work.is_empty() and map.explored.get_data() == expected,"Budgeted map reveals preserve the synchronous mask including ridge occlusion")
	map.reset_exploration(); map.explore(observer_point,1); map.finish_exploration()
	check(map._exploration_work.is_empty() and map.explored.get_data() == expected,"Saving can flush pending exploration without losing discovered pixels")
	map.reset_exploration(); map.explore(observer_point,1); map.reset_exploration()
	check(map._exploration_work.is_empty() and map.explored.get_data().count(0) == map.RESOLUTION*map.RESOLUTION,"New-game exploration reset discards queued work")
	var expired := Node3D.new(); expired.free()
	check(not preload("res://wildlife_combat.gd").alive(expired),"Expired prey/threat references are harmless before the next perception scan")
	var world := Node3D.new(); root.add_child(world)
	var camera := Camera3D.new(); world.add_child(camera)
	var reflection := preload("res://canopy_reflections.gd").new(); world.add_child(reflection)
	var glass: Array[ShaderMaterial] = []; reflection.setup(world.get_world_3d(),glass,camera)
	var captured := {}
	for frame in range(6):
		reflection.update_capture(1.0/60,true,camera)
		var active := 0
		for index in range(6):
			if reflection.views[index].render_target_update_mode == SubViewport.UPDATE_ONCE: captured[index] = true; active += 1
		check(active == 1,"Cockpit reflections render one extra view per frame")
	check(captured.size() == 6 and reflection.warmed,"Six consecutive frames refresh every reflection direction")
	reflection.update_capture(0.1,false,camera)
	check(not reflection.warmed and reflection.views.all(func(view: SubViewport) -> bool: return view.render_target_update_mode == SubViewport.UPDATE_DISABLED),"Hidden cockpit disables reflection rendering")
	reflection.free(); camera.free()
	var pop := FlatPopulation.new(); world.add_child(pop)
	pop.world = world; pop.streaming = true; pop.set_physics_process(false)
	var observer := Observer.new(); world.add_child(observer); pop.player = observer
	var fishes: Array[Node3D] = []
	for index in range(2):
		var fish := Fish.new()
		fish.setup(Node3D.new(),Vector3(10 + index * 10,0,10),AABB(Vector3.ONE * -1000,Vector3.ONE * 2000),100,0.2,42)
		fish.population = pop; pop.add_child(fish)
		fish.mission_owner = "movement_fixture"
		fish.swim_speed = 6; fish.attack_range = 0; fish.flee_range = 0
		fish.direction = Vector3.BACK; fish.goal = fish.position + Vector3.BACK * 100
		fish.turn_timer = 100; fish.roam_radius = 1000; fish.visual_animation_enabled = index == 0
		fishes.append(fish)
	await physics_frame
	var starts := [fishes[0].position,fishes[1].position]
	for tick in range(126): await physics_frame
	var visible_distance: float = fishes[0].position.distance_to(starts[0])
	var hidden_distance: float = fishes[1].position.distance_to(starts[1])
	check(absf(visible_distance - hidden_distance) < 0.65,"Offscreen movement preserves speed within one batched step")
	check(absf(fishes[1].velocity.length() - 6.0) < 0.001,"Offscreen velocity remains in world units per second")
	for fish in fishes: fish.set_physics_process(false)
	var crawler: Node3D = fishes[0]; pop.probes = 0
	crawler._crawler_contact(crawler.global_position)
	for index in range(12): crawler._crawler_contact(crawler.global_position + Vector3.RIGHT * 0.001)
	check(pop.probes == 21,"Distant flat support reuses corner probes while keeping a live centre probe")
	crawler._crawler_contact(crawler.global_position + Vector3.RIGHT)
	check(pop.probes == 30,"Large displacement invalidates cached crawler support")
	var wall := StaticBody3D.new(); world.add_child(wall); wall.position = Vector3(20,0,25)
	var wall_shape := CollisionShape3D.new(); wall_shape.shape = BoxShape3D.new(); wall_shape.shape.size = Vector3(4,4,0.2); wall.add_child(wall_shape)
	fishes[1].set_physics_process(true)
	for tick in range(60): await physics_frame
	check(fishes[1].position.z < 25,"Batched movement cannot pass through a wall")
	for fish in fishes: fish.free()
	wall.free()
	var traffic := preload("res://submarine_traffic.gd").new(); world.add_child(traffic)
	traffic.navigation_ready = true; traffic.set_physics_process(false)
	var model := Node3D.new(); model.name = "AuthoredTrader"; world.add_child(model); model.position.z = 1
	Identity.assign_id(model,Identity.authored("fixture/trader",0))
	var trader := preload("res://trader_submarine.gd").install(model,{})
	trader.system = traffic; traffic.traders.append(trader); trader.reset(); trader.running = true; trader.set_physics_process(false)
	trader.attacked.connect(func(_faction: int) -> void: alerts += 1)
	trader.destroyed.connect(func(id: String, attacker: String) -> void: deaths.append([id,attacker]))
	var predator := Fish.new(); predator.setup(Node3D.new(),Vector3.ZERO,AABB(Vector3.ONE * -100,Vector3.ONE * 200),100,0.2,42)
	predator.population = pop; predator.response = "attack"; predator.direction = Vector3.BACK
	pop.add_child(predator); predator.set_physics_process(false)
	predator.configure_combat({}); predator.combat.settings.has_zapper = false
	predator.combat.settings.bite_range = 2; predator.combat.settings.bite_damage = 1; predator.combat.target = trader.body
	await physics_frame
	predator.combat.attack(1.0 / 60.0)
	check(is_equal_approx(trader.health.remaining,9.7) and alerts == 0,"Custom wildlife bites apply raw damage with the receiver's sustain once and never blame the player")
	trader.mission_owner = "escort"; var saved: Dictionary = traffic.snapshot()
	var id := Identity.of(trader)
	check(saved.has(id) and Identity.of(trader.body) == id,"Actor controller and collider share persistent save identity")
	model.name = "Renamed"; var container := Node3D.new(); world.add_child(container); model.reparent(container)
	trader.health.remaining = 1; trader.mission_owner = ""; traffic.restore(saved)
	check(is_equal_approx(trader.health.remaining,9.7) and trader.mission_owner == "escort","Save restoration survives runtime renaming/reparenting")
	Identity.assign_id(observer,"player"); traffic.player = observer
	trader.take_weapon_damage_from(1000,Vector3.ZERO,observer)
	check(deaths == [[id,"player"]],"Destruction reports stable target and attacker identities once")
	trader.take_weapon_damage_from(1000,Vector3.ZERO,observer)
	check(deaths.size() == 1,"Repeated damage cannot replay destruction")
	saved = traffic.snapshot(); trader.mission_owner = ""; traffic.restore(saved)
	traffic.replenish_docked(1)
	check(trader.dead,"Saved mission ownership suppresses generic dock respawn")
	trader.mission_owner = ""; traffic.replenish_docked(1)
	check(not trader.dead and deaths.size() == 1,"Unclaimed NPCs still replenish without destruction events")
	var state := preload("res://mission_state.gd").empty()
	state.active.escort = {"target":id,"delivered":2}; state.completed.intro = true
	var restored := preload("res://player_progress.gd").restore({"missions":JSON.parse_string(JSON.stringify(state))})
	check(restored.missions.version == state.version and restored.missions.active.escort.target == id and restored.missions.active.escort.delivered == 2 and restored.missions.completed.intro == true,"Mission state round-trips through JSON and player progress")
	state.active.escort.delivered = NAN
	check(not preload("res://mission_state.gd").valid(state),"Non-finite mission progress is rejected")
	_check_wakes(world)
	world.free()
	print("Performance foundation: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func _check_wakes(world: Node3D) -> void:
	preload("res://propeller_bubbles.gd").set_limit(-1)
	var camera := Camera3D.new(); world.add_child(camera); camera.make_current()
	var wake := preload("res://propeller_bubbles.gd").new(); world.add_child(wake)
	wake.set_physics_process(false); wake.set_process(false); wake.surface_height = 10.0
	var normal := {"replay_id":1,"position":Vector3(2,2,2),"drift":Vector3(0.1,0,0.2),"rise":1.0,"age":0.0,"size":0.08}
	var timed := {"replay_id":2,"position":Vector3(0.5,9.6,0),"drift":Vector3.ZERO,"rise":0.1,"age":0.6,"size":0.1,"end_size":0.4,"lifetime":1.0,"opacity":0.5}
	wake.particles.assign([normal.duplicate(),{"replay_id":3,"position":Vector3(0,10,0),"drift":Vector3.ZERO,"rise":1.0,"age":0.0,"size":0.1},timed.duplicate()])
	wake.advance(0.1,false); wake.advance(0.1,false)
	check(wake.particles.size() == 2 and wake.particles[0].replay_id == 1 and wake.particles[1].replay_id == 2,"Wake compaction preserves survivor identities/order across catch-up ticks")
	var expected: Vector3 = normal.position+normal.drift*((1.0-exp(-12.0*0.2))/12.0)+Vector3.UP*0.2
	check(wake.particles[0].position.is_equal_approx(expected) and is_equal_approx(wake.particles[0].age,0.2),"Deferred rendering retains every physics tick of bubble travel and age")
	check(wake.instances.visible_instance_count == 0,"Catch-up ticks do not submit intermediate render buffers")
	wake._update_instances()
	check(wake.instances.visible_instance_count == 2 and wake.render_buffer.size() == wake.capacity*16,"One frame upload includes every surviving bubble")
	var size := 0.08*(1.0+0.2/6.0*0.45)
	check(is_equal_approx(wake.render_buffer[0],size) and Vector3(wake.render_buffer[3],wake.render_buffer[7],wake.render_buffer[11]).is_equal_approx(expected),"Bulk buffer preserves original scale/translation layout")
	var point: Vector3 = wake.particles[1].position
	var opacity := 0.5*smoothstep(0.25,1.25,camera.global_position.distance_to(point))*smoothstep(0.0,0.2,10.0-point.y)*smoothstep(0.0,0.5,0.2)
	check(is_equal_approx(wake.render_buffer[16],0.34) and is_equal_approx(wake.render_buffer[31],opacity),"Timed bubbles retain growth plus camera/surface/lifetime fading")
	wake.advance(0.3)
	check(wake.particles.size() == 1 and wake.instances.visible_instance_count == 1,"Expired timed bubbles leave no stale visible instance")
	wake.clear();wake.advance(0)
	check(wake.instances.visible_instance_count == 0 and wake.particles.is_empty(),"Clearing a wake empties the render and replay source")
	for index in wake.capacity: wake.particles.append(normal.duplicate())
	wake.advance(0.01)
	check(wake.particles.size() == wake.capacity and wake.instances.visible_instance_count == wake.capacity,"Full original wake capacity remains available without quality reduction")
	wake.free();camera.free()
