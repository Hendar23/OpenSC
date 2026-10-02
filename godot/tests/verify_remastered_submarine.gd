extends SceneTree
const Mods = preload("res://mod_registry.gd")
const Assets = preload("res://clump_loader.gd")
const Paths = preload("res://asset_paths.gd")
const Game = preload("res://game.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(description)
func bounds(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var transform := Transform3D.IDENTITY
		var current: Node3D = node
		while current != model:
			transform = current.transform * transform
			current = current.get_parent() as Node3D
		var box: AABB = model.transform * transform * node.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
func _run() -> void:
	Mods.initialize(false)
	check(Mods.packs.any(func(pack: Dictionary) -> bool: return pack.id == "test.remastered-submarine" and pack.valid), "Remastered submarine is discovered as a valid mod")
	check(not Mods.active_ids().has("test.remastered-submarine"), "Test mod is disabled by default")
	var folder := Paths.find_game_folder()
	var original := Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF"))
	var original_bounds := bounds(original)
	original.free()
	Mods.apply(["test.remastered-submarine"], Mods.order, false)
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete and game.pilot.visual.get_meta("modern_model", false), "Game launches with remastered replacement")
	var model: Node3D = game.pilot.visual
	var parts: Dictionary = model.get_meta("submarine_parts", {})
	check(parts.size() == 5, "All five moving assemblies resolve")
	var new_bounds := bounds(model)
	print("Original bounds: ", original_bounds, " / replacement bounds: ", new_bounds)
	check(new_bounds.size.length() / original_bounds.size.length() < 1.2 and new_bounds.size.length() / original_bounds.size.length() > 0.6, "Replacement retains the current submarine scale")
	if parts.size() == 5:
		for role in ["left_pod", "right_pod"]:
			var pod := model.get_node(NodePath(parts[role])) as Node3D
			var rest: Basis = pod.get_meta("rest_basis")
			game.pilot.movement.tilt = PI / 4.0
			game.pilot._update_animation(0.1)
			check(not pod.basis.is_equal_approx(rest), role + " tilts")
		game.pilot.movement.main_power = 1.0
		game.pilot.movement.left_power = 1.0
		game.pilot.movement.right_power = 1.0
		for role in ["main_propeller", "left_propeller", "right_propeller"]:
			var propeller := model.get_node(NodePath(parts[role])) as Node3D
			var rest := propeller.basis
			game.pilot._update_animation(0.03)
			check(not propeller.basis.is_equal_approx(rest), role + " spins")
	game.queue_free()
	await process_frame
	Mods.initialize(false)
	print("Remastered submarine verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
