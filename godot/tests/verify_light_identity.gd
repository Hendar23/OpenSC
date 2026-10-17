extends "res://tests/test_scene_tree.gd"
const Document = preload("res://map_document.gd")
const Pulse = preload("res://pulse_light.gd")
const Searchlight = preload("res://searchlight.gd")
const Scenery = preload("res://scenery_loader.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void:
 var storage = preload("res://player_storage.gd")
 storage.root_override = "res://tests/cache-light-identity-fixtures"
 storage.ensure_parent(storage.preferences_path())
 var cfg := ConfigFile.new()
 cfg.set_value("game","folder",ProjectSettings.globalize_path("res://../Original Sub Culture"))
 cfg.save(storage.preferences_path())
 call_deferred("run")
func run() -> void:
 preload("res://mod_registry.gd").initialize(false)
 var game = preload("res://game.gd").new()
 game.remember_preferences = false; game.use_map_overrides = false; root.add_child(game)
 for frame in range(3000):
  if game.startup_complete: break
  await process_frame
 check(game.startup_complete,"Original world loads")
 if not game.startup_complete: quit(1); return
 var world: Node3D = game.world_root
 var baseline := Document.capture(world)
 var moved: Dictionary = baseline.entities["Scenery/Beacon_Object_62"].duplicate(true)
 moved.transform[9] += 0.12; moved.name = "User dock lamp"
 var old := Document.empty()
 old.entities["Scenery/Light_69"] = moved.duplicate(true)
 old.entities["Scenery/Light_69"].erase("light_source_id")
 old.entities["Scenery/Light_69"].erase("light_source_position")
 var tombstone: Dictionary = baseline.entities["Scenery/Beacon_Object_62"].duplicate(true)
 tombstone.deleted = true; tombstone.erase("light_source_id"); tombstone.erase("light_source_position")
 old.entities["Scenery/Light_33"] = tombstone
 var removed: Dictionary = baseline.entities["Scenery/Beacon_Light_1"].duplicate(true)
 removed.deleted = true; removed.erase("light_source_id"); removed.erase("light_source_position")
 old.entities["Scenery/Light_71"] = removed
 old.entities["Scenery/Light_59"] = removed.duplicate(true)
 old.entities["Added/custom"] = moved.duplicate(true)
 var distant := moved.duplicate(true); distant.transform[9] += 100
 distant.erase("light_source_id"); distant.erase("light_source_position")
 old.entities["Scenery/Light_999"] = distant
 Document.migrate_light_ids(world,old)
 check(old.entities["Scenery/Beacon_Object_62"].transform == moved.transform,"Retained moved light wins over duplicate tombstones")
 check(old.entities["Scenery/Beacon_Object_62"].name == moved.name,"Retained light settings/name survive")
 check(old.entities["Scenery/Beacon_Light_1"].deleted,"Old deletion maps to original source")
 check(not old.entities.has("Scenery/Light_59") and not old.entities.has("Scenery/Light_71"),"Duplicate historical IDs collapse")
 check(old.entities.has("Added/custom") and old.entities.has("Scenery/Light_999"),"Added and distant authored lights remain intact")
 var once := old.duplicate(true); Document.migrate_light_ids(world,old)
 check(old == once,"Migration is idempotent")
 old.entities["Scenery/Beacon_Object_62"].deleted = true
 old.entities["Scenery/Light_69"] = moved.duplicate(true)
 Document.migrate_light_ids(world,old)
 check(old.entities["Scenery/Beacon_Object_62"].deleted,"Permanent deletion wins over historical live alias")
 # Adding unrelated children must never rename original-table lights.
 var scratch := Node3D.new(); root.add_child(scratch)
 Scenery._add_light(scratch,Vector3.ZERO,1,4,game.game_folder,"Object_7")
 scratch.add_child(Node3D.new())
 Scenery._add_light(scratch,Vector3.RIGHT * 5,1,4,game.game_folder,"Light_7")
 check(scratch.has_node("Beacon_Object_7") and scratch.has_node("Beacon_Light_7"),"Source rows have stable, separate table namespaces")
 scratch.free()
 var data := Document.load_path(Document.DEFAULT_PATH)
 var before := data.duplicate(true)
 Document.migrate_light_ids(world,data)
 for field in before:
  if field != "entities": check(before[field] == data[field],"Migration preserves " + str(field))
 for key in before.entities:
  if before.entities[key].get("kind") != "light": check(before.entities[key] == data.entities[key],"Non-light entity preserved: " + key)
 check(data.entities["Scenery/Beacon_Light_0"].deleted and data.entities["Scenery/Beacon_Light_1"].deleted,"Both repeatedly deleted placements remain deleted")
 var dock_lamp: Dictionary = data.entities["Scenery/Beacon_Object_62"]
 check(not dock_lamp.get("deleted",false),"Repositioned dock lamp retained")
 Document.apply_entities(world,game.game_folder,data)
 var count := 0
 for node in world.find_children("*","Node3D",true,false):
  if node is Pulse or node is Searchlight: count += 1
 check(count == 21,"Eleven beacons and ten searchlights, no recreated duplicates")
 check(not world.has_node("Scenery/Beacon_Light_1"),"Former light 129 absent")
 var lamp: Node3D = world.get_node("Scenery/Beacon_Object_62")
 check(lamp.global_transform.is_equal_approx(Document.decode(dock_lamp.transform)),"Former light 94 uses relocated dock lamp placement")
 var captured := Document.capture(world)
 check(captured.entities["Scenery/Beacon_Object_62"].light_source_position == baseline.entities["Scenery/Beacon_Object_62"].light_source_position,"Source position stays immutable after moving")
 # Editor baseline merging must retain the permanent tombstones across a file roundtrip.
 var path := "res://tests/cache-light-identity-fixtures/map.json"
 check(Document.save(data,path) == OK,"Migrated map saves")
 var restored := Document.load_path(path)
 for key in baseline.entities:
  if not restored.entities.has(key): restored.entities[key] = baseline.entities[key]
 check(restored.entities["Scenery/Beacon_Light_1"].deleted,"Editor baseline merge cannot resurrect deleted source")
 game.free()
 print("Light identity: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
