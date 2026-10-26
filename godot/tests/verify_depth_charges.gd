extends "res://tests/test_scene_tree.gd"
const Charge = preload("res://depth_charge.gd")
const Shop = preload("res://equipment_shop.gd")
const Progress = preload("res://player_progress.gd")
class Receiver extends RigidBody3D:
	var damage := 0.0
	var attacker: Node3D
	func take_weapon_damage_from(amount: float, _point: Vector3, source: Node3D) -> void:
		damage += amount; attacker = source
class Tools extends Node:
	var equipment: Node3D
	var explosion_frames: Array[Texture2D] = []
	var explosion_sound: AudioStream
	func runtime() -> Node: return null
class Equipment extends Node3D:
	var pilot: Node3D
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func sphere(body: CollisionObject3D, radius: float = 0.1) -> void:
	var shape := CollisionShape3D.new(); shape.shape = SphereShape3D.new(); shape.shape.radius = radius; body.add_child(shape)
func receiver(world: Node3D, point: Vector3) -> Receiver:
	var body := Receiver.new(); world.add_child(body); body.position = point
	body.gravity_scale = 0.0; body.collision_layer = 8; body.collision_mask = 0; sphere(body)
	return body
func run() -> void:
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	var catalogue := preload("res://original_game_data.gd").load_catalogue(folder,false)
	var ammo := Shop.offer(catalogue,"1",1,"depth")
	var launcher := Shop.offer(catalogue,"1",1,"depthl")
	check(ammo.available and ammo.quantity == 4 and ammo.maximum == 80 and ammo.price == 1000 and ammo.sell_price == 500,"Touka sells original four-charge packs for 1000 with an 80-charge capacity")
	check(launcher.available and launcher.price == 3000,"Original opening-stage Charge Launcher is sold at Touka for 3000")
	check(not Shop.offer(catalogue,"2",2,"depth").available and not Shop.offer(catalogue,"4",2,"depthl").available,"Procha cities do not sell charges or launcher before original stage-three availability")
	check(Shop.offer(catalogue,"3",2,"depth").price == 980 and Shop.offer(catalogue,"4",3,"depth").price == 1190,"Beluga and later Tryton keep original local ammo prices")
	var progress := Progress.restore(); progress.status.credits = 10000
	check(Shop.buy(progress,launcher).is_empty() and progress.hold.depthl == 1 and progress.hold.depth == 8 and progress.status.credits == 7000,"Buying a launcher includes eight free charges")
	check(Shop.buy(progress,ammo).is_empty() and progress.hold.depth == 12 and progress.status.credits == 6000,"Ammo purchase supplies four individual usable charges")
	progress.hold.depth = 77
	check(not Shop.buy(progress,ammo).is_empty() and progress.hold.depth == 77 and progress.status.credits == 6000,"A pack cannot partially overflow capacity or take credits")
	progress.hold.depth = 76
	check(Shop.buy(progress,ammo).is_empty() and progress.hold.depth == 80,"The final complete pack fills capacity exactly")
	check(Shop.sell(progress,ammo).is_empty() and progress.hold.depth == 76 and progress.status.credits == 5500,"Selling trades four charges for the original pack resale price")
	progress.hold.depth = 3
	check(not Shop.sell(progress,ammo).is_empty() and progress.hold.depth == 3 and progress.status.credits == 5500,"Less than a full pack cannot be sold for full pack credits")
	progress.status.credits = 0
	check(not Shop.buy(progress,ammo).is_empty() and progress.hold.depth == 3,"Insufficient credits do not change ammunition")
	check(Progress.restore({"hold":{"depth":17,"depthl":1}}).hold.depth == 17,"Published beta individual ammo counts retain their meaning on load")
	var world := Node3D.new(); root.add_child(world)
	var moving := Charge.new(); world.add_child(moving); moving.position = Vector3(20,10,0); moving.linear_velocity = Vector3(2,0,0)
	for frame in range(23): await physics_frame
	check(is_instance_valid(moving) and moving.age > 0.3 and moving.age < 0.5,"Charge remains live before its original short fuse")
	check(absf(moving.linear_velocity.x - 2.0) < 0.01 and absf(moving.linear_velocity.y + moving.age * Charge.SINK_ACCELERATION) < 0.01,"Physical charge inherits horizontal momentum and sinks at original 2.5 units/s² without linear damping")
	for frame in range(65): await physics_frame
	check(not is_instance_valid(moving),"A missed depth charge explodes after the recovered fuse instead of sinking forever")
	var floor_body := StaticBody3D.new(); world.add_child(floor_body); floor_body.position = Vector3(20,0,0)
	var floor_shape := CollisionShape3D.new(); floor_shape.shape = BoxShape3D.new(); floor_shape.shape.size = Vector3(4,0.1,4); floor_body.add_child(floor_shape)
	var impact := Charge.new(); world.add_child(impact); impact.position = Vector3(20,0.3,0)
	for frame in range(35): await physics_frame
	check(not is_instance_valid(impact),"Contact with scenery detonates a charge before its fuse")
	var tools := Tools.new(); world.add_child(tools); tools.equipment = Equipment.new(); world.add_child(tools.equipment)
	var shooter := receiver(world,Vector3(0.5,0,0)); tools.equipment.pilot = shooter
	var near := receiver(world,Vector3(1,0,0)); var far := receiver(world,Vector3(0,0,2)); var outside := receiver(world,Vector3(4,0,0))
	var mine := preload("res://floating_mine.gd").new()
	mine.setup(preload("res://object_definitions.gd").FLOATING_MINE,Node3D.new(),null,true); world.add_child(mine); mine.position = Vector3(0,0,-0.4); mine.set_physics_process(false)
	var burst := Charge.new(); burst.tools = tools; world.add_child(burst); burst.freeze = true
	await physics_frame; await physics_frame
	burst.detonate(); burst.detonate()
	check(is_equal_approx(near.damage,4.0) and is_equal_approx(far.damage,2.0),"Blast damages ordinary objects with original 4/distance falloff exactly once")
	check(near.attacker == shooter and far.attacker == shooter,"Player attribution reaches ordinary damage receivers")
	check(shooter.damage == 0.0 and outside.damage == 0.0,"Original blast excludes its player and objects outside its three-unit radius")
	check(mine.dead,"Depth charges can destroy nearby mines as well as mission vents")
	await physics_frame; await physics_frame
	check(near.linear_velocity.x > 0.5 and far.linear_velocity.z > 0.1,"Blast applies outward physical impulses to nearby bodies")
	var vent := preload("res://mission_vent.gd").new(); world.add_child(vent)
	vent.open = false; vent.open_amount = 0; vent.depth_charge_from(10,Vector3(0,0.3,0),Vector3.DOWN)
	check(is_equal_approx(vent.health,1.5-0.4/2.3),"Original radial splash reaches the internal target even without a shaft-entry flag")
	vent.open = true; vent.open_amount = 1; vent.depth_charge_from(10,Vector3(0.8,0.3,0),Vector3.DOWN)
	check(not vent.dead,"Distant splash does less damage than a charge inside the shaft")
	vent.depth_charge_from(10,Vector3(0,0.3,0),Vector3.UP)
	check(not vent.dead,"Splash direction does not artificially disable distance falloff")
	vent.depth_charge_from(10,Vector3(0,0.3,0),Vector3.DOWN)
	check(not vent.dead,"Charges exploding above the hatch apply reduced splash damage")
	check(vent.accepts_charge(Vector3(0,0.3,0),Vector3.DOWN),"An open aperture accepts a descending charge from above")
	check(vent.accepts_charge(Vector3(0.7,0.3,0.4),Vector3.DOWN),"Visible rectangular opening admits off-centre charges outside the old circular gate")
	check(not vent.accepts_charge(Vector3(0.8,0.3,0),Vector3.DOWN),"A charge overlapping the visible frame cannot pass through it")
	check(vent.accepts_charge(Vector3(0.2,1.0,0),Vector3(0,-12,0),1.0/60.0),"Swept entry catches fast charges before the physics shell contact")
	vent.open_amount = 0.5
	check(vent.accepts_charge(Vector3(0,0.3,0),Vector3.DOWN) and not vent.accepts_charge(Vector3(0,0.3,0.4),Vector3.DOWN),"A partially open hatch exposes only its actual gap")
	vent.open_amount = 0
	check(not vent.accepts_charge(Vector3(0,0.3,0),Vector3.DOWN),"Closed hatch blocks physical entry")
	vent.open_amount = 1
	var before_outside := vent.health
	vent.depth_charge_from(100,Vector3(0,-6,0),Vector3.DOWN,true)
	check(vent.health == before_outside,"Internal targets outside the original three-unit blast radius are untouched")
	vent.depth_charge_from(10,Vector3(0,-1.8,0),Vector3.DOWN,true)
	check(vent.dead,"A charge inside the shaft damages the original internal target using its sustain")
	var physical_vent := preload("res://mission_vent.gd").new(); world.add_child(physical_vent)
	physical_vent.position = Vector3(100,0,0); sphere(physical_vent,0.65); physical_vent.open = true; physical_vent.open_amount = 1
	physical_vent.door = preload("res://map_document.gd").load_model("TESTDOOR",folder,true)
	physical_vent.add_child(physical_vent.door)
	physical_vent._process(0.0)
	var door_mesh: MeshInstance3D = physical_vent.door_meshes[0]
	var vertices: PackedVector3Array = door_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var closed_vertices: PackedVector3Array = door_mesh.mesh.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
	var open_gap := absf(vertices[4].z-vertices[14].z)
	var closed_gap := absf(closed_vertices[4].z-closed_vertices[14].z)
	check(open_gap > 1.3 and closed_gap < 0.001,"Original TESTDOOR geometry confirms base pose has a gap and morph pose joins the leaves")
	check(is_zero_approx(door_mesh.get_blend_shape_value(0)) and physical_vent.accepts_charge(Vector3(100,0.3,0),Vector3.DOWN),"Visible open leaves and charge admission agree")
	physical_vent.open = false; physical_vent._process(0.5)
	check(is_equal_approx(door_mesh.get_blend_shape_value(0),1.0) and not physical_vent.accepts_charge(Vector3(100,0.3,0),Vector3.DOWN),"Visible closed leaves and blocked charge admission agree")
	physical_vent.open = true; physical_vent._process(0.5)
	physical_vent.shell = StaticBody3D.new(); world.add_child(physical_vent.shell); physical_vent.shell.position = Vector3(100,-0.1,0); sphere(physical_vent.shell,1.5)
	var through_hatch := Charge.new(); world.add_child(through_hatch); through_hatch.position = physical_vent.position + Vector3.UP * 0.8
	for frame in range(3): await physics_frame
	check(through_hatch.entered_vent == physical_vent,"A real falling charge enters the open aperture and bypasses only that base shell")
	for frame in range(100): await physics_frame
	check(physical_vent.dead and not is_instance_valid(through_hatch),"A charge admitted into the open shaft reaches the target and disables it in one hit")
	var timeout_vent := preload("res://mission_vent.gd").new(); world.add_child(timeout_vent); timeout_vent.position = Vector3(150,0,0)
	var escaped := Charge.new(); world.add_child(escaped); escaped.freeze = true; escaped.entered_vent = timeout_vent
	escaped.global_position = timeout_vent.global_position+Vector3(2,0,0); escaped.age = Charge.FUSE_SECONDS
	escaped._physics_process(0.0)
	check(escaped.spent,"A charge leaving the shaft resumes its ordinary fuse instead of retaining the extension")
	var stalled := Charge.new(); world.add_child(stalled); stalled.freeze = true; stalled.entered_vent = timeout_vent
	stalled.global_position = timeout_vent.global_position; stalled.age = Charge.FUSE_SECONDS+2.01
	stalled._physics_process(0.0)
	check(stalled.spent,"A trapped shaft charge cannot postpone detonation indefinitely")
	var deep_vent := preload("res://mission_vent.gd").new(); world.add_child(deep_vent); deep_vent.position = Vector3(200,0,0); sphere(deep_vent,0.65)
	var deep_charge := Charge.new(); world.add_child(deep_charge); deep_charge.freeze = true; deep_charge.position = Vector3(200,-3.5,0)
	await physics_frame; await physics_frame
	deep_charge.detonate()
	check(is_equal_approx(deep_vent.health,1.5-0.4/1.5),"Blast finds an internal target even when its hatch collider lies outside the radius")
	world.free(); print("Depth charges: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
