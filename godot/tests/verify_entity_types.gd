extends SceneTree
const Document = preload("res://map_document.gd")
const Types = Document.EntityTypes
const Editor = preload("res://map_editor.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
 checks += 1
 if not value: failures += 1; push_error(message)
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var map := Document.empty()
 for index in range(3):
  map.entities["Added/turret%d" % index] = {"name":"Turret", "kind":"model","model":"TURRET","transform":Document.encode(Transform3D(Basis.IDENTITY,Vector3(index,0,0))),"turret_health":8.0 if index < 2 else 12.0,"turret_armed":index == 1,"turret_faction":index}
 map.entities["Added/car"] = {"name":"Car","kind":"model","model":"TRADCAR","transform":Document.encode(Transform3D.IDENTITY),"npc_radius":5.0}
 map.entities["Added/smoke"] = {"name":"Smoke","kind":"smoke","model":"","transform":Document.encode(Transform3D.IDENTITY),"emission_rate":7.0}
 map.entities["Added/turret1"].turret_health = 8
 check(Document.valid(map),"Legacy definitions validate")
 Types.migrate(map)
 check(Document.valid(map),"Migrated map validates")
 check(map.entity_types.size() == 3 and map.npc_types.size() == 1,"Different legacy tuning preserved as variants")
 check(map.entities["Added/turret0"].entity_type == map.entities["Added/turret1"].entity_type,"Local faction and hostility do not split shared types")
 check(not map.entities["Added/turret0"].has("turret_health"),"Instances no longer shadow tuning")
 var before := map.duplicate(true); Types.migrate(map)
 check(map == before,"Migration is idempotent")
 var type := Types.find_type(map,"entity_type",map.entities["Added/turret0"].entity_type)
 type.turret_health = 20.0
 for index in range(2): check(Types.effective(map,map.entities["Added/turret%d" % index]).turret_health == 20.0,"Type edit reaches linked placement")
 check(Types.effective(map,map.entities["Added/turret2"]).turret_health == 12.0,"Variant stays independent")
 check(map.entities["Added/turret1"].turret_armed and map.entities["Added/turret1"].turret_faction == 1,"Instance-specific settings preserved")
 var npc: Dictionary = map.npc_types[0]; npc.model = "TECHTRUK"; npc.npc_speed = 0.7
 var effective := Types.effective(map,map.entities["Added/car"])
 check(effective.model == "TECHTRUK" and effective.npc_speed == 0.7 and effective.npc_radius == 5.0,"Shared vehicle model and tuning resolve with local operating area")
 var invalid := map.duplicate(true); invalid.entities["Added/car"].npc_type = "missing"
 check(not Document.valid(invalid),"Unknown type rejected")
 invalid = map.duplicate(true); invalid.entity_types[0].turret_health = -1
 check(not Document.valid(invalid),"Invalid shared health rejected")
 invalid = map.duplicate(true); invalid.entities["Added/car"].npc_speed = 1.2
 check(not Document.valid(invalid),"Silent instance tuning overrides rejected")
 invalid = map.duplicate(true); invalid.npc_types[0].npc_wait_min = 10; invalid.npc_types[0].npc_wait_max = 1
 check(not Document.valid(invalid),"Invalid shared wait range rejected")
 var file := "res://tests/cache-traffic-fixtures/entity-types.json"
 check(Document.save(map,file) == OK,"Shared types save")
 var loaded := Document.load_path(file)
 check(loaded.entity_types.size() == map.entity_types.size() and loaded.npc_types.size() == map.npc_types.size() and loaded.entities["Added/turret0"].entity_type == type.id and Types.effective(loaded,loaded.entities["Added/turret0"]).turret_health == 20.0 and Types.effective(loaded,loaded.entities["Added/car"]).npc_speed == 0.7 and loaded.entities["Added/car"].npc_radius == 5.0,"Shared references round trip")
 var tombstone := Document.empty()
 tombstone.entities["Added/deleted"] = {"name":"Deleted turret","kind":"model","model":"TURRET","transform":Document.encode(Transform3D.IDENTITY),"deleted":true}
 Types.migrate(tombstone)
 check(tombstone.entity_types.is_empty(),"Deleted placements do not recreate removed templates")
 var saved := Document.load_path(Document.DEFAULT_PATH)
 check(not saved.is_empty() and Document.valid(saved),"Current map migrates successfully")
 for model in Document.Pirate.PIRATE_MODELS:
  check(saved.npc_types.any(func(type: Dictionary) -> bool: return type.family == "pirate" and type.model == model),"Default map lists pirate template " + model)
 var trader_map := Document.empty()
 trader_map.entities["Added/shuttle"] = {"name":"Trader","kind":"model","model":"TRADSHUT","transform":Document.encode(Transform3D.IDENTITY),"npc_faction":1}
 Types.migrate(trader_map)
 check(trader_map.npc_types.size() == 1 and trader_map.npc_types[0].family == "trader","Civilian submarines migrate into NPC types")
 trader_map.npc_types[0].npc_speed = 3.0
 check(Document.valid(trader_map) and Types.effective(trader_map,trader_map.entities["Added/shuttle"]).npc_speed == 3.0,"Trader tuning is shared through the NPC template")
 var panel := Editor.new(); root.add_child(panel); panel.document = trader_map
 panel.shared_type_fields(trader_map.npc_types[0])
 check(panel.fields.has("npc_health") and panel.fields.has("npc_speed") and panel.fields.has("npc_wait_min"),"Trader editor exposes health, cruising and internal berth time")
 panel.free()
 var pirate_map := Document.empty()
 pirate_map.entities["Added/pirate"] = {"name":"Pirate","kind":"model","model":"PIRATE","transform":Document.encode(Transform3D.IDENTITY)}
 Types.migrate(pirate_map)
 check(pirate_map.npc_types.size() == 1 and pirate_map.npc_types[0].family == "pirate","Pirates use shared NPC templates")
 check(Document.valid(pirate_map),"Pirate template and placement validate")
 pirate_map.npc_types[0].npc_health = 40.0
 check(Types.effective(pirate_map,pirate_map.entities["Added/pirate"]).npc_health == 40.0,"Pirate instance inherits shared health")
 panel = Editor.new(); root.add_child(panel); panel.document = pirate_map
 panel.shared_type_fields(pirate_map.npc_types[0])
 check(panel.fields.has("npc_attack_range") and panel.fields.has("npc_detection") and panel.fields.has("npc_fire_interval"),"Pirate combat settings exposed in editor")
 panel.free()
 invalid = pirate_map.duplicate(true); invalid.npc_types[0].npc_attack_range = -1
 check(not Document.valid(invalid),"Invalid pirate combat settings rejected")
 print("Entity types: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
