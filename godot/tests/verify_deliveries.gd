extends SceneTree
const Game = preload("res://game.gd")
const Definitions = preload("res://object_definitions.gd")
const Progress = preload("res://player_progress.gd")
var checks := 0
var failures := 0
func check(ok: bool,message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var types := {"object_types":Definitions.metal_types(),"object_groups":[]}; Definitions.ensure(types)
 for type in types.object_types:
  if type.id in ["coin","bottletop","milktop","thorium","cigarette_end"]:
   check(type.delivery_quantity == (4 if type.id == "thorium" else 1 if type.id == "cigarette_end" else 2),"Imported object settings receive delivery quantity for " + type.id)
   check(type.delivery_commodity == ("ore" if type.id == "thorium" else "tobacco" if type.id == "cigarette_end" else "copper" if type.id == "coin" else "metal"),"Object delivery commodity for " + type.id)
 check(Definitions.valid(types),"Delivery settings remain valid map data")
 types.object_types[0].delivery_quantity = 7; types.object_types[0].delivery_commodity = "copper"; Definitions.ensure(types)
 check(types.object_types[0].delivery_quantity == 7 and types.object_types[0].delivery_commodity == "copper","Editor choices are preserved rather than replaced by defaults")
 var progress := Progress.restore({"pending_deliveries":{"1":{"copper":3},"2":{"metal":6}}})
 progress = Progress.restore(JSON.parse_string(JSON.stringify(progress)))
 Progress.collect_deliveries(progress,1)
 check(progress.cargo.get("copper",0) == 3 and not progress.cargo.has("metal") and progress.pending_deliveries.has("2"),"Saved deliveries are collected only at the matching city")
 Progress.collect_deliveries(progress,1)
 check(progress.cargo.copper == 3,"Repeated docking cannot duplicate collected goods")
 var game := Game.new(); game.remember_preferences = false; root.add_child(game)
 for frame in range(2400):
  if game.startup_complete: break
  await physics_frame
 check(game.startup_complete,"Game loads")
 if not game.startup_complete: quit(1); return
 var accepted: Array = []; var collected: Array = []; var sessions: Array = []; var docks: Array = []
 game.events.delivery_accepted.connect(func(id: String, city: int, commodity: String, quantity: int) -> void: accepted.append({"id":id,"city":city,"commodity":commodity,"quantity":quantity}))
 game.events.deliveries_collected.connect(func(city: int, goods: Dictionary) -> void: collected.append({"city":city,"goods":goods}))
 game.events.session_started.connect(func(restored: bool) -> void: sessions.append(restored))
 game.events.city_docked.connect(func(city: int) -> void: docks.append(city))
 game._begin_new_game(); game.pilot.controls_enabled = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
 game.equipment.set_installed(["deep_sea_lights","magnet"])
 var magnet: Node3D = game.equipment.magnet; magnet.set_physics_process(false); magnet.set_enabled(true)
 var coin := preload("res://salvage_body.gd").new(); game.object_population.add_child(coin)
 var definition: Dictionary = Definitions.metal_types()[2]
 coin.setup(definition,preload("res://object_population.gd").appearance(definition,game.game_folder),0,0.0,true)
 coin.global_position = magnet.head.global_position + Vector3.DOWN * 0.1; magnet._attach(coin)
 var city := int(game.docking.ports[0].node.get_meta("city_id"))
 var pad := preload("res://drop_off_point.gd").new(); game.world_root.add_child(pad); pad.configure(2.0,city); pad.global_position = coin.global_position
 check(pad.contains_point(pad.global_position + Vector3.UP * 3.9),"Drop-off vertical reach is doubled")
 check(not pad.contains_point(pad.global_position + Vector3.UP * 4.1) and not pad.contains_point(pad.global_position + Vector3.RIGHT * 2.1),"Vertical expansion preserves the horizontal acceptance range")
 magnet.drop_points.assign([pad]); magnet._physics_process(0.016)
 check(game._delivery_prompt_active(),"Carrying salvage into a city's zone opens its confirmation request")
 game._process(0)
 check(game.docking_prompt.visible and game.docking_prompt.text.contains("automatically retrieved"),"Confirmation appears in the game HUD")
 var no := InputEventKey.new(); no.keycode = KEY_N; no.pressed = true; game._input(no)
 check(magnet.target == coin and game.player_progress.pending_deliveries.is_empty(),"N leaves the object attached and creates no goods")
 check(accepted.is_empty() and collected.is_empty(),"Declined deliveries do not emit completion events")
 magnet._physics_process(0.016)
 check(not game._delivery_prompt_active(),"Declined prompt stays dismissed inside the zone")
 pad.global_position += Vector3(10,0,0); magnet._physics_process(0.016)
 pad.global_position = coin.global_position; magnet._physics_process(0.016)
 check(game._delivery_prompt_active(),"Leaving and re-entering the zone allows another delivery request")
 var yes := InputEventJoypadButton.new(); yes.button_index = JOY_BUTTON_A; yes.pressed = true; game._input(yes)
 check(magnet.target == null and magnet.retracting and not coin.is_queued_for_deletion() and coin.get_meta("delivery_city",-1) == city,"Controller confirmation releases the physical object and retracts the magnet normally")
 check(game.player_progress.pending_deliveries[str(city)].copper == 2 and game.player_progress.cargo.is_empty(),"Delivery records two Copper at the city without immediately adding hold cargo")
 check(accepted.size() == 1 and accepted[0].id == coin.get_meta("entity_id") and accepted[0].city == city and accepted[0].commodity == "copper" and accepted[0].quantity == 2,"Acceptance event identifies the exact object and delivery terms")
 check(game.object_population.snapshot().any(func(entry: Dictionary) -> bool: return entry.get("delivery_city",-1) == city),"Accepted salvage remains in the saved world until docking at its city")
 magnet.enabled = true; magnet._attach(coin)
 check(magnet.target == null,"Accepted salvage cannot be delivered twice")
 magnet.enabled = false
 game.save_games.folder = "res://tests/delivery-save-fixture"
 game.docking.current = game.docking.ports[1]; game.docking.stage = game.Docking.Stage.DOCKED
 check(game.save_games.write(0,game._save_snapshot("Pending delivery")) == OK,"Pending city deliveries are written to a valid save file")
 game.player_progress = Progress.restore()
 check(await game._load_saved_game(0),"Save containing pending deliveries loads normally")
 check(sessions == [false,true] and docks.is_empty() and accepted.size() == 1 and collected.is_empty(),"Loading publishes restored-session state without replaying docking or delivery events")
 check(game.player_progress.pending_deliveries[str(city)].copper == 2 and game.player_progress.cargo.is_empty(),"Loading at another city preserves the delivery without collecting it")
 check(game.object_population.snapshot().any(func(entry: Dictionary) -> bool: return entry.get("delivery_city",-1) == city),"Loading at another city also preserves the physical delivered object")
 game.docking.current = game.docking.ports[0]; game.docking.stage = game.Docking.Stage.DOCKED; game.dock_interface_active = false; game._process(0)
 check(game.player_progress.cargo.get("copper",0) == 2 and not game.player_progress.pending_deliveries.has(str(city)),"Docking transfers the saved delivery to the sub's trade inventory")
 check(not game.object_population.snapshot().any(func(entry: Dictionary) -> bool: return entry.get("delivery_city",-1) == city),"Docking at the receiving city removes its accepted objects")
 check(collected.size() == 1 and collected[0].city == city and collected[0].goods == {"copper":2},"Collection is a separate event from acceptance")
 game._collect_city_deliveries(city)
 check(collected.size() == 1,"Repeated collection does not replay a completed delivery")
 game.docking.docked.emit()
 check(docks == [city],"Actual docking publishes its city ID")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_games.path(0)))
 DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_games.folder))
 game.queue_free(); await process_frame
 print("Deliveries: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
