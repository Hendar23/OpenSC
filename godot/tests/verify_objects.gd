extends SceneTree
const Document = preload("res://map_document.gd")
const Population = preload("res://object_population.gd")
const Thorium = preload("res://thorium_body.gd")
const Mods = preload("res://mod_registry.gd")
const Editor = preload("res://asset_editor.gd")
class DamageBody extends StaticBody3D:
	var health := 100.0
	func take_damage(amount: float, _source: Vector3) -> void: health -= amount
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	Mods.initialize(false)
	var editor := Editor.new(); editor.remember_preferences = false; root.add_child(editor)
	await process_frame; editor._set_mode(true)
	var map = editor.map_editor
	for tick in range(1800):
		if map.loaded: break
		await physics_frame
	check(map.loaded,"Editor loads with legacy map")
	if not map.loaded: quit(1); return
	# Use an isolated in-memory map; the user's authored groups may change between runs.
	map.document.erase("menu_camera")
	map.document.object_groups = []
	map.document.object_types = [preload("res://object_definitions.gd").FLOATING_MINE.duplicate(true)]
	map._sync()
	check(map.objects.get_child_count() == 0,"Empty authored groups do not import original mission mines")
	map.category.select(6); map._refresh_list(); map.select("object_type:floating_mine")
	check(map.fields.damage.value == 30 and not map.fields.has("count") and not map.fields.has("radius"),"Shared type stats use measured damage and exclude group population")
	check(map.species_preview.model is Sprite3D,"Type preview uses original masked mine bitmap")
	map.fields.size.value = 1.2; map.fields.health.value = 2; map.apply_properties()
	map.add_object_group(); var key: String = map.selected
	check(map.fields.has("count") and map.fields.has("radius"),"Object group has its own count and radius")
	map.fields.count.value = 6; map.fields.radius.value = 3; map.apply_properties()
	check(map.objects.get_child_count() == 6,"Editor renders authored object count")
	check(map.objects.get_children().all(func(mine: Node3D) -> bool: return not mine.armed),"Editor preview never arms mines")
	var homes: Array = map.objects.placements.duplicate()
	map.undo(); check(map.objects.get_child_count() == 1,"Undo restores group population")
	map.redo(); check(map.objects.placements == homes,"Redo preserves deterministic scatter")
	map.duplicate_selection(); check(map.document.object_groups.size() == 2,"Object group duplication works")
	map.delete_selection(); check(map.document.object_groups.size() == 1,"Object group deletion works")
	map.select("object_type:floating_mine"); map.delete_selection()
	check(map.document.object_types.size() == 1,"Referenced object type cannot be deleted")
	map.select(key); map._move(Vector3(0,0,-4)); map._sync(); map.frame_selection()
	var drag_start: Vector3 = map.point()
	var screen: Vector2 = map.camera.unproject_position(drag_start)
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.shift_pressed = true; click.ctrl_pressed = true; click.position = screen
	map._view_input(click)
	var motion := InputEventMouseMotion.new(); motion.position = screen - Vector2(20,40); map._view_input(motion)
	check(map.point().y > drag_start.y and is_equal_approx(map.point().x,drag_start.x) and is_equal_approx(map.point().z,drag_start.z),"Ctrl+Shift mouse drag changes height only")
	click.pressed = false; map._view_input(click); map.undo()
	check(map.point().is_equal_approx(drag_start),"Vertical mouse drag supports undo")
	map.frame_selection(); screen = map.camera.unproject_position(drag_start)
	click.pressed = true; click.ctrl_pressed = false; click.position = screen; map._view_input(click)
	motion.position = screen + Vector2(40,20); map._view_input(motion)
	check(is_equal_approx(map.point().y,drag_start.y) and map.point().distance_to(drag_start) > 0.1,"Shift mouse drag stays horizontal")
	click.pressed = false; map._view_input(click); map.undo()
	var menu_pose: Transform3D = map.camera.transform
	map.capture_menu_camera()
	check(Document.decode(map.document.menu_camera.transform).is_equal_approx(menu_pose),"Menu camera captures editor position and angle")
	map.camera.position += Vector3.ONE; map.view_menu_camera()
	check(map.camera.transform.is_equal_approx(menu_pose),"View menu camera restores captured framing")
	map.undo(); check(not map.document.has("menu_camera"),"Menu camera capture supports undo")
	map.redo()
	var data: Dictionary = map.document.duplicate(true)
	check(Document.save(data,"res://tests/objects-map.json") == OK,"Object definitions and placements save")
	var saved := Document.load_path("res://tests/objects-map.json")
	check(saved.object_groups[0].count == 6 and saved.object_types[0].damage == 30,"Mine properties survive JSON round trip")
	check(Document.decode(saved.menu_camera.transform).is_equal_approx(menu_pose),"Menu camera survives map JSON round trip")
	var invalid := data.duplicate(true); invalid.object_types[0].count = 20
	check(not Document.valid(invalid),"Counts are rejected on global object types")
	invalid = data.duplicate(true); invalid.object_groups[0].count = 2.5
	check(not Document.valid(invalid),"Fractional population is rejected")
	invalid = data.duplicate(true); invalid.object_groups[0].type = "missing"
	check(not Document.valid(invalid),"Unknown object types are rejected")
	invalid = data.duplicate(true); invalid.object_types[0].texture = "../../outside"
	check(not Document.valid(invalid),"Unsafe asset identifiers are rejected")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280,720); map.category.select(6); map._refresh_list(); map.select("object_type:floating_mine")
		for tick in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/object-types-preview.png")
	map.document.object_types.append(preload("res://object_definitions.gd").THORIUM.duplicate(true))
	map.select("object_type:thorium")
	check(map.fields.has("spawn_chance") and map.fields.has("maximum_population") and map.fields.has("shard1") and map.fields.has("radiation_range") and map.fields.has("glow_energy"),"Thorium editor exposes random drops, shards, radiation and glow settings")
	map.fields.spawn_chance.value = 75; map.fields.maximum_population.value = 90; map.apply_properties()
	check(map.record().spawn_chance == 75 and map.record().maximum_population == 90,"Thorium settings apply and survive preview rebuild")
	map.add_object_group(); map.fields.count.value = 2; map.apply_properties()
	check(map.objects.get_children().filter(func(body: Node) -> bool: return body is Thorium).size() == 2,"Editor renders manually placed frozen crystals")
	var folder: String = map.folder
	editor.queue_free(); await process_frame
	var world := Node3D.new(); root.add_child(world)
	data.object_types[0].health = 2.0; data.object_groups[0].count = 1
	var pop := Population.new(); world.add_child(pop); pop.setup(folder,data)
	var mine = pop.get_child(0)
	check(mine.position == Vector3(0,0,-4),"Single mine uses exact authored position")
	check(mine.get_child(0).texture.get_image().get_pixel(0,0).a == 0,"Original bitmap mask removes background")
	mine.take_damage(1.0); check(mine.health == 1.0 and not mine.dead,"Zapper-compatible damage reduces mine health")
	var victim := DamageBody.new(); victim.collision_layer = 2
	var victim_shape := CollisionShape3D.new(); var sphere := SphereShape3D.new(); sphere.radius = 0.1; victim_shape.shape = sphere; victim.add_child(victim_shape); world.add_child(victim)
	victim.position = mine.position + Vector3(0,0,1)
	await physics_frame; await physics_frame
	var blasts := []; mine.exploded.connect(func(point: Vector3, damage: float, radius: float) -> void: blasts.append([point,damage,radius]))
	mine.take_damage(1.0); check(mine.dead and mine.collision_layer == 0 and blasts.size() == 1 and blasts[0][1] == 30,"Lethal damage detonates and emits configured damage once")
	await process_frame
	check(victim.health == 70,"Explosion delivers 30 damage through the future shield hook")
	victim.free()
	mine.take_damage(100); mine.detonate(); check(blasts.size() == 1,"Destroyed mine cannot detonate twice")
	var burst = pop.get_node("MineExplosion")
	burst.set_process(false)
	check(burst.frames.size() == 12 and burst.sprite.texture != null,"Mine uses twelve original masked EX animation frames")
	burst._process(1.0 / burst.FRAME_RATE)
	check(burst.sprite.texture == burst.frames[1],"Explosion advances original animation")
	if DisplayServer.get_name() != "headless":
		var preview_camera := Camera3D.new(); world.add_child(preview_camera)
		preview_camera.position = Vector3(0,0,2); preview_camera.look_at(burst.global_position); preview_camera.current = true
		burst._process(2.0 / burst.FRAME_RATE)
		await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/mine-explosion-preview.png")
		preview_camera.free()
	burst._process(1.0); check(not burst.sprite.visible,"Original explosion animation finishes without looping")
	check(pop.has_node("MineExplosion") and pop.get_node("MineExplosion").find_children("*","AudioStreamPlayer3D",true,false).size() == 1,"Mine explosion plays machinery explosion sound")
	pop.free()
	pop = Population.new(); world.add_child(pop); pop.setup(folder,data)
	mine = pop.get_child(0)
	var pilot := preload("res://submarine_controller.gd").new(); pilot.remember_settings = false; world.add_child(pilot); pilot.set_physics_process(false); pilot.active = true; pilot.controls_enabled = true
	pop.player = pilot; pilot.position = mine.position + Vector3(0,0,5)
	mine._physics_process(0.1); check(not mine.dead,"Distant submarine does not trigger mine")
	pilot.position = mine.position; mine._physics_process(0.1); check(mine.dead,"Nearby submarine triggers mine")
	pop.free()
	# Real weapon ray and auto aim target the mine on the same layer as creatures.
	var assets = preload("res://clump_loader.gd")
	var visual := assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF")); pilot.add_child(visual); pilot.visual = visual; visual.scale *= pilot.VISUAL_SCALE; visual.rotation.y = PI
	var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(2,1,2)
	var weapon := preload("res://submarine_weapons.gd").new(); pilot.add_child(weapon)
	weapon.setup(pilot,folder,camera,{}); weapon.set_physics_process(false)
	var muzzle: Vector3 = weapon.muzzle.get_node("Emitter").global_position
	data.object_groups[0].position = Document.array(muzzle + Vector3(0,0,-2))
	data.object_types[0].trigger_distance = 0
	pop = Population.new(); world.add_child(pop); pop.setup(folder,data); mine = pop.get_child(0)
	mine.set_physics_process(false)
	await physics_frame; await physics_frame
	weapon.update_fire(true,0.1)
	check(weapon.last_hit == mine and is_equal_approx(mine.health,1.0),"Zapper ray damages floating mines")
	weapon.update_fire(true,0.1); check(mine.dead,"Zapper destroys mine on lethal damage")
	weapon.update_fire(false,0)
	pop.free(); pilot.free(); camera.free()
	data.object_groups[0].position = [0,0,-4]
	data.object_groups[0].count = 6; data.object_groups[0].radius = 3
	pop = Population.new(); world.add_child(pop); pop.setup(folder,data)
	check(pop.placements.all(func(point: Vector3) -> bool: return point.distance_to(Vector3(0,0,-4)) <= 3),"Group members remain within scatter radius")
	var repeat_pop := Population.new(); world.add_child(repeat_pop); repeat_pop.setup(folder,data)
	check(pop.placements == repeat_pop.placements,"Same map seed produces same runtime mine positions")
	pop.free(); repeat_pop.free()
	var definition: Dictionary = data.object_types[0].duplicate(true); definition.appearance = "model"
	var model := Population.appearance(definition,folder)
	check(model != null and not model.find_children("*","MeshInstance3D",true,false).is_empty(),"Original mine DFF works as alternative 3D appearance")
	if model != null: model.free()
	# Exercise the actual mod manifest path, including an image with its own alpha.
	var fixture := "res://tests/object-mod-fixture/mine"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	var image := Image.create(8,8,false,Image.FORMAT_RGBA8); image.fill(Color(1,0,0,0.5)); image.save_png(fixture.path_join("mine.png"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../Mods/test-3d-map-instrument/MapPanel.glb"),ProjectSettings.globalize_path(fixture.path_join("mine.glb")))
	var file := FileAccess.open(fixture.path_join("mod.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"id":"mine-fixture","name":"Mine fixture","assets":{"texture.mine":"mine.png"}})); file.close()
	Mods.initialize(false,"res://tests/object-mod-fixture"); Mods.apply(["mine-fixture"],[],false)
	definition.appearance = "sprite"
	var sprite := Population.appearance(definition,folder) as Sprite3D
	check(sprite != null and sprite.texture.get_image().get_pixel(0,0).r == 1 and sprite.texture.get_image().get_pixel(0,0).a > 0.4,"PNG mod supplies its own alpha without original mask")
	if sprite != null: sprite.free()
	file = FileAccess.open(fixture.path_join("mod.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version":1,"id":"mine-fixture","name":"Mine fixture","assets":{"model.mine":"mine.glb"}})); file.close(); Mods.refresh()
	model = Population.appearance(definition,folder)
	check(model != null and not model.find_children("*","MeshInstance3D",true,false).is_empty(),"GLB mod replaces billboard without changing map appearance")
	if model != null: model.free()
	Mods.initialize(false)
	for filename in ["mine.png","mine.glb","mod.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture)); DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.get_base_dir()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://tests/objects-map.json"))
	world.queue_free(); await process_frame
	print("Objects: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
