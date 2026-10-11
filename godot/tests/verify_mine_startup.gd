extends SceneTree
const Game = preload("res://game.gd")
const Mines = preload("res://mine_population.gd")
const Mine = preload("res://floating_mine.gd")
const Document = preload("res://map_document.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 preload("res://mod_registry.gd").initialize(false)
 var game = Game.new(); game.remember_preferences = false; root.add_child(game)
 for frame in range(1800):
  if game.startup_complete: break
  await physics_frame
 check(game.startup_complete,"World loads with original mine spawning")
 if not game.startup_complete: quit(1); return
 var population = game.object_population
 var mines = population.mines
 check(mines.fields.size() == 3 and mines.fields.map(func(field: Dictionary): return field.attempts) == [25,25,30],"All three authored mine forests retain their 25/25/30 attempts")
 var data = JSON.parse_string(FileAccess.get_file_as_string("res://../Maps/scen1.json"))
 check(not data.object_groups.any(func(group: Dictionary): return group.type == "floating_mine"),"Six approximated Aquatraz groups are removed")
 check(Mines.WORLD_ATTEMPTS == 11 and Mines.FIELD_STEP == 0.625,"Startup loop and scatter grid match recovered executable")
 var candidate_center := Vector3(100,100,100)
 population.random.seed = 42
 for attempt in range(100):
  var delta: Vector3 = mines.field_candidate(candidate_center) - candidate_center
  check(delta.x >= -10 and delta.x <= 9.375 and delta.y >= -10 and delta.y <= 9.375 and delta.z >= -10 and delta.z <= 9.375 and (delta * 1.6).is_equal_approx((delta * 1.6).round()),"Field candidate uses original discrete three-axis scatter")
 check(not mines.valid_field_point(Vector3(0,population.surface_height + 1,0)),"Minefield rejects above-water candidates")
 game.set_process(false); game.set_physics_process(false)
 population.random.seed = 42; mines.populate_startup()
 var saved: Array = mines.snapshot()
 print("Generated mines: ",saved.size()," by field ",mines.fields)
 check(saved.size() > 0 and saved.size() <= 91,"Terrain validation produces no more than the 91 total placement attempts")
 for field in mines.fields:
  var prefix := "startup-mine/field-%d/" % field.record
  var members = saved.filter(func(entry: Dictionary): return entry.entity_id.begins_with(prefix))
  check(members.size() <= field.attempts and members.all(func(entry: Dictionary): return mines.valid_field_point(Document.vector(entry.home))),"Mine forest accepts only positions between ground and surface")
  check(members.all(func(entry: Dictionary): return Document.vector(entry.home).distance_to(field.center) <= sqrt(3.0) * 10.001),"Mine forest stays in original scatter cube")
 population.random.seed = 42; mines.populate_startup()
 check(mines.snapshot() == saved,"Repeated seeded generation is deterministic and replaces previous generated mines")
 var live: Array = population.get_children().filter(func(body: Node): return body is Mine and body.get_meta("startup_mine",false))
 var removed_id = preload("res://entity_identity.gd").of(live[0]); live[0].dead = true
 if live.size() > 1: live[1].health = 0.2
 var after: Array = JSON.parse_string(JSON.stringify(mines.snapshot()))
 check(Mines.valid_snapshot(after) and after.size() == saved.size() - 1,"Save snapshot excludes destroyed mines and validates remaining mines")
 mines.restore(after)
 var restored: Array = mines.snapshot()
 var matches := restored.size() == after.size()
 for index in range(restored.size()):
  matches = matches and restored[index].entity_id == after[index].entity_id and Document.vector(restored[index].home).is_equal_approx(Document.vector(after[index].home)) and is_equal_approx(restored[index].health,after[index].health) and is_equal_approx(restored[index].phase,after[index].phase) and is_equal_approx(restored[index].age,after[index].age)
 check(matches and not restored.any(func(entry: Dictionary): return entry.entity_id == removed_id),"Load preserves mine placement, health, phase and destruction")
 mines.restore([])
 check(mines.snapshot().is_empty(),"An empty saved minefield remains empty")
 var invalid := after.duplicate(true)
 if not invalid.is_empty():
  invalid[0].home[0] = NAN; check(not Mines.valid_snapshot(invalid),"Non-finite saved mine coordinates are rejected")
 await game._begin_new_game()
 check(not mines.snapshot().is_empty(),"New Game repopulates mines after a cleared save")
 game.docking.current = game.docking.ports[0]
 var snapshot: Dictionary = game._save_snapshot("Mine startup test")
 check(snapshot.has("mines") and preload("res://save_games.gd").valid(snapshot),"Session save includes valid generated mine state")
 snapshot.erase("mines")
 check(preload("res://save_games.gd").valid(snapshot),"Old saves without mine state remain supported")
 game.queue_free(); await process_frame
 print("Original mine startup: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
