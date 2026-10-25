extends RefCounted
## Builds a world in ordered stages while the game node owns live scene state.

var game: Node3D
var map_data: Dictionary = {}

func _init(context: Node3D) -> void:
	game = context

const Assets = preload("res://clump_loader.gd")
const World = preload("res://world_loader.gd")
const Scenery = preload("res://scenery_loader.gd")
const Creatures = preload("res://creature_loader.gd")
const Docking = preload("res://docking_controller.gd")
const Paths = preload("res://asset_paths.gd")
const Pilot = preload("res://submarine_controller.gd")
const Tuning = preload("res://tuning_panel.gd")
const SoundPanel = preload("res://sound_panel.gd")
const Mods = preload("res://mod_registry.gd")
const MapDocument = preload("res://map_document.gd")
const Wildlife = preload("res://wildlife_population.gd")
const HUD = preload("res://cockpit_hud.gd")
const Equipment = preload("res://submarine_equipment.gd")
const Weapons = preload("res://submarine_weapons.gd")
const SessionExplosion = preload("res://mine_explosion.gd")
const OriginalGameData = preload("res://original_game_data.gd")
const SUB_RENDER_LAYER := 2

func _start_game(folder: String) -> void:
	if game.photo_mode != null and game.photo_mode.active: game.photo_mode.leave()
	if game.photo_mode != null: game.photo_mode.replay.clear()
	if game.menu_backdrop != null:
		game.menu_backdrop.close(); game.menu_backdrop.free(); game.menu_backdrop = null
	if game.dock_interface != null: game.dock_interface.dismiss(); game.dock_interface_active = false
	game._set_map_open(false)
	if game.map_overlay != null:
		game.map_overlay.free(); game.map_overlay = null; game.expanded_map = null; game.map_screen = null
	if game.world_loading: return
	if not Paths.valid_game_folder(folder):
		game._fail_startup("Could not find CLUMPS/SUB.DFF and DATA/SCEN1.BSP in that folder.")
		return
	game.world_loading = true
	game.front_end.load_art(folder)
	game.front_end.show_loading()
	await game.get_tree().process_frame
	game.gameplay_catalogue = OriginalGameData.load_catalogue(folder)
	for warning in game.gameplay_catalogue.warnings: Mods.note(warning)
	game.export_all_button.disabled = true
	game.export_all_dialog.hide()
	game.pilot_mode = false
	if game.radio_feed != null: game.radio_feed.clear()
	game.radio_greeting = ""; game.radio_status = ""
	if game.docking != null:
		game.docking.cancel()
		game.docking.free()
		game.docking = null
	if game.pilot != null: game.pilot.active = false
	if game.cockpit_hud != null:
		game.cockpit_hud.free()
		game.cockpit_hud = null
	if game.equipment != null:
		game.equipment.free()
		game.equipment = null
	if game.weapons != null:
		game.weapons.free(); game.weapons = null
	game.loading_canvas.visible = true
	game.game_folder = folder
	if game.model != null:
		game.model.free()
		game.model = null
	if game.world_root != null:
		game.world_root.free()
		game.world_root = null
	if not await _load_environment(folder): return
	await _populate_world(folder)
	await _setup_vehicle(folder)
	await _setup_actors(folder)
	await _finish_start(folder)

func _load_environment(folder: String) -> bool:
	game.model = Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF"))
	if game.model == null:
		game._fail_startup("The submarine model could not be read.")
		return false
	game.world_root = await World.load_world(folder.path_join("DATA/SCEN1.BSP"), game.get_tree(), game._progress)
	if game.world_root == null:
		game.model.free()
		game.model = null
		game._fail_startup("The map could not be read.")
		return false
	game.world_root.set_meta("world_loading", true)
	game.add_child(game.world_root)
	await World.add_collision(game.world_root, game.get_tree(), game._progress)
	await game.get_tree().physics_frame
	await game.get_tree().physics_frame
	await Scenery.populate(game.world_root, folder, game.get_tree(), game._progress)
	map_data = MapDocument.load_active() if game.use_map_overrides else {}
	game.wildlife = null
	if not map_data.is_empty(): MapDocument.apply_entities(game.world_root, folder, map_data)
	await preload("res://scenery_scatter.gd").populate(game.world_root, folder, game.get_tree(), game.scenery_seed)
	OriginalGameData.apply_city_names(game.world_root,game.gameplay_catalogue)
	game.plant_current.attach(game.world_root)
	game._add_water_surface()
	await game.get_tree().physics_frame
	await game.natural_light.build(game.world_root,game._progress)
	return true

