extends "res://tests/test_scene_tree.gd"
const World = preload("res://world_loader.gd")
const Document = preload("res://map_document.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-turret-grounding-fixtures"
	var mods = preload("res://mod_registry.gd")
	mods.initialize(false)
	var args := OS.get_cmdline_user_args()
	if args.size() == 1:
		mods.initialize(false,args[0]); mods.apply(["high-poly-terrain"],[],false)
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	var world := await World.load_world(folder.path_join("DATA/SCEN1.BSP"),self,func(_s):pass)
	root.add_child(world)
	world.set_meta("player_spawn",Vector3.ZERO)
	await World.add_collision(world,self,func(_s):pass)
	await physics_frame; await physics_frame
	if args.size() == 1: check(world.has_meta("terrain_asset_hash"),"Grounding check uses replacement terrain")
	var document := Document.load_path(Document.DEFAULT_PATH)
	var key := "Scenery/TURRET_83"
	var entry: Dictionary = document.entities[key]
	var scenery := Node3D.new(); scenery.name = "Scenery"; world.add_child(scenery)
	var model := Document.load_model("TURRET",folder); model.name = "TURRET_83"; scenery.add_child(model)
	model.set_meta("editor_model","TURRET")
	Document.apply_entities(world,folder,{"entities":{key:entry}})
	var turret := model.get_node("GunTurret")
	turret.set_physics_process(false)
	var authored := Document.decode(entry.transform)
	check(Vector2(model.position.x,model.position.z).is_equal_approx(Vector2(authored.origin.x,authored.origin.z)) and model.basis.get_scale().is_equal_approx(authored.basis.get_scale()),"Grounding preserves authored horizontal position and scale")
	var minimum := INF; var maximum := -INF
	for mesh in turret.collision_meshes:
		if turret.head != null and turret.head.is_ancestor_of(mesh): continue
		var bottom: float = mesh.mesh.get_aabb().position.y
		for vertex in mesh.mesh.get_faces():
			if vertex.y > bottom + 0.001: continue
			var point: Vector3 = mesh.global_transform * vertex
			var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*2,point-Vector3.UP*2,16); query.hit_back_faces = true
			var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty(): continue
			minimum = minf(minimum,point.y-hit.position.y); maximum = maxf(maximum,point.y-hit.position.y)
	check(absf(minimum-0.005) < 0.001,"Pirate-pipe turret base contacts terrain rather than floating or burying")
	check(maximum < (0.09 if args.size() == 1 else 0.17),"Base follows the surrounding slope within its uneven terrain footprint")
	check(Document.capture(world).entities[key].get("ground_turret",false),"Map capture preserves the terrain-fitting placement")
	check(turret.hitbox.global_position.is_equal_approx(model.global_position),"Articulated collision follows grounded model")
	print("Base footprint clearance: %.6f to %.6f" % [minimum,maximum])
	if DisplayServer.get_name() != "headless":
		var lighting := WorldEnvironment.new(); lighting.environment = Environment.new()
		lighting.environment.background_mode = Environment.BG_COLOR; lighting.environment.background_color = Color(0.03,0.25,0.3)
		lighting.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		lighting.environment.ambient_light_color = Color.WHITE; lighting.environment.ambient_light_energy = 0.8
		world.add_child(lighting)
		var light := DirectionalLight3D.new(); world.add_child(light); light.rotation_degrees = Vector3(-50,-30,0)
		var camera := Camera3D.new(); world.add_child(camera); camera.current = true
		camera.global_position = model.global_position + Vector3(1.8,0.8,1.8); camera.look_at(model.global_position+Vector3.UP*0.2)
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/turret-grounded.png")
	world.free(); print("Turret grounding: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
