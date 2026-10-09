extends SceneTree
const Game = preload("res://game.gd")
const Market = preload("res://commodity_market.gd")
var checks := 0
var failures := 0
var sounds: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func action(game: Node, name: String, payload: Dictionary, expected: String) -> void:
	sounds.clear(); game._dock_ui_action(name,payload)
	var outcomes := sounds.filter(func(role: String) -> bool: return role in ["equipment_trade","commodity_trade","repair","install","error"])
	check(outcomes == ([] if expected.is_empty() else [expected]),name + " produces exactly its transaction outcome sound: " + expected)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Game starts")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.set_physics_process(false); game.pilot.freeze = true
	game.docking.set_physics_process(false); game.docking.current = game.docking.ports[0]; game.docking.stage = game.Docking.Stage.DOCKED
	game.dock_interface_active = true; game.dock_interface.open("equipment")
	game.dock_interface.menu_sound_played.connect(func(role: String) -> void: sounds.append(role))
	var expected := {"equipment_trade":"SUBCYCLE","commodity_trade":"SELECT","repair":"SHIELD","install":"LOAD","error":"ERROR"}
	for role in expected:
		var stream: AudioStream = game.dock_interface.sound_players[role].stream
		check(stream != null and str(stream.get_meta("asset_source","")).ends_with(expected[role] + ".RAW"),"Recovered original sample loaded: " + role)
	action(game,"buy_equipment",{"item":"shield"},"error")
	game.player_progress.status.credits = 100000
	action(game,"buy_equipment",{"item":"shield"},"equipment_trade")
	action(game,"sell_equipment",{"item":"shield"},"equipment_trade")
	action(game,"sell_equipment",{"item":"shield"},"error")
	action(game,"buy_equipment",{"item":"shield"},"equipment_trade")
	action(game,"use_repair",{"item":"shield"},"error")
	game.pilot.restore_health(100,50)
	action(game,"use_repair",{"item":"shield"},"repair")
	check(game.pilot.health == 100 and not game.player_progress.hold.has("shield"),"Repair feedback follows actual consumption and restoration")
	game.player_progress.hold.hullstr = 1
	action(game,"use_repair",{"item":"hullstr"},"repair")
	action(game,"use_repair",{"item":"hullstr"},"")
	game.player_progress.hold.magnet = 1
	action(game,"equipment_slot",{"slot":3,"item":"magnet"},"install")
	action(game,"equipment_slot",{"slot":3,"item":""},"")
	game.dock_interface.open("goods")
	var city := str(int(game.docking.current.node.get_meta("city_id")))
	var offers := Market.offers(game.gameplay_catalogue,game.player_progress,city)
	var available: Array = offers.values().filter(func(offer: Dictionary) -> bool: return offer.buy_price > 0 and offer.sell_price > 0 and offer.stock > 0)
	check(not available.is_empty(),"Station has a two-way commodity trade fixture")
	if not available.is_empty():
		var id := str(available[0].id)
		action(game,"buy_commodity",{"item":id},"commodity_trade")
		action(game,"sell_commodity",{"item":id},"commodity_trade")
		action(game,"sell_commodity",{"item":id},"error")
	game.queue_free(); await process_frame
	print("Dock transaction audio: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
