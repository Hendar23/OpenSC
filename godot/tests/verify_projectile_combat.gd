extends "res://tests/verify_remaining_equipment.gd"
const Pirate = preload("res://pirate_submarine.gd")
const Document = preload("res://map_document.gd")
const Projectile = preload("res://player_projectile.gd")

func check_fuel_lifecycle(id: String, arsenal: Node3D) -> void:
	# An isolated sea floor avoids the real map's surface ceiling and avoids
	# losing sub-millimetre travel precision far from the world origin.
	var sandbox := SubViewport.new(); sandbox.own_world_3d = true; root.add_child(sandbox)
	var ocean := Node3D.new(); sandbox.add_child(ocean)
	var floor_origin := Vector3.ZERO
	var floor_body := body(floor_origin,Vector3(200,0.5,200))
	floor_body.reparent(ocean)
	floor_body.collision_layer = 1
	await physics_frame; await physics_frame
	var start := floor_origin+Vector3.UP*6
	var shot := Projectile.new(); ocean.add_child(shot)
	shot.setup(arsenal,id,start,Vector3.FORWARD); shot.set_physics_process(false)
	shot.velocity = Vector3.ZERO
	var old_distance := 0.0; var old_velocity := Vector3.ZERO
	# Integrate the previous flight independently to check actual range, not
	# just a doubled timer (which also includes the launch acceleration twice).
	for tick in range(39 if id == "missile" else 133):
		old_velocity = (old_velocity+Vector3.FORWARD*((0.0075 if id == "missile" else 0.0025)/0.1*25.0))*0.857142857
		old_distance += old_velocity.length()/25.0
	for tick in range(600):
		shot.advance(0.04)
		if shot.out_of_fuel or shot.spent: break
	check(shot.out_of_fuel and not shot.spent and shot.visible,"Exhausted torpedo stays visible: "+id)
	check(absf(shot.powered_distance-2.0*old_distance) < 0.001 and absf(start.distance_to(shot.global_position)-2.0*old_distance) < 0.001,"Powered travel doubles the previous actual range: "+id)
	var trail: Node3D = arsenal.bubbles()
	check(trail != null and not trail.credits.has(shot.get_instance_id()),"Engine bubbles stop at fuel exhaustion: "+id)
	var coast_start: Vector3 = shot.global_position
	var initial_basis: Basis = shot.global_basis
	var forward_speed: float = shot.velocity.length()
	shot.advance(1.0)
	check(shot.global_position.y < coast_start.y-0.2 and shot.velocity.y < 0,"Unpowered torpedo sinks: "+id)
	check(shot.velocity.length() < forward_speed and not shot.global_basis.is_equal_approx(initial_basis),"Unpowered torpedo loses speed and tumbles: "+id)
	check(not trail.credits.has(shot.get_instance_id()) and shot.target == null,"Sinking torpedo has no exhaust or guidance: "+id)
	var effects_before: int = game.pilot.get_parent().get_child_count()
	for tick in range(400):
		shot.advance(0.04)
		if shot.spent: break
	check(shot.spent and absf(shot.global_position.y-floor_origin.y-0.25) < 0.01,"Spent torpedo reaches the seabed before detonation: "+id)
	check(game.pilot.get_parent().get_child_count() == effects_before+1,"Seabed contact creates one explosion: "+id)
	await physics_frame
	sandbox.free()

