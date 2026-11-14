extends "res://tests/test_scene_tree.gd"
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-dropoff-guidance-fixtures"; storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new(); config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER")); config.save(storage.preferences_path())
	call_deferred("run")
func run() -> void:
	var game := preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game starts with drop-off guidance")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game()
	game.set_process(false); game.set_physics_process(false)
	game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	# Check real authored points as well as the isolated projection fixture.
	for point in get_nodes_in_group("city_drop_off_points"):
		if not game.world_root.is_ancestor_of(point): continue
		var visible_approaches := 0
		for direction in range(8):
			var angle := direction * TAU / 8.0
			var origin: Vector3 = point.global_position + Vector3(cos(angle)*4,2,sin(angle)*4)
			var query := PhysicsRayQueryParameters3D.create(origin,point.global_position,1,[point.get_rid(),game.pilot.get_rid()])
			if game.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): visible_approaches += 1
		check(visible_approaches > 0,"Authored drop-off centre has visible approaches: " + str(point.city_id))
	game.equipment.set_installed(["magnet","grapple"])
	var magnet: Node3D = game.equipment.magnet; var grapple: Node3D = game.equipment.grapple
	magnet.set_physics_process(false); grapple.set_physics_process(false)
	var cargo := preload("res://mission_cargo.gd").new(); game.world_root.add_child(cargo); cargo.freeze = true
	cargo.stats = {"delivery_commodity":"copper","delivery_quantity":2}
	cargo.global_position = Vector3(50,300,50)
	var pads: Array[Node] = []
	for city in [1,2,3,4,6]:
		var pad := preload("res://drop_off_point.gd").new(); game.world_root.add_child(pad); pad.configure(0.5,city)
		pad.global_position = cargo.global_position + Vector3((pads.size()-2)*1.5,0,0); pad.reset_physics_interpolation(); pads.append(pad)
	magnet.enabled = true; magnet.target = cargo; magnet.drop_points.assign(pads)
	check(game.game_dock.delivery_targets() == pads,"Ordinary deliverable salvage marks all available drop-off points")
	cargo.stats.delivery_quantity = 0
	check(game.game_dock.delivery_targets().is_empty(),"Cargo with no delivery yield has no markers")
	cargo.stats.delivery_quantity = 2
	magnet.target = null; grapple.enabled = true; grapple.target = cargo; grapple.drop_points.assign(pads)
	check(game.game_dock.delivery_targets() == pads,"Grapple cargo uses the same drop-off guidance")
	grapple.enabled = false
	check(game.game_dock.delivery_targets().is_empty(),"Stowed tool cannot leave stale guidance")
	grapple.enabled = true; cargo.set_meta("delivery_city",1)
	check(game.game_dock.delivery_targets().is_empty(),"Accepted cargo immediately clears guidance")
	cargo.remove_meta("delivery_city"); cargo.dead = true
	check(game.game_dock.delivery_targets().is_empty(),"Destroyed cargo has no drop-off guidance")
	cargo.dead = false
	var jobs: Node = game.mission_runtime.side_jobs
	var students := preload("res://student_rescue.gd").new(); students.ship = cargo; jobs.controller = students
	check(game.game_dock.delivery_targets() == [pads[1],pads[3]],"Student rescue marks only Procha destinations")
	students.delivered = true
	check(game.game_dock.delivery_targets().is_empty(),"Completed rescue has no destination guidance")
	var filters := preload("res://hijacked_filters.gd").new(); filters.filter_body = cargo; filters.cities.assign([1,4]); jobs.controller = filters
	check(game.game_dock.delivery_targets() == [pads[1],pads[2]] and filters.cities == [1,4],"Filter guidance excludes refinery and previously served cities without advancing the mission")
	var weapon := preload("res://genocide_weapon.gd").new(); weapon.head = cargo; weapon.phase = "head"; jobs.controller = weapon
	check(game.game_dock.delivery_targets() == [pads[0],pads[2]],"Project 13 head marks only Bohine destinations")
	weapon.phase = "handoff"
	check(game.game_dock.delivery_targets().is_empty(),"Handoff clears head destination guidance")
	var tag := preload("res://stage_two_remaining.gd").new(); tag.family = "tagtech"; tag.cargo = cargo; jobs.controller = tag
	check(game.game_dock.delivery_targets() == [pads[1],pads[3]],"Recovered canister marks only its accepted destinations")
	var allied := preload("res://allied_distress.gd").new(); allied.ship = cargo; jobs.controller = allied
	check(game.game_dock.delivery_targets().is_empty(),"Allied distress ship cannot be handed in at a city")
	var bombs := preload("res://bomb_disposal.gd").new(); bombs.bombs.append({"active":true,"body":cargo}); jobs.controller = bombs
	check(game.game_dock.delivery_targets().is_empty(),"Disposal bombs never mark city drop-off points")
	jobs.controller = null; jobs.id = "stranded"; jobs.target = cargo
	check(game.game_dock.delivery_targets() == [pads[0],pads[1],pads[2],pads[3]],"Bacau shuttle excludes the refinery")
	jobs.id = ""; jobs.target = null
	var marker: Control = game.mission_runtime.target_marker
	game.camera.global_position = cargo.global_position + Vector3(0,2,8); game.camera.look_at(cargo.global_position)
	game.camera.reset_physics_interpolation(); game.pilot.active = true; game.pilot_mode = true; game.dock_interface_active = false; game.map_open = false; game.front_end.menu_layer.hide()
	await physics_frame; await physics_frame
	check(marker.delivery_target_points().size() == 5,"Visible destinations project into the HUD using existing green brackets")
	game.map_open = true
	check(marker.delivery_target_points().is_empty(),"Fullscreen map hides destination brackets")
	game.map_open = false; paused = true
	check(marker.delivery_target_points().is_empty() and marker.can_process(),"Pause clears destination brackets")
	paused = false
	if DisplayServer.get_name() != "headless":
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/dropoff-guidance.png")
	var wall := StaticBody3D.new(); game.world_root.add_child(wall)
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(20,10,0.5); shape.shape = box; wall.add_child(shape)
	wall.global_position = cargo.global_position + Vector3(0,1,4)
	await physics_frame; await physics_frame
	check(marker.delivery_target_points().is_empty(),"Solid scenery occludes drop-off brackets")
	wall.free()
	game.camera.look_at(game.camera.global_position + Vector3.BACK); game.camera.reset_physics_interpolation()
	check(marker.delivery_target_points().is_empty(),"Destinations behind the camera have no brackets")
	game.camera.look_at(cargo.global_position); game.camera.reset_physics_interpolation()
	grapple.target = null
	check(game.game_dock.delivery_targets().is_empty() and marker.delivery_target_points().is_empty(),"Releasing cargo immediately removes destination brackets")
	magnet.enabled = false; grapple.enabled = false
	game.queue_free(); await process_frame
	print("Drop-off guidance: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
