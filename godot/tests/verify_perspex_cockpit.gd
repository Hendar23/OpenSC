extends "res://tests/test_scene_tree.gd"

const Game = preload("res://game.gd")
const Cockpit = preload("res://perspex_cockpit.gd")
const Storage = preload("res://player_storage.gd")
const Mods = preload("res://mod_registry.gd")
const PilotInput = preload("res://pilot_input.gd")
var checks := 0
var failures := 0

class MovingSub extends Node:
	var pilot: Node3D
	var start: Transform3D
	var elapsed := 0.0

	func _physics_process(delta: float) -> void:
		elapsed += delta
		var turn := Basis.from_euler(Vector3(0.20, 0.7, 0.12) * elapsed)
		pilot.global_transform = start * Transform3D(turn, Vector3(0.7, 0.2, -3.0) * elapsed)


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	Storage.root_override = test_fixture_path("perspex-cockpit")
	Storage.ensure_parent(Storage.preferences_path())
	var config := ConfigFile.new()
	config.set_value("game", "folder", OS.get_environment("OPENSC_TEST_GAME_FOLDER"))
	config.save(Storage.preferences_path())
	var model_instruments := "--model-instruments" in OS.get_cmdline_user_args()
	if model_instruments:
		Mods.initialize(false)
		var ids: Array[String] = ["test-3d-map-instrument"]
		Mods.apply(ids, ids, false)
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete, "OpenSC starts with the cockpit controls")
	if not game.startup_complete: quit(1); return
	var menu = game.front_end.gameplay_menu
	menu.fmvs_enabled = false
	await game._begin_new_game()
	var native := DisplayServer.get_name() != "headless"
	if native:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1920,1080)
	game.pilot.freeze = true
	game.pilot.set_physics_process(false)
	game.pilot.reset_physics_interpolation()
	var cockpit = game.perspex_cockpit
	var hud = game.cockpit_hud
	check(cockpit.hull != null and cockpit.hull.get_meta("asset_source").get_file().to_upper() == "SUB.DFF",
		"The cockpit uses the original player asset")
	var retained_surfaces := 0
	for mesh: MeshInstance3D in cockpit.hull.find_children("*", "MeshInstance3D", true, false):
		for i in range(mesh.mesh.get_surface_count()):
			retained_surfaces += 1
			check(not mesh.get_active_material(i).get_meta("exterior_canopy", false), "No exterior glazing in the cockpit model")
	check(retained_surfaces == 7, "Original hull, console and assemblies remain")
	var authored := ConfigFile.new()
	authored.load("res://view_defaults.cfg")
	var matches_authored := true
	for key in Cockpit.DEFAULTS:
		var value: Variant = authored.get_value("view", "cockpit_" + key, Cockpit.DEFAULTS[key])
		matches_authored = matches_authored and (game.cockpit_tuning[key] == value if value is bool
			else is_equal_approx(game.cockpit_tuning[key], float(value)))
	check(matches_authored, "Cockpit starts with the current authored tuning")
	check(game.developer_tabs.find_child("Cockpit", false, false) != null and game.cockpit_controls.size() == 8,
		"Glass and seat tuning have their own F1 tab")
	game._set_camera_mode(false)
	var third_person_layout := hud_rects(hud)
	check(third_person_layout.size() == 5, "Third person displays all five instruments")
	if native: await capture("third-person")
	game._set_camera_mode(true)
	check(cockpit.visible and not hud.holder.visible and hud.mounted_panels.size() == 5,
		"First person renders five fixed cockpit mounts")
	var mounts := mounted_poses(hud)
	var original_eye: Transform3D = cockpit.global_transform.affine_inverse() * game.camera.global_transform
	var neutral_projection := mounted_centres(hud, game.camera)
	var model: Node3D
	if model_instruments:
		model = hud.model_views[2].get_meta("instrument_model")
		check(hud.model_views.size() == 5 and model.get_parent() == hud.mounted_panels[2]
			and hud.model_views[2].render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"First person renders the actual replacement mesh at its mount")
		var rigid_models := true
		for view: SubViewport in hud.model_views:
			var instrument: Node3D = view.get_meta("instrument_model")
			var basis := instrument.basis
			rigid_models = rigid_models and instrument.get_world_3d() == game.camera.get_world_3d()
			rigid_models = rigid_models and basis.get_scale().is_equal_approx(Vector3.ONE * basis.x.length())
			rigid_models = rigid_models and basis.orthonormalized().scaled(Vector3.ONE * basis.x.length()).is_equal_approx(basis)
			for mesh: MeshInstance3D in instrument.find_children("*", "MeshInstance3D", true, false):
				rigid_models = rigid_models and mesh.layers == Cockpit.RENDER_LAYER
		check(rigid_models and hud.mounted_root.get_parent() == cockpit,
			"The normal camera renders uniformly scaled instrument meshes parented to the cockpit")
	else:
		check(hud.mounted_sprites.size() == 5 and hud.displays[2].get_parent() == hud.mounted_sprites[2],
			"Stock instruments retain their live sprite artwork at the same mounts")
	verify_replay_registration(game)
	check(game.camera.position.is_finite() and game.camera.global_position.is_equal_approx(game.pilot.global_transform * cockpit.eye_position()),
		"Camera uses the approved position relative to the hull")
	check(game.pilot.is_physics_interpolated() and not cockpit.is_physics_interpolated(),
		"The render-frame cockpit does not inherit a second interpolation pass")
	if native:
		check(cockpit.redirected and cockpit.source_camera.cull_mask & Cockpit.RENDER_LAYER == 0,
			"Wide refraction view captures the world without the foreground cockpit")
		check(cockpit.source_view.canvas_cull_mask == 0 and hud.mounted_root.get_viewport() == game.camera.get_viewport() and hud.mounted_root.visible,
			"Refraction samples the scene without the shared HUD canvas")
		await capture("forward")
		await verify_mounted_image(game, third_person_layout)
		await verify_moving_cockpit(game)
	var seat_settings := {"sideways": 0.30, "height": -0.20, "forward": 0.50}
	for key in seat_settings:
		game.cockpit_controls[key].value = seat_settings[key]
	game._update_follow_camera(0.0, true)
	check(mounted_poses(hud) == mounts and not (cockpit.global_transform.affine_inverse() * game.camera.global_transform).is_equal_approx(original_eye)
		and mounted_centres(hud, game.camera) != neutral_projection,
		"Seat adjustments move the eye while the instrument mounts stay fixed")
	var model_pose := model.transform if model != null else Transform3D.IDENTITY
	var seat_projection := mounted_centres(hud, game.camera)
	var sub_pose := game.pilot.global_transform
	var forward_mark: Vector2 = game.first_person_crosshair.aim_screen_position()
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.pressed = true
	game._input(button)
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(122.0, -17.0)
	game._input(motion)
	game._update_follow_camera(0.0, true)
	var turned_mark: Vector2 = game.first_person_crosshair.aim_screen_position()
	check(game.game_camera.freelook and not game.camera.global_basis.is_equal_approx(sub_pose.basis),
		"Right mouse rotates the view")
	check(game.pilot.global_transform.is_equal_approx(sub_pose) and mounted_poses(hud) == mounts
		and (model == null or model.transform == model_pose),
		"Freelook leaves the sub, instrument mounts and model transforms unchanged")
	check(hud.mounted_root.get_parent() == cockpit
		and mounted_centres(hud, game.camera) != seat_projection,
		"Only the viewing camera changes the projected position of the fixed instruments")
	check(turned_mark.is_finite() and turned_mark.distance_to(forward_mark) > 50.0,
		"The hull-aligned crosshair moves away from screen centre as the head turns")
	if native:
		await capture("freelook")
		var bend: float = game.cockpit_controls["bend"].value
		game.cockpit_controls["bend"].value = 0.0
		await capture("clear-glass")
		game.cockpit_controls["bend"].value = bend
		check(mounted_poses(hud) == mounts, "Changing glass refraction leaves every instrument mount fixed")
	button.pressed = false
	game._input(button)
	var recentering := true
	for frame in range(48):
		game._update_follow_camera(1.0 / 60.0, true)
		recentering = recentering and mounted_poses(hud) == mounts and hud.mounted_root.visible
	check(not game.game_camera.freelook and game.camera.global_basis.is_equal_approx(sub_pose.basis),
		"Releasing right mouse recentres the view")
	check(recentering and game.camera.global_basis.is_equal_approx(cockpit.global_basis),
		"The eye recentres while the mounts stay fixed on every frame")
	verify_stick_freelook(game)
	verify_damage_shake(game, "3D cockpit")
	if native:
		game.cockpit_controls["reflections"].button_pressed = true
		for i in range(14): await RenderingServer.frame_post_draw
		check(cockpit.reflection_capture != null and cockpit.glass.get_shader_parameter("reflection_ready"),
			"F1 enables live Perspex reflections")
		game.cockpit_controls["reflections"].button_pressed = false
		for i in range(3): await RenderingServer.frame_post_draw
		check(not cockpit.glass.get_shader_parameter("reflection_ready"), "F1 turns off Perspex reflections independently")
	hud.set_enabled(0, false, false)
	check(not hud.mounted_panels[0].visible, "Existing instrument toggle hides the forward panel")
	hud.set_enabled(0, true, false)
	check(hud.mounted_panels[0].visible, "Existing instrument toggle restores the forward panel")
	menu.cockpit_3d_button.pressed.emit()
	check(not menu.cockpit_3d_enabled and not cockpit.visible and hud_rects(hud) == third_person_layout,
		"General options restore the classic camera and screen-fixed HUD")
	check(game.camera.global_position.is_equal_approx(game.pilot.global_transform * game.cockpit_camera_offset),
		"Classic view restores the old eye position")
	verify_damage_shake(game, "Classic cockpit")
	if native: await capture("classic")
	menu.cockpit_3d_button.pressed.emit()
	game.cockpit_controls["forward"].value = 0.50
	game._update_follow_camera(0.0, true)
	check(is_equal_approx(game._view_settings()["cockpit_forward"], 0.50) and
		game.camera.global_position.is_equal_approx(game.pilot.global_transform * cockpit.eye_position()),
		"F1 tuning updates the live camera and participates in settings export")
	if native: await verify_solar_flare(game)
	game._set_map_open(true)
	cockpit.refresh()
	check(not cockpit.visible and not cockpit.redirected, "Map view releases cockpit rendering")
	game._set_map_open(false)
	await verify_wall_collision_shake(game)
	game._set_camera_mode(false)
	check(not cockpit.visible and (game.camera.cull_mask & game.SUB_RENDER_LAYER) != 0, "Third person restores the exterior hull")
	game.queue_free()
	await process_frame
	print("Perspex cockpit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func verify_damage_shake(game: Node3D, label: String) -> void:
	const FRAME := 1.0 / 60.0
	game._process(FRAME)
	var view: Transform3D = game.camera.global_transform
	var hull: Transform3D = game.pilot.global_transform
	var mounts := mounted_poses(game.cockpit_hud)
	var aim: Transform3D = game.game_camera.aim_pose()
	var health: float = game.pilot.health
	var capacity: float = game.pilot.max_health
	game.pilot.take_damage(2.0, Vector3.ZERO, false)
	game._process(FRAME)
	var light_hit: Basis = game.camera.global_basis
	check(not light_hit.is_equal_approx(view.basis) and game.camera.global_position.is_equal_approx(view.origin),
		label + " kicks the view around the pilot's eye on actual hull damage")
	check(game.pilot.global_transform.is_equal_approx(hull) and mounted_poses(game.cockpit_hud) == mounts
		and game.game_camera.aim_pose().is_equal_approx(aim), label + " keeps the hull, instruments and aim fixed")
	var cockpit = game.perspex_cockpit
	if cockpit.redirected:
		cockpit.refresh()
		check(cockpit.source_camera.global_transform.is_equal_approx(game.camera.global_transform),
			"Perspex refraction follows the same shake as the cockpit view")
	for frame in range(36): game._process(FRAME)
	check(game.camera.global_transform.is_equal_approx(view), label + " settles back to the exact seat pose")
	game.pilot.take_damage(18.0, Vector3.ZERO, false)
	game._process(FRAME)
	var large_hit: Basis = game.camera.global_basis
	check(view.basis.get_rotation_quaternion().angle_to(large_hit.get_rotation_quaternion()) >
		view.basis.get_rotation_quaternion().angle_to(light_hit.get_rotation_quaternion()),
		label + " reacts more strongly to a larger hit")
	paused = true
	game._process(FRAME)
	paused = false
	game.pilot.restore_health(capacity, health)
	game._process(FRAME)
	check(game.camera.global_transform.is_equal_approx(view), label + " clears the shake on pause and stays steady after repair")


func verify_wall_collision_shake(game: Node3D) -> void:
	var pilot = game.pilot
	var wall := StaticBody3D.new()
	wall.collision_layer = 1 << 20
	wall.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 10.0, 10.0)
	collider.shape = box
	wall.add_child(collider)
	root.add_child(wall)
	var start := Vector3(0.0, pilot.surface_height - 12.0, 0.0)
	wall.position = start + Vector3.RIGHT * 2.0
	pilot.collision_mask = wall.collision_layer
	pilot.reset_at(start)
	pilot.freeze = false
	await physics_frame
	var health: float = pilot.health
	pilot.velocity = Vector3.RIGHT * 4.0
	var peak := 0.0
	for frame in range(90):
		await physics_frame
		var aim: Transform3D = game.game_camera.aim_pose()
		peak = maxf(peak, aim.basis.get_rotation_quaternion().angle_to(game.camera.global_basis.get_rotation_quaternion()))
	var loss: float = health - pilot.health
	check(loss > 0.0 and loss < 1.0, "Real wall collision takes a fraction of a shield point")
	check(peak > deg_to_rad(0.6), "A low-damage wall collision visibly jolts the cockpit camera (%.2f degrees)" % rad_to_deg(peak))
	pilot.freeze = true
	wall.free()


