extends "res://tests/test_scene_tree.gd"
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-menu-propeller-fixtures"
	call_deferred("run")
func run() -> void:
	var menu := preload("res://menu_backdrop.gd").new(); root.add_child(menu)
	menu.set_process(false); menu.show()
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	for id in ["SUB"] + Array(menu.PASS_MODELS):
		var model: Node3D = preload("res://clump_loader.gd").load_submarine(folder.path_join("CLUMPS/SUB.DFF")) if id == "SUB" else preload("res://map_document.gd").load_model(id,folder)
		check(model != null,"Menu model loads: " + id)
		if model == null: continue
		menu.add_child(model); menu.pass_propellers.clear()
		menu._register_propellers(model,id)
		var expected := 3 if id == "SUB" else 2 if id in ["TRAD2","PRISON"] else 1 if id in ["TRADSHUT","TRAD-SUB"] else 0
		check(menu.pass_propellers.size() == expected,"Correct separate rotor count: " + id)
		var hull: Node3D = model.get_child(0)
		var hull_basis := hull.basis
		menu.time = 0.05; menu._animate_propellers()
		for part in menu.pass_propellers:
			check(not part.node.basis.is_equal_approx(part.rest),"Original rotor animates: " + id)
		check(hull.basis.is_equal_approx(hull_basis),"Animation leaves hull fixed: " + id)
		model.hide(); menu.time = 0.1
		var poses: Array[Basis] = []
		for part in menu.pass_propellers: poses.append(part.node.basis)
		menu._animate_propellers()
		for index in menu.pass_propellers.size(): check(menu.pass_propellers[index].node.basis.is_equal_approx(poses[index]),"Hidden variant rotor stays idle")
		model.free()
	var custom := Node3D.new(); menu.add_child(custom)
	var rotor := Node3D.new(); rotor.name = "CustomFan"; custom.add_child(rotor)
	custom.set_meta("modern_model",true); custom.set_meta("submarine_parts",{"main_propeller":"CustomFan"})
	menu.pass_propellers.clear(); menu._register_propellers(custom,"TECHSHUT")
	check(menu.pass_propellers.size() == 1,"Mod-declared propeller binds independently of node name")
	menu.time = 0.05; menu._animate_propellers()
	check(not rotor.basis.is_equal_approx(Basis.IDENTITY),"Mod-declared rotor animates")
	menu.free()
	if not FileAccess.file_exists("res://tests/verify_menu_propellers.gd.uid"):
		var uid := FileAccess.open("res://tests/verify_menu_propellers.gd.uid",FileAccess.WRITE)
		uid.store_string(ResourceUID.id_to_text(ResourceUID.create_id()) + "\n")
	print("Menu propellers: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
