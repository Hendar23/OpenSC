extends SceneTree
const Defence = preload("res://dock_defence.gd")
const Fish = preload("res://fish_controller.gd")
const Population = preload("res://wildlife_population.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var population := Population.new(); population.world = world; world.add_child(population); population.set_physics_process(false)
	var port := Node3D.new(); port.set_meta("city_id",0); world.add_child(port)
	port.position = Vector3(10,2,-5); port.rotation.y = PI * 0.5
	var camera := Camera3D.new(); world.add_child(camera); camera.current = true
	var fish := Fish.new()
	fish.setup(Node3D.new(),port.to_global(Defence.SEARCH_CENTER),AABB(Vector3.ONE * -100,Vector3.ONE * 200),100,0.2,1)
	fish.population = population; fish.swim_speed = 0; fish.configure_health(100); fish.damage_sustain = 0.01
	population.add_child(fish)
	var defence := Defence.new(); world.add_child(defence); defence.setup(world,population); defence.set_physics_process(false)
	check(defence.ports.size() == 1,"World docks receive defence automatically")
	defence._physics_process(0.02)
	check(fish.health == 100,"Damage waits for an original 25 Hz tick")
	defence._physics_process(0.02)
	check(is_equal_approx(fish.health,100.0 - Defence.DAMAGE * fish.damage_sustain),"Dock tick uses the same damage protection as the submarine zapper")
	var state: Dictionary = defence.ports[0]
	check(state.arcs.size() == 3,"All three spike emitters produce arcs")
	for index in range(3):
		check(state.arcs[index].beam_start.is_equal_approx(port.to_global(Defence.EMITTERS[index])),"Emitter follows dock rotation and translation")
		check(not state.arcs[index].is_physics_processing(),"Environmental arc does not run player weapon logic")
	defence._physics_process(0.96)
	check(is_equal_approx(fish.health,100.0 - Defence.DAMAGE * fish.damage_sustain * 25),"Damage runs at 25 Hz without triple damage from three arcs")
	var dock_loss := Defence.DAMAGE * fish.damage_sustain
	var before_sub: float = fish.health
	preload("res://original_damage.gd").weapon(fish,preload("res://submarine_weapons.gd").DEFAULTS.damage_per_tick,port.global_position)
	check(is_equal_approx(dock_loss,3.0 * (before_sub - fish.health)),"Default dock damage is three times standard sub damage against the same wildlife")
	defence.damage_per_tick = 0
	var before_zero: float = fish.health; defence._physics_process(0.04)
	check(fish.health == before_zero,"Zero damage disables harm")
	defence.damage_per_tick = Defence.DAMAGE
	fish.position = port.to_global(Defence.SEARCH_CENTER) + Vector3(3.1,0,0)
	check(defence._target(port) == fish,"Acquisition includes the creature body radius")
	fish.position.x += 1
	check(defence._target(port) == null,"Wildlife outside dock range is safe")
	fish.position = port.to_global(Defence.SEARCH_CENTER)
	fish.set_meta("original_object_id",73)
	check(defence._target(port) == null,"Original tagged mission fish are protected")
	fish.set_meta("original_object_id",0); fish.set_meta("wildlife_awake",false)
	check(defence._target(port) == null,"Sleeping wildlife is not targeted")
	fish.set_meta("wildlife_awake",true); fish.dead = true
	check(defence._target(port) == null,"Dead wildlife is not targeted")
	fish.dead = false
	population.simulating = false; var health: float = fish.health; defence._physics_process(1.0)
	check(fish.health == health and state.target == null and not state.arcs[0].firing,"Suspended world stops damage and arcs")
	population.simulating = true; defence._physics_process(0.04)
	check(fish.health < health,"Resuming restores dock defence")
	port.set_meta("city_id",5); defence._stop(state); health = fish.health; defence._physics_process(0.04)
	check(fish.health < health and not state.arcs[0].firing,"Aquatraz retains original damage without ordinary dock spike arcs")
	port.set_meta("city_id",0); fish.configure_health(0.1); fish.damage_sustain = 1.0; defence._physics_process(0.04)
	check(fish.dead and not state.arcs[0].firing,"Fatal zap uses creature death and stops arcs")
	world.free()
	print("Dock defence: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
