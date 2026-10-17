extends "res://tests/test_scene_tree.gd"
const Mods = preload("res://mod_registry.gd")
const HUD = preload("res://cockpit_hud.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-depth-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",ProjectSettings.globalize_path("res://../Original Sub Culture")); config.save(storage.preferences_path())
	call_deferred("run")
func capture(path: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	var game := preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game loads the depth-charge loadout")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.set_process(false); game.docking.set_physics_process(false); game.weapons.set_physics_process(false)
	game.equipment.support_tools.set_physics_process(false)
	game.player_progress.status.credits = 100000
	game.docking.current = game.submarine_traffic.port_by_id(1); game.docking.stage = game.Docking.Stage.DOCKED
	game.dock_interface.open("equipment")
	game._dock_ui_action("buy_equipment",{"item":"depthl"})
	check(game.player_progress.hold.get("depthl",0) == 1 and game.player_progress.hold.get("depth",0) == 8,"Dock transaction buys the launcher and eight free charges")
	game._dock_ui_action("buy_equipment",{"item":"depth"})
	check(game.player_progress.hold.get("depth",0) == 12 and game.player_progress.status.credits == 96000,"Dock transaction buys a four-pack at its quoted price")
	game.dock_interface.selected_sale = "depth"; game.dock_interface.selected_hold = "depth"; game.dock_interface.rebuild()
	var list: ItemList = game.dock_interface.sale_list
	var pack_found := false
	for index in range(list.item_count):
		if list.get_item_metadata(index) == "depth": pack_found = list.get_item_text(index).to_lower() == "4 depth charges"
	check(pack_found,"Shop labels ammunition as four Depth Charges")
	await capture("res://tests/depth-shop.png")
	game.player_progress.hold.depth = 77; game.dock_interface.rebuild()
	check(game.dock_interface.layout.get_node("BuyShieldRepair").disabled,"Dock UI rejects a pack when fewer than four ammo spaces remain")
	game.player_progress.hold.depth = 3; game.dock_interface.rebuild()
	check(game.dock_interface.layout.get_node("SellShieldRepair").disabled,"Dock UI prevents selling an incomplete four-pack")
	game.player_progress.hold.depth = 12
	game._dock_ui_action("equipment_slot",{"slot":7,"item":"depthl"})
	check(game.weapons.mounted.any(func(item: Dictionary) -> bool: return item.id == "depthl") and not game.player_progress.hold.has("depthl"),"Bought launcher installs through the regular equipment mount")
	game.weapons.selected = 1
	var display: Control = game.cockpit_hud.displays[3]
	check(display.weapon_count() == 12,"Original weapon HUD reads the available individual charges")
	var tools: Node3D = game.equipment.support_tools
	check(str(tools.depth_audio.stream.get_meta("asset_source","")).get_file() == "DEPTH.RAW" and str(tools.explosion_sound.get_meta("asset_source","")).get_file() == "DCHARGE.RAW","Launcher and explosion load their distinct original sounds")
	game.front_end.hide_menu(); game.dock_interface.dismiss(); game.docking.stage = game.Docking.Stage.IDLE
	paused = false
	game.pilot.active = true; game.pilot.controls_enabled = false
	tools.fire_depth(true)
	check(tools.projectiles.is_empty() and game.player_progress.hold.depth == 12,"Menus and disabled controls cannot fire or spend ammunition")
	game.pilot.controls_enabled = true
	game.pilot.global_position = Vector3(10000,-10,10000); game.pilot.global_basis = Basis.IDENTITY
	game.pilot.linear_velocity = Vector3(2,0.4,-1)
	game.weapons.update_fire(true,0.01)
	var projectile: RigidBody3D = tools.projectiles.back()
	check(projectile.global_position.is_equal_approx(game.weapons.depth_mount.global_position) and projectile.linear_velocity.is_equal_approx(game.pilot.linear_velocity),"Charge leaves the configured launcher mount with all inherited momentum")
	check(game.player_progress.hold.depth == 11 and display.weapon_count() == 11 and not game.weapons.firing,"Firing decrements HUD ammo without enabling the zapper")
	game.weapons.update_fire(true,0.01)
	check(tools.projectiles.size() == 1 and game.player_progress.hold.depth == 11,"Holding fire respects the original one-second launcher interval")
	game.camera.global_position = game.pilot.global_position + Vector3(2,1.2,3); game.camera.look_at(game.pilot.global_position)
	await capture("res://tests/depth-hud.png")
	tools.depth_cooldown = 0; game.player_progress.hold.depth = 1
	game.weapons.update_fire(true,0.01)
	check(not game.player_progress.hold.has("depth") and display.weapon_count() == 0 and game.weapons.current().id == "depthl","Last charge shows 00 and leaves the empty launcher installed")
	var deployed: int = tools.projectiles.size(); tools.depth_cooldown = 0
	game.weapons.update_fire(true,0.01)
	check(tools.projectiles.size() == deployed and display.weapon_count() == 0,"Empty launcher creates no charge and cannot produce negative ammo")
	game.weapons.selected = 0
	check(display.weapon_count() == -1,"Selecting the zapper clears the depth-charge counter")
	tools.reset()
	# Live NPC receiver: blast damage must use sustain, player attribution and
	# the steering momentum used on the following simulation step.
	var trader: Node3D = game.submarine_traffic.traders.filter(func(agent: Node3D) -> bool: return agent.get_script() == preload("res://trader_submarine.gd"))[0]
	trader.running = true; trader.dead = false; trader.stage = "travel"; trader.release_port()
	# Use normal activation so an initially distant NPC's shapes are enabled too.
	trader.local_simulation = false; trader.set_local_simulation(true); trader.set_physics_process(false)
	trader.get_parent().show(); trader.get_parent().global_position = Vector3(10010,-10,10000)
	trader.body.collision_layer = 10; trader.health.configure(10,0.3); trader.motion.velocity = Vector3.ZERO
	var blast := preload("res://depth_charge.gd").new(); blast.tools = tools; game.world_root.add_child(blast)
	blast.freeze = true; blast.global_position = trader.body.global_position - Vector3.RIGHT
	await physics_frame; await physics_frame
	blast.detonate()
	check(trader.health.remaining < 10.0 and trader.flee > 0.0,"Depth-charge blast damages a real NPC sub through its normal attack response")
	check(trader.motion.velocity.x > 0.5,"Blast push feeds the real NPC steering momentum")
	var jobs: Node = game.mission_runtime.side_jobs
	jobs.start("spytrad2"); jobs.set_physics_process(false); jobs._spawn_base()
	check(jobs.base_defences.size() == 3 and jobs.base_defences.all(func(defence: Dictionary) -> bool: return defence.model.global_position.is_equal_approx(jobs.base_poses[jobs.base_defences.find(defence)].origin) and defence.vent.shell.get_parent() == defence.model),"Each original base building owns its defence and matching vent target")
	check(str(jobs.missile_template.get_meta("asset_source","")).get_file() == "TMISSILE.DFF","Original mission base loads Procha TMISSILE rather than the player's MISSILE")
	var building_shot: Node3D
	var firing_base: Dictionary = jobs.base_defences[0]
	for offset in [Vector3(0,2,6),Vector3(6,2,0),Vector3(0,2,-6),Vector3(-6,2,0),Vector3(0,7,0)]:
		game.pilot.global_position = firing_base.model.global_position + offset; game.pilot.linear_velocity = Vector3.ZERO
		building_shot = jobs._fire_base(firing_base)
		if building_shot != null: break
	check(building_shot != null,"An original mission building can fire into clear surrounding water")
	if building_shot != null:
		check(absf(building_shot.global_position.distance_to(firing_base.model.global_position)-1.0) < 0.001,"Live mission missile starts at the recovered one-unit offset from its building")
		building_shot.set_physics_process(false); building_shot._physics_process(0.04)
		check(not building_shot.is_queued_for_deletion(),"Live base shot clears the original building's own collision shell")
		building_shot.queue_free()
	for agent in jobs.vessels: agent.set_physics_process(false)
	var vent: Node3D = jobs.vents[0]; vent.open = true; vent._process(0.6)
	var off_centre := preload("res://depth_charge.gd").new(); game.world_root.add_child(off_centre)
	off_centre.global_position = vent.door.to_global(Vector3(0.7,0.3,0.4)); off_centre.prepare_aperture()
	check(off_centre.entered_vent == vent,"Original rectangular hatch accepts a visibly aligned off-centre charge")
	for frame in range(100): await physics_frame
	check(vent.health < 1.5,"An off-centre charge damages the real mission internal target")
	vent.dead = false; vent.health = 1.5
	game.pilot.global_position = vent.global_position + Vector3(0,0.3,-0.35); game.pilot.global_basis = Basis.IDENTITY; game.pilot.linear_velocity = Vector3.ZERO
	game.weapons.selected = 1; game.player_progress.hold.depth = 1; tools.depth_cooldown = 0
	tools.fire_depth(true)
	var falling: Node3D = tools.projectiles.back()
	check(falling.entered_vent == vent,"A deployed charge enters the original fully open mission hatch")
	for frame in range(100): await physics_frame
	check(vent.health < 1.5,"Launcher drops a real charge through the original mission base aperture and damages its internal target")
	game.pilot.global_transform = Transform3D(Basis.IDENTITY,vent.global_position + Vector3(0,0.3,-0.35)); game.pilot.linear_velocity = Vector3.ZERO
	game.player_progress.hold.depth = 1; tools.depth_cooldown = 0; tools.fire_depth(true)
	for frame in range(100): await physics_frame
	check(vent.dead,"A further charge finishes the damaged original internal target")
	var plumes: Array = firing_base.smoke
	check(plumes.size() == 2,"Disabling a weapon starts both original smoke plumes")
	if plumes.size() == 2:
		check(plumes[0].global_position.is_equal_approx(firing_base.model.global_position + Vector3.UP * 0.9) and plumes[1].global_position.is_equal_approx(vent.global_position),"Smoke originates above the building and at its separate vent")
		check(plumes.all(func(plume: Node3D) -> bool: return plume.enabled and not plume.puffs.is_empty()),"Both disabled-base emitters produce persistent smoke")
		jobs._disable_base(firing_base)
		check(plumes.size() == 2,"Repeated disable notifications do not duplicate smoke")
	check(jobs.base_defences[1].smoke.is_empty() and jobs.base_defences[2].smoke.is_empty(),"Undamaged buildings do not smoke")
	for index in range(3):
		var hover_vent: Node3D = jobs.vents[index]
		hover_vent.dead = false; hover_vent.health = 1.5; hover_vent.open = true; hover_vent._process(0.6); hover_vent.set_process(false)
		game.pilot.global_transform = Transform3D(Basis.IDENTITY,hover_vent.global_position+Vector3.UP*(1.0+float(index)*0.5))
		game.pilot.linear_velocity = Vector3.ZERO
		var launch_offset: Vector3 = game.weapons.depth_mount.global_position-game.pilot.global_position
		game.pilot.global_position -= Vector3(launch_offset.x,0,launch_offset.z)
		game.player_progress.hold.depth = 1; tools.depth_cooldown = 0; tools.fire_depth(true)
		for frame in range(160): await physics_frame
		check(hover_vent.dead,"One actual launcher drop from normal hover height disables original vent %d" % index)
	jobs.clear()
	check(plumes.all(func(plume: Node3D) -> bool: return plume.is_queued_for_deletion()),"Mission cleanup removes both smoke emitters")
	var selected: Array[String] = ["test-3d-map-instrument"]
	check(Mods.apply(selected,selected,false) == OK,"3D HUD mod loads for the weapon-counter check")
	game.cockpit_hud.free(); game.cockpit_hud = HUD.new(); game.add_child(game.cockpit_hud)
	game.cockpit_hud.setup(game.pilot,game.equipment,game.world_root,game.game_folder,game.weapons)
	game.cockpit_hud.setup_lighting(game.water_environment,game.sun)
	game.weapons.selected = 1; game.player_progress.hold.depth = 8
	var weapon_view: SubViewport = game.cockpit_hud.model_views[3]
	var counter := weapon_view.get_node_or_null("WeaponCounter") as SubViewport
	check(counter != null and not game.cockpit_hud.displays[3].show_weapon_counter,"3D weapon instrument binds its dedicated counter instead of drawing over the icon")
	if counter != null:
		check(counter.get_child(0).weapon_count() == 8,"3D weapon counter reads the same live ammunition")
	await capture("res://tests/depth-hud-3d.png")
	game.queue_free(); await process_frame
	print("Depth loadout: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
