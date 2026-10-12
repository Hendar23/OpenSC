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
	var world := Node3D.new(); root.add_child(world)
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
	check(is_equal_approx(trader.health.remaining,9.9) and alerts == 0,"Wildlife bites retain damage but never blame the player")
	trader.mission_owner = "escort"; var saved: Dictionary = traffic.snapshot()
	var id := Identity.of(trader)
	check(saved.has(id) and Identity.of(trader.body) == id,"Actor controller and collider share persistent save identity")
	model.name = "Renamed"; var container := Node3D.new(); world.add_child(container); model.reparent(container)
	trader.health.remaining = 1; trader.mission_owner = ""; traffic.restore(saved)
	check(is_equal_approx(trader.health.remaining,9.9) and trader.mission_owner == "escort","Save restoration survives runtime renaming/reparenting")
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
	world.free()
	print("Performance foundation: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
