extends RefCounted
## New-game resets and save snapshots/restoration. Mission state can extend this boundary without changing UI code.

const Docking = preload("res://docking_controller.gd")
const Mods = preload("res://mod_registry.gd")
const MapDocument = preload("res://map_document.gd")
const HUD = preload("res://cockpit_hud.gd")
const SessionDebris = preload("res://creature_death.gd")
const SessionExplosion = preload("res://mine_explosion.gd")
const PlayerProgress = preload("res://player_progress.gd")

var game: Node

func _init(context: Node) -> void:
	game = context

func _begin_new_game() -> void:
	if game.world_loading: return
	game.front_end.hide_menu()
	if game.menu_backdrop != null: game.menu_backdrop.close()
	if game.dock_interface != null: game.dock_interface.dismiss()
	game.get_tree().paused = false
	if not game._can_reuse_world():
		await game._start_game(game.game_folder)
	if not game.pilot_mode: return
	game._reset_loaded_world()
	game.object_population.populate_startup()
	game.cockpit_hud.set_bottom_camera_enabled(false)
	game.day_night.hour = 10.0
	game.player_progress = PlayerProgress.restore()
	game._update_daylight()
	game.has_started_game = true
	game.front_end.can_resume = true
	game.cockpit_hud.map_data.reset_exploration()
	game._update_mouse_pointer()
	game.events.session_started.emit(false)

func _world_asset_key() -> String:
	return JSON.stringify([game.game_folder,Mods.layers,Mods.movement])

func _can_reuse_world() -> bool:
	return game.pilot_mode and is_instance_valid(game.world_root) and game.loaded_world_assets == game._world_asset_key()

func _reset_loaded_world() -> void:
	if game.menu_backdrop != null: game.menu_backdrop.close()
	game.dock_interface.dismiss(); game.dock_interface_active = false
	game._set_map_open(false)
	game.docking.cancel()
	game.docking.nearby = {}; game.docking.declined_port = null; game.docking.message = ""
	game.docking.greeted_ports.clear(); game.docking.greeting_port = {}; game.docking.greeting_remaining = 0.0
	if game.docking_portrait != null: game.docking_portrait.reset_signal()
	if game.docked_screen != null: game.docked_screen.hide()
	game.weapons.update_fire(false,0); game.weapons.selected = 0; game.weapons.elapsed = 0.0
	for particle in game.weapons.hit_blood.particles: particle.node.free()
	game.weapons.hit_blood.particles.clear()
	for patch in game.plant_current.patches:
		patch.bend = Vector3.ZERO
		for material in patch.materials: material.set_shader_parameter("propeller_bend",Vector3.ZERO)
	game._clear_session_effects(game.world_root)
	game.pilot.hull_rating = 100; game.pilot.radiation_rating = 0
	game.pilot.restore_health(); game.pilot.collision_layer = 2
	game.pilot.collision_mask = 13; game.pilot.active = true; game.pilot.controls_enabled = true
	game.weapons.show()
	game.equipment.show()
	game.pilot.visual.show()
	game.pilot.reset_at(game.world_root.get_meta("player_spawn",game.world_root.get_meta("bounds").get_center()),game.world_root.get_meta("player_spawn_basis",Basis.IDENTITY))
	game.pilot._update_animation(0)
	game.equipment.vacuum.reset()
	game.equipment.reset_towing()
	game.equipment.set_installed(["deep_sea_lights","suckomat"])
	game.weapons.set_installed(["zapper"])
	game.equipment.selected = 0
	for item in game.equipment.available:
		item.enabled = false
		item.mount.transform = item.mount.get_meta("default_mount")
		preload("res://submarine_mounts.gd").apply(item.mount,game.pilot.visual,item.id)
	game.weapons.muzzle.transform = game.weapons.muzzle.get_meta("default_mount")
	preload("res://submarine_mounts.gd").apply(game.weapons.muzzle,game.pilot.visual,"zapper")
	game.equipment.apply_settings()
	if game.wildlife != null: game.wildlife.reroll()
	else: game._reset_provisional_wildlife()
	game.object_population.reset_population()
	game.cockpit_hud.map_data.reset_exploration()
	game.camera_was_frozen = false
	game._set_camera_mode(false)

func _clear_session_effects(node: Node) -> void:
	for child in node.get_children():
		if child is SessionDebris or child is SessionExplosion:
			child.free()
		else: game._clear_session_effects(child)

func _map_signature() -> String:
	# Editable placements and type stats are not map identity. The underlying
	# terrain remains the same when objects, wildlife or spawn points change.
	return "terrain-v1:" + FileAccess.get_sha256(game.game_folder.path_join("DATA/SCEN1.BSP"))

func _exploration_matches_map(signature: String) -> bool:
	# This only controls restoration of map exploration, never save validity.
	return signature == game._map_signature()

func _save_snapshot(name: String) -> Dictionary:
	game.player_progress.suckomat = game.equipment.vacuum.storage.duplicate()
	var items: Array = []
	for item in game.equipment.mounted: items.append({"id":item.id,"enabled":item.enabled})
	var arms: Array = []
	for item in game.weapons.mounted: arms.append(item.id)
	var explored = game.cockpit_hud.map_data.explored.duplicate() as Image
	explored.convert(Image.FORMAT_L8)
	return {"version":game.save_games.VERSION,"name":name.left(64),"saved_at":Time.get_datetime_string_from_system(),"dock":{"id":int(game.docking.current.node.get_meta("city_id")),"name":game.docking.current.name},"pose":MapDocument.encode(game.pilot.global_transform),"hour":game.day_night.hour,"equipment":items,"weapons":arms,"equipment_selected":game.equipment.current().get("id",""),"weapon_selected":game.weapons.current().get("id",""),"explored":Marshalls.raw_to_base64(explored.get_data()),"map_signature":game._map_signature(),"mods":Mods.active_ids(),"progress":game.player_progress.duplicate(true),"objects":game.object_population.snapshot()}

