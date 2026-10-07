extends SceneTree
const Game = preload("res://game.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Game starts")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	game.pilot.freeze = true; game.pilot.active = false
	for port in game.docking.ports:
		game.docking.current = port
		var offer: Dictionary = game._dock_ui_model().repair_offer
		check(offer.available == (int(port.node.get_meta("city_id")) != 5),"Repair availability follows original city pricing at " + str(port.name))
	game.docking.current = game.docking.ports[0]; game.docking.stage = game.Docking.Stage.DOCKED
	game.dock_interface_active = true
	game.dock_interface.open("equipment")
	var buy: Button = game.dock_interface.layout.get_node("BuyShieldRepair")
	check(buy.disabled,"Buying without credits is disabled")
	game._dock_ui_action("buy_repair",{})
	check(game.player_progress.hold.is_empty() and game.player_progress.status.credits == 0,"Insufficient funds cannot buy a kit")
	var grant: Button = game.find_child("GiveTestingCredits",true,false)
	grant.pressed.emit()
	check(game.player_progress.status.credits == 100000,"System button adds 100,000 credits")
	game.dock_interface.sale_list.select(0); game.dock_interface.sale_list.item_selected.emit(0)
	check(not game.dock_interface.info_dialog.visible,"Selecting a sale item does not open Info")
	var cost: int = game._dock_ui_model().repair_offer.price
	game.dock_interface.layout.get_node("BuyShieldRepair").grab_focus()
	game.dock_interface.layout.get_node("BuyShieldRepair").pressed.emit()
	check(game.player_progress.hold.get("shield",0) == 1 and game.player_progress.status.credits == 100000 - cost,"Purchase deducts the original station price and puts repair in the hold")
	check(not game.dock_interface.layout.get_node("BuyShieldRepair").disabled,"Further repair kits can be purchased")
	check(root.gui_get_focus_owner() == game.dock_interface.layout.get_node("BuyShieldRepair"),"Buying keeps focus on Buy rather than Done")
	game.dock_interface.layout.get_node("BuyShieldRepair").pressed.emit()
	check(game.player_progress.hold.get("shield",0) == 2 and game.dock_interface.hold_list.get_item_text(game.dock_interface.hold_list.item_count - 1).ends_with("×2"),"Multiple kits stack with a quantity in the hold")
	check(game.dock_interface.hold_list.item_count == game.equipment.mounted.size() + game.weapons.mounted.size() + 1,"Hold has separate non-overlapping item rows")
	check(game.dock_interface.layout.get_node("UseShieldRepair").disabled,"Repair must be selected before clicking the sub")
	game.dock_interface.hold_list.select(game.dock_interface.hold_list.item_count - 1)
	game.dock_interface.hold_list.item_selected.emit(game.dock_interface.hold_list.item_count - 1)
	game.dock_interface._repair_info()
	check(game.dock_interface.info_dialog.visible,"Info shows the original repair description and graphic")
	game.dock_interface.info_dialog.hide()
	check(not game.dock_interface.layout.get_node("UseShieldRepair").disabled,"Selecting the hold item enables use on the sub image")
	game.dock_interface.layout.get_node("UseShieldRepair").pressed.emit()
	check(game.player_progress.hold.get("shield",0) == 2,"A full shield does not waste the repair kit")
	game.pilot.restore_health(200,50)
	game.dock_interface.rebuild()
	if DisplayServer.get_name() != "headless":
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/shield-shop-preview.png")
	game.save_games.folder = "res://tests/shield-shop-fixtures"
	var saved: Dictionary = game._save_snapshot("Repair test")
	check(game.save_games.write(0,saved) == OK,"Repair inventory saves")
	game.dock_interface.layout.get_node("UseShieldRepair").pressed.emit()
	check(game.pilot.health == 200 and game.player_progress.status.shields == 100 and game.player_progress.hold.get("shield",0) == 1,"Clicking the sub consumes one kit and restores its full upgraded shield capacity")
	check(await game._load_saved_game(0),"Saved repair inventory loads")
	for frame in range(10): await process_frame
	check(game.player_progress.hold.get("shield",0) == 2 and game.pilot.health == 50 and game.player_progress.status.credits == 100000 - cost * 2,"Loading preserves the purchased kits, credits and damage")
	game.dock_interface.open("equipment")
	game.dock_interface.hold_list.select(game.dock_interface.hold_list.item_count - 1)
	game.dock_interface.hold_list.item_selected.emit(game.dock_interface.hold_list.item_count - 1)
	var resale: int = game._dock_ui_model().repair_offer.sell_price
	game.dock_interface.layout.get_node("SellShieldRepair").pressed.emit()
	check(game.player_progress.hold.get("shield",0) == 1 and game.player_progress.status.credits == 100000 - cost * 2 + resale,"Selling one kit returns the original station resale price")
	check(preload("res://player_progress.gd").restore({}).hold.is_empty(),"Older saves have an empty hold")
	DirAccess.remove_absolute("res://tests/shield-shop-fixtures/slot-0.json")
	paused = false; game.queue_free(); await process_frame
	print("Shield repair: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