func _populate_world(folder: String) -> void:
	if map_data.is_empty():
		await Creatures.populate(game.world_root, folder, game.get_tree(), game._progress)
		var stats: Dictionary = game.gameplay_catalogue.tables.creature_stats.records
		var death_frames := preload("res://creature_death.gd").load_gore(folder)
		var death_flesh := Assets._load_texture(folder,"BEEF2","",{})
		for fish in game.world_root.get_node("AmbientFish").get_children():
			fish.configure_health(float(stats.get(str(fish.get_meta("species","")).to_lower(),{}).get("health",10)))
			fish.damage_sustain = float(stats.get(str(fish.get_meta("species","")).to_lower(),{}).get("sustain",1.0))
			fish.death_texture = Assets._load_texture(folder,"BUBBLE","BUBBLEM",{})
			fish.death_sound = Weapons._sound(folder,"audio.creature.death","SPLAT")
			fish.death_frames = death_frames
			fish.death_flesh_texture = death_flesh
	else:
		game.wildlife = Wildlife.new()
		game.wildlife.max_active = game.front_end.gameplay_menu.wildlife_limit
		game.wildlife.gameplay_catalogue = game.gameplay_catalogue
		game.wildlife.name = "AmbientFish"
		game.world_root.add_child(game.wildlife)
		game.wildlife.density = game.wildlife_density_slider.value / 100.0
		game.wildlife.view_camera = game.camera
		game.wildlife.visibility_range = game.fog_visibility if game.fog_button.button_pressed else game.camera.far
		game.wildlife.setup(game.world_root, folder, map_data,true)
	game.object_population = preload("res://object_population.gd").new()
	game.world_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	if game.wildlife != null:
		var defence := preload("res://dock_defence.gd").new(); defence.name = "DockDefence"
		defence.damage_per_tick = game.dock_zapper_damage_slider.value
		game.world_root.add_child(defence); defence.setup(game.world_root,game.wildlife)
	game.object_population.name = "MapObjects"; game.world_root.add_child(game.object_population)
	game.object_population.setup(folder,map_data)
	game.water_visuals.reset_materials()
	game.water_visuals.attach(game.world_root)
	if game.wildlife != null:
		for template in game.wildlife.templates.values(): game.water_visuals.attach(template)
	game.water_visuals.sync_plants(game.plant_current)
	game.natural_light.materials.clear(); game.natural_light.attach(game.world_root)
	var canopy_reflections := preload("res://exterior_reflections.gd").new()
	canopy_reflections.name = "ExteriorCanopyReflections"; game.world_root.add_child(canopy_reflections)
	canopy_reflections.setup(game.world_root.get_world_3d(),game.front_end.player_graphics.settings.reflective_canopies)
	if game.wildlife != null:
		for template in game.wildlife.templates.values(): game.natural_light.attach(template)

