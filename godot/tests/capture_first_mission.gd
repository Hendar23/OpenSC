extends SceneTree
func _initialize() -> void:
	var storage = preload("res://player_storage.gd"); storage.root_override = "res://tests/cache-mission-fixtures"
	call_deferred("run")
func capture(name: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/cache-mission-fixtures/" + name + ".png")
func run() -> void:
	var game := preload("res://game.gd").new(); game.remember_preferences = false; game.show_start_menu = true; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await process_frame
	game._begin_new_game()
	for port in game.docking.ports:
		if int(port.node.get_meta("city_id")) == 1: game.docking.current = port
	game.docking.stage = game.Docking.Stage.DOCKED; game.dock_interface_active = true; paused = true
	game.dock_interface.open("missions"); await capture("mission-board")
	game.dock_interface.layout.get_node("choose_mission").pressed.emit(); await capture("mission-selected")
	var accept := game.dock_interface.layout.get_node("accept_mission") as Button
	accept.button_down.emit(); await capture("mission-accept-pressed"); accept.button_up.emit()
	game.mission_runtime.accept(1); game.dock_interface.rebuild(); await capture("mission-active")
	game.dock_interface.open("home"); await capture("mission-no-save")
	game.dock_interface.open("load"); await capture("mission-autosave")
	game.mission_runtime.docked(6); game.player_progress.cargo.thorium = 1; game.mission_runtime.docked(1)
	game.dock_interface.open("missions")
	var deadline := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline: await process_frame
	await capture("mission-complete")
	game.mission_runtime.outcome.dismiss()
	game.player_progress = preload("res://player_progress.gd").restore(); game.mission_runtime.accept(1); game.mission_runtime.finish(false)
	deadline = Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < deadline: await process_frame
	await capture("mission-failed")
	game.free(); quit()
