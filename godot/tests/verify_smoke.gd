extends SceneTree
const Editor = preload("res://asset_editor.gd")
const Document = preload("res://map_document.gd")
const Smoke = preload("res://smoke_emitter.gd")
var failures := 0
var checks := 0
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	preload("res://mod_registry.gd").initialize(false)
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	var editor := Editor.new(); editor.remember_preferences = false; root.add_child(editor)
	await process_frame
	editor._load_folder(folder); editor._set_mode(true)
	var map: HBoxContainer = editor.map_editor
	for frame in range(1800):
		if map.loaded: break
		await physics_frame
	check(map.loaded,"Editor loads")
	if not map.loaded: quit(1); return
	var keys: Array = map.document.entities.keys().filter(func(key: String) -> bool: return map.document.entities[key].kind == "smoke")
	check(keys.size() == 2,"Exactly two canonical factory emitters imported")
	var database := Document.Scenery.read_database(folder.path_join("DATA/SCEN1.DDB"))
	for key in keys:
		var smoke: Node3D = map.world.get_node(NodePath(key))
		var index := int(key.get_slice("_",1))
		var rows: Array = database.Objects.filter(func(row: Dictionary) -> bool: return int(row.index) == index)
		check(rows.size() == 1 and smoke.transform.is_equal_approx(Document.Scenery.placement(rows[0],map.world.get_meta("database_offset"))),"Factory smoke retains original database transform")
		check(smoke.textures.size() == 3 and smoke.textures.all(func(texture: Texture2D) -> bool: return texture != null),"Original masked smoke textures load")
	map.category.select(7); map._refresh_list()
	check(map.list_keys.size() == 2,"Smoke category lists factory emitters")
	if DisplayServer.get_name() != "headless":
		var target: Vector3 = map.world.get_node(NodePath(keys[0])).global_position
		map.camera.global_position = target + Vector3(7,3,8)
		map.camera.look_at(target + Vector3.UP)
		for key in keys:
			var emitter: Node3D = map.world.get_node(NodePath(key))
			for frame in range(60): emitter._process(0.1)
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		map.viewport.get_texture().get_image().save_png("res://../dist/factory-smoke-preview.png")
	map.select(keys[0]); map.fields.emission_rate.value = 8; map.fields.drift_x.value = 0.4; map.fields.opacity.value = 0.7
	map.apply_properties()
	var smoke: Node3D = map.world.get_node(NodePath(keys[0]))
	check(smoke.tuning.emission_rate == 8 and is_equal_approx(smoke.tuning.opacity,0.7),"Editor properties update live emitter")
	var path := "res://tests/smoke-roundtrip.json"
	check(Document.save(map.document,path) == OK,"Smoke settings save")
	var saved := Document.load_path(path)
	check(saved.entities[keys[0]].emission_rate == 8 and saved.entities[keys[0]].drift_x == 0.4,"Smoke settings survive map load")
	var invalid := saved.duplicate(true); invalid.entities[keys[0]].lifetime = -1
	check(not Document.valid(invalid),"Invalid smoke settings rejected")
	map.duplicate_selection()
	check(map.world.get_node(NodePath(map.selected)) is Smoke and map.record().emission_rate == 8,"Duplicate retains smoke settings")
	map.delete_selection(); map.undo()
	check(map.world.get_node_or_null(NodePath(map.selected)) != null or map.document.entities.values().any(func(entry: Dictionary) -> bool: return entry.kind == "smoke" and entry.name.ends_with("copy") and not entry.deleted),"Undo restores deleted smoke")
	map._add_entity("smoke","")
	check(map.record().kind == "smoke" and map.world.get_node(NodePath(map.selected)) is Smoke,"Add smoke creates editable emitter")
	smoke = map.world.get_node(NodePath(map.selected)); smoke.set_process(false)
	for frame in range(100): smoke._process(0.1)
	check(smoke.puffs.size() > 10 and smoke.puffs.size() <= Smoke.CAPACITY,"Puffs emit and expire within bounded pool")
	var puff: Dictionary = smoke.puffs[smoke.puffs.size() / 2]
	check(puff.node.global_position.y > smoke.global_position.y,"Smoke rises in world space")
	var point: Vector3 = puff.node.global_position
	var size: Vector3 = puff.node.scale
	smoke._process(0.05)
	check(puff.node.global_position.y > point.y and puff.node.scale.x > size.x,"Smoke drifts and expands")
	smoke.enabled = false
	for frame in range(100): smoke._process(0.1)
	check(smoke.puffs.is_empty(),"Disabled emitter lets remaining puffs dissipate")
	smoke.enabled = true; smoke.set_process(true)
	paused = true; var count: int = smoke.puffs.size()
	await create_timer(0.3,true).timeout
	check(smoke.puffs.size() == count,"Dock/menu tree pause freezes smoke")
	paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	editor.queue_free(); await process_frame
	print("Smoke: %d checks, %d failures" % [checks,failures]); quit(0 if failures == 0 else 1)
