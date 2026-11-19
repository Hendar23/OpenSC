extends "res://tests/test_scene_tree.gd"
const Document = preload("res://map_document.gd")
const Mods = preload("res://mod_registry.gd")
class Editor extends "res://map_editor.gd":
	func _sync() -> void: pass
	func _refresh_list() -> void: pass
	func select(_key: String) -> void: pass
class Front extends RefCounted:
	var menu_config := {"camera_anchor":[0,0,0],"camera_offset":[5,2,5],"look_offset":[0,0,0]}
class Context extends Node3D:
	var use_map_overrides := true
	var camera: Camera3D
	var front_end := Front.new()
	var world_root: Node3D
	var pilot: Node3D
	var cockpit_hud: Control
	var canvas: Control
	var particles: Node3D
	var docked_screen: Control
class Wake extends Node3D:
	func clear() -> void: pass
class Backdrop extends "res://menu_backdrop.gd":
	func _add_plants() -> void: pass
	func _refresh_wildlife() -> void: generation += 1
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-menu-views-fixtures"
	var editor := Editor.new(); root.add_child(editor); editor.loaded = true
	editor.document = Document.empty()
	var first := {"transform":Document.encode(Transform3D(Basis.IDENTITY,Vector3(10,4,10))),"fov":60.0}
	editor.document.menu_camera = first.duplicate(true)
	check(Document.menu_camera_slots(editor.document)[0] == first,"Existing single camera becomes View 1 without rewriting authored data")
	check(editor.menu_view_slot.item_count == 4,"Editor offers four camera slots")
	for slot in range(1,4):
		editor.menu_view_slot.select(slot)
		editor.camera.transform = Transform3D(Basis(Vector3.UP,slot * 0.2),Vector3(slot * 10,4,10)); editor.camera.fov = 60 + slot
		var pose := editor.camera.transform; editor.capture_menu_camera()
		check(Document.valid(editor.document) and editor.document.menu_camera == first,"Capturing View %d preserves legacy View 1 and validates" % (slot+1))
		editor.camera.position += Vector3.ONE; editor.view_menu_camera()
		check(editor.camera.transform.is_equal_approx(pose) and editor.camera.fov == 60+slot,"Preview restores selected camera position, rotation and FOV")
	var all_views := editor.document.duplicate(true)
	editor.clear_menu_camera(); check(editor.document.menu_cameras[3].is_empty(),"Clear affects selected camera only")
	editor.undo(); check(editor.document == all_views,"Camera removal supports undo")
	editor.redo(); check(editor.document.menu_cameras[3].is_empty(),"Camera removal supports redo")
	editor.undo()
	var fixture := "res://tests/cache-menu-views-fixtures/Mods/views"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	check(Document.save(editor.document,fixture.path_join("map.json")) == OK,"Four cameras save to isolated map")
	var loaded := Document.load_path(fixture.path_join("map.json"))
	var round_trip := true
	for slot in range(4):
		round_trip = round_trip and Document.decode(loaded.menu_cameras[slot].transform).is_equal_approx(Document.decode(all_views.menu_cameras[slot].transform)) and is_equal_approx(float(loaded.menu_cameras[slot].fov),float(all_views.menu_cameras[slot].fov))
	check(round_trip,"All camera transforms and FOVs survive JSON round trip")
	for bad in [null,{},[first,first,first,first,first],[{"fov":60}],[first,42]]:
		var invalid := all_views.duplicate(true); invalid.menu_cameras = bad
		check(not Document.valid(invalid),"Invalid camera collection is rejected")
	var invalid := all_views.duplicate(true); invalid.menu_cameras[2].fov = 180
	check(not Document.valid(invalid),"Invalid FOV in any slot is rejected")
	invalid = all_views.duplicate(true); invalid.menu_cameras[2].transform[0] = 2
	check(not Document.valid(invalid),"Scaled camera basis in any slot is rejected")
	var manifest := FileAccess.open(fixture.path_join("mod.json"),FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema_version":1,"id":"menu-view-fixture","name":"Menu view fixture","assets":{"map.scen1":"map.json"}})); manifest.close()
	Mods.initialize(false,fixture.get_base_dir()); Mods.apply(["menu-view-fixture"],[],false)
	var context := Context.new(); root.add_child(context)
	context.camera = Camera3D.new(); context.add_child(context.camera); context.camera.far = 500
	context.world_root = Node3D.new(); context.add_child(context.world_root); context.world_root.set_meta("surface_height",100)
	var menu := Backdrop.new(); context.add_child(menu); menu.game = context; menu.set_process(false)
	menu.wake = Wake.new(); menu.add_child(menu.wake)
	menu.submarine = Node3D.new(); menu.add_child(menu.submarine)
	menu.propeller_audio = AudioStreamPlayer3D.new(); menu.add_child(menu.propeller_audio)
	menu.random.seed = 91823
	var seen := {}; var eligible := true; var stable := true
	for iteration in range(128):
		menu.open()
		var index := -1
		for slot in range(4):
			if menu.view.transform.is_equal_approx(Document.decode(all_views.menu_cameras[slot].transform)): index = slot
		eligible = eligible and index >= 0 and is_equal_approx(menu.view.fov,float(all_views.menu_cameras[index].fov))
		seen[index] = true
		var pose := menu.view.transform; menu.open()
		stable = stable and menu.view.transform.is_equal_approx(pose)
		menu.close()
	check(eligible and seen.size() == 4,"Opening the menu randomly uses all four saved views with their own FOVs")
	check(stable,"An already-open menu retains its chosen camera")
	check(menu.generation == 128,"Each menu opening refreshes its camera-local population once")
	var sparse := Document.empty(); sparse.menu_cameras = [{},{},first,{}]
	Document.save(sparse,fixture.path_join("map.json")); menu.open()
	check(menu.view.transform.is_equal_approx(Document.decode(first.transform)),"Empty slots are excluded from random selection")
	menu.close()
	var legacy := Document.empty(); legacy.menu_camera = first
	Document.save(legacy,fixture.path_join("map.json")); menu.open()
	check(menu.view.transform.is_equal_approx(Document.decode(first.transform)),"Published single-camera maps still work")
	menu.close(); Document.save(Document.empty(),fixture.path_join("map.json")); menu.open()
	check(menu.view.position.is_equal_approx(Vector3(5,2,5)) and menu.view.fov == 65,"No captured views restores default menu framing and FOV")
	menu.close(); context.queue_free(); editor.queue_free(); await process_frame
	for name in ["map.json","mod.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.path_join(name)))
	print("Menu views: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
