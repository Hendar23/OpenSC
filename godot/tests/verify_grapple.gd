extends SceneTree
const Game = preload("res://game.gd")
const Definitions = preload("res://object_definitions.gd")
const Population = preload("res://object_population.gd")
const Shop = preload("res://equipment_shop.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func capture(pilot: Node3D, grapple: Node3D, cargo: Node3D) -> void:
	if DisplayServer.get_name() == "headless": return
	var viewport := SubViewport.new(); viewport.size = Vector2i(960,640); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var scene := Node3D.new(); viewport.add_child(scene)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color(0.025,0.065,0.085)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color.WHITE; environment.environment.ambient_light_energy = 0.6; scene.add_child(environment)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-45,-30,0); scene.add_child(light)
	var bounds := AABB(); var first := true
	for source in [pilot.visual,grapple.head,cargo] + grapple.links:
		for mesh in source.find_children("*","MeshInstance3D",true,false):
			var copy := MeshInstance3D.new(); copy.mesh = mesh.mesh; scene.add_child(copy); copy.global_transform = mesh.global_transform
			for blend in range(copy.mesh.get_blend_shape_count()): copy.set_blend_shape_value(blend,mesh.get_blend_shape_value(blend))
			var box: AABB = copy.global_transform * copy.mesh.get_aabb()
			bounds = box if first else bounds.merge(box); first = false
	var camera := Camera3D.new(); scene.add_child(camera); camera.current = true; camera.fov = 40; camera.near = 0.001
	camera.position = bounds.get_center() + Vector3(1,0.2,1).normalized() * bounds.size.length() * 1.6; camera.look_at(bounds.get_center())
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://tests/grapple-preview.png")
	viewport.free()
