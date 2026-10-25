extends RefCounted
## Dock menu data, transactions, autosave, and delivered cargo.

var game: Node3D

func _init(context: Node3D) -> void:
	game = context

const Docking = preload("res://docking_controller.gd")
const PlayerProgress = preload("res://player_progress.gd")

func _dock_ui_model() -> Dictionary:
	var port: Dictionary = game.docking.current if game.docking != null else {}
	var city_id := str(int(port.node.get_meta("city_id"))) if port.get("node") != null else ""
	var city: Dictionary = game.gameplay_catalogue.get("tables",{}).get("city_info",{}).get("records",{}).get(city_id,{})
	var standing: String = game.player_progress.standing.get(str(port.get("race",1)),"neutral")
	var description_id := "%s%d.%s" % [city.get("description_key",""),game.player_progress.campaign_stage,standing]
	var description: String = game.gameplay_catalogue.get("tables",{}).get("city_descriptions",{}).get("records",{}).get(description_id,{}).get("text","")
	return {"autosave":game.save_games.automatic_slot() if game.dock_interface != null and game.dock_interface.page in ["save","load"] else {},"missions":game.mission_runtime.board(int(city_id) if not city_id.is_empty() else 0),"can_save":game.mission_runtime.can_save(),"city":port.get("name","Dock"),"city_id":city_id,"title_bitmap":city.get("title_bitmap",""),"welcome":description,"standing":{"bad":"Hostile","neutral":"Neutral","good":"Friendly"}.get(standing,"Neutral"),"mission":game.player_progress.mission,"status":game.player_progress.status.duplicate(),"race":port.get("race",1),"repair_offer":preload("res://equipment_shop.gd").shield_repair(game.gameplay_catalogue,city_id,game.player_progress.campaign_stage,game.testing_all_equipment),"offers":preload("res://equipment_shop.gd").offers(game.gameplay_catalogue,city_id,game.player_progress.campaign_stage,game.testing_all_equipment),"installed":preload("res://equipment_shop.gd").installed(game.equipment,game.weapons) if game.equipment != null and game.weapons != null else {},"hold":game.player_progress.hold.duplicate(),"commodity_offers":preload("res://commodity_market.gd").offers(game.gameplay_catalogue,game.player_progress,city_id),"cargo":game.player_progress.cargo.duplicate(),"mail":preload("res://mailbox.gd").messages(game.gameplay_catalogue,game.player_progress,int(city_id) if not city_id.is_empty() else 0),"slots":game.save_games.slots() if game.dock_interface != null and game.dock_interface.page in ["save","load"] else []}

