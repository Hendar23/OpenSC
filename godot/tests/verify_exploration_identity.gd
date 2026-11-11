extends "res://tests/test_scene_tree.gd"

const Mods = preload("res://mod_registry.gd")
const Terrain = preload("res://terrain_asset.gd")
var checks := 0
var failures := 0
var game: Node
var expected_mask := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: return
	failures += 1
	push_error(message)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(1)
		return
	var storage := preload("res://player_storage.gd")
	storage.root_override = "res://../.local/high-poly-terrain/exploration-test-player"
	storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new()
	config.set_value("game", "folder", args[0])
	config.save(storage.preferences_path())
	Mods.initialize(false, args[1], storage.preferences_path())
	var pack := Mods.packs.filter(func(item: Dictionary) -> bool: return item.id == "high-poly-terrain")
	check(pack.size() == 1, "High-poly fixture is available")
	if pack.size() != 1: quit(1); return
	var identity := Terrain.read_exploration_identity(pack[0].assets["terrain.scen1"].path)
	var original_signature := "terrain-v1:" + FileAccess.get_sha256(args[0].path_join("DATA/SCEN1.BSP"))
	check(identity.get("signature") == original_signature and identity.get("aliases", []).size() == 1, "High-poly asset declares its original-map identity and legacy save alias")
	if identity.get("aliases", []).is_empty(): quit(1); return
	game = preload("res://game.gd").new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in 3000:
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete, "Game starts with the original terrain")
	if not game.startup_complete: quit(1); return
	game.front_end.gameplay_menu.fmvs_enabled = false
	await game._begin_new_game()
	dock()
	var map: RefCounted = game.cockpit_hud.map_data
	map.reset_exploration()
	map.explored.set_pixel(100, 101, Color.WHITE)
	map.explored.set_pixel(410, 287, Color(0.6, 0.6, 0.6))
	map.discovered_cities["4"] = true
	map.landmarks.visited["Pipe"] = true
	var stock: Dictionary = game._save_snapshot("Original terrain exploration")
	expected_mask = stock.explored
	check(game.save_games.write(0, stock) == OK and stock.map_signature == original_signature, "Original terrain saves the shared exploration identity")
	var legacy := stock.duplicate(true)
	legacy.map_signature = identity.aliases[0]
	check(game.save_games.write(2, legacy) == OK, "Legacy high-poly save fixture is written")
	await switch_mod(true)
	check(game._map_signature() == original_signature, "High-poly terrain uses the same exploration identity")
	await restore(0, "Original to high-poly")
	check(game.save_games.write(1, game._save_snapshot("High-poly exploration")) == OK, "High-poly save retains the stable identity")
	await restore(2, "Legacy high-poly to updated high-poly")
	await switch_mod(false)
	await restore(1, "High-poly to original")
	await restore(2, "Legacy high-poly to original with the mod disabled")
	check(not game._exploration_matches_map("terrain-asset-v1:" + "a".repeat(64)), "Unknown terrain assets do not inherit exploration")
	check(not game._exploration_matches_map("terrain-v1:" + "a".repeat(64)), "Different original maps do not inherit exploration")
	game.free()
	paused = false
	print("Exploration switching: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func switch_mod(enabled: bool) -> void:
	var ids: Array[String] = []
	if enabled: ids.append("high-poly-terrain")
	Mods.apply(ids, ["high-poly-terrain"], false)
	paused = false
	await game._start_game(game.game_folder)
	check(game.world_root.has_meta("terrain_asset_hash") == enabled, "Normal startup applies the requested terrain selection")

func restore(slot: int, label: String) -> void:
	check(await game._load_saved_game(slot), label + " save loads")
	var snapshot: Dictionary = game._save_snapshot("Restored exploration")
	check(snapshot.explored == expected_mask, label + " keeps every reveal-mask byte")
	check("4" in snapshot.discovered_cities, label + " keeps discovered cities")
	check("Pipe" in snapshot.map_landmarks.visited, label + " keeps landmark visits")

func dock() -> void:
	game.pilot.freeze = true
	game.pilot.set_physics_process(false)
	game.docking.set_physics_process(false)
	game.set_process(false)
	var port: Dictionary = game.docking.ports[0]
	game.docking.current = port
	game.docking.saved_collision_mask = game.pilot.collision_mask
	game.pilot.global_position = port.inside
	game.pilot.active = false
	game.docking._transition(game.Docking.Stage.DOCKED)
