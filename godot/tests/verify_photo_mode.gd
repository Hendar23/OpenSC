extends "res://tests/verify_remaining_stage_two.gd"
const Bindings = preload("res://input_bindings.gd")
class FixtureCapture extends "res://capture_overlay.gd":
	func screenshot_folder() -> String: return ProjectSettings.globalize_path("res://../.local/photo-mode-captures")
class ClockProbe extends Node:
	var elapsed := 0.0
	func _process(delta: float) -> void: elapsed += delta

func button(code: int, pressed: bool = true) -> void:
	var event := InputEventJoypadButton.new(); event.device = 77; event.button_index = code; event.pressed = pressed
	root.push_input(event,true)

func key(code: int) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true; root.push_input(event,true)

func run() -> void:
	Bindings.install(); var original := Bindings.bindings.duplicate(true); Bindings.reset_defaults()
	check(Bindings.bindings.photo_mode[1].button == JOY_BUTTON_BACK and Bindings.bindings.photo_mode[0].code == KEY_P,"Photo mode defaults to controller View and keyboard P")
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Game loads for photo mode")
	if not game.startup_complete: quit(1); return
	var photo: Node3D = game.photo_mode
	check(not photo.enter(),"Title/menu state cannot activate photo mode")
	await game._begin_new_game()
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	await fresh("escort")
	jobs.set_physics_process(true); game.pilot.freeze = false; game.pilot.set_physics_process(true)
	for agent in jobs.vessels: agent.running = true; agent.set_physics_process(true)
	game.set_process(true); game.docking.set_physics_process(true)
	for frame in range(4): await physics_frame
	game.capture_overlay.free(); game.capture_overlay = FixtureCapture.new(); game.add_child(game.capture_overlay)
	game.capture_overlay.fps_label.show()
	var hidden := CanvasLayer.new(); hidden.name = "HiddenBeforePhoto"; game.add_child(hidden); hidden.hide()
	var clock := ClockProbe.new(); clock.process_mode = Node.PROCESS_MODE_ALWAYS; game.add_child(clock)
	game._set_camera_mode(true)
	var pose: Transform3D = game.pilot.global_transform; var velocity: Vector3 = game.pilot.linear_velocity
	var camera_pose: Transform3D = game.camera.global_transform; var cull: int = game.camera.cull_mask
	var hour: float = game.day_night.hour; var elapsed: float = jobs.remaining.elapsed
	var npc_pose: Transform3D = jobs.remaining.ship.get_parent().global_transform
	var credits: float = game.player_progress.status.credits
	var status: Dictionary = game._save_snapshot("Photo boundary")
	button(JOY_BUTTON_BACK); button(JOY_BUTTON_BACK,false)
	check(photo.active and paused and photo.view.current,"Controller View enters a paused free camera")
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,"Photo camera captures the mouse without displaying a cursor")
	check(not game.camera.current and photo.view.global_transform.is_equal_approx(camera_pose),"Free camera starts exactly at the existing view")
	check((photo.view.cull_mask & game.SUB_RENDER_LAYER) != 0 and (photo.view.cull_mask & preload("res://first_person_cockpit.gd").RENDER_LAYER) == 0,"Photo camera sees player hull and excludes camera-local canopy")
	check(game.find_children("*","CanvasLayer",true,false).all(func(layer: CanvasLayer) -> bool: return not layer.visible),"All HUD, mission, radio, FPS and other UI layers are hidden")
	check(photo.find_children("*","Control",true,false).is_empty(),"Photo mode creates no on-screen instructions or controls")
	for frame in range(20): await process_frame
	check(game.pilot.global_transform.is_equal_approx(pose) and game.pilot.linear_velocity.is_equal_approx(velocity),"Player position and momentum stay frozen")
	check(jobs.remaining.ship.get_parent().global_transform.is_equal_approx(npc_pose) and jobs.remaining.elapsed == elapsed,"NPC movement and mission timers stay frozen")
	check(game.day_night.hour == hour and game.player_progress.status.credits == credits,"World clock and economy do not advance")
	check(clock.elapsed == 0,"Controllers that normally run while paused are frozen too")
	var start: Vector3 = photo.view.global_position
	photo.move(Vector3(1,0,-1),1,0.5); photo.look(Vector2(0.3,-0.2))
	check(photo.view.global_position.distance_to(start) > 1 and not photo.view.global_basis.is_equal_approx(camera_pose.basis),"Camera translates and looks freely while simulation is paused")
	check(game.camera.global_transform.is_equal_approx(camera_pose),"Free movement never changes the gameplay camera")
	if DisplayServer.get_name() != "headless":
		# Controller capture uses the screenshot system without a text overlay.
		button(JOY_BUTTON_A); button(JOY_BUTTON_A,false)
		for frame in range(60):
			if not game.capture_overlay.last_screenshot.is_empty(): break
			await process_frame
		check(FileAccess.file_exists(game.capture_overlay.last_screenshot) and not game.capture_overlay.screenshot_label.visible,"Controller capture writes a clean screenshot without a notification")
		check(game.capture_overlay.shutter.playing and game.capture_overlay.shutter.stream.get_length() > 0 and game.capture_overlay.shutter.process_mode == Node.PROCESS_MODE_ALWAYS,"Requested shutter sound plays while photo mode keeps the game paused")
		game.capture_overlay.last_screenshot = ""; key(KEY_F12)
		for frame in range(60):
			if not game.capture_overlay.last_screenshot.is_empty(): break
			await process_frame
		check(photo.active and FileAccess.file_exists(game.capture_overlay.last_screenshot) and not game.capture_overlay.screenshot_label.visible,"Existing keyboard screenshot binding also works without an overlay while paused")
		check(game.capture_overlay.shutter.playing and game.capture_overlay.shutter.bus == &"Effects","Keyboard screenshots replay the shutter through the normal effects-volume bus")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../.local/photo-mode-native.png")
	button(JOY_BUTTON_BACK); button(JOY_BUTTON_BACK,false)
	check(not photo.active and not paused and game.camera.current,"View exits photo mode and resumes the original camera")
	check(game.camera.global_transform.is_equal_approx(camera_pose) and game.camera.cull_mask == cull and game.first_person,"First-person pose, culling and camera mode restored")
	check(game.cockpit_hud.visible and game.capture_overlay.visible and game.capture_overlay.fps_label.visible and not hidden.visible,"Visible and previously hidden UI states restored exactly")
	check(game.process_mode == Node.PROCESS_MODE_ALWAYS and jobs.process_mode != Node.PROCESS_MODE_DISABLED,"Normal processing modes restored")
	check(clock.process_mode == Node.PROCESS_MODE_ALWAYS,"Always-running controllers regain their original mode")
	check(game.pilot.linear_velocity.is_equal_approx(velocity),"Exit preserves original submarine momentum")
	var after: Dictionary = game._save_snapshot("Photo boundary")
	status.erase("saved_at"); after.erase("saved_at")
	check(after == status,"Photo mode changes no save-game state")
	game._set_camera_mode(false); key(KEY_P)
	check(photo.active,"Keyboard P can enter from third person")
	key(KEY_ESCAPE)
	check(not photo.active and not paused and not game.front_end.menu_layer.visible,"Escape leaves photo mode without opening a hidden menu")
	Bindings.set_binding("photo_mode",1,{"kind":"button","button":JOY_BUTTON_LEFT_STICK,"modifier":-1})
	button(JOY_BUTTON_BACK); button(JOY_BUTTON_BACK,false)
	check(not photo.active,"Remapping photo mode removes the former controller binding")
	button(JOY_BUTTON_LEFT_STICK); button(JOY_BUTTON_LEFT_STICK,false)
	check(photo.active,"Remapped controller button activates photo mode")
	button(JOY_BUTTON_LEFT_STICK); button(JOY_BUTTON_LEFT_STICK,false)
	Bindings.reset_defaults()
	game.map_open = true; check(not photo.enter(),"Map blocks photo entry"); game.map_open = false
	game.developer_ui_visible = true; check(not photo.enter(),"Developer panel blocks photo entry"); game.developer_ui_visible = false
	game.docking.stage = game.Docking.Stage.DOCKED; check(not photo.enter(),"Docked screen blocks photo entry"); game.docking.stage = game.Docking.Stage.IDLE
	game.pilot.dead = true; check(not photo.enter(),"Death blocks photo entry"); game.pilot.dead = false
	Bindings.capture_active = true; check(not photo.enter(),"Binding assignment cannot activate photo mode"); Bindings.capture_active = false
	check(photo.enter(),"Photo mode can be entered repeatedly")
	game._show_main_menu()
	check(not photo.active and paused and game.front_end.menu_layer.visible,"Programmatic menu transitions restore photo state before opening the menu")
	game._resume_game()
	check(photo.enter(),"Photo mode remains available after returning from the menu")
	Bindings.bindings = original; Bindings.apply_all()
	for path in ["res://photo_mode.gd","res://tests/verify_photo_mode.gd"]:
		if not FileAccess.file_exists(path+".uid"):
			var file := FileAccess.open(path+".uid",FileAccess.WRITE); file.store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	game.free()
	check(not paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"Removing the scene from photo mode releases pause and the captured pointer")
	await process_frame
	print("Photo mode: %d/%d checks passed" % [checks-failures,checks]); quit(1 if failures else 0)