func capture(label: String) -> void:
	for i in range(3): await RenderingServer.frame_post_draw
	var path := Storage.root_override.path_join(label + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Captured " + label)


func verify_stick_freelook(game: Node3D) -> void:
	var button := InputEventJoypadButton.new()
	button.device = 7
	button.button_index = JOY_BUTTON_RIGHT_STICK
	button.pressed = true
	game._input(button)
	check(game.game_camera.freelook and game.pilot.freelook_device == button.device
		and not game.game_camera.mouse_freelook and game._desired_mouse_mode() != Input.MOUSE_MODE_CAPTURED,
		"The first right-stick click enables freelook without capturing the mouse")
	button.pressed = false
	game._input(button)
	check(game.game_camera.freelook and game.pilot.freelook_device == button.device,
		"Releasing the stick button leaves freelook active")
	var motion := InputEventJoypadMotion.new()
	motion.device = button.device
	motion.axis = JOY_AXIS_RIGHT_Y
	motion.axis_value = -0.75
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	var before: Transform3D = game.camera.global_transform
	var mounts := mounted_poses(game.cockpit_hud)
	game._update_follow_camera(0.2, true)
	check(game.camera.global_position.is_equal_approx(before.origin) and not game.camera.global_basis.is_equal_approx(before.basis)
		and PilotInput.read(game.pilot.freelook_device).y == 0.0,
		"The stick turns the view without producing vertical thrust while freelook is active")
	check(mounted_poses(game.cockpit_hud) == mounts
		and not game.camera.global_basis.is_equal_approx(game.perspex_cockpit.global_basis),
		"Controller freelook also changes the angle from which the HUD mount is viewed")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check(PilotInput.read(game.pilot.freelook_device).y > 0.9, "Keyboard vertical thrust remains available while looking with the stick")
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)
	button.pressed = true
	game._input(button)
	game._update_follow_camera(1.0, true)
	check(not game.game_camera.freelook and game.pilot.freelook_device < 0
		and game.camera.global_transform.is_equal_approx(before) and PilotInput.read().y > 0.5,
		"The next click recenters the view and restores ordinary stick controls")
	button.pressed = false
	game._input(button)
	check(not game.game_camera.freelook, "Releasing the button after the second click leaves freelook off")
	motion = motion.duplicate() as InputEventJoypadMotion
	motion.axis_value = 0.0
	Input.parse_input_event(motion)
	Input.flush_buffered_events()


