extends "res://tests/test_scene_tree.gd"
const Resources = preload("res://campaign_resources.gd")
const Identity = preload("res://entity_identity.gd")
var game: Node
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func _initialize() -> void:
	var paths = preload("res://asset_paths.gd")
	var folder := ProjectSettings.globalize_path("res://../Original Sub Culture")
	if not paths.valid_game_folder(folder): folder = paths.find_game_folder()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-campaign-resources-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")

func bonus() -> Array[Node]:
	var result: Array[Node] = []
	for body in game.object_population.get_children():
		if body.is_queued_for_deletion(): continue
		if body.get_meta("object_group","") == Resources.GROUP or str(body.get_meta("source_entity_id","")).begins_with(Resources.GROUP+"/"): result.append(body)
	return result

func stabilize() -> void:
	game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.docking.set_physics_process(false); game.set_process(false); game.set_physics_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	for body in game.object_population.get_children():
		if body is RigidBody3D: body.freeze = true

func port() -> void:
	game.docking.current = game.submarine_traffic.port_by_id(1); game.docking.stage = game.Docking.Stage.DOCKED

func inspect_cave() -> void:
	await physics_frame
	var exclusions: Array[RID] = []
	for body in bonus(): exclusions.append(body.get_rid())
	var center := Vector3.ZERO
	for body in bonus():
		if body.stats.id != "inert_thorium": continue
		center += body.global_position*0.25
		var roof := PhysicsRayQueryParameters3D.create(body.global_position,body.global_position+Vector3.UP*40,1,exclusions)
		var floor_ray := PhysicsRayQueryParameters3D.create(body.global_position,body.global_position+Vector3.DOWN*30,1,exclusions)
		roof.hit_back_faces = true; floor_ray.hit_back_faces = true
		var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
		check(not space.intersect_ray(roof).is_empty() and not space.intersect_ray(floor_ray).is_empty(),"Source crystal sits inside the actual abyss cave, with rock above and below")
	if DisplayServer.get_name() == "headless": return
	var previous: Transform3D = game.camera.global_transform
	for offset in [Vector3(4,2,4),Vector3(-4,2,4),Vector3(2,0.5,2),Vector3(-2,0.5,-2)]:
		var ray := PhysicsRayQueryParameters3D.create(center,center+offset,1,exclusions); ray.hit_back_faces = true
		if game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			game.camera.global_position = center+offset; break
	game.camera.look_at(center); game.camera.make_current()
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/campaign-cave.png")
	game.camera.global_transform = previous

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Campaign fixture loads the original assets")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); stabilize(); port()
	var runtime: Node = game.mission_runtime
	check(bonus().is_empty(),"New game does not seed the opening bonus before acceptance")
	check(runtime.accept(1).is_empty(),"First opening acceptance succeeds")
	check(bonus().size() == 7 and runtime.spawned.size() == 6,"Four cave crystals and three caps are independent of the six mission-owned actors")
	check(not game.save_games.read(-1).progress.missions.has("world_events"),"Pre-mission autosave precedes the one-time resource event")
	var crystals := 0; var caps := 0
	var offset: Vector3 = game.world_root.get_meta("database_offset")
	for row in game.gameplay_catalogue.tables["database.objects"].records.values():
		if int(row.get("MissionID",0)) != 33 or int(row.get("AutoCreate",0)) != 1: continue
		var found: Array[Node] = bonus().filter(func(body: Node) -> bool: return Identity.of(body) == Resources.GROUP+"/"+str(row.index))
		check(found.size() == 1,"Each original placement has exactly one persistent identity")
		if found.is_empty(): continue
		var body: Node3D = found[0]
		var expected: Transform3D = preload("res://scenery_loader.gd").placement(row,offset)
		check(body.global_transform.is_equal_approx(expected) and not body.has_meta("mission_owner"),"Original source transform is retained without mission ownership")
		if int(row.ObjectType) == 64:
			crystals += 1
			check(body.stats.id == "inert_thorium" and body.shard == 0 and is_equal_approx(body.mass,game.object_population.thorium_types.inert_thorium.mass),"Abyss placement is a full inert crystal and respects authored mass settings")
			check(is_equal_approx(body.stats.radiation_strength,game.object_population.thorium_types.inert_thorium.radiation_strength),"Cave crystal uses the configured inert radiation strength")
		else: caps += 1
	check(crystals == 4 and caps == 3,"Retail opening AutoCreate population matches the source data")
	stabilize()
	await inspect_cave()
	var crystal: Node3D = bonus().filter(func(body: Node) -> bool: return body.stats.id == "inert_thorium")[0]
	var source := Identity.of(crystal)
	crystal.take_damage(100)
	await process_frame
	var shards: Array[Node] = bonus().filter(func(body: Node) -> bool: return body.get_meta("source_entity_id","") == source)
	check(shards.size() == 3 and shards.all(func(body: Node) -> bool: return body.shard > 0 and not body.has_meta("mission_owner")),"Mining makes three persistent, unowned shards")
	runtime.finish(false); await process_frame
	check(bonus().size() == 9,"Opening failure cleanup preserves cave ore, mined shards and caps")
	port(); check(runtime.accept(1).is_empty() and bonus().size() == 9,"Retry does not refill the cave or duplicate bonus salvage")
	runtime.docked(6); runtime.docked(1); await process_frame
	check(game.player_progress.campaign_stage == 2 and bonus().size() == 9,"Opening completion keeps all surviving bonus resources")
	stabilize(); port()
	var before: Dictionary = game._save_snapshot("Persistent cave")
	check(game.save_games.write(0,before) == OK,"Published beta save format accepts the additive event marker")
	check(await game._load_saved_game(0),"Actual game loader restores the cave save")
	stabilize()
	var identities: Array = bonus().map(func(body: Node) -> String: return Identity.of(body))
	var expected_ids: Array = before.objects.filter(func(entry: Dictionary) -> bool: return entry.get("object_group","") == Resources.GROUP or str(entry.get("source_entity_id","")).begins_with(Resources.GROUP+"/")).map(func(entry: Dictionary) -> String: return entry.entity_id)
	identities.sort(); expected_ids.sort()
	check(identities == expected_ids and bonus().size() == 9,"Save/load retains surviving resource and shard identities without duplication")
	for body in bonus(): body.free()
	port(); check(game.save_games.write(1,game._save_snapshot("Depleted cave")) == OK,"Depleted cave saves normally")
	check(await game._load_saved_game(1),"Depleted cave save loads")
	check(bonus().is_empty(),"One-time marker prevents mined/collected resources respawning on load")
	var legacy: Dictionary = before.duplicate(true)
	legacy.progress.missions.erase("world_events")
	legacy.progress.status.credits = 43210; legacy.progress.cargo.gold = 3
	legacy.objects = legacy.objects.filter(func(entry: Dictionary) -> bool: return entry.get("object_group","") != Resources.GROUP and not str(entry.get("source_entity_id","")).begins_with(Resources.GROUP+"/"))
	check(game.save_games.write(2,legacy) == OK and await game._load_saved_game(2),"Post-opening save from the published beta migrates through the real loader")
	check(bonus().size() == 7 and game.player_progress.status.credits == 43210 and game.player_progress.cargo.gold == 3,"Old save receives the missing deposit once without changing credits or hold")
	Resources.restore_for_progress(game)
	check(bonus().size() == 7,"Repeated event restoration cannot duplicate the correction")
	game.player_progress.missions.erase("world_events")
	for body in bonus():
		if body.stats.id != "inert_thorium": body.free()
	Resources.restore_for_progress(game)
	check(bonus().size() == 4 and game.player_progress.missions.world_events.opening_bonus,"Surviving legacy event objects are recognized without replenishing a partially depleted deposit")
	game._begin_new_game(); stabilize(); port()
	check(bonus().is_empty() and not game.player_progress.missions.has("world_events"),"Starting another game resets both population and event marker")
	Resources.restore_for_progress(game)
	check(bonus().is_empty(),"An old pre-opening save remains untouched until the opening mission is accepted")
	game.queue_free(); await process_frame
	print("Campaign resources: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
