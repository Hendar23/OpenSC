extends "res://tests/test_scene_tree.gd"
class WakeProbe extends Node3D:
	var calls: Array[Dictionary] = []
	func emit_from(key: int, origin: Vector3, exhaust: Vector3, power: float, rate: float, delta: float) -> void:
		calls.append({"key":key,"origin":origin,"exhaust":exhaust,"power":power,"rate":rate,"delta":delta})
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
	menu.submarine = Node3D.new(); menu.add_child(menu.submarine)
	menu.submarine.position = Vector3(4,10,-3); menu.submarine.rotation.y = 0.7
	menu.wake = WakeProbe.new(); menu.add_child(menu.wake)
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	for id in ["SUB"] + Array(menu.PASS_MODELS):
		var model: Node3D = preload("res://clump_loader.gd").load_submarine(folder.path_join("CLUMPS/SUB.DFF")) if id == "SUB" else preload("res://map_document.gd").load_model(id,folder)
		check(model != null,"Menu model loads: " + id)
		if model == null: continue
		menu.submarine.add_child(model); model.scale *= 0.6; model.rotation.y += PI; menu.pass_propellers.clear()
		menu._register_propellers(model,id)
		var expected := 3 if id == "SUB" else 2 if id in ["TRAD2","PRISON"] else 1 if id in ["TRADSHUT","TRAD-SUB"] else 0
		check(menu.pass_propellers.size() == expected,"Correct separate rotor count: " + id)
		var hull: Node3D = model.get_child(0)
		var hull_basis := hull.basis
		menu.time = 0.05; menu._animate_propellers()
		for part in menu.pass_propellers:
			check(not part.node.basis.is_equal_approx(part.rest),"Original rotor animates: " + id)
		check(hull.basis.is_equal_approx(hull_basis),"Animation leaves hull fixed: " + id)
		menu.wake.calls.clear(); menu._emit_wake(Vector3.RIGHT,0.25)
		check(menu.wake.calls.size() == maxi(1,expected),"Menu wake uses every visible propeller, or the existing fallback: " + id)
		var total_rate := 0.0
		for index in menu.wake.calls.size():
			var emission: Dictionary = menu.wake.calls[index]; total_rate += emission.rate
			var origin: Vector3 = menu.pass_propellers[index].node.global_position - Vector3.RIGHT * 0.04 if expected > 0 else menu.submarine.global_position - Vector3.RIGHT * 0.4
			check(emission.origin.is_equal_approx(origin) and emission.exhaust == Vector3.LEFT,"Wake follows transformed rotor position and trails travel direction: " + id)
		check(is_equal_approx(total_rate,16.0),"Total menu bubble rate is preserved: " + id)
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
	menu.wake.calls.clear(); menu._emit_wake(Vector3.RIGHT,0.25)
	check(menu.wake.calls.size() == 1 and menu.wake.calls[0].origin.is_equal_approx(rotor.global_position - Vector3.RIGHT * 0.04),"Mod-declared rotor also supplies the menu wake origin")
	custom.hide(); menu.pass_propellers.clear(); menu.wake.free()
	menu.wake = preload("res://propeller_bubbles.gd").new(); menu.add_child(menu.wake); menu.wake.set_physics_process(false)
	var prison := preload("res://map_document.gd").load_model("PRISON",folder); menu.submarine.add_child(prison)
	prison.scale *= 0.6; prison.rotation.y = PI; menu._register_propellers(prison,"PRISON")
	menu._emit_wake(Vector3.RIGHT,0.25)
	check(menu.wake.particles.size() == 4,"Prison emits its full bubble count from two independent outlets")
	for particle in menu.wake.particles:
		var nearest := INF
		for part in menu.pass_propellers: nearest = minf(nearest,particle.position.distance_to(part.node.global_position - Vector3.RIGHT * 0.04))
		check(nearest < 0.07,"Actual prison bubble spawns within the propeller's existing jitter radius")
	var first_position: Vector3 = menu.wake.particles[0].position
	menu.submarine.position.x += 3
	check(menu.wake.particles[0].position == first_position,"Released menu bubbles stay in world space as the prison moves")
	menu.free()
	if not FileAccess.file_exists("res://tests/verify_menu_propellers.gd.uid"):
		var uid := FileAccess.open("res://tests/verify_menu_propellers.gd.uid",FileAccess.WRITE)
		uid.store_string(ResourceUID.id_to_text(ResourceUID.create_id()) + "\n")
	print("Menu propellers: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