func _setup_vehicle(folder: String) -> void:
	if game.pilot == null:
		game.pilot = Pilot.new()
		game.pilot.process_mode = Node.PROCESS_MODE_PAUSABLE
		game.pilot.name = "PlayerSubmarine"
		game.pilot.remember_settings = game.remember_preferences
		game.add_child(game.pilot)
		game.pilot.health_changed.connect(game._submarine_health_changed)
		game.pilot.destroyed.connect(game._submarine_destroyed)
	else: game.pilot.movement.load_settings(game.remember_preferences)
	game.turret_system = preload("res://turret_system.gd").new(); game.turret_system.name = "TurretSystem"
	game.world_root.add_child(game.turret_system)
	preload("res://entity_identity.gd").assign_id(game.pilot,"player")
	game.turret_system.events = game.events
	game.turret_system.setup(game.world_root,folder,game.pilot,func(faction: int) -> bool: return faction > 0 and game.player_progress.standing.get(str(faction),"neutral") == "bad")
	game.ground_traffic = preload("res://ground_traffic.gd").new(); game.ground_traffic.name = "GroundTraffic"; game.world_root.add_child(game.ground_traffic)
	game.ground_traffic.simulating = false
	game.ground_traffic.events = game.events
	game.ground_traffic.setup(game.world_root,folder,game.pilot,func(faction: int) -> void:
		if faction <= 0: return
		game.player_progress.standing[str(faction)] = "bad"
		for turret in game.turret_system.turrets:
			if int(turret.tuning.turret_faction) == faction: turret.activate(60)
	)
	var selected_tab: StringName = game.developer_tabs.get_current_tab_control().name if game.tuning_panel != null and game.developer_tabs.get_current_tab_control() != null else &"Movement"
	for child in game.bubble_controls.get_children(): child.free()
	if game.tuning_panel != null: game.tuning_panel.free()
	game.tuning_panel = Tuning.new()
	game.tuning_panel.name = "Movement"
	game.developer_tabs.add_child(game.tuning_panel)
	game.developer_tabs.move_child(game.tuning_panel, 0)
	game.tuning_panel.setup(game.pilot.movement, true, game.bubble_controls)
	game.tuning_panel.settings_changed.connect(game._schedule_settings_save)
	game.pilot.surface_height = float(game.world_root.get_meta("surface_height"))
	await game.get_tree().physics_frame
	await game.get_tree().physics_frame
	var bounds: AABB = game.world_root.get_meta("bounds")
	var point: Vector3 = game.world_root.get_meta("player_spawn", bounds.get_center())
	game.pilot.reset_at(point,game.world_root.get_meta("player_spawn_basis",Basis.IDENTITY))
	game.model.scale *= Pilot.VISUAL_SCALE
	game.model.rotation.y = PI
	game.pilot.add_child(game.model)
	game.pilot.visual = game.model
	game.pilot.setup_damage_smoke(folder)
	game.pilot.fit_collision_to_visual()
	game.equipment = Equipment.new()
	game.pilot.add_child(game.equipment)
	game.equipment.setup(game.pilot, folder)
	game.equipment.vacuum.population = game.object_population
	# Keep lights and equipment working while excluding the sub geometry
	# from the cockpit camera. Visibility still belongs to docking.
	for node in game.pilot.find_children("*","MeshInstance3D",true,false): node.layers = SUB_RENDER_LAYER
	game.weapons = Weapons.new(); game.pilot.add_child(game.weapons); game.weapons.setup(game.pilot,folder,game.camera,game.gameplay_catalogue)
	game.weapons.auto_aim_enabled = game.front_end.gameplay_menu.zapper_auto_aim
	var weapon_values: Dictionary = game.weapons.settings.duplicate(); weapon_values.merge(game.weapon_overrides,true)
	for key in game.weapon_controls: game.weapon_controls[key].set_value_no_signal(weapon_values[key])
	game._update_weapon_settings()
	var hull_bounds := Equipment._bounds(Equipment._meshes(game.pilot.visual,Transform3D.IDENTITY,true))
	game.cockpit_camera_offset = Vector3(hull_bounds.get_center().x,hull_bounds.position.y + hull_bounds.size.y * 0.48,hull_bounds.position.z + hull_bounds.size.z * 0.25)
	game._update_equipment_settings()
	game.water_visuals.attach(game.pilot)
	game.natural_light.attach(game.pilot)
	game.cockpit_hud = HUD.new()
	game.cockpit_hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.add_child(game.cockpit_hud)
	await game.cockpit_hud.map_data.setup_async(game.world_root,game.pilot.collision_height() + 2.0 * game.pilot.safe_margin,game.get_tree())
	game.cockpit_hud.setup(game.pilot, game.equipment, game.world_root, folder,game.weapons)
	game.cockpit_hud.map_data.landmarks.setup(game.gameplay_catalogue)
	game.cockpit_hud.setup_lighting(game.water_environment,game.sun)
	game.cockpit_hud.natural_light = game.natural_light
	if is_instance_valid(game.first_person_cockpit): game.first_person_cockpit.free()
	game.first_person_cockpit = preload("res://first_person_cockpit.gd").new(); game.camera.add_child(game.first_person_cockpit); game.first_person_cockpit.setup(game)
	game._build_expanded_map()
	game._update_hud_settings()
	for index in range(5):
		game.cockpit_hud.set_enabled(index,game.hud_enabled[index],false)
	game.pilot.reset_physics_interpolation()
	game.submarine_bubble_texture = Assets._load_texture(folder,"BUBBLE","BUBBLEM",{})
	game.pilot.bubbles.configure(game.submarine_bubble_texture)
	if game.camera.get_node_or_null("ExplosionShake") == null:
		var shake := preload("res://explosion_camera_shake.gd").new(); shake.name = "ExplosionShake"; shake.observer = game.pilot; game.camera.add_child(shake)
	game.submarine_explosion_frames = SessionExplosion.load_frames(folder)
	# Retail player-death callback 00434180 plays sample 0x0c: EXPL.RAW.
	game.submarine_explosion_sound = Weapons._sound(folder,"audio.submarine.explosion","EXPL")
	game.pilot.submarine_audio.setup(game.pilot, folder)
	game.front_end.audio_tuning = game.pilot.submarine_audio.tuning
	game.dock_interface.audio_tuning = game.pilot.submarine_audio.tuning
	if game.sound_panel != null: game.sound_panel.free()
	game.sound_panel = SoundPanel.new()
	game.sound_panel.name = "Sound"
	game.developer_tabs.add_child(game.sound_panel)
	game.developer_tabs.move_child(game.sound_panel, 1)
	game.sound_panel.setup(game.pilot.submarine_audio, true)
	game.sound_panel.settings_changed.connect(game._schedule_settings_save)
	game._select_developer_tab(str(selected_tab))
	game.pilot.hull_rating = 100; game.pilot.radiation_rating = 0
	game.pilot.restore_health(); game.pilot.collision_layer = 2; game.pilot.collision_mask = 13
	game.pilot.active = true

