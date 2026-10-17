extends "res://tests/test_scene_tree.gd"
const Cache = preload("res://asset_cache.gd")
const Storage = preload("res://player_storage.gd")
const Assets = preload("res://clump_loader.gd")
const Mods = preload("res://mod_registry.gd")
const Data = preload("res://original_game_data.gd")
const World = preload("res://world_loader.gd")
var checks := 0
var failures := 0
func _init() -> void: Cache.enabled = true
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func signature(node: Node) -> Array:
	var records: Array = []
	for child in [node] + node.find_children("*", "", true, false):
		var record: Array = [str(node.get_path_to(child)), child.get_class()]
		if child is Node3D: record.append(child.transform)
		if child is MeshInstance3D:
			record.append(child.mesh.get_blend_shape_count())
			for surface in child.mesh.get_surface_count():
				record.append(hash(child.mesh.surface_get_arrays(surface)))
				record.append(hash(child.mesh.surface_get_blend_shape_arrays(surface)))
				var material := child.mesh.surface_get_material(surface) as StandardMaterial3D
				if material != null:
					record.append([material.albedo_color, material.transparency, material.cull_mode])
					if material.albedo_texture != null: record.append(hash(material.albedo_texture.get_image().get_data()))
		if child is CollisionShape3D and child.shape is ConcavePolygonShape3D: record.append(hash(child.shape.get_faces()))
		records.append(record)
	return records
func run() -> void:
	Storage.root_override = "res://tests/cache-fixtures"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("res://tests/") and argument.ends_with("-fixtures"): Storage.root_override = argument
	Storage.ensure_parent(Storage.root_path().path_join(".gdignore"))
	var ignore := FileAccess.open(Storage.root_path().path_join(".gdignore"), FileAccess.WRITE); ignore.close()
	Mods.initialize(false)
	var warm := "warm" in OS.get_cmdline_user_args()
	var started := Time.get_ticks_msec()
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var result := {}
	for model in ["SUB", "CLAM", "JACKFISH", "AQUATRAZ"]:
		var node := Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF")) if model == "SUB" else Assets.load_clump(folder.path_join("CLUMPS/" + model + ".DFF"), PackedStringArray(), true)
		check(node != null, model + " loads")
		if node == null: continue
		result[model] = signature(node)
		if model == "SUB": check(node.get_node_or_null("Hull/LeftPod") != null or node.find_child("LeftPod", true, false) != null,"Cached submarine retains movable pods")
		node.free()
	var modern := preload("res://modern_model.gd").load_model("res://../Mods/3d-bubbles/bubble.glb")
	check(modern != null,"Modern mod model loads")
	if modern != null: result["modern"] = signature(modern); modern.free()
	var catalogue := Data.load_catalogue(folder, false)
	check(not catalogue.get("tables", {}).is_empty(),"Gameplay tables load")
	result["catalogue"] = catalogue
	var world := await World.load_world(folder.path_join("DATA/SCEN1.BSP"), self, func(_message): pass)
	check(world != null,"World loads")
	if world != null:
		await World.add_collision(world, self, func(_message): pass)
		result["world"] = signature(world)
		result["bounds"] = world.get_meta("bounds")
		check(world.has_meta("collision_ready") and world.get_node_or_null("WaterSurfaceCollision") != null,"Cached terrain includes collision and water surface")
		world.free()
	var duration := Time.get_ticks_msec() - started
	var baseline := Storage.root_path().path_join("baseline.bin")
	if warm:
		var expected := bytes_to_var(FileAccess.get_file_as_bytes(baseline)) as Dictionary
		for entry in result: check(result[entry] == expected.get(entry),"Disk-cached " + str(entry) + " matches fresh conversion")
		check(Cache.hits >= 7 and Cache.writes == 0,"Separate process reuses conversions without rebuilding")
	else:
		var file := FileAccess.open(baseline, FileAccess.WRITE); file.store_buffer(var_to_bytes(result)); file.close()
		check(Cache.writes > 0,"Cold run creates local conversions")
	print("Asset cache %s: %d ms, %d hits, %d misses, %d writes" % ["warm" if warm else "cold", duration, Cache.hits, Cache.misses, Cache.writes])
	var ship_path := folder.path_join("CLUMPS/SUB.DFF")
	var first := Assets.load_submarine(ship_path)
	var second := Assets.load_submarine(ship_path)
	var ship_key := Assets.conversion_key("clump", ship_path, [PackedStringArray(["Hull", "RearPropeller", "LeftPod", "RightPod", "RightPropeller", "LeftPropeller"]), false])
	check(ResourceLoader.get_dependencies(Cache.path_for(ship_key, "res")).is_empty(),"Cached models embed textures without dependencies on other cache entries")
	var pod := first.find_child("LeftPod", true, false) as Node3D
	var other_pod := second.find_child("LeftPod", true, false) as Node3D
	var rest := other_pod.transform
	pod.rotate_x(0.5)
	check(other_pod.transform == rest,"Cached instances keep independent movable parts")
	first.free(); second.free()
	# Corrupt entries must fall back to original decoding, rather than break launch.
	var image_path := folder.path_join("GAMETEX/BUBBLE.BMP")
	var image := preload("res://legacy_bmp.gd").load_image(image_path)
	check(image != null,"Original bubble image loads")
	if image != null:
		var key := Cache.key("image", [image_path])
		var file := FileAccess.open(Cache.path_for(key, "res"), FileAccess.WRITE); file.store_string("broken cache"); file.close()
		var restored := preload("res://legacy_bmp.gd").load_image(image_path)
		check(restored != null and restored.get_data() == image.get_data(),"Damaged cache is rebuilt from original bytes")
	var fixture := Storage.root_path().path_join("source.txt")
	var source := FileAccess.open(fixture, FileAccess.WRITE); source.store_string("one"); source.close()
	Cache.reset_session(); var before := Cache.key("fixture", [fixture])
	source = FileAccess.open(fixture, FileAccess.WRITE); source.store_string("two"); source.close()
	Cache.reset_session()
	check(before != Cache.key("fixture", [fixture]),"Same-size source edit invalidates cache on the next launch")
	var base_key := Assets.conversion_key("clump", folder.path_join("CLUMPS/SUB.DFF"))
	Mods.apply(["3d-bubbles"], Mods.order, false)
	check(base_key != Assets.conversion_key("clump", folder.path_join("CLUMPS/SUB.DFF")),"Changing active mods invalidates converted assets")
	check(not Cache.path_for("test", "res").begins_with("res://game_assets"),"Conversions are separate from distributed game assets")
	print("Asset cache: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