func hud_rects(hud: CanvasLayer) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for instrument: Control in hud.instruments:
		if instrument.get_parent() == hud.holder and instrument.is_visible_in_tree():
			rects.append(instrument.get_global_rect())
	return rects


func verify_replay_registration(game: Node3D) -> void:
	var replay: Node3D = game.photo_mode.replay
	var was_enabled: bool = replay.enabled
	replay.set_enabled(true)
	replay.clear()
	replay._start_recording()
	var exterior: MeshInstance3D = game.pilot.visual.find_children("*", "MeshInstance3D", true, false)[0]
	check(replay.tracks.has(exterior.get_instance_id()), "Replay still records the exterior submarine")
	var cockpit_skipped := true
	for mesh: MeshInstance3D in game.perspex_cockpit.find_children("*", "MeshInstance3D", true, false):
		cockpit_skipped = cockpit_skipped and not replay.tracks.has(mesh.get_instance_id())
	check(cockpit_skipped, "Replay skips geometry rendered only by the cockpit camera")
	var archive_before: int = replay.archive_id
	for i in range(4):
		game._set_camera_mode(false)
		game._set_camera_mode(true)
		replay._register_pending()
	check(replay.archive_id == archive_before, "Camera round trips create no archived instrument tracks")
	replay.clear()
	replay.set_enabled(was_enabled)


