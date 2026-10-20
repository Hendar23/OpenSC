extends "res://tests/test_scene_tree.gd"
const Shop = preload("res://equipment_shop.gd")
const Progress = preload("res://player_progress.gd")
const Damage = preload("res://original_damage.gd")
var game: Node
var checks := 0
var failures := 0
var point := Vector3(0,25,0)

class Victim extends StaticBody3D:
	var health := 10000.0
	var dead := false
	var active := true
	var controls_enabled := true
	var hits := 0
	var attacker: Node3D
	func take_damage(amount: float, _source: Vector3 = Vector3.ZERO) -> void: health -= amount; hits += 1
	func take_weapon_damage_from(amount: float, source: Vector3, owner_body: Node3D) -> void:
		attacker = owner_body; take_damage(amount,source)

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-remaining-equipment-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://../Original Sub Culture")
	var config := ConfigFile.new(); config.set_value("game","folder",folder); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func body(at: Vector3, size: Vector3 = Vector3.ONE) -> StaticBody3D:
	var victim := Victim.new(); victim.collision_layer = 8; victim.collision_mask = 0
	var shape := CollisionShape3D.new(); shape.shape = BoxShape3D.new(); shape.shape.size = size; victim.add_child(shape)
	game.world_root.add_child(victim); victim.global_position = at; return victim

func equip(id: String) -> void:
	game.player_progress.hold[id] = 1
	check(Shop.swap(game.player_progress,game.equipment,game.weapons,Shop.SLOTS[id],id).is_empty(),"Equip "+id)

