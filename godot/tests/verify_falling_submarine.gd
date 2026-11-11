extends "res://tests/test_scene_tree.gd"

const Wreck = preload("res://falling_submarine.gd")
const Bubbles = preload("res://propeller_bubbles.gd")
const Population = preload("res://object_population.gd")

class Player extends RigidBody3D:
	const COLLIDER_RADIUS := 0.5
	var dead := false
	var bumps := 0
	var damage := 0.0
	func receive_towing_impulse(impulse: Vector3, _offset: Vector3) -> void:
		if not impulse.is_zero_approx(): bumps += 1
	func receive_explosion(_point: Vector3, amount: float, _force: float) -> void:
		damage += amount

var world: Node3D
var emitter: Node3D
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func collider(body: CollisionObject3D, dimensions: Vector3, at: Vector3, layer: int) -> void:
	world.add_child(body)
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var box := BoxShape3D.new(); box.size = dimensions
	var shape := CollisionShape3D.new(); shape.shape = box
	body.add_child(shape)

func wreck(at: Vector3, momentum: Vector3, style: Wreck.Fall, population: Node3D, target: Node3D, follows_player: bool = false) -> CharacterBody3D:
	var hull := MeshInstance3D.new(); hull.mesh = BoxMesh.new()
	world.add_child(hull); hull.position = at
	var result := Wreck.new(); world.add_child(result); result.position = at
	result.blast = population._exploded; result.player = target; result.track_player = follows_player
	result.bubble_emitter = emitter
	result.setup([hull],momentum,style)
	hull.free()
	return result

func run() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "user://falling-submarine-test"
	DirAccess.make_dir_recursive_absolute(storage.mods_path())
	preload("res://mod_registry.gd").initialize(false)
	world = Node3D.new(); root.add_child(world)
	emitter = Bubbles.new(); world.add_child(emitter)
	emitter.surface_height = 16.0
	var target := Player.new(); target.freeze = true
	collider(target,Vector3.ONE,Vector3(1.1,1.9,0),2)
	var floor_body := StaticBody3D.new()
	collider(floor_body,Vector3(30,1,30),Vector3(0,-0.5,0),1)
	var population := Population.new(); world.add_child(population)
	population.player = target
	population.set_process(false); population.set_physics_process(false)
	await physics_frame
	check(Wreck.choose_fall(3,0.19) == Wreck.Fall.INSTANT and Wreck.choose_fall(0,0.2) == Wreck.Fall.SPIN and Wreck.choose_fall(3,0.2) == Wreck.Fall.ARC,"All three death paths can be chosen")
	preload("res://propeller_bubbles.gd").set_limit(200)
	var arc := wreck(Vector3(0,2.0,0),Vector3(4,0,0),Wreck.Fall.ARC,population,target)
	var end_points: Array[Vector3] = []
	arc.detonated.connect(func() -> void: end_points.append(arc.position))
	for i in range(150):
		await physics_frame
		if not is_instance_valid(arc): break
	check(target.bumps == 1,"Falling hull gives the player a physical bump")
	check(target.damage > 0,"The final blast reaches the player via gameplay blast damage")
	check(end_points.size() == 1 and end_points[0].y < 0.8,"Bumped hull explodes once at the seabed: " + str(end_points))
	check(emitter.particles.size() == 96 and emitter.particles.all(func(b: Dictionary) -> bool: return b.position.distance_to(end_points[0]) < 0.7),"Impact emits a full bubble cloud from the blast centre")
	emitter.advance(5.0,false)
	check(emitter.particles.size() == 96,"Bubble cloud remains after the fireball has faded")
	emitter.advance(20.0,false)
	check(emitter.particles.is_empty(),"Bubbles clear when they reach the surface")
	var clear_arc := wreck(Vector3(0,6,6),Vector3(4,0,0),Wreck.Fall.ARC,population,target)
	for i in range(15): await physics_frame
	check(clear_arc.position.x > 0.5 and clear_arc.position.y < 6.0,"Unobstructed wreck carries forward momentum while dropping")
	clear_arc.free()
	var spin := wreck(Vector3(8,6,0),Vector3.ZERO,Wreck.Fall.SPIN,population,target)
	await physics_frame; await physics_frame
	check(spin.position.y < 6.0 and is_equal_approx(spin.position.x,8.0) and not is_zero_approx(spin.rotation.y),"Stationary hull sinks and rotates with no forward drift")
	spin.free()
	target.dead = true
	var deep := wreck(Vector3(50,50,0),Vector3.ZERO,Wreck.Fall.SPIN,population,target,true)
	var player_explosions: Array[Vector3] = []
	deep.detonated.connect(func() -> void: player_explosions.append(target.position))
	await physics_frame; await physics_frame
	check(target.position.is_equal_approx(deep.position) and player_explosions.is_empty(),"Dead player camera anchor follows the falling hull before the final blast")
	deep.elapsed = Wreck.MAX_FALL_TIME
	await physics_frame; await physics_frame
	check(not is_instance_valid(deep) and player_explosions.size() == 1,"A deep-water player wreck signals the final blast once when its lifetime expires")
	var instant := wreck(Vector3(50,50,0),Vector3.ZERO,Wreck.Fall.INSTANT,population,target)
	await process_frame; await process_frame
	check(not is_instance_valid(instant),"An instant wreck detonates without falling")
	world.free()
	print("Falling submarine: %d failures" % failures)
	quit(1 if failures else 0)