func mounted_poses(hud: CanvasLayer) -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for panel: Node3D in hud.mounted_panels:
		poses.append(panel.transform)
	return poses


func mounted_centres(hud: CanvasLayer, camera: Camera3D) -> Array[Vector2]:
	var centres: Array[Vector2] = []
	for panel: Node3D in hud.mounted_panels:
		centres.append(camera.unproject_position(panel.global_position))
	return centres


func verify_mounted_image(game: Node3D, frames: Array[Rect2]) -> void:
	var hud: CanvasLayer = game.cockpit_hud
	var with_instruments := root.get_texture().get_image()
	hud.set_process(false)
	for panel: Node3D in hud.mounted_panels: panel.hide()
	for i in range(3): await RenderingServer.frame_post_draw
	var without_instruments := root.get_texture().get_image()
	for panel: Node3D in hud.mounted_panels: panel.show()
	hud.set_process(true)
	for i in frames.size():
		var area := Rect2i(root.get_stretch_transform() * frames[i])
		var changed := 0
		for y in range(area.position.y, area.end.y, 4):
			for x in range(area.position.x, area.end.x, 4):
				var difference := with_instruments.get_pixel(x, y) - without_instruments.get_pixel(x, y)
				if absf(difference.r) + absf(difference.g) + absf(difference.b) > 0.18: changed += 1
		check(changed > 100, "Instrument %d is visible through the normal cockpit camera (%d changed samples)" % [i + 1, changed])