func pirate_at(center: Vector3) -> Node3D:
	var model := Document.load_model("PIRATE",game.game_folder)
	game.world_root.add_child(model); model.global_position = center
	var agent := Pirate.install_pirate(model,{"npc_health":30.0,"npc_sustain":0.3})
	game.submarine_traffic.register_vessel(agent,game.world_root,game.game_folder)
	model.global_position -= model.global_basis*agent.bounds.get_center()
	agent.mission_owner = "combat-fixture"; agent.set_physics_process(false)
	return agent

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for real NPC projectile collisions")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.set_process(false); game.docking.set_physics_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.pilot.reset_at(Vector3(10000,25,10000)); game.pilot.pending_reset = false
	game.pilot.active = true; game.pilot.controls_enabled = true
	game.weapons.set_physics_process(false); game.equipment.extra_tools.set_physics_process(false)
	game.player_progress.status.credits = 1000000
	equip("missile"); game.weapons.select_id("missile")
	var arsenal: Node3D = game.weapons.arsenal
	var muzzle: Vector3 = preload("res://submarine_mounts.gd").launch_point(arsenal.mounts.missile,game.pilot.visual,"missile",Vector3(0,0,-0.3))
	var forward: Vector3 = -arsenal.mounts.missile.global_basis.z.normalized()
	for moving in [false,true]:
		var agent := pirate_at(muzzle+forward*5)
		await physics_frame; await physics_frame
		var hits := 0
		for shot_index in range(9):
			if agent.dead: break
			# Keep the engagement at five units; otherwise a stationary shooter
			# eventually watches the fleeing target leave the torpedo's range.
			if moving:
				agent.get_parent().global_position = muzzle+forward*5-agent.get_parent().global_basis*agent.bounds.get_center()
				await physics_frame
			var before: float = agent.health.remaining
			arsenal._launch("missile")
			var shot: Node3D = arsenal.shots.back(); shot.set_physics_process(false)
			for tick in range(40):
				if shot.spent: break
				if moving:
					agent.get_parent().global_position += forward*2.5/25.0; agent.body.velocity = forward*2.5
					await physics_frame
				shot.advance(0.04)
			check(agent.health.remaining < before,"Actual pirate loses hull to each direct torpedo hit; moving="+str(moving))
			hits += 1; await physics_frame
		check(agent.dead and hits <= 9,"Direct torpedoes destroy an original 30-hull pirate; moving="+str(moving)+" hits="+str(hits))
		check(not agent.get_parent().visible and agent.body.collision_layer == 0,"Destroyed pirate leaves its ordinary wreck")
		arsenal.reset()
	var shot := preload("res://player_projectile.gd").new(); game.world_root.add_child(shot)
	shot.setup(arsenal,"missile",muzzle+Vector3.UP*10,forward); shot.set_physics_process(false)
	shot.advance(0.8)
	check(shot.velocity.length() > 10.0,"Standard player torpedo reaches original faster speed")
	shot.advance(0.81)
	check(not shot.spent and not shot.out_of_fuel,"Standard torpedo keeps flying beyond its former lifetime")
	shot.free()
	await physics_frame
	for id in ["missile","homers"]: await check_fuel_lifecycle(id,arsenal)
	# A real convex fish hull: the bolt globe overlaps its flank while its
	# centre ray would miss. The whole globe must stop and discharge on contact.
	var visual := Document.load_model("LIONFISH",game.game_folder,true)
	var bounds := preload("res://submarine_equipment.gd")._bounds(preload("res://submarine_equipment.gd")._meshes(visual,Transform3D.IDENTITY))
	visual.position -= bounds.get_center()
	var fish := preload("res://fish_controller.gd").new()
	var fish_point := muzzle+Vector3(15,0,0)
	fish.setup(visual,fish_point,AABB(fish_point-Vector3.ONE*50,Vector3.ONE*100),game.pilot.surface_height,0.2,1)
	game.world_root.add_child(fish); fish.configure_health(1000); fish.damage_sustain = 1; fish.set_physics_process(false); fish.set_process(false)
	await physics_frame; await physics_frame
	var start := fish_point+Vector3(bounds.size.x*0.5+0.2,0,5)
	var ray := PhysicsRayQueryParameters3D.create(start,start+Vector3.FORWARD*10,8)
	check(game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"Grazing fish fixture is outside the old point-ray path")
	var bolt := preload("res://player_projectile.gd").new(); game.world_root.add_child(bolt)
	bolt.setup(arsenal,"electro",start,Vector3.FORWARD); bolt.velocity = Vector3.FORWARD*30; bolt.set_physics_process(false)
	for tick in range(12):
		bolt.advance(0.04)
		if bolt.bursting: break
	check(bolt.bursting and fish.health < 1000,"Electro globe collides with real fish flank and starts damaging discharge")
	var stop: Vector3 = bolt.global_position
	bolt.advance(0.2)
	check(bolt.global_position.is_equal_approx(stop) and fish.health < 996,"Discharging globe stays at impact instead of passing through fish")
	bolt.free(); fish.free(); await physics_frame
	var hud: Control = game.cockpit_hud.displays[3]
	check(hud.weapon_counter_rect() == Rect2(93,18,26,10),"Original three-digit counter fits its recovered HUD coordinates")
	check(Shop.offer(game.gameplay_catalogue,"1",2,"mammo",true).maximum == 200 and Shop.offer(game.gameplay_catalogue,"1",2,"homers",true).maximum == 40,"Original ammunition limits remain 200 standard and 40 homing")
	check(Shop.offer(game.gameplay_catalogue,"1",2,"mammo",true).name == "Torpedoes" and Shop.offer(game.gameplay_catalogue,"1",2,"homers",true).name == "Homing Torpedoes","Shop ammunition uses requested torpedo names")
	check(game.weapons.current().name == "Torpedo Launcher" and game.map_screen.item_names.mammo == "Torpedoes","Weapon selection and map inventory use torpedo names")
	check(game.map_screen.body.get_child_count() == 1,"Map hold contents have no extra heading")
	game.player_progress.hold.mammo = 200
	check(hud.counter_digit_count() == 3 and hud.weapon_count() == 200,"Torpedoes retain a three-digit ammo display")
	if DisplayServer.get_name() != "headless":
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/torpedo-hud-counter.png")
	equip("electro"); game.weapons.select_id("electro")
	check(hud.counter_digit_count() == 2 and hud.weapon_count() == 99,"Electro charge displays two figures")
	if DisplayServer.get_name() != "headless":
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/electro-hud-counter.png")
	game.free(); await process_frame
	print("Projectile combat: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