func _dock_ui_action(action: String, payload: Dictionary) -> void:
	match action:
		"accept_mission":
			if game.docking.stage != Docking.Stage.DOCKED: return
			var result: String = game.mission_runtime.accept(int(game.docking.current.node.get_meta("city_id")),str(payload.get("id","")))
			if result.is_empty(): game.dock_interface.open("home")
			else: game.dock_interface.report(result)
		"read_mail":
			if game.docking.stage != Docking.Stage.DOCKED: return
			preload("res://mailbox.gd").mark_read(game.player_progress,str(payload.get("id","")))
		"buy_commodity","sell_commodity":
			if game.docking.stage != Docking.Stage.DOCKED: return
			var city_id := str(int(game.docking.current.node.get_meta("city_id")))
			var id := str(payload.get("item",""))
			var credits_before := int(game.player_progress.status.credits)
			var result := preload("res://commodity_market.gd").trade(game.gameplay_catalogue,game.player_progress,city_id,id,action == "buy_commodity")
			game.dock_interface.transaction_feedback(result,"commodity_trade")
			if result.is_empty(): game.events.commodity_traded.emit(int(city_id),id,1 if action == "buy_commodity" else -1,int(game.player_progress.status.credits) - credits_before)
		"equipment_slot":
			if game.docking.stage != Docking.Stage.DOCKED: return
			var incoming := str(payload.get("item",""))
			var installing: bool = preload("res://equipment_shop.gd").SLOTS.get(incoming,0) == int(payload.slot) and int(game.player_progress.hold.get(incoming,0)) > 0
			game.dock_interface.transaction_feedback(preload("res://equipment_shop.gd").swap(game.player_progress,game.equipment,game.weapons,int(payload.slot),incoming),"install",installing)
		"buy_equipment","sell_equipment":
			if game.docking.stage != Docking.Stage.DOCKED: return
			var id := str(payload.get("item",""))
			var offer: Dictionary = game._dock_ui_model().offers.get(id,{})
			if offer.is_empty(): game.dock_interface.transaction_feedback("Item unavailable.","equipment_trade"); return
			if action == "buy_equipment":
				if id != "shield" and preload("res://equipment_shop.gd").owned(game.player_progress,game.equipment,game.weapons,id) + int(offer.get("quantity",1)) > int(offer.maximum):
					game.dock_interface.transaction_feedback("Already owned.","equipment_trade"); return
				game.dock_interface.transaction_feedback(preload("res://equipment_shop.gd").buy(game.player_progress,offer),"equipment_trade")
			else: game.dock_interface.transaction_feedback(preload("res://equipment_shop.gd").sell(game.player_progress,offer),"equipment_trade")
		"use_repair":
			if game.docking.stage != Docking.Stage.DOCKED: return
			var id := str(payload.get("item","shield"))
			var previous_count := int(game.player_progress.hold.get(id,0))
			var result := preload("res://equipment_shop.gd").use_item(game.player_progress,game.pilot,id)
			game.weapons.set_upgraded(game.player_progress.status.zapper_upgrade == 1)
			game.dock_interface.transaction_feedback(result,"repair",int(game.player_progress.hold.get(id,0)) < previous_count)
			if int(game.player_progress.hold.get(id,0)) < previous_count: game.events.item_used.emit(id)
		"launch":
			if game.docking.stage == Docking.Stage.DOCKED:
				game.get_tree().paused = false
				game.dock_interface.dismiss(); game.dock_interface_active = false; game._request_docking()
		"close": game._show_main_menu()
		"save_slot":
			if int(payload.get("slot",-1)) < 0: return
			if game.docking.stage != Docking.Stage.DOCKED: game.dock_interface.report("Save games are available while docked."); return
			var result: Error = game.save_games.write(int(payload.slot),game._save_snapshot(str(payload.name)))
			game.dock_interface.report("" if result == OK else game.save_games.error)
		"load_slot": game._load_saved_game(int(payload.slot))

func _autosave_docked() -> void:
	if game.docking.stage != Docking.Stage.DOCKED or not game.mission_runtime.can_save(): return
	if game.save_games.write(-1,game._save_snapshot("Auto Save")) != OK:
		game.dock_interface.report("Autosave failed: " + game.save_games.error)

func _delivery_terms(body: RigidBody3D) -> Dictionary:
	var stats: Dictionary = body.get("stats") if body.get("stats") is Dictionary else {}
	var defaults := preload("res://object_definitions.gd").delivery_defaults(stats)
	if int(body.get("shard")) != 0: return {"commodity":"","quantity":0}
	return {"commodity":str(stats.get("delivery_commodity",defaults.commodity)).to_lower(),"quantity":int(stats.get("delivery_quantity",defaults.quantity))}

func _answer_delivery(accepted: bool) -> void:
	if not game._delivery_prompt_active(): return
	var magnet: Node3D = game.equipment.towing_tool()
	if not accepted: magnet.decline_delivery(); return
	var body: RigidBody3D = magnet.target
	if game.mission_runtime.side_jobs.delivery(body,int(magnet.delivery_point.city_id)): return
	if body == game.mission_runtime.side_jobs.target and game.mission_runtime.side_jobs.id == "stranded":
		game.mission_runtime.side_jobs.radio("x27"); magnet.decline_delivery(); return
	var terms: Dictionary = game._delivery_terms(body)
	var city := str(int(magnet.delivery_point.city_id))
	if not game.player_progress.pending_deliveries.has(city): game.player_progress.pending_deliveries[city] = {}
	var goods: Dictionary = game.player_progress.pending_deliveries[city]
	goods[terms.commodity] = int(goods.get(terms.commodity,0)) + terms.quantity
	magnet.set_enabled(false)
	body.set_meta("delivery_city",int(city))
	body.set_meta("metal_tow_target",false)
	body.set_meta("grapple_tow_target",false)
	game.events.delivery_accepted.emit(preload("res://entity_identity.gd").of(body),int(city),terms.commodity,terms.quantity)

func _collect_city_deliveries(city_id: int) -> void:
	var goods: Dictionary = game.player_progress.pending_deliveries.get(str(city_id),{}).duplicate(true)
	game.object_population.collect_delivered_objects(city_id)
	PlayerProgress.collect_deliveries(game.player_progress,city_id)
	if not game.loading_save and not goods.is_empty(): game.events.deliveries_collected.emit(city_id,goods)
