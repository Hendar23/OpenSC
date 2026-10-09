extends SceneTree
const Game = preload("res://game.gd")
const Market = preload("res://commodity_market.gd")
var checks := 0
var failures := 0
var sounds: Array[String] = []
var transactions: Array = []
var uses: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func action(game: Node, name: String, payload: Dictionary, expected: String) -> void:
	transactions.clear(); uses.clear()
	var credits_before := int(game.player_progress.status.credits)
	sounds.clear(); game._dock_ui_action(name,payload)
	var outcomes := sounds.filter(func(role: String) -> bool: return role in ["equipment_trade","commodity_trade","repair","install","error"])
	check(outcomes == ([] if expected.is_empty() else [expected]),name + " produces exactly its transaction outcome sound: " + expected)
	if name in ["buy_commodity","sell_commodity"]:
		check(transactions.size() == (1 if expected == "commodity_trade" else 0),"Only completed commodity transactions emit gameplay events")
		if not transactions.is_empty():
			check(transactions[0].quantity == (1 if name == "buy_commodity" else -1) and transactions[0].credits == int(game.player_progress.status.credits) - credits_before,"Trade event records actual quantity and credit delta")
	if name == "use_repair": check(uses == ([str(payload.item)] if expected == "repair" else []),"Only consumed items emit item-used events")
func _initialize() -> void: call_deferred("run")
func click(game: Node, button_name: String, expected: String, controller: bool = false) -> void:
	var ui: Node = game.dock_interface
	var button: Button = ui.layout.get_node(button_name)
	button.grab_focus(); sounds.clear()
	if controller:
		var accept := InputEventJoypadButton.new(); accept.button_index = JOY_BUTTON_A; accept.pressed = true
		ui._input(accept)
		check(button.held and sounds.is_empty(),"Controller transaction press holds artwork without a second sound")
		accept.pressed = false; ui._input(accept)
	else:
		button.button_down.emit()
		check(button.held and sounds.is_empty(),"Mouse transaction press holds artwork without a second sound")
		button.button_up.emit(); button.pressed.emit()
	check(sounds == [expected],button_name + " click plays only its outcome sound")
func run() -> void:
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Game starts")
	if not game.startup_complete: quit(1); return
	game.events.commodity_traded.connect(func(city: int, item: String, quantity: int, credits: int) -> void: transactions.append({"city":city,"item":item,"quantity":quantity,"credits":credits}))
	game.events.item_used.connect(func(id: String) -> void: uses.append(id))
	var sessions: Array[bool] = []
	game.events.session_started.connect(func(restored: bool) -> void: sessions.append(restored))
	game._begin_new_game(); game.pilot.set_physics_process(false); game.pilot.freeze = true
	check(sessions == [false],"New game emits its session event after initialization")
	var activations: Array = []
	game.events.equipment_activated.connect(func(id: String, active: bool) -> void: activations.append({"id":id,"active":active}))
	game.equipment.toggle_selected()
	check(activations.size() == 1 and activations[0].active,"Player equipment activation emits a gameplay event")
	game.equipment.apply_settings()
	check(activations.size() == 1,"Reapplying equipment settings does not replay activation")
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
	game.dock_interface.selected_sale = "shield"; game.dock_interface.report("")
	click(game,"BuyShieldRepair","equipment_trade")
	game.dock_interface.selected_hold = "shield"; game.dock_interface.report("")
	click(game,"SellShieldRepair","equipment_trade",true)
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
		game.dock_interface.selected_commodity = id; game.dock_interface.report("")
		click(game,"BuyCommodity","commodity_trade")
		click(game,"SellCommodity","commodity_trade",true)
		# Force the error path through an enabled button too, as stale quotes can
		# become unaffordable between pointer-down and transaction completion.
		game.player_progress.status.credits = 0
		click(game,"BuyCommodity","error")
	game.queue_free(); await process_frame
	print("Dock transaction audio: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
