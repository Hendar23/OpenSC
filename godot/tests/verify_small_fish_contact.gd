extends "res://tests/test_scene_tree.gd"
const Fish = preload("res://fish_controller.gd")
const Pilot = preload("res://submarine_controller.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	preload("res://player_storage.gd").root_override="res://tests/cache-small-fish-contact-fixtures"
	var world := Node3D.new(); root.add_child(world)
	var player := Pilot.new(); player.remember_settings=false; world.add_child(player)
	player.active=true; player.controls_enabled=false; player.surface_height=20
	player.movement.settings.forward_drag=0; player.movement.settings.lateral_drag=0
	player.movement.settings.vertical_drag=0; player.movement.settings.water_resistance=0
	player.global_position=Vector3(0,10,0); player.pending_reset=false
	var population := preload("res://wildlife_population.gd").new(); world.add_child(population); population.player=player
	var fish := Fish.new(); var visual := MeshInstance3D.new()
	var sphere := SphereMesh.new(); var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,sphere.surface_get_arrays(0))
	visual.mesh=mesh; visual.scale=Vector3.ONE*0.1
	fish.setup(visual,Vector3(0.1,10,-0.4),AABB(Vector3(-10,0,-10),Vector3(20,20,20)),20,0.06,42)
	world.add_child(fish); fish.population=population; fish.swim_speed=0; fish.roam_radius=0
	check(fish.yields_to_submarine(player),"Very small fish yields to the much larger submarine")
	var small_radius := fish.radius
	fish.radius=player.wildlife_contact_radius()
	check(not fish.yields_to_submarine(player),"Comparable-size fish keeps physical collision")
	fish.radius=player.wildlife_contact_radius()*2
	check(not fish.yields_to_submarine(player),"Larger fish keeps physical collision")
	fish.radius=small_radius
	await physics_frame; await physics_frame
	fish.global_position=Vector3(0.1,10,-0.4)
	player.linear_velocity=Vector3(0,0,-3)
	var original_fish := fish.global_position
	for frame in 12: await physics_frame
	check(player.angular_velocity.length()<0.001,"Tiny fish produces no angular jolt on the submarine")
	check(player.linear_velocity.is_equal_approx(Vector3(0,0,-3)),"Tiny fish does not slow or deflect the submarine")
	check(fish.global_position.distance_to(original_fish)>0.05,"Tiny fish is pushed out of the submarine's way")
	check(fish.get_collision_exceptions().has(player),"Only the tiny fish bypasses the rigid-body solver")
	fish.clear_ambient_state()
	check(not fish.get_collision_exceptions().has(player),"Pooling removes the previous submarine exception")
	world.free(); await process_frame
	print("Small fish contact: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