func _setup_actors(folder: String) -> void:
	if game.docking != null: game.docking.free()
	game.docking = Docking.new()
	game.docking.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.add_child(game.docking)
	game.docking.setup(game.pilot, game.world_root, folder, game.camera,game.gameplay_catalogue)
	game.submarine_traffic = preload("res://submarine_traffic.gd").new(); game.submarine_traffic.name = "SubmarineTraffic"; game.world_root.add_child(game.submarine_traffic)
	game.submarine_traffic.events = game.events
	game.submarine_traffic.prepare_visual = func(visual: Node3D) -> void: game.water_visuals.attach(visual); game.natural_light.attach(visual)
	game.submarine_traffic.setup(game.world_root,folder,game.docking.ports,game.cockpit_hud.map_data,game.pilot,func(faction: int) -> void:
		game.player_progress.standing[str(faction)] = "bad"
		for turret in game.turret_system.turrets:
			if int(turret.tuning.turret_faction) == faction: turret.activate(60)
	)
	while not game.submarine_traffic.navigation_ready:
		game.submarine_traffic.build_graph(128)
		await game.get_tree().process_frame
	game.submarine_traffic.pirate_defeated.connect(game._pirate_bounty)
	game.submarine_traffic.enable_roaming_pirates(folder,map_data)
	game.submarine_traffic.roaming_population.transmission.connect(func(message: Dictionary) -> void:
		if game.radio_feed != null: game.radio_feed.push_message(message,game.docking.radio_static)
	)
	var activity := preload("res://actor_activity.gd").new()
	activity.name = "ActorActivity"; activity.game = game
	activity.submarines = game.submarine_traffic; activity.ground = game.ground_traffic
	activity.turrets = game.turret_system
	game.world_root.add_child(activity)
	activity.refresh_views(); activity.update_actors(0.0)
	if game.wildlife != null: game.wildlife.activity = activity
	game.save_games.city_names.clear()
	for port in game.docking.ports: game.save_games.city_names[int(port.node.get_meta("city_id"))] = str(port.name)
	game._update_docking_radius()
	if game.wildlife != null: game.wildlife.player = game.pilot
	game.object_population.player = game.pilot
	game.docking.docked.connect(game._reset_docked_wildlife)
	game.docking.docked.connect(func() -> void: game.events.city_docked.emit(int(game.docking.current.node.get_meta("city_id"))))
	game.equipment.activated.connect(func(id: String, active: bool) -> void: game.events.equipment_activated.emit(id,active))

func _finish_start(folder: String) -> void:
	if game.radio_feed == null: game._build_radio_feed()
	game.radio_message_audio.setup(folder,game.radio_feed,game.pilot.submarine_audio.tuning,game.game_radio._radio_audio_allowed)
	game.dock_interface.setup(folder,game._dock_ui_model)
	game.pilot_mode = true
	game.world_root.remove_meta("world_loading")
	game.ground_traffic.set_simulating(true)
	game.world_loading = false
	game.loaded_world_assets = game._world_asset_key()
	game.export_all_button.disabled = false
	game.status_label.text = str(game.world_root.get_meta("scenery_summary", "Piloting ready."))
	game._update_follow_camera(0.0, true)
	game.particles.material.set_shader_parameter("surface_height", game.pilot.surface_height)
	game.particles._rebuild()
	game._update_water_environment()
	var activity: Node = game.world_root.get_node("ActorActivity")
	activity.refresh_views(); activity.update_actors(0.0)
	if game.wildlife != null: game.wildlife._stream_update(true)
	if game.menu_backdrop == null:
		game.menu_backdrop = preload("res://menu_backdrop.gd").new()
		game.add_child(game.menu_backdrop); game.menu_backdrop.setup(game)
	if not is_instance_valid(game.sun_shafts):
		game.sun_shafts = preload("res://sun_shafts.gd").new()
		game.world_root.add_child(game.sun_shafts); game.sun_shafts.setup(game)
	game.sun_shafts.brightness = game.sun_shafts_brightness_slider.value / 100.0
	game.sun_shafts.set_enabled(game.front_end.gameplay_menu.sun_shafts_enabled)
	game.front_end.progress_bar.value = 95.0
	if game.show_start_menu and DisplayServer.get_name() != "headless":
		for frame in range(600):
			if game.cockpit_hud.map_data.scenery_baked: break
			await game.get_tree().process_frame
	game.front_end.progress_bar.value = 100.0
	if not game.loading_save: game.loading_canvas.visible = false
	game._save_preferences()
