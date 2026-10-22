extends "res://tests/test_scene_tree.gd"
const Shop = preload("res://equipment_shop.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-zapper-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	var config := ConfigFile.new(); config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")
func run() -> void:
	var game := preload("res://game.gd").new(); game.remember_preferences = false; game.show_start_menu = true; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game loads upgrade support")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.set_physics_process(false); game.pilot.freeze = true
	game.docking.set_physics_process(false); game.docking.stage = game.Docking.Stage.DOCKED
	var final_prices := {"Beluga":4400,"Touka":4230,"Tryton":3250,"Velcova":3800}
	for port in game.docking.ports:
		game.docking.current = port
		var city := str(port.name).get_slice(" ",0)
		for stage in [1,2,3,4]:
			game.player_progress.campaign_stage = stage
			var offer: Dictionary = game._dock_ui_model().offers.zapperup
			var expected := 3500 if stage == 3 and city == "Tryton" else int(final_prices.get(city,0)) if stage == 4 else 0
			check(offer.available == (expected > 0) and offer.price == expected,"Original upgrade stock/price: %s stage %d" % [city,stage])
	game.player_progress.campaign_stage = 1; game.testing_all_equipment = true
	game.player_progress.status.credits = 10000
	var ui = game.dock_interface; ui.open("equipment"); ui.selected_sale = "zapperup"; ui.rebuild()
	var standard_picture: Texture2D = ui.slot_buttons[0].get_child(0).texture
	check(not ui.layout.get_node("BuyShieldRepair").disabled,"Developer override unlocks the upgrade before its campaign stage")
	var price: int = game._dock_ui_model().offers.zapperup.price
	ui.layout.get_node("BuyShieldRepair").pressed.emit()
	check(game.player_progress.hold.get("zapperup",0) == 1 and game.player_progress.status.credits == 10000 - price and not game.weapons.upgraded,"Buying stores the upgrade without applying it")
	ui.selected_hold = "zapperup"; ui.rebuild(); ui.layout.get_node("UseShieldRepair").pressed.emit()
	check(game.weapons.upgraded and game.player_progress.status.zapper_upgrade == 1 and not game.player_progress.hold.has("zapperup"),"Using upgrade applies and consumes it through the dock UI")
	var upgraded_picture: Texture2D = ui.slot_buttons[0].get_child(0).texture
	check(upgraded_picture != null and upgraded_picture.get_image().get_data() != standard_picture.get_image().get_data(),"Mounted Zapper shop illustration changes immediately after applying the upgrade")
	var expected_picture: Texture2D = ui.texture("texture.ui_equipment_square_zapperup",str(game._dock_ui_model().offers.zapperup.square_bitmap))
	check(upgraded_picture.get_image().get_data() == expected_picture.get_image().get_data(),"Upgraded slot uses the recovered upgrade square picture")
	check(not Shop.upgrade_available(game.player_progress,"zapperup") and not Shop.buy(game.player_progress,game._dock_ui_model().offers.zapperup).is_empty(),"Permanent upgrade cannot be bought again")
	game.save_games.folder = "res://tests/cache-zapper-fixtures/zapper-saves"
	check(game.save_games.write(0,game._save_snapshot("Zapper upgrade")) == OK,"Upgrade saves to disk")
	game.weapons.set_upgraded(false); game.player_progress.status.zapper_upgrade = 0
	check(await game._load_saved_game(0),"Upgrade save loads")
	check(game.weapons.upgraded and game.weapons.muzzle.visible and game.weapons.effective_damage() == 5,"Loading restores permanent upgrade effects")
	game._begin_new_game()
	check(not game.weapons.upgraded and game.player_progress.status.zapper_upgrade == 0,"New Game clears the permanent zapper upgrade")
	game.free(); print("Zapper upgrade: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
