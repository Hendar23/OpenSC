extends "res://tests/verify_remaining_stage_two.gd"
const Definitions = preload("res://object_definitions.gd")
const Thorium = preload("res://thorium_body.gd")

func shadow_probe() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(256,256); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color.BLACK; environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_energy = 0; viewport.add_child(environment)
	var ground := MeshInstance3D.new(); ground.mesh = PlaneMesh.new(); ground.mesh.size = Vector2(6,6); viewport.add_child(ground)
	var material := StandardMaterial3D.new(); material.albedo_color = Color.WHITE; ground.material_override = material
	var ceiling := MeshInstance3D.new(); ceiling.mesh = BoxMesh.new(); ceiling.mesh.size = Vector3(6,0.1,6); ceiling.position.y = 1.5; ceiling.material_override = material; viewport.add_child(ceiling)
	var source := Thorium.new(); var model := MeshInstance3D.new(); model.mesh = SphereMesh.new(); model.material_override = StandardMaterial3D.new()
	var definition := Definitions.THORIUM.duplicate(true); definition.glow_emission = 0
	source.setup(definition,model,0,10,false); viewport.add_child(source); source.position.y = 1.8
	var camera := Camera3D.new(); viewport.add_child(camera); camera.position = Vector3(0,0.8,2); camera.look_at(Vector3(0,0,0)); camera.current = true
	check(source.glow_light.shadow_enabled,"Thorium light casts terrain-occluded shadows")
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var blocked := viewport.get_texture().get_image(); var dark := blocked.get_pixel(128,160).v
	source.glow_light.shadow_enabled = false
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var leaking := viewport.get_texture().get_image(); var bright := leaking.get_pixel(128,160).v
	print("Cave light sample: blocked=",dark," without shadows=",bright)
	check(bright > 0.03 and dark < bright*0.25,"Actual rendered cave roof blocks the orange light that previously leaked through")
	blocked.save_png("res://../.local/thorium-roof-occluded.png"); leaking.save_png("res://../.local/thorium-roof-unoccluded.png")
	viewport.free()

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for cave spawn checks")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false); game.set_process(false); game.set_physics_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	await fresh("tagtech")
	var center: Vector3 = jobs.remaining.cargo.global_position
	var pop: Node3D = game.object_population; pop.set_physics_process(false)
	var original: AABB = pop.world_bounds; pop.dock_spawn_exclusions.clear()
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var columns := 0; var startups := 0; var drops := 0
	var repair_point := Vector3.INF; var repair_roof := 0.0
	for z in range(-6,7):
		for x in range(-6,7):
			var point: Vector3 = center+Vector3(x*0.7,0,z*0.7)
			var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x,pop.surface_height+5,point.z),Vector3(point.x,original.position.y-5,point.z),16); ray.hit_back_faces = true
			var roof := space.intersect_ray(ray); ray.hit_back_faces = false; var floor_hit := space.intersect_ray(ray)
			if roof.is_empty() or floor_hit.is_empty() or roof.position.y < floor_hit.position.y+1.5: continue
			columns += 1
			pop.world_bounds = AABB(Vector3(point.x-0.001,original.position.y,point.z-0.001),Vector3(0.002,original.size.y,0.002))
			for startup in [true,false]:
				var spawn: Dictionary = pop._random_spawn_point(Definitions.THORIUM,startup)
				if spawn.is_empty(): continue
				check(spawn.position.y < roof.position.y-0.45 and spawn.floor.y < roof.position.y-1,"Actual cave spawn stays below the roof: " + str(startup))
				if startup: startups += 1
				else:
					drops += 1
					if not repair_point.is_finite(): repair_point = spawn.position; repair_roof = roof.position.y
	print("Actual cave columns=",columns," startup=",startups," timed=",drops)
	check(columns > 10 and startups > 5 and drops > 5,"Both startup crystals and timed drops can spawn inside the real mission cave")
	pop.world_bounds = original
	if repair_point.is_finite():
		var invalid: Node3D = pop._create_thorium(Definitions.THORIUM,0,Transform3D(Basis.IDENTITY,Vector3(repair_point.x,repair_roof+0.7,repair_point.z)))
		var authored: Node3D = pop._create_thorium(Definitions.THORIUM,0,Transform3D(Basis.IDENTITY,Vector3(repair_point.x+3,repair_roof+0.7,repair_point.z)))
		authored.set_meta("object_group","authored/test-roof")
		var identity: String = preload("res://entity_identity.gd").of(invalid)
		var authored_id: String = preload("res://entity_identity.gd").of(authored)
		var authored_pose: Transform3D = authored.global_transform
		pop.restore_snapshot(pop.snapshot())
		var repaired: Node3D; var preserved: Node3D
		for body in pop.get_children():
			if preload("res://entity_identity.gd").of(body) == identity: repaired = body
			if preload("res://entity_identity.gd").of(body) == authored_id: preserved = body
		check(is_instance_valid(repaired) and repaired.global_position.is_equal_approx(repair_point),"Existing beta save roof spawns are restored below the cave ceiling")
		check(is_instance_valid(preserved) and preserved.global_transform.is_equal_approx(authored_pose),"Save repair preserves explicitly authored placements")
	if DisplayServer.get_name() != "headless": await shadow_probe()
	game.free(); await process_frame
	print("Cave resource verification: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
