extends SceneTree

const Pilot = preload("res://submarine_controller.gd")
const Assets = preload("res://clump_loader.gd")
const Paths = preload("res://asset_paths.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)

func occupied(space: PhysicsDirectSpaceState3D, point: Vector3) -> bool:
	var sphere := SphereShape3D.new(); sphere.radius = 0.012
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere; query.transform.origin = point; query.collision_mask = 2
	return not space.intersect_shape(query).is_empty()

func _run() -> void:
	Mods.initialize(false)
	var world := Node3D.new(); root.add_child(world)
	var pilot := Pilot.new(); pilot.remember_settings = false; world.add_child(pilot)
	var visual := Assets.load_submarine(Paths.find_game_folder().path_join("CLUMPS/SUB.DFF"))
	visual.scale *= pilot.VISUAL_SCALE; visual.rotation.y = PI
	pilot.add_child(visual); pilot.visual = visual; pilot.fit_collision_to_visual()
	await physics_frame; await physics_frame
	check(pilot.collision_parts.size() == 6,"Original sub uses three hull sections, two pods and a rear propeller shape")
	var space := world.get_world_3d().direct_space_state
	check(occupied(space,Vector3(0,-0.07,-0.25)),"Bow has solid collision")
	check(occupied(space,Vector3(0,0.08,0.3)),"Stern has solid collision")
	check(occupied(space,Vector3(0.22,-0.01,-0.10)),"Left pod has solid collision")
	check(occupied(space,Vector3(-0.22,-0.01,-0.10)),"Right pod has solid collision")
	check(not occupied(space,Vector3(0.24,0,0.28)),"Empty space beside the stern stays clear of collision")
	check(not occupied(space,Vector3(-0.24,0,-0.28)),"Empty space beside the bow stays clear of collision")
	check(is_equal_approx(pilot.collision_height(),0.459277),"Surface and minimap clearance follow the fitted model height")
	pilot.movement.tilt = PI / 2.0
	pilot._update_animation(1.0 / 60.0); pilot._sync_pod_collisions()
	for part in pilot.collision_parts:
		if not part.has("source"): continue
		var expected: Transform3D = pilot.global_transform.affine_inverse() * part.source.global_transform * part.rest_pose.affine_inverse()
		check(part.collider.transform.is_equal_approx(expected) and not part.collider.basis.is_equal_approx(Basis.IDENTITY),"Pod collider follows its tilted visual")
	world.queue_free(); await process_frame
	print("Compound submarine collision: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