func run() -> void:
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Game starts with the new equipment and object type")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.set_physics_process(false); game.docking.set_physics_process(false); game.pilot.freeze = true
	var grapple: Node3D = game.equipment.grapple
	var item: Dictionary = game.equipment.available.filter(func(entry: Dictionary) -> bool: return entry.id == "grapple")[0]
	check(grapple.housing != null and grapple.chain_template != null and grapple.deploy_audio.stream != null,"Original grapple, rope and sound load")
	check(item.mount.transform.is_equal_approx(game.equipment.magnet.get_parent().transform),"Grapple initially shares the current magnet mounting position")
	for index in range(3):
		var original := preload("res://legacy_bmp.gd").load_image(game.game_folder.path_join("GAMETEX/TOW%d.RAS" % (index + 1)))
		check(item.icons[index] != null and item.icons[index].get_image().get_data() == original.get_data(),"Original grapple HUD state %d" % (index + 1))
	for port in game.docking.ports:
		game.docking.current = port
		var offer: Dictionary = game._dock_ui_model().offers.grapple
		var expected := 1000 if str(port.name).begins_with("Beluga") else 1100 if str(port.name).begins_with("Touka") else 1400 if str(port.name).contains("Refinery") else 0
		check(offer.available == (expected > 0) and offer.price == expected,"Original initial grapple availability and price: " + str(port.name))
	game.player_progress.status.credits = 100000
	game.docking.current = game.docking.ports.filter(func(port: Dictionary) -> bool: return str(port.name).begins_with("Touka"))[0]
	var offer: Dictionary = game._dock_ui_model().offers.grapple
	Shop.buy(game.player_progress,offer)
	check(game.player_progress.hold.get("grapple",0) == 1,"Purchased grapple goes into the hold")
	Shop.swap(game.player_progress,game.equipment,game.weapons,3,"grapple")
	check(Shop.installed(game.equipment,game.weapons).get(3) == "grapple" and game.player_progress.hold.get("suckomat",0) == 1,"Grapple replaces SOM in the shared slot")
	check(game.equipment.towing_tool() == grapple and item.mount.visible and not game.equipment.magnet.get_parent().visible,"Only the equipped underside tool is visible")
	game.pilot.active = true; game.pilot.controls_enabled = true; game.pilot.visual.show(); game.pilot.freeze = true
	game.docking.stage = game.Docking.Stage.IDLE
	game.equipment.selected = game.equipment.mounted.find(item); game.equipment.toggle_selected()
	check(grapple.enabled and grapple.links.size() == 4 and grapple.rig.name == "GrappleRope","Activating the grapple pays out the original rope")
	for frame in range(10): await physics_frame
	check(grapple.paid_length > 0 and grapple.paid_length < grapple.chain_length,"Rope deployment is progressive")
	for frame in range(90): await physics_frame
	grapple.set_physics_process(false)
	var coin: RigidBody3D = game.object_population._create_thorium(Definitions.metal_types()[2],0,Transform3D(Basis.IDENTITY,grapple.head.global_position))
	grapple._attach(coin)
	check(grapple.target == null,"Grapple rejects magnet-only metal objects")
	coin.queue_free()
	var cigarette: RigidBody3D = game.object_population._create_thorium(Definitions.CIGARETTE,0,Transform3D(Basis.IDENTITY,grapple.head.global_position + Vector3.DOWN * 0.1))
	check(is_equal_approx(cigarette.mass,0.6),"Cigarette uses its original OBJECTS.CSV mass")
	grapple._attach(cigarette)
	check(grapple.target == cigarette and is_instance_valid(grapple.clamp_joint),"Grapple clamps cigarette ends")
	check(game.pilot.movement.cargo_mass > 0,"The cigarette adds towing weight")
	await capture(game.pilot,grapple,cigarette)
	var terms: Dictionary = game._delivery_terms(cigarette)
	check(terms.commodity == "tobacco" and terms.quantity == 1,"Cigarette delivery yields editable tobacco units")
	var point: Node = grapple.drop_points[0]; grapple.delivery_point = point
	check(game._delivery_prompt_active(),"Grappled cargo triggers the same city drop-off confirmation")
	game._answer_delivery(true)
	check(cigarette.has_meta("delivery_city") and not cigarette.is_queued_for_deletion() and grapple.target == null and grapple.retracting,"Accepting releases the cigarette at the city and retracts the grapple")
	check(game.player_progress.pending_deliveries[str(int(point.city_id))].tobacco == 1 and not game.player_progress.cargo.has("tobacco"),"Tobacco waits at the receiving city until docking")
	var saved: Array = JSON.parse_string(JSON.stringify(game.object_population.snapshot()))
	check(Population.valid_snapshot(saved) and saved.any(func(entry: Dictionary) -> bool: return entry.stats.id == "cigarette_end" and entry.has("delivery_city")),"Cigarette state and pending drop-off survive serialization")
	game._collect_city_deliveries(int(point.city_id))
	check(game.player_progress.cargo.get("tobacco",0) == 1 and cigarette.is_queued_for_deletion(),"Docking transfers tobacco and removes the delivered cigarette")
	grapple.reset(); grapple.set_enabled(true)
	var thorium: RigidBody3D = game.object_population._create_thorium(Definitions.THORIUM,0,Transform3D(Basis.IDENTITY,grapple.head.global_position + Vector3.DOWN * 0.1))
	grapple._attach(thorium)
	check(grapple.target == thorium and game._delivery_terms(thorium).quantity == 4,"Whole thorium can be grappled for four raw thorium")
	grapple.release()
	var shard: RigidBody3D = game.object_population._create_thorium(Definitions.THORIUM,1,Transform3D(Basis.IDENTITY,grapple.head.global_position))
	grapple._attach(shard)
	check(grapple.target == null,"Thorium shards remain SOM cargo rather than grapple targets")
	grapple.reset(); game.equipment.set_installed(["deep_sea_lights","magnet"])
	game.equipment.magnet.set_enabled(true); game.equipment.magnet._attach(thorium)
	check(game.equipment.magnet.target == null,"Magnet rejects whole thorium by default")
	game.equipment.reset_towing(); game.equipment.set_installed(["deep_sea_lights","grapple"])
	game.docking.current = game.docking.ports[0]; game.docking.stage = game.Docking.Stage.DOCKED
	game.save_games.folder = "res://tests/grapple-fixtures"
	check(game.save_games.write(0,game._save_snapshot("Grapple test")) == OK,"Grapple equipment and cigarette inventory save")
	game.equipment.set_installed(["deep_sea_lights","suckomat"])
	check(await game._load_saved_game(0),"Saved grapple loadout loads")
	check(Shop.installed(game.equipment,game.weapons).get(3) == "grapple" and game.player_progress.cargo.get("tobacco",0) == 1,"Equipped grapple and tobacco cargo survive loading")
	check(game.equipment_controls.has("grapple_length") and game.equipment_controls.has("grapple_water_drag") and game.equipment_controls.has("grapple_volume_db"),"Developer menu exposes grapple tuning")
	game._begin_new_game()
	check(not grapple.enabled and not is_instance_valid(grapple.rig) and Shop.installed(game.equipment,game.weapons).get(3) == "suckomat","New game resets grapple and restores SOM")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_games.path(0)))
	game.free()
	print("Grapple: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
