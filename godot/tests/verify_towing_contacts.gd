extends "res://tests/test_scene_tree.gd"
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func _initialize() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-contact-fixtures"
	preload("res://player_storage.gd").ensure_parent("res://tests/cache-contact-fixtures/.gdignore")
	var file := FileAccess.open("res://tests/cache-contact-fixtures/.gdignore",FileAccess.WRITE); file.store_string("")
	call_deferred("run")
func run() -> void:
	preload("res://mod_registry.gd").initialize(false)
	var world := Node3D.new(); root.add_child(world); world.set_meta("surface_height",0.0)
	var pilot := preload("res://tests/verify_magnet.gd").Pilot.new(); pilot.mass = 100; pilot.gravity_scale = 0; pilot.freeze = true; pilot.position.y = -5; world.add_child(pilot)
	pilot.visual = Node3D.new(); pilot.add_child(pilot.visual)
	var mount := Node3D.new(); pilot.visual.add_child(mount)
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var housing := preload("res://clump_loader.gd").load_clump(folder.path_join("CLUMPS/MAGNET.DFF")); mount.add_child(housing)
	var magnet := preload("res://submarine_magnet.gd").new(); mount.add_child(magnet); magnet.setup(pilot,housing,folder); magnet.set_enabled(true)
	for tick in range(150): await physics_frame
	var cargo := preload("res://mission_cargo.gd").new(); world.add_child(cargo)
	var visual := Node3D.new(); cargo.add_child(visual); cargo.appearance = visual
	var mesh := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3(0.8,0.4,1.2); mesh.mesh = box; visual.add_child(mesh)
	var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = Vector3(1.2,0.8,1.5); collision.shape = shape; cargo.add_child(collision)
	cargo.global_position = magnet.head.global_position + Vector3.DOWN * 0.3
	magnet._attach(cargo)
	var head_shape: CollisionShape3D = magnet.head.find_children("*","CollisionShape3D",true,false)[0]
	var gap: float = magnet.head.global_position.y - head_shape.shape.size.y*0.5 - (cargo.global_position.y+0.2)
	check(absf(gap) < 0.002,"Magnet seats on visible metal, closing the gap inside an oversized collision hull: %f" % gap)
	check(magnet.head.get_collision_exceptions().has(cargo),"The clamped head cannot be pushed away by the cargo's enclosing hull")
	for tick in range(60): await physics_frame
	gap = magnet.head.global_position.y - head_shape.shape.size.y*0.5 - (cargo.global_position.y+0.2)
	check(absf(gap) < 0.015,"The visible contact remains seated after a second of physical cable simulation: %f" % gap)
	pilot.freeze = false; var previous: float = pilot.global_position.y
	for tick in range(60): await physics_frame
	check(pilot.global_position.y < previous-0.02,"Without upward thrust, the shuttle's weight pulls the stopped submarine down")
	magnet.set_enabled(false); previous = cargo.global_position.y
	for tick in range(60): await physics_frame
	check(cargo.global_position.y < previous-0.3 and cargo.linear_velocity.y < -0.4,"Released shuttle sinks noticeably under its own submerged weight")
	check(not magnet.head.get_collision_exceptions().has(cargo) if is_instance_valid(magnet.head) else true,"Release restores normal cargo collision")
	pilot.freeze = true
	cargo.set_meta("grapple_tow_target",true)
	for id in ["magnet","grapple"]:
		magnet.tool_id = id; magnet.set_enabled(true)
		cargo.global_position = magnet.head.global_position + Vector3.DOWN * 0.3
		magnet._attach(cargo)
		check(magnet.target == cargo,"Recall regression starts with attached cargo: " + id)
		magnet.release()
		check(not magnet.enabled and magnet.retracting and magnet.target == null,"External release automatically recalls " + id)
		for tick in range(150): await physics_frame
		check(not is_instance_valid(magnet.rig) and housing.visible,"Automatically recalled tool finishes stowing: " + id)
		magnet.set_enabled(true)
		cargo.global_position = magnet.head.global_position + Vector3.DOWN * 0.3
		magnet._attach(cargo); cargo.set_meta("delivery_city",1)
		await physics_frame; await physics_frame
		check(not magnet.enabled and magnet.retracting,"Externally delivered load recalls " + id)
		cargo.remove_meta("delivery_city")
		for tick in range(150): await physics_frame
	world.queue_free(); await process_frame
	print("Towing contacts: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
