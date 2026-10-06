extends SceneTree
const Death = preload("res://creature_death.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var folder := preload("res://asset_paths.gd").find_game_folder()
	var flesh := preload("res://clump_loader.gd")._load_texture(folder,"BEEF2","",{})
	check(flesh != null,"Original BEEF2 flesh texture loads")
	for model in ["TURTLE","SEAHORSE","ANGEL"]:
		var visual := preload("res://clump_loader.gd").load_clump(folder.path_join("CLUMPS/" + model + ".DFF"),PackedStringArray(),true)
		var creature := preload("res://fish_controller.gd").new()
		creature.setup(visual,Vector3(0,5,0),AABB(Vector3.ONE * -10,Vector3.ONE * 20),10,0.5,123)
		world.add_child(creature); creature.set_physics_process(false)
		creature.death_flesh_texture = flesh
		creature.take_damage(creature.health)
		var explosion := world.get_child(world.get_child_count() - 1)
		check(explosion is Death and explosion.pieces.size() > 1,model + " produces model fragments on death")
		var flesh_on_backs := true
		for fragment in explosion.pieces:
			var fragment_material: Material = fragment.material
			flesh_on_backs = flesh_on_backs and fragment_material is ShaderMaterial and fragment_material.get_shader_parameter("has_backface_texture") == true and fragment_material.get_shader_parameter("backface_texture") == flesh
		check(flesh_on_backs,model + " fragments use BEEF2 on their reverse faces")
		explosion.free(); creature.free()
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
	print("Creature debris: 11 checks, %d failures" % failures); quit(1 if failures else 0)
