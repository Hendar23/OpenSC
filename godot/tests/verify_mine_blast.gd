extends SceneTree
const Pilot = preload("res://submarine_controller.gd")
const Population = preload("res://object_population.gd")
class FakeJoy extends RefCounted:
	var calls := 0
	func get_connected_joypads() -> Array: return [0]
	func start_joy_vibration(_device: int, _weak: float, _strong: float, _duration: float) -> void: calls += 1
	func stop_joy_vibration(_device: int) -> void: pass
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var pilot := Pilot.new(); pilot.remember_settings = false; root.add_child(pilot)
	pilot.set_physics_process(false); pilot.mass = 100.0; pilot.active = true
	pilot.visual = Node3D.new(); pilot.add_child(pilot.visual)
	var joy := FakeJoy.new(); pilot.impact_rumble.joy_input = joy
	var population := Population.new(); root.add_child(population); population.player = pilot
	check(is_equal_approx(preload("res://original_damage.gd").mine_raw_damage(17.5,2.0),0.25),"Ordinary targets receive original inflict/distance before their sustain")
	check(is_equal_approx(preload("res://original_damage.gd").mine_raw_damage(17.5,2.0,true),1.0),"Other mines receive the recovered fourfold chain-reaction strength")
	var resistant := preload("res://floating_mine.gd").new()
	resistant.setup(preload("res://object_definitions.gd").FLOATING_MINE,Node3D.new(),null,true); population.add_child(resistant)
	preload("res://original_damage.gd").weapon(resistant,2.5,Vector3.ZERO)
	check(is_equal_approx(resistant.health,0.25) and not resistant.dead,"Mine health uses the original 0.1 weapon sustain")
	preload("res://original_damage.gd").weapon(resistant,2.5,Vector3.ZERO)
	check(is_zero_approx(resistant.health) and not resistant.dead,"Original mine callback detonates below zero shields")
	preload("res://original_damage.gd").weapon(resistant,0.1,Vector3.ZERO)
	check(resistant.dead,"Further weapon damage detonates a depleted mine")
	resistant.free()
	pilot.position = Vector3.RIGHT
	await physics_frame; await physics_frame
	var hull := CollisionShape3D.new(); var hull_shape := SphereShape3D.new(); hull_shape.radius = 0.54; hull.shape = hull_shape; pilot.add_child(hull)
	var contact := preload("res://floating_mine.gd").new()
	contact.setup(preload("res://object_definitions.gd").FLOATING_MINE,Node3D.new(),null,true); population.add_child(contact)
	contact.set_physics_process(false); contact.player = pilot
	pilot.position = Vector3.RIGHT * 1.2
	await physics_frame; await physics_frame
	contact._physics_process(0.0)
	check(not contact.dead,"Default mine does not use the old centre proximity trigger")
	pilot.position = Vector3.RIGHT * 0.9
	await physics_frame; await physics_frame
	contact._physics_process(0.0)
	check(contact.dead,"Mine detonates when its sphere touches the actual hull collider")
	contact.free(); hull.free(); pilot.position = Vector3.RIGHT
	await physics_frame; await physics_frame
	population._exploded(Vector3.ZERO,30.0,2.0,300.0)
	await physics_frame; await physics_frame
	check(pilot.linear_velocity.x > 1.2 and absf(pilot.linear_velocity.z) < 0.01, "Blast pushes the real rigid body away with distance falloff")
	check(joy.calls == 1, "Blast damage triggers controller feedback once")
	check(is_equal_approx(pilot.health,70.0),"A 30-damage mine removes 30 percent of starting shield capacity")
	var before := pilot.linear_velocity.x
	population._exploded(Vector3(-10,0,0),30.0,2.0,300.0)
	check(joy.calls == 1 and is_equal_approx(pilot.linear_velocity.x,before), "Outside the blast radius there is no force or rumble")
	population._exploded(pilot.position - Vector3.RIGHT,30.0,2.0,0.0)
	check(joy.calls == 2 and is_equal_approx(pilot.linear_velocity.x,before), "Zero blast impulse disables movement independently of damage feedback")
	population._exploded(pilot.position - Vector3.RIGHT,0.0,2.0,300.0)
	await physics_frame; await physics_frame
	check(pilot.linear_velocity.x > before + 1.2 and joy.calls == 2, "Zero damage still allows force without damage rumble")
	pilot.controls_enabled = false
	before = pilot.linear_velocity.x
	population._exploded(pilot.position - Vector3.RIGHT,30.0,2.0,300.0)
	check(joy.calls == 2 and is_equal_approx(pilot.linear_velocity.x,before), "Docking manoeuvres are not interrupted by explosions")
	pilot.controls_enabled = true; pilot.restore_health()
	population._exploded(pilot.position - Vector3.RIGHT * 2.0,17.5,3.0,0.0)
	check(is_equal_approx(pilot.health,91.25),"Original floating mine loses half its one-unit damage at two units")
	pilot.restore_health(); pilot.hull_rating = 200.0
	population._exploded(pilot.position - Vector3.RIGHT,17.5,3.0,0.0)
	check(is_equal_approx(pilot.health,97.5),"Blast damage applies upgraded hull sustain exactly once")
	pilot.hull_rating = 100.0; pilot.restore_health()
	for remaining in [65.0,30.0,0.0]:
		var mine := preload("res://floating_mine.gd").new()
		var definition: Dictionary = preload("res://object_definitions.gd").FLOATING_MINE.duplicate(true)
		definition.damage = 35.0; definition.blast_force = 0.0
		mine.setup(definition,Node3D.new(),null,true); population.add_child(mine)
		mine.global_position = pilot.global_position - Vector3.RIGHT
		mine.exploded.connect(population._exploded.bind(0.0))
		mine.detonate()
		await process_frame; await process_frame
		check(is_equal_approx(pilot.health,remaining),"An isolated 35-damage mine leaves %d shields" % int(remaining))
		mine.free()
	check(pilot.dead,"Three isolated 35-damage mines destroy a submarine with 100 shields")
	pilot.free(); population.free()
	print("Mine blast: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