func verify_moving_cockpit(game: Node3D) -> void:
	var driver := MovingSub.new()
	driver.pilot = game.pilot
	driver.start = game.pilot.global_transform
	game.add_child(driver)
	var cockpit: Node3D = game.perspex_cockpit
	var expected := mounted_poses(game.cockpit_hud)
	var aligned := true
	for frame in range(36):
		await RenderingServer.frame_pre_draw
		var view: Transform3D = game.camera.global_transform
		aligned = aligned and mounted_poses(game.cockpit_hud) == expected
		aligned = aligned and view.is_equal_approx(cockpit.global_transform * Transform3D(Basis.IDENTITY, cockpit.eye_position()))
		aligned = aligned and cockpit.source_camera.global_transform.is_equal_approx(view)
	check(driver.elapsed > 0.1 and aligned,
		"Turning and moving preserve the HUD layout and keep refraction aligned with the eye on every draw")
	game.pilot.global_transform = driver.start
	driver.free()
	game.pilot.reset_physics_interpolation()
	game._update_follow_camera(0.0, true)


func verify_solar_flare(game: Node3D) -> void:
	const Flare = preload("res://lens_flare.gd")
	game.set_process(false)
	game.day_night.hour = 11.0
	game._update_daylight()
	var sun: Vector3 = game.sun.global_basis.z
	var lateral := Vector3(sun.x, 0.0, sun.z) / 1.25
	var apparent_sun := lateral + Vector3.UP * sqrt(1.0 - lateral.length_squared())
	game.pilot.global_position.y = game.pilot.surface_height - 2.0
	game.pilot.global_basis = Basis.looking_at((apparent_sun + Vector3(0.15, -0.17, 0.04)).normalized(), Vector3.UP)
	game.pilot.reset_physics_interpolation()
	game._update_follow_camera(0.0, true)
	Flare.set_enabled(false)
	await capture("sun-flare-off")
	var plain := root.get_texture().get_image()
	Flare.set_enabled(true)
	await capture("sun-flare-on")
	var lit := root.get_texture().get_image()
	var darker := 0
	var brighter := 0
	var sample_step := Vector2i(maxi(roundi(lit.get_width() / 160.0), 1), maxi(roundi(lit.get_height() / 90.0), 1))
	for y in range(lit.get_height() / 4, lit.get_height() * 9 / 10, sample_step.y):
		for x in range(0, lit.get_width(), sample_step.x):
			var delta := lit.get_pixel(x, y).get_luminance() - plain.get_pixel(x, y).get_luminance()
			if delta < -0.20: darker += 1
			if delta > 0.03: brighter += 1
	print("Solar flare samples: %d brighter, %d substantially darker" % [brighter, darker])
	check(brighter > 20 and darker < 35, "The sun adds a visible flare without darkening a rectangle around it")
	game.set_process(true)