func select_tool(id: String) -> void:
	for index in range(game.equipment.mounted.size()):
		if game.equipment.mounted[index].id == id: game.equipment.selected = index; return

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game loads")
	if not game.startup_complete: quit(1); return
	create_timer(30.0).timeout.connect(func() -> void: push_error("Equipment test did not complete"); quit(1))
	game._begin_new_game(); game.set_process(false); game.docking.set_physics_process(false)
	game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	point.y = game.pilot.surface_height-2.0
	var arsenal: Node3D = game.weapons.arsenal; var tools: Node3D = game.equipment.extra_tools
	tools.set_physics_process(false); game.weapons.set_physics_process(false)
	game.pilot.active = true; game.pilot.freeze = true; game.pilot.controls_enabled = true
	game.pilot.reset_at(point); game.pilot.pending_reset = false
	game.player_progress.status.credits = 1000000
	for stage in [1,3,4]:
		for city in game.gameplay_catalogue.tables.city_info.records:
			var offers := Shop.offers(game.gameplay_catalogue,city,stage)
			for id in ["bubble","repel","strobe","flarel","sflarel","woosh","missile","mammo","homers","ripper","rammo","electro"]:
				var raw: Dictionary = game.gameplay_catalogue.tables["equipment_prices.%d" % stage].records.get(id,{})
				var city_record: Dictionary = game.gameplay_catalogue.tables.city_info.records[city]
				var key: String = city_record.get("shop_price_key",str(city_record.get("name","")).get_slice(" ",0))
				check(offers[id].available == (int(raw.get(key+" buy",0)) > 0),"Original stock "+id+" at "+city+" stage "+str(stage))
				check(offers[id].price == maxi(0,int(raw.get(key+" buy",0))),"Original price "+id)
	check(not Shop.ITEMS.has("fishstim") and not Shop.ITEMS.has("geiger"),"Cut retail items excluded")
	for id in ["mammo","homers","rammo"]:
		var offer := Shop.offer(game.gameplay_catalogue,"1",4,id,true)
		check(offer.quantity == Shop.AMMO[id],"Original ammunition pack "+id)
		check(Shop.buy(game.player_progress,offer).is_empty(),"Buy ammo "+id)
		check(game.player_progress.hold[id] == offer.quantity,"Buy yields whole pack")
		game.player_progress.hold[id] = offer.maximum
		var balance: int = game.player_progress.status.credits
		check(not Shop.buy(game.player_progress,offer).is_empty() and game.player_progress.status.credits == balance,"Capacity failure never charges credits")
		game.player_progress.hold[id] = offer.quantity-1
		check(not Shop.sell(game.player_progress,offer).is_empty(),"Cannot sell incomplete pack")
		game.player_progress.hold[id] = offer.quantity
		if offer.sell_price > 0:
			check(Shop.sell(game.player_progress,offer).is_empty() and not game.player_progress.hold.has(id),"Sell removes exactly one pack")
	for id in ["bubble","repel","strobe","flarel","sflarel","woosh"]:
		var item: Dictionary = tools.item(id)
		check(not item.is_empty() and item.icons.all(func(icon: Texture2D) -> bool: return icon != null),"Original tool HUD assets "+id)
		check(not item.mount.find_children("*","MeshInstance3D",true,false).is_empty(),"Visible original tool housing "+id)
		equip(id)
		check(Shop.installed(game.equipment,game.weapons).get(Shop.SLOTS[id]) == id,"Correct slot "+id)
	check(tools.repel_audio.stream != null and tools.bubble_audio.stream != null and tools.flare_audio.stream != null,"Original equipment sounds load")
	check(arsenal.charge_audio.stream != null and arsenal.gun_audio.stream != null and arsenal.bolt_frames.all(func(frame: Texture2D) -> bool: return frame != null),"Original weapon sounds and all masked bolt frames load")
	# All mount families swap across equipment and weapons without losing either.
	equip("electro")
	check(game.player_progress.hold.get("woosh",0) == 1 and not tools.on("woosh"),"Electro Bolt displaces Woosh from the shared mast slot")
	equip("repel")
	check(game.player_progress.hold.get("electro",0) == 1 and not arsenal.mounts.electro.visible,"Repeller displaces the weapon into hold")
	equip("missile"); game.player_progress.hold.mammo = 16; game.player_progress.hold.homers = 4
	check(game.weapons.mounted.any(func(item: Dictionary) -> bool: return item.id == "homers"),"Launcher exposes separate homing selection")
	check(Shop.installed(game.equipment,game.weapons).get(6) == "missile" and not Shop.installed(game.equipment,game.weapons).has(0),"Homing mode is ammunition, not a second installed launcher")
	game.player_progress.hold.homers = 0; game.weapons.select_id("missile"); game.weapons.cycle(1)
	check(game.weapons.current().id != "homers","Cycling skips the empty homing mode")
	game.player_progress.hold.homers = 4
	equip("ripper")
	check(not game.weapons.mounted.any(func(item: Dictionary) -> bool: return item.id in ["missile","homers"]) and game.player_progress.hold.missile == 1,"Ripper replaces both launcher firing modes")
	check(arsenal.count("ripper") == 0 and arsenal.count("missile") == 16,"Ammo survives launcher swap")
	# Swept projectile collision, attribution, homing and obstruction.
	equip("missile"); game.weapons.select_id("missile")
	var victim: StaticBody3D = body(point+Vector3(0,0,-3),Vector3(1.6,1.6,0.3)); await physics_frame
	arsenal.cooldown = 0; game.weapons.update_fire(true,0.04)
	check(game.player_progress.hold.mammo == 15 and arsenal.shots.size() == 1,"Firing consumes one standard missile")
	var missile: Node3D = arsenal.shots.back(); missile.set_physics_process(false)
	for tick in range(40):
		if missile.spent: break
		missile.advance(0.04)
	check(victim.hits == 1 and victim.attacker == game.pilot,"Swept missile registers one attributed hit (hits=%d, point=%s, shot=%s)" % [victim.hits,point,missile.global_position])
	check(not game.weapons.firing,"Missile selection never emits the Zapper")
	var normal_loss: float = 10000.0-victim.health
	await physics_frame
	game.weapons.select_id("homers"); arsenal.cooldown = 0
	game.weapons.update_fire(true,0.04)
	var homer: Node3D = arsenal.shots.back(); homer.set_physics_process(false)
	check(homer.kind == "homers" and homer.target == victim and game.player_progress.hold.homers == 3,"Homing shot acquires a visible target and uses homing stock")
	check(arsenal.homing_target == victim and arsenal.sight.frame != null,"Homing mode has the original target sight artwork and a live lock")
	var heading: Vector3 = homer.direction; victim.position.x += 1.0; homer.advance(0.04)
	check(homer.direction.x > heading.x,"Homing shot turns toward moving target")
	await physics_frame
	homer.global_position = victim.global_position+Vector3(0,0,0.3); homer.direction = Vector3.FORWARD; homer.velocity = Vector3.FORWARD*3.75
	var before_homing: float = victim.health; homer.advance(0.12)
	check(normal_loss > 25 and normal_loss < 36,"Standard launcher uses the faster player projectile's impact strength")
	check(is_equal_approx(before_homing-victim.health,36.0),"Player homing launcher applies twelvefold HMISSILE inflict at its original speed")
	arsenal.reset(); victim.free(); await physics_frame
	# Ripper hits immediately and loses damage with distance; no free fire when empty.
	equip("ripper"); game.weapons.select_id("ripper"); game.player_progress.hold.rammo = 32
	victim = body(point+Vector3(0,0,-3),Vector3(2,2,0.2)); await physics_frame
	game.weapons.update_fire(true,0.04)
	check(victim.hits == 1 and victim.attacker == game.pilot,"Ripper hits instantly with player attribution")
	var first_loss: float = 10000-victim.health
	for tick in range(11): game.weapons.update_fire(true,0.04)
	check(game.player_progress.hold.rammo == 31,"Ripper consumes stored ammunition at the recovered tick rate")
	game.player_progress.hold.erase("rammo"); var hits: int = victim.hits
	game.weapons.update_fire(true,1.0); check(victim.hits == hits,"Empty Ripper cannot damage targets")
	victim.free(); await physics_frame
	# Electro charge-up, recharge, splash damage to different target categories.
	equip("electro"); game.weapons.select_id("electro"); game.player_progress.ammunition.electro = 99
	game.weapons.update_fire(true,0.04)
	check(arsenal.charge_remaining > 1 and arsenal.shots.is_empty(),"Electro charges before launching")
	for tick in range(34): game.weapons.update_fire(false,0.04)
	check(arsenal.shots.size() == 1 and game.player_progress.ammunition.electro < 2,"Electro launch empties the energy meter")
	var bolt: Node3D = arsenal.shots.back(); bolt.set_physics_process(false); bolt.global_position = point+Vector3(0,0,-4)
	victim = body(bolt.global_position+Vector3.RIGHT)
	var second: StaticBody3D = body(bolt.global_position+Vector3.LEFT*2)
	await physics_frame
	bolt.bursting = true; bolt.burst_ticks = 20; var shields: float = game.pilot.health
	bolt.pulse()
	check(victim.hits == 1 and second.hits == 1 and game.pilot.health == shields,"Electro radial discharge damages multiple bodies and excludes player")
	check(bolt.arcs.size() == 5 and bolt.arcs[0].firing,"Electro displays electrical discharge arcs")
	game.weapons.update_fire(true,0.04); check(arsenal.shots.size() == 1,"Cannot fire Electro before recharge")
	game.weapons.update_fire(false,8.0); check(game.player_progress.ammunition.electro == 99,"Electro recharges without buying ammunition")
	arsenal.reset(); victim.free(); second.free(); await physics_frame
	# Woosh changes real movement without mutating the user's tuning settings.
	equip("woosh"); select_tool("woosh"); game.player_progress.ammunition.woosh = 50.0
	var tuning: Dictionary = game.pilot.movement.settings.duplicate(true)
	game.equipment.toggle_selected(); tools.advance(1.0)
	check(game.pilot.movement.boost_multiplier == tools.BOOST and game.player_progress.status.top_speed == 166,"Woosh applies turbo and displays boosted speed")
	check(is_equal_approx(game.player_progress.ammunition.woosh,48.75),"Woosh consumes finite fuel")
	var movement = preload("res://movement_model.gd").new(); movement.settings = tuning.duplicate(true)
	for tick in range(1200): movement.step(1.0/60.0,Basis.IDENTITY,1,0,0)
	var ordinary: float = -movement.velocity.z; movement.reset_motion(); movement.boost_multiplier = tools.BOOST
	for tick in range(1200): movement.step(1.0/60.0,Basis.IDENTITY,1,0,0)
	check(-movement.velocity.z > ordinary*1.4,"Turbo increases actual cruising speed")
	check(game.pilot.movement.settings == tuning,"Turbo preserves authored/mod movement settings")
	game.equipment.toggle_selected(); check(game.pilot.movement.boost_multiplier == 1,"Turning off restores ordinary propulsion")
	game.player_progress.ammunition.woosh = 1.1; game.equipment.toggle_selected(); tools.advance(0.2)
	check(not tools.installed("woosh") and game.pilot.movement.boost_multiplier == 1,"Exhausted Woosh is consumed and boost removed")
	# Bubble screen has burst and cooldown, suppressing target acquisition only.
	select_tool("bubble"); game.equipment.toggle_selected(); tools.advance(0.1)
	check(game.pilot.get_meta("bubble_screened",false) and game.pilot.controls_enabled,"Bubble cloud screens the sub while preserving controls")
	var pirate = preload("res://pirate_submarine.gd").new(); game.world_root.add_child(pirate)
	check(not pirate._valid_target(game.pilot),"NPCs do not acquire screened player")
	var remaining: float = tools.bubble_remaining; game.equipment.toggle_selected()
	check(tools.bubble_remaining == remaining,"Bubble Gun cannot restart during cooldown")
	tools.advance(2.1); check(not game.pilot.get_meta("bubble_screened",false),"Bubble protection ends after the active burst")
	pirate.free()
	# Strobe actually lights scenery; flares launch, collide and retain distinct behaviour.
	select_tool("strobe"); game.equipment.toggle_selected(); tools.advance(0.05)
	check(tools.strobe.light_energy > 0 and tools.strobe.spot_range == 20,"Strobe lights the world")
	tools.advance(0.6); check(is_zero_approx(tools.strobe.light_energy),"Strobe has a dark interval")
	game.equipment.toggle_selected()
	for id in ["flarel","sflarel"]:
		equip(id); select_tool(id); tools.flare_cooldown = 0; game.equipment.toggle_selected()
		var flare: Node3D = tools.flares.back(); flare.set_physics_process(false)
		check(flare.stationary == (id == "sflarel") and flare.lamp.omni_range == 8,"Flare type and real illumination "+id)
		check(not tools.item(id).enabled,"Flare launcher is momentary rather than a stuck toggle")
		var wall: StaticBody3D = body(flare.global_position+flare.direction*0.6,Vector3(4,4,0.1)); wall.collision_layer = 1
		await physics_frame
		flare._physics_process(0.5)
		check(flare.stuck if id == "sflarel" else flare.velocity.dot(flare.direction) > 0 and flare.velocity.z > 0,"Persistent flare sticks; ordinary flare bounces off scenery: "+id)
		wall.free(); await physics_frame
	# Wildlife repulsion, including mission fish, expires and releases old attraction.
	var fish: Node3D = game.wildlife.get_children().filter(func(entry: Node) -> bool: return entry.mobility == "swimming")[0]
	var old_pose: Vector3 = fish.global_position
	fish.global_position = point+Vector3.RIGHT*2; fish.attract_to(point,10)
	equip("repel"); select_tool("repel"); game.equipment.toggle_selected(); tools.field_clock = 0; tools.advance(0.04)
	check(fish.repulsion_remaining > 0 and fish.attraction_remaining == 0,"Repeller overrides attraction on nearby wildlife (on=%s, active=%s, enabled=%s, dead=%s)" % [tools.on("repel"),game.pilot.active,game.pilot.controls_enabled,game.pilot.dead])
	check((fish.global_position-fish.repulsion_point).normalized().x > 0,"Repeller steers wildlife away from the stern field point")
	fish.global_position = old_pose
	# Numeric state restores without changing beta save schema or old ammunition.
	game.player_progress.ammunition.woosh = 34.25; game.player_progress.ammunition.electro = 12.5; game.player_progress.ammunition.bigears = 2
	game.player_progress.hold.mammo = 123; game.player_progress.hold.homers = 7; game.player_progress.hold.rammo = 234
	var restored := Progress.restore(game.player_progress)
	check(restored.ammunition.woosh == 34.25 and restored.ammunition.electro == 12.5 and restored.ammunition.bigears == 2,"Fuel, energy and old Big Ears counts round-trip")
	check(restored.hold.mammo == 123 and restored.hold.homers == 7 and restored.hold.rammo == 234,"Independent ammunition stocks round-trip")
	var old := Progress.restore({"ammunition":{"bigears":3}})
	check(old.ammunition.woosh == 99 and old.ammunition.electro == 99 and old.ammunition.bigears == 3,"Published saves get safe missing-field defaults")
	var invalid := Progress.restore({"ammunition":{"woosh":-3,"electro":"bad"}})
	check(invalid.ammunition.woosh == 0 and invalid.ammunition.electro == 99,"Invalid new meter values validated")
	game.weapons.select_id("ripper"); game.weapons.set_installed(["ripper"])
	check(game.cockpit_hud.displays[3].weapon_count() == 234,"HUD exposes full three-digit weapon stock")
	# Exercise the real beta disk boundary, rather than only dictionary copying.
	equip("woosh"); game.player_progress.ammunition.woosh = 34.25
	game.weapons.set_installed(["missile"]); game.weapons.select_id("homers")
	game.docking.current = game.submarine_traffic.port_by_id(1); game.docking.stage = game.Docking.Stage.DOCKED
	game.pilot.active = false; game.pilot.controls_enabled = false; tools.refresh()
	game.save_games.folder = "res://tests/cache-remaining-equipment-fixtures/saves"
	check(game.save_games.write(0,game._save_snapshot("New equipment")) == OK,"New equipment saves through the existing version-one format")
	game.player_progress.hold.clear(); game.player_progress.ammunition.woosh = 1
	check(await game._load_saved_game(0),"New loadout restores through the real save loader")
	check(game.player_progress.hold.mammo == 123 and game.player_progress.hold.homers == 7 and game.player_progress.hold.rammo == 234,"Disk load preserves independent ammunition stocks")
	check(game.player_progress.ammunition.woosh == 34.25 and game.player_progress.ammunition.electro == 12.5,"Disk load preserves partial fuel and charge")
	check(Shop.installed(game.equipment,game.weapons).get(8) == "woosh" and game.weapons.current().id == "homers","Disk load restores installed gear and selected homing mode")
	check(game.pilot.movement.boost_multiplier == 1 and not game.pilot.get_meta("bubble_screened",false),"Loading docked never leaves active turbo or bubble protection")
	paused = false
	game.testing_all_equipment = true
	game.docking.current = game.submarine_traffic.port_by_id(1); game.docking.stage = game.Docking.Stage.DOCKED
	game.dock_interface.open("equipment")
	check(game.dock_interface.slot_buttons[5].get_meta("slot") == 1 and game.dock_interface.slot_buttons[6].get_meta("slot") == 2 and game.dock_interface.slot_buttons[7].get_meta("slot") == 6,"All new slot buttons are usable")
	await process_frame; await process_frame
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("res://../.local/equipment-shop-preview.png")
		game.dock_interface.dismiss(); game.dock_interface_active = false
		game.docking.stage = game.Docking.Stage.IDLE; game.pilot.controls_enabled = true; game.pilot.active = true; game.pilot.freeze = true
		game.pilot.reset_at(point); game.pilot.pending_reset = false; game.pilot.visual.show()
		game.equipment.set_installed(["deep_sea_lights","suckomat","bubble","flarel","strobe","repel"])
		game.weapons.set_installed(["zapper","missile","depthl"])
		game.camera.global_position = point+Vector3(1.5,1.3,-2); game.camera.look_at(point)
		await process_frame; await process_frame
		root.get_texture().get_image().save_png("res://../.local/equipment-mounts-preview.png")
		game.weapons.set_installed(["zapper","electro"]); game.weapons.select_id("electro")
		arsenal._launch("electro")
		var display_bolt: Node3D = arsenal.shots.back(); display_bolt.set_physics_process(false)
		display_bolt.global_position = point+Vector3(0,0.5,-1); display_bolt._arcs([point+Vector3(1,0,-1)])
		await process_frame; await process_frame
		root.get_texture().get_image().save_png("res://../.local/electro-preview.png")
	tools.reset(); arsenal.reset()
	check(not game.pilot.get_meta("bubble_screened",false) and game.pilot.movement.boost_multiplier == 1 and tools.flares.is_empty() and arsenal.shots.is_empty(),"Session reset clears all effects and propulsion overrides")
	print("Remaining equipment: %d checks, %d failures" % [checks,failures])
	game.queue_free(); await process_frame; quit(1 if failures else 0)
