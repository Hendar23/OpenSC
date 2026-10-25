extends RefCounted
## Frame orchestration, docking request, and submarine destruction.

var game: Node3D

func _init(context: Node3D) -> void:
	game = context

const Docking = preload("res://docking_controller.gd")
const SessionExplosion = preload("res://mine_explosion.gd")

func _process(delta: float) -> void:
	var in_dock_menu: bool = game.docking != null and game.docking.stage == Docking.Stage.DOCKED and game.dock_interface_active and game.dock_interface.visible and game.dock_interface.page != "load"
	if in_dock_menu and is_instance_valid(game.submarine_traffic):
		game.submarine_traffic.replenish_docked(delta)
	if game.pilot_mode and not game.world_loading and not game.front_end.menu_layer.visible and (not game.get_tree().paused or in_dock_menu):
		preload("res://commodity_market.gd").advance(game.gameplay_catalogue,game.player_progress,delta * game.market_speed_slider.value / 100.0)
		game.market_ui_elapsed += delta
		if game.market_ui_elapsed >= 0.3:
			game.market_ui_elapsed = 0.0
			if game.dock_interface_active and game.dock_interface.visible and game.dock_interface.page == "goods": game.dock_interface.refresh_market()
	game._update_mouse_pointer()
	if game.radio_feed != null: game.radio_feed.visible = game.pilot_mode and not game.world_loading and not game.get_tree().paused and not game.front_end.menu_layer.visible
	if game.get_tree().paused or game.world_loading or game.loading_save: return
	game.particles.active = game.pilot_mode and not game.world_loading
	if game.pilot_mode and not game.world_loading and not game.developer_ui_visible: game.day_night.step(delta)
	game._update_daylight()
	if not game.pilot_mode: return
	if not game.world_loading: game.plant_current.update_wash(game.pilot,delta)
	if game.docked_screen != null:
		game.docked_screen.visible = game.docking.stage == Docking.Stage.DOCKED
		if game.docked_screen.visible and not game.front_end.menu_layer.visible:
			if not game.dock_interface_active:
				game.equipment.vacuum.transfer_to(game.player_progress.cargo)
				game._collect_city_deliveries(int(game.docking.current.node.get_meta("city_id")))
				game.dock_interface.open("home"); game.dock_interface_active = true
				game._autosave_docked()
			elif not game.dock_interface.visible: game.dock_interface.show()
			game.get_tree().paused = true
		elif game.docking.stage != Docking.Stage.DOCKED and game.dock_interface_active:
			game.dock_interface.dismiss(); game.dock_interface_active = false
	if game.docking != null and game.docking.camera_frozen():
		game.camera.global_position = game.docking.cinematic_camera
		var target: Vector3 = game.pilot.get_global_transform_interpolated().origin + Vector3.UP * 0.35
		if game.camera.global_position.distance_to(target) > 0.01: game.camera.look_at(target, Vector3.UP)
		game.camera_was_frozen = true
	else:
		if game.camera_was_frozen:
			game.camera_follow.resume(game.camera.global_position, game.pilot.get_global_transform_interpolated().origin + Vector3.UP * 0.35)
			game.camera_was_frozen = false
		game._update_follow_camera(delta)
	game._update_radio_messages(delta)
	if game.developer_ui_visible:
		var state: RefCounted = game.pilot.movement
		game.telemetry.text = "Speed: %.2f · Vertical: %.2f units/s\nPod tilt: %.1f° · Hull pitch: %.1f°\nDocking limit: %.2f units/s" % [state.velocity.length(), state.velocity.y, rad_to_deg(state.tilt), rad_to_deg(asin(clampf(-game.pilot.global_basis.z.y, -1.0, 1.0))), game.docking.maximum_docking_speed()]

func _request_docking() -> void:
	if game.pilot.dead: return
	var launching: bool = game.docking.stage == Docking.Stage.DOCKED
	if game.docking.request_docking():
		if game.first_person:
			game._set_camera_mode(false)
			if not launching: game.docking.cinematic_camera = game.camera.global_position
		if launching: game.camera.global_position = game.docking.cinematic_camera

func _submarine_health_changed(remaining: float, capacity: float) -> void:
	game.player_progress.status.shields = int(round(remaining / capacity * 100.0))

func _submarine_destroyed() -> void:
	game.mission_runtime.finish(false)
	game.mission_runtime.outcome.play_game_over(game.game_folder)
	game._set_map_open(false)
	game.weapons.update_fire(false,0)
	var wreck := preload("res://submarine_death.gd").new(); game.world_root.add_child(wreck)
	wreck.global_position = game.pilot.global_position
	var mounts: Array[Node3D] = [game.weapons.muzzle]
	for item in game.equipment.mounted: mounts.append(item.mount)
	wreck.setup_submarine(game.pilot,game.submarine_bubble_texture,mounts)
	var burst := SessionExplosion.new(); game.world_root.add_child(burst); burst.global_position = game.pilot.global_position
	burst.setup(game.submarine_explosion_frames,maxf(1.0,game.pilot.collision_height() * 3.0),game.submarine_explosion_sound)
	game.equipment.reset_towing()
	game.weapons.hide(); game.equipment.hide()
	game._set_camera_mode(false)
