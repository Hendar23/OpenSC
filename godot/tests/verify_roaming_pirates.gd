extends "res://tests/test_scene_tree.gd"
const Damage = preload("res://original_damage.gd")
const Shop = preload("res://equipment_shop.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-traffic-fixtures"; storage.ensure_parent(storage.preferences_path())
	var config := ConfigFile.new(); config.set_value("game","folder",ProjectSettings.globalize_path("res://../Original Sub Culture")); config.save(storage.preferences_path())
	call_deferred("run")
func run() -> void:
	var game = preload("res://game.gd").new(); game.remember_preferences = false; game.show_start_menu = true; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game starts with roaming pirates")
	if not game.startup_complete: quit(1); return
	game.front_end.hide_menu(); paused = false
	var traffic = game.submarine_traffic
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	for agent in traffic.traders: agent.set_local_simulation(true)
	await physics_frame
	var population = traffic.roaming_population
	check(population != null and population.ships.size() == 2,"Two random pirate slots created")
	check(population.ships.all(func(agent: Node3D) -> bool: return not agent.dead),"Two pirates spawn alive")
	check(population.ships.all(func(agent: Node3D) -> bool: return agent.get_parent().get_meta("editor_model",agent.get_parent().get_meta("asset_id","")).to_upper().find("PIRATE3") == -1),"Pirate model 3 excluded")
	for agent in population.ships:
		check(traffic.water_clear(agent.global_position),"Pirate starts in navigable water")
		check(agent.global_position.distance_to(game.pilot.global_position) >= 80,"Pirate starts away from player")
		check(agent.roaming,"Random pirate roams instead of waiting at placement")
	for agent in traffic.traders: agent.set_physics_process(false)
	population.set_physics_process(false); traffic.set_physics_process(false)
	game.wildlife.set_simulating(false); game.pilot.active = false
	var pirate = population.ships[0]
	var credits: int = game.player_progress.status.credits
	var ordinary = traffic.traders.filter(func(agent: Node3D) -> bool: return not agent.has_method("configure_resources"))[0]
	Damage.weapon(pirate.body,10000,ordinary.global_position,ordinary)
	check(pirate.dead and game.player_progress.status.credits == credits,"NPC kills earn no player bounty")
	check(population.replace(pirate) and not pirate.dead,"Destroyed pirate is replaced in safe water")
	check(is_equal_approx(pirate.health.remaining,30.0),"Roaming pirate resets to full original health")
	Damage.weapon(pirate.body,2.5,game.pilot.global_position,game.pilot)
	check(not pirate.dead and is_equal_approx(pirate.health.remaining,29.25),"Single standard zapper tick applies sustain once")
	Damage.weapon(pirate.body,10000,ordinary.global_position,ordinary)
	check(pirate.dead and game.player_progress.status.credits == credits,"Player damage followed by NPC killing blow earns no bounty")
	check(population.replace(pirate),"Reset pirate after shared combat")
	Damage.weapon(pirate.body,10000,pirate.global_position)
	check(pirate.dead and game.player_progress.status.credits == credits,"Unattributed environmental kill earns no bounty")
	check(population.replace(pirate),"Reset pirate after environmental damage")
	var factory: Dictionary = {}
	for port in game.docking.ports:
		if int(port.node.get_meta("city_id")) == 6: factory = port
	pirate.get_parent().global_position = factory.node.global_position + Vector3.UP * 3
	Damage.weapon(pirate.body,10000,game.pilot.global_position,game.pilot)
	check(game.player_progress.status.credits == credits + 1000,"Player kill pays 1000 immediately")
	check(game.bounty_radio_queue.size() == 1 and game.bounty_radio_queue[0].node == factory.node,"Nearest Factory sends thanks regardless of faction")
	Damage.weapon(pirate.body,10000,game.pilot.global_position,game.pilot)
	check(game.player_progress.status.credits == credits + 1000,"Dead pirate cannot pay a second bounty")
	check(pirate.dead,"Pirate stays dead during ordinary swimming")
	population.replenish_docked(0.1)
	check(population.ships.all(func(agent: Node3D) -> bool: return not agent.dead),"Docked replenishment restores two live pirates")
	pirate.victim = null; pirate.path.clear(); pirate.replan = 0
	game.pilot.global_position = Vector3(10000,10000,10000)
	for agent in traffic.traders:
		if agent != pirate: agent.running = false
	for attempt in range(10):
		pirate._physics_process(1.0)
		if not pirate.path.is_empty(): break
	check(not pirate.path.is_empty(),"Idle pirate chooses a map-wide roaming route")
	var snapshot: Dictionary = traffic.snapshot(); var position: Vector3 = pirate.global_position
	snapshot["population/pirates/2"] = snapshot["population/pirates/0"].duplicate(true)
	check(traffic.valid_snapshot(snapshot),"Published-beta snapshot with a third pirate remains valid")
	pirate.get_parent().position += Vector3.ONE
	traffic.restore(snapshot)
	check(pirate.global_position.is_equal_approx(position),"Random pirate poses survive save restore")
	check(population.ships.size() == 2,"Loading old third-pirate data preserves new two-pirate cap")
	var map = game.cockpit_hud.map_data
	map.discovered_cities.clear()
	var marker: Dictionary = map.markers[0]
	map.discover_cities(marker.position + Vector3(100,0,0))
	check(not map.city_known(marker),"Distant dock does not reveal its name")
	map.discover_cities(marker.position + Vector3(5,-20,0))
	check(map.city_known(marker),"Dock name reveals by proximity without line of sight")
	map.discover_cities(marker.position + Vector3(100,0,0))
	check(map.city_known(marker),"Discovered city name stays known")
	game.cockpit_hud.map_zoom = 2
	check(map.npc_in_range(Vector3.ZERO,Vector3(20,0,10)) and not map.npc_in_range(Vector3.ZERO,Vector3(100,0,0)),"Full map NPC range matches local minimap extent")
	game.cockpit_hud.map_zoom = 4
	check(not map.npc_in_range(Vector3.ZERO,Vector3(20,0,0)),"NPC view range follows minimap zoom")
	var system = game.developer_tabs.get_node("System")
	var money = system.get_node("GiveTestingCredits")
	var unlock = system.get_node("UnlockTestingEquipment")
	var presets = system.get_node("TimeOfDayPresets")
	check(unlock.get_index() == money.get_index() + 1 and presets.get_index() == unlock.get_index() + 1,"Equipment override and time buttons sit beneath money")
	var stage: int = game.player_progress.campaign_stage
	unlock.button_pressed = true
	check(game.testing_all_equipment,"Developer button enables equipment testing")
	for city_id in range(1,7):
		var offers := Shop.offers(game.gameplay_catalogue,str(city_id),stage,game.testing_all_equipment)
		check(offers.values().all(func(offer: Dictionary) -> bool: return offer.available and offer.price > 0),"All implemented equipment sold at station " + str(city_id))
	unlock.button_pressed = false
	check(not game.testing_all_equipment and game.player_progress.campaign_stage == stage,"Testing override switches off without advancing campaign")
	# WEAPONS1.CSV baseline: shield, hull, radiation, lights, suction, zapper, magnet, grapple.
	var opening_prices := {
		"1":[2000,13600,0,620,480,0,0,1100],
		"2":[1900,15000,0,600,540,0,2500,0],
		"3":[2100,13400,0,650,500,0,0,1000],
		"4":[1800,15100,1000,590,0,0,2300,0],
		"5":[0,0,0,0,0,0,0,0],
		"6":[1600,14000,700,0,580,0,0,1400]}
	check(stage == 1,"New game uses campaign stage one")
	for city_id in opening_prices:
		for index in range(Shop.ITEMS.size()):
			var id: String = Shop.ITEMS[index]
			var offer := Shop.offer(game.gameplay_catalogue,city_id,1,id,false)
			var expected: int = opening_prices[city_id][index] if index < opening_prices[city_id].size() else 0
			check(offer.available == (expected > 0) and offer.price == expected,"Original new-game stock and price: city %s / %s" % [city_id,id])
	for button in presets.get_children():
		if button.text == "Night": button.pressed.emit()
	check(game.day_night.hour == 0,"Moved time button still changes time")
	game.docking.current = factory
	var saved: Dictionary = game._save_snapshot("Pirate bounty test")
	check(game.save_games.valid(saved) and saved.discovered_cities.has(str(marker.id)) and saved.progress.status.credits == credits + 1000,"Save includes discovered city names and immediate bounty credits")
	check(game.save_games.write(6,saved) == OK,"Bounty and discovery save writes")
	check(await game._load_saved_game(6),"Saved pirate game loads")
	check(game.cockpit_hud.map_data.city_known(marker) and game.player_progress.status.credits == credits + 1000,"Discovery and bounty survive complete game restore")
	check(game.submarine_traffic.roaming_population.ships.size() == 2,"Load retains two roaming slots")
	game.bounty_radio_queue.clear()
	game.bounty_radio_queue.append({"text":"old paid bounty","ttl":12.0})
	game.bounty_radio_queue.append({"text":"mission dialogue","mission":"intro"})
	game.bounty_remaining = 7.0
	game._age_radio(13.0)
	check(game.bounty_remaining == 0,"Hidden radio display still times out while docking")
	check(game.bounty_radio_queue.size() == 1 and game.bounty_radio_queue[0].has("mission"),"Stale bounty announcements expire without losing mission dialogue")
	map.reset_exploration(); check(map.discovered_cities.is_empty(),"New game clears city discovery")
	for script in ["res://pirate_population.gd","res://tests/verify_roaming_pirates.gd"]:
		if not FileAccess.file_exists(script + ".uid"):
			var file := FileAccess.open(script + ".uid",FileAccess.WRITE); file.store_string(ResourceUID.id_to_text(ResourceUID.create_id()) + "\n")
	game.queue_free(); await process_frame
	print("Roaming pirates and developer controls: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
