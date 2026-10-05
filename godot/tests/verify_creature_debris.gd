extends SceneTree
const Death = preload("res://creature_death.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(20,1,20); shape.shape = box; floor_body.add_child(shape); floor_body.position.y = -0.5; world.add_child(floor_body)
	var burst := Death.new(); world.add_child(burst); burst.set_process(false)
	var part := MeshInstance3D.new(); part.mesh = BoxMesh.new(); part.mesh.size = Vector3(0.2,0.2,0.2); part.position.y = 2; burst.add_child(part)
	var material := StandardMaterial3D.new(); part.material_override = material
	var piece := {"node":part,"velocity":Vector3(0.4,0,0),"spin":Vector3(0.5,1,0.2),"material":material,"settled":false}; burst.pieces.append(piece)
	await physics_frame; await physics_frame
	for frame in range(600): burst._process(1.0 / 60)
	check(piece.settled and part.global_position.y > 0 and part.global_position.y < 0.3,"Fragments sink and rest on the seabed without passing through it")
	var resting := part.global_position
	burst._process(30)
	check(part.global_position.is_equal_approx(resting) and material.albedo_color.a == 1,"Settled fragments remain still and opaque during their lifetime")
	burst.age = 60.5; burst._process(0)
	check(is_equal_approx(material.albedo_color.a,0.5),"Fragments only fade after the configured hold time")
	burst.age = 61; burst._process(0); await process_frame
	check(not is_instance_valid(burst),"Expired debris is removed")
	world.queue_free(); await process_frame
	print("Creature debris: 4 checks, %d failures" % failures); quit(1 if failures else 0)