func _load_saved_game(slot: int) -> bool:
	if game.loading_save or game.world_loading: return false
	var data = game.save_games.read(slot)
	if data.is_empty(): game.dock_interface.report(game.save_games.error); return false
	var port_exists: bool = game.docking.ports.any(func(port: Dictionary) -> bool: return int(port.node.get_meta("city_id")) == int(data.dock.id))
	if not port_exists: game.dock_interface.report("The saved dock is not present in this map."); return false
	for item in data.equipment:
		if not game.equipment.available.any(func(mounted: Dictionary) -> bool: return mounted.id == item.id): game.dock_interface.report("Required equipment is unavailable: " + item.id); return false
	for id in data.weapons:
		if not game.weapons.available.any(func(mounted: Dictionary) -> bool: return mounted.id == id): game.dock_interface.report("Required weapon is unavailable: " + id); return false
	game.loading_save = true
	game.front_end.hide_menu(); game.dock_interface.dismiss(); game.get_tree().paused = false
	game._set_camera_mode(false)
	if not game._can_reuse_world(): await game._start_game(game.game_folder)
	if not game.pilot_mode: game.loading_save = false; return false
	game._reset_loaded_world()
	var port: Dictionary = {}
	for candidate in game.docking.ports:
		if int(candidate.node.get_meta("city_id")) == int(data.dock.id): port = candidate; break
	if port.is_empty():
		game.loading_save = false; game._show_main_menu(); game.dock_interface.open("load"); game.dock_interface.report("The saved dock is unavailable."); return false
	game.docking.current = port; game.docking.saved_collision_mask = game.pilot.collision_mask
	game.pilot.active = false; game.pilot.controls_enabled = false; game.pilot.collision_mask = 0
	game.pilot.global_transform = MapDocument.decode(data.pose); game.pilot.global_position = port.inside
	game.pilot.velocity = Vector3.ZERO; game.pilot.angular_velocity = Vector3.ZERO
	game.pilot.pending_reset = false
	game.pilot.visual.visible = false; game.pilot.reset_visual_history()
	# A restored save has no approach-camera position to reuse. Place it at
	# launch height, behind/right of the upright sub, above the dock's roof.
	var launch_basis = Docking.upright_basis(game.pilot.global_basis)
	var launch_distance = maxf(2.0,float(game.pilot.movement.settings.camera_distance))
	game.docking.cinematic_camera = port.entry + launch_basis.z * launch_distance + launch_basis.x * launch_distance * 0.3
	game.camera.global_position = game.docking.cinematic_camera
	game.camera.look_at(game.pilot.global_position + Vector3.UP * 0.35,Vector3.UP)
	game.docking._set_open(0); port.collision.collision_layer = 1; game.docking._transition(Docking.Stage.DOCKED)
	game.day_night.hour = float(data.hour); game._update_daylight()
	game.equipment.set_installed(data.equipment.map(func(item: Dictionary) -> String: return str(item.id)))
	game.weapons.set_installed(data.weapons)
	for item in data.equipment:
		for index in range(game.equipment.mounted.size()):
			if game.equipment.mounted[index].id == item.id:
				game.equipment.mounted[index].enabled = item.enabled
				if item.id == data.get("equipment_selected",""): game.equipment.selected = index
	game.equipment.apply_settings()
	for index in range(game.weapons.mounted.size()):
		if game.weapons.mounted[index].id == data.get("weapon_selected",""): game.weapons.selected = index
	if game._exploration_matches_map(data.map_signature):
		var bytes := Marshalls.base64_to_raw(data.explored)
		game.cockpit_hud.map_data.explored = Image.create_from_data(HUD.Map.RESOLUTION,HUD.Map.RESOLUTION,false,Image.FORMAT_L8,bytes)
		game.cockpit_hud.map_data.exploration_texture.update(game.cockpit_hud.map_data.explored)
		game.cockpit_hud.map_data.last_explored = Vector2(INF,INF)
	else: game.cockpit_hud.map_data.reset_exploration()
	game.has_started_game = true; game.front_end.can_resume = true
	if data.has("objects"): game.object_population.restore_snapshot(data.objects)
	game.player_progress = PlayerProgress.restore(data.get("progress",{}))
	game._collect_city_deliveries(int(game.docking.current.node.get_meta("city_id")))
	game.equipment.vacuum.storage.assign(game.player_progress.suckomat)
	game.equipment.vacuum.transfer_to(game.player_progress.cargo)
	game.pilot.hull_rating = float(game.player_progress.status.hull_strength)
	game.pilot.radiation_rating = float(game.player_progress.status.radiation_shield)
	game.pilot.restore_health(100.0,float(game.player_progress.status.shields))
	game.dock_interface.open("home"); game.dock_interface_active = true
	game.get_tree().paused = true
	game.loading_save = false; game._update_mouse_pointer()
	game.events.session_started.emit(true)
	return true

