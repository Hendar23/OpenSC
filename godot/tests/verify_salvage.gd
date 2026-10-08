extends SceneTree
const Document = preload("res://map_document.gd")
const Definitions = preload("res://object_definitions.gd")
const Population = preload("res://object_population.gd")
const Salvage = preload("res://salvage_body.gd")
class Player extends Node3D:
 var active := true
 var controls_enabled := true
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 preload("res://mod_registry.gd").initialize(false)
 var data := Document.empty()
 var metals := Definitions.metal_types()
 check(Document.valid(data) and metals.size() == 3,"Three original metal types are registered")
 for index in range(3):
  data.object_groups.append({"id":"metal"+str(index),"name":metals[index].name,"type":metals[index].id,"position":[index * 2 - 2,2,0],"count":1,"radius":0})
 var world := Node3D.new(); root.add_child(world)
 world.set_meta("bounds",AABB(Vector3(-50,-10,-50),Vector3(100,20,100))); world.set_meta("surface_height",0.0)
 var ground := StaticBody3D.new(); ground.position.y = -6
 var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(100,1,100); shape.shape = box; ground.add_child(shape); world.add_child(ground)
 var pilot := Player.new(); world.add_child(pilot); pilot.position = Vector3(0,-2,0)
 var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(0,-1,3); camera.look_at(Vector3(0,-2,-10)); camera.current = true
 var dock := Node3D.new(); dock.set_meta("city_id",1); dock.position = Vector3(20,-2,0); world.add_child(dock)
 var dock_visual := MeshInstance3D.new(); var dock_box := BoxMesh.new(); dock_box.size = Vector3(4,4,4); dock_visual.mesh = dock_box; dock.add_child(dock_visual)
 var pop := Population.new(); world.add_child(pop); pop.setup("../Original Sub Culture",data); pop.player = pilot; pop.view_camera = camera
 check(pop.dock_spawn_exclusions.size() == 1 and not pop._clear_of_docks(Vector3(20,100,0),0.5) and not pop._clear_of_docks(Vector3(27,-100,0),0.5),"Dock footprint and safety margin exclude drops regardless of altitude")
 check(pop.get_child_count() == 3,"All three manually placed original models load")
 for body in pop.get_children():
  check(body is Salvage and body.mass == metals.filter(func(definition: Dictionary) -> bool: return definition.id == body.stats.id)[0].mass,"Original mass: " + str(body.stats.id))
  check(body.get_child(1) is CollisionShape3D and body.collision_layer == 9 and body.get_meta("metal_tow_target",false),"Solid model collision and metal targeting metadata: " + str(body.stats.id))
  check(not body.has_method("pickup_item") and body.get_node_or_null("ThoriumGlow") == null,"Metal cannot be vacuumed and has no Thorium glow")
 for tick in range(100): await physics_frame
 check(pop.get_children().all(func(body: Node3D) -> bool: return body.position.y < 0 and body.position.y > -6),"Metal objects fall through the water")
 var item: RigidBody3D = pop.get_child(0); item.apply_central_impulse(Vector3(4,0,0))
 var start: Vector3 = item.position
 for tick in range(20): await physics_frame
 check(item.position.x > start.x,"Metal object can be pushed around")
 var saved: Array = JSON.parse_string(JSON.stringify(pop.snapshot()))
 check(Population.valid_snapshot(saved),"Metal saves validate after JSON conversion")
 pop.restore_snapshot(saved)
 check(pop.snapshot().size() == 3 and Document.decode(pop.snapshot()[0].pose).is_equal_approx(Document.decode(saved[0].pose)) and Document.vector(pop.snapshot()[0].velocity).is_equal_approx(Document.vector(saved[0].velocity)),"Position and motion survive restoring saved metal")
 var bad := saved.duplicate(true); bad[0].shard = 1
 check(not Population.valid_snapshot(bad),"Metal cannot masquerade as a Thorium shard in saves")
 pop.reset_population()
 check(pop.snapshot().size() == 3 and pop.get_child(0).position.y == 2,"New game restores authored placements")
 pop.restore_snapshot([]); pop.random.seed = 42
 await physics_frame; await physics_frame
 for definition in metals:
  definition.maximum_population = 1
  pop._random_drop(definition)
 check(pop.get_child_count() == 3,"Each metal has its own population budget")
 for body in pop.get_children():
  check(body.position.y > 0 and Vector2(body.position.x,body.position.z).length() <= 35 and not camera.is_position_in_frustum(body.position),"Metal drops above water near the player and outside view")
  check(pop._clear_of_docks(body.global_position,float(body.stats.size) * 0.5),"Random metal drops avoid the dock safety radius")
 for definition in metals: pop._random_drop(definition)
 check(pop.get_child_count() == 3,"Per-type caps stop further drops")
 pop.restore_snapshot([])
 var exclusions: Array[Dictionary] = pop.dock_spawn_exclusions.duplicate(true)
 pop.dock_spawn_exclusions = [{"center":Vector2.ZERO,"radius":1000.0}]
 for definition in metals: pop._random_drop(definition)
 pop._random_drop(Definitions.THORIUM)
 check(pop.get_child_count() == 0,"Blocked dock areas suppress both Thorium and metal drops rather than falling back to unsafe positions")
 pop.dock_spawn_exclusions = exclusions
 for definition in metals: pop.salvage_types[definition.id] = definition
 pop.spawn_elapsed = 59; pop._physics_process(2)
 check(pop.get_child_count() == 3,"Metal uses the same timed random-drop system as Thorium")
 pilot.controls_enabled = false; pop.spawn_elapsed = 59; pop._physics_process(2)
 check(pop.spawn_elapsed == 59,"Dock/menu sequences stop random drops")
 world.free()
 var editor := preload("res://asset_editor.gd").new(); editor.remember_preferences = false; root.add_child(editor)
 await process_frame; editor._set_mode(true)
 var map = editor.map_editor
 for tick in range(1800):
  if map.loaded: break
  await physics_frame
 check(map.loaded,"Map editor loads with metal types")
 if map.loaded:
  for definition in metals:
   map.select("object_type:"+str(definition.id))
   check(map.fields.magnet_compatible is CheckBox and map.fields.magnet_compatible.button_pressed,"Metal editor exposes enabled magnet compatibility: " + str(definition.id))
   map.fields.magnet_compatible.button_pressed = false
   check(map.fields.has("mass") and map.fields.has("spawn_chance") and map.fields.has("maximum_population") and not map.fields.has("shard1") and not map.fields.has("radiation_range"),"Metal editor exposes size, mass and spawning controls: " + str(definition.id))
   map.fields.size.value = 1.5; map.fields.mass.value = 3; map.fields.spawn_chance.value = 40; map.fields.maximum_population.value = 9
   var chosen_size: float = map.fields.size.value; var chosen_mass: float = map.fields.mass.value; map.apply_properties()
   check(is_equal_approx(map.record().size,chosen_size) and is_equal_approx(map.record().mass,chosen_mass) and map.record().spawn_chance == 40 and map.record().maximum_population == 9,"Metal properties apply")
   check(not map.record().magnet_compatible,"Editor applies disabled magnet compatibility")
  var path := "res://tests/metal-map-fixture.json"
  check(Document.save(map.document,path) == OK and Document.valid(Document.load_path(path)),"Metal types survive map export and reload")
  var restored := Document.load_path(path)
  for definition in restored.object_types:
   if definition.behavior == "salvage":
    check(not definition.magnet_compatible,"Export preserves magnet compatibility: " + str(definition.id))
    var body := Salvage.new(); body.setup(definition,Assets_for_test(definition),0,0.0,true)
    check(not body.get_meta("metal_tow_target",true),"Runtime respects saved compatibility: " + str(definition.id)); body.free()
  DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 editor.queue_free(); await process_frame
 print("Metal salvage: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
func Assets_for_test(definition: Dictionary) -> Node3D:
 return preload("res://clump_loader.gd").load_clump("../Original Sub Culture/CLUMPS/" + str(definition.model) + ".DFF")
