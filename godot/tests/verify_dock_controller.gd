extends SceneTree
const Game = preload("res://game.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func press(ui: Node, button: int) -> void:
	var event := InputEventJoypadButton.new(); event.button_index = button; event.pressed = true; ui._input(event)
	event.pressed = false; ui._input(event)
func run() -> void:
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete, "Game starts")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	game.docking.current = game.docking.ports[0]; game.docking.stage = game.Docking.Stage.DOCKED
	game.player_progress.status.credits = 100000
	game._process(0)
	var ui: Node = game.dock_interface
	ui.open("equipment")
	check(root.gui_get_focus_owner() == ui.layout.get_node("home"), "Equipment opens with Done focused")
	ui.layout.get_node("home").grab_focus(); press(ui, JOY_BUTTON_DPAD_RIGHT)
	check(root.gui_get_focus_owner() == ui.layout.get_node("goods"), "Done navigates directly right to Goods")
	press(ui, JOY_BUTTON_DPAD_LEFT)
	check(root.gui_get_focus_owner() == ui.layout.get_node("home"), "Goods navigates directly left to Done")
	ui.sale_list.grab_focus()
	for index in ui.sale_list.item_count:
		if ui.sale_list.get_item_metadata(index) == "shield": ui.sale_list.select(index); break
	press(ui, JOY_BUTTON_A)
	check(ui.selected_sale == "shield" and root.gui_get_focus_owner() == ui.layout.get_node("SaleInfo"), "Confirm selects equipment and leaves the list for its actions")
	press(ui, JOY_BUTTON_DPAD_UP)
	var confirmed_row: int = ui.sale_list.get_selected_items()[0]
	press(ui, JOY_BUTTON_DPAD_DOWN)
	check(ui.sale_list.get_selected_items()[0] != confirmed_row and ui.selected_sale == "shield", "White navigation cursor moves without changing the confirmed equipment")
	check(ui.sale_list.get_item_icon(confirmed_row) == ui.selection_dot and ui.sale_list.get_item_icon(ui.sale_list.get_selected_items()[0]) == ui.empty_dot, "Yellow dot stays on confirmed equipment while browsing")
	check(ui.sale_list.get_theme_color("font_selected_color") == Color.WHITE, "Focused navigation row is highlighted white")
	ui.layout.get_node("SaleInfo").grab_focus()
	check(ui.sale_list.get_theme_color("font_selected_color") == ui.text_colour, "Leaving the list removes its white navigation highlight")
	press(ui, JOY_BUTTON_DPAD_RIGHT)
	check(root.gui_get_focus_owner() == ui.layout.get_node("BuyShieldRepair"), "Selected equipment can navigate to Buy")
	var held_before := int(game.player_progress.hold.get("shield",0))
	press(ui, JOY_BUTTON_A)
	check(int(game.player_progress.hold.get("shield",0)) == held_before + 1, "Controller buys the selected equipment")
	ui.hold_list.grab_focus()
	for index in ui.hold_list.item_count:
		if ui.hold_list.get_item_metadata(index) == "shield": ui.hold_list.select(index); break
	press(ui, JOY_BUTTON_A); press(ui, JOY_BUTTON_DPAD_RIGHT)
	check(ui.selected_hold == "shield" and root.gui_get_focus_owner() == ui.layout.get_node("SellShieldRepair"), "Hold selection remains selected while navigating to Sell")
	press(ui, JOY_BUTTON_A)
	check(int(game.player_progress.hold.get("shield",0)) == held_before, "Controller sells the selected equipment")
	ui.open("goods")
	check(root.gui_get_focus_owner() == ui.layout.get_node("equipment"), "Goods opens with Done focused")
	ui.sale_list.grab_focus()
	var offers: Dictionary = game._dock_ui_model().commodity_offers
	var commodity := ""
	for index in ui.sale_list.item_count:
		var id: String = ui.sale_list.get_item_metadata(index)
		if int(offers[id].buy_price) > 0 and int(offers[id].sell_price) > 0 and int(offers[id].stock) > 0:
			commodity = id; ui.sale_list.select(index); break
	check(not commodity.is_empty(), "City has a commodity available for a round-trip transaction")
	press(ui, JOY_BUTTON_A)
	check(ui.selected_commodity == commodity and root.gui_get_focus_owner() == ui.layout.get_node("CommodityInfo"), "Confirm selects a commodity and moves to Info")
	press(ui, JOY_BUTTON_DPAD_UP)
	confirmed_row = ui.sale_list.get_selected_items()[0]
	press(ui, JOY_BUTTON_DPAD_DOWN if confirmed_row + 1 < ui.sale_list.item_count else JOY_BUTTON_DPAD_UP)
	check(ui.selected_commodity == commodity and ui.sale_list.get_selected_items()[0] != confirmed_row, "Commodity browsing does not replace the confirmed trade target")
	check(ui.sale_list.get_item_icon(confirmed_row) == ui.commodity_dot and ui.sale_list.get_item_icon(ui.sale_list.get_selected_items()[0]) == ui.commodity_empty_dot, "Commodity yellow dot and white cursor are independent")
	ui.layout.get_node("CommodityInfo").grab_focus()
	press(ui, JOY_BUTTON_A)
	check(ui.info_dialog.visible, "Controller opens selected commodity information")
	press(ui, JOY_BUTTON_A)
	check(not ui.info_dialog.visible and ui.selected_commodity == commodity, "Closing Info preserves commodity selection")
	press(ui, JOY_BUTTON_DPAD_RIGHT)
	var cargo_before := int(game.player_progress.cargo.get(commodity,0))
	press(ui, JOY_BUTTON_A)
	check(int(game.player_progress.cargo.get(commodity,0)) == cargo_before + 1, "Controller buys one selected commodity")
	press(ui, JOY_BUTTON_DPAD_RIGHT); press(ui, JOY_BUTTON_A)
	check(int(game.player_progress.cargo.get(commodity,0)) == cargo_before, "Controller sells one selected commodity")
	game.queue_free(); await process_frame
	print("Dock controller: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
