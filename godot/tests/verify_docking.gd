extends SceneTree

const Game = preload("res://game.gd")
const Docking = preload("res://docking_controller.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func advance(controller: Node, expected: int) -> void:
	for frame in range(2000):
		if controller.stage == expected: break
		controller._physics_process(0.1)
	check(controller.stage == expected, "Docking reaches stage %d" % expected)

func _run() -> void:
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete, "Game starts with docking available")
	if game.docking == null:
		quit(1)
		return
	game.set_process(false)
	game.set_physics_process(false)
	game.pilot.set_physics_process(false)
	game.pilot.freeze = true
	var controller: Node = game.docking
	controller.set_physics_process(false)
	var audio: Node = controller.audio
	var finishes: Array[int] = []
	audio.door_finished.connect(func() -> void: finishes.append(controller.stage))
	for role in audio.SAMPLES:
		var stream: AudioStreamWAV = audio.players[role].stream
		check(stream != null and stream.mix_rate == 11025 and stream.get_meta("asset_source").ends_with(audio.SAMPLES[role] + ".RAW"), "Docking sample %s uses the requested original sound" % role)
		check(stream.loop_mode == (AudioStreamWAV.LOOP_FORWARD if role == "sequence" else AudioStreamWAV.LOOP_DISABLED), "Only the docking background loops")
	check(audio.players.values().all(func(p: AudioStreamPlayer) -> bool: return not p.playing), "Idle docking audio is silent")
	check(controller.ports.size() == 6, "Six original city ports registered")
	check(game.pilot.visual.scale.is_equal_approx(Vector3.ONE * 0.8) and game.pilot.get_node("HullCollision").shape is ConvexPolygonShape3D and game.pilot.collision_parts.size() >= 5, "Ship keeps its visual scale and uses separate fitted hull and pod shapes")
	game.pilot.movement.settings.forward_speed = 4.6
	check(is_equal_approx(controller.maximum_docking_speed(), 4.6 * 2.0 / 3.0), "Docking permission uses two-thirds of configured forward speed")
	game.pilot.movement.settings.forward_speed = 6.0
	check(is_equal_approx(controller.maximum_docking_speed(), 4.0), "Docking speed limit updates with live speed tuning")
	game.pilot.movement.settings.forward_speed = 4.6
	game.pilot.position = Vector3(120.0, 120.0, 120.0)
	controller.update_approach()
	check(controller.message.is_empty() and not controller.request_docking(), "Cannot dock away from a port")
	var port_index := 0
	game.docking_radius_slider.value = 2.0
	game.pilot.velocity = Vector3.ZERO
	game.pilot.global_position = controller.ports[0].entry + Vector3.RIGHT * 2.1
	controller.update_approach()
	check(controller.message.is_empty() and not controller.request_docking(), "Docking stays unavailable outside the configured radius")
	game.pilot.global_position = controller.ports[0].entry + Vector3.RIGHT * 1.9
	controller.update_approach()
	check(controller.message.contains("(Y/N)"), "Docking appears close above the port")
	for port in controller.ports:
		var heading := port_index * TAU / 6.0
		game.pilot.global_basis = Basis(Vector3.UP, heading)
		port_index += 1
		game.pilot.global_position = port.entry
		game.pilot.velocity = Vector3(0.0, 0.0, controller.maximum_docking_speed() + 0.1)
		controller.update_approach()
		check(controller.message.to_lower().contains("too fast") and not controller.request_docking(), "Moving too fast shows warning and rejects docking")
		game.pilot.velocity = Vector3.ZERO
		controller.update_approach()
		game._process(0.0)
		check(controller.message.contains("Do you want to dock?") and game.docking_prompt.visible and not game.canvas.visible, "Docking prompt visible with developer UI hidden")
		check(game.docking_portrait.visible and game.docking_portrait.texture.get_size() == Vector2(64, 80), "Original controller portrait appears alongside prompt")
		var camera_position: Vector3 = game.camera.global_position
		var key := InputEventKey.new()
		key.keycode = KEY_Y
		key.pressed = true
		game._unhandled_input(key)
		check(controller.stage == Docking.Stage.ALIGN and not game.pilot.active and game.pilot.collision_mask == 0, "Y starts controlled docking transit")
		var finish_count := finishes.size()
		check(audio.players.sequence.playing and not audio.players.doors.playing, "Docking loop starts on acceptance without premature door sound")
		var continuous_loop: AudioStreamPlayback = audio.players.sequence.get_stream_playback()
		game._process(0.1)
		check(game.camera.global_position.distance_to(camera_position) < 0.00001, "Docking freezes the current camera without snapping")
		check(not controller.request_docking(), "Repeated request cannot restart transit")
		advance(controller, Docking.Stage.OPEN)
		check(game.pilot.global_basis.is_equal_approx(Basis(Vector3.UP, heading)), "Docking retains the approach compass heading")
		check(audio.players.sequence.playing and audio.players.doors.playing, "Door sound starts once on opening")
		advance(controller, Docking.Stage.DESCEND)
		check(not audio.players.doors.playing and audio.players.door_stop.playing and finishes.size() == finish_count + 1, "Opening completion stops doors and plays DOCKSHUT once")
		check(audio.players.sequence.get_stream_playback() == continuous_loop, "Docking background preserves playback phase across animation stages")
		var mesh: MeshInstance3D = port.meshes[0]
		check(is_equal_approx(mesh.get_blend_shape_value(mesh.mesh.get_blend_shape_count() - 1), 1.0) and port.collision.collision_layer == 0, "Original door reaches open pose before descending")
		advance(controller, Docking.Stage.CLOSE)
		check(audio.players.sequence.playing and audio.players.doors.playing, "Door sound starts once when closing begins")
		check(game.pilot.global_position.distance_to(port.inside) < 0.001 and game.pilot.visual.visible, "Submarine remains visible after descending")
		controller._physics_process(0.6)
		check(game.pilot.visual.visible, "Submarine remains visible while hatch closes")
		advance(controller, Docking.Stage.DOCKED)
		game.pilot.submarine_audio.update(0.1)
		check(not audio.players.sequence.playing and not audio.players.doors.playing and audio.players.door_stop.playing and finishes.size() == finish_count + 2, "Closed hatch stops loops while DOCKSHUT remains audible behind hidden hull")
		controller._physics_process(5.0)
		check(finishes.size() == finish_count + 2, "Docked idle does not replay the door completion sound")
		check(not game.pilot.visual.visible, "Submarine hides only after hatch fully closes")
		check(port.collision.collision_layer == 1 and is_zero_approx(mesh.get_blend_shape_value(0)), "Dock closes and restores collision")
		check(controller.message.contains("undock") and controller.request_docking(), "Docked player can leave with Y")
		check(audio.players.sequence.playing and audio.players.doors.playing, "Undocking restarts background and opening doors")
		check(game.pilot.visual.visible, "Submarine is present before hatch starts opening")
		controller._physics_process(0.6)
		check(game.pilot.visual.visible, "Submarine remains visible throughout hatch opening")
		advance(controller, Docking.Stage.ASCEND)
		check(audio.players.sequence.playing and not audio.players.doors.playing and finishes.size() == finish_count + 3, "Exit opening finishes with one DOCKSHUT while background continues")
		check(game.pilot.visual.visible, "Submarine becomes visible for departure after opening")
		advance(controller, Docking.Stage.EXIT_CLOSE)
		check(audio.players.sequence.playing and audio.players.doors.playing, "Exit closing starts its door sound while docking background continues")
		check(not controller.camera_frozen(), "Camera releases only after submarine clears the port")
		game._process(0.0)
		check(game.camera.global_position.distance_to(camera_position) < 0.00001, "Camera reattachment begins without a position jump")
		advance(controller, Docking.Stage.IDLE)
		check(game.pilot.global_basis.is_equal_approx(Basis(Vector3.UP, heading)), "Undocking retains the compass heading")
		check(not audio.players.sequence.playing and not audio.players.doors.playing and audio.players.door_stop.playing and finishes.size() == finish_count + 4, "Departure completion stops loops and plays the final DOCKSHUT once")
		check(game.pilot.active and game.pilot.collision_mask == 5 and game.pilot.velocity.is_zero_approx(), "Departure restores piloting and collision without stale velocity")
		check(game.pilot.global_position.distance_to(port.entry) < 0.001 and game.pilot.global_position.y + game.pilot.surface_clearance(game.pilot.global_basis) < game.pilot.surface_height, "Departure ends above port and below water surface")
	controller.request_docking()
	advance(controller, Docking.Stage.DESCEND)
	game._reset_submarine()
	check(audio.players.values().all(func(p: AudioStreamPlayer) -> bool: return not p.playing), "Reset cancels all docking audio")
	check(controller.stage == Docking.Stage.IDLE and game.pilot.active and game.pilot.visual.visible and game.pilot.collision_mask == 5, "Reset safely cancels docking")
	check(is_zero_approx(controller.ports[-1].meshes[0].get_blend_shape_value(1)), "Reset closes the interrupted port")
	game.pilot.global_position = controller.ports[0].entry
	game.pilot.velocity = Vector3.ZERO
	controller.update_approach()
	var decline := InputEventKey.new()
	decline.keycode = KEY_N
	decline.pressed = true
	game._unhandled_input(decline)
	controller.update_approach()
	game._process(0.0)
	check(controller.message.is_empty() and not game.docking_portrait.visible, "N dismisses radio prompt and portrait")
	game.pilot.global_position = Vector3(120, 120, 120)
	controller.update_approach()
	game.pilot.global_position = controller.ports[0].entry
	controller.update_approach()
	check(controller.message.contains("(Y/N)"), "Docking offer returns when approaching again")
	check(controller.radio_messages.get("city23", "").contains("Automatic docking in progress"), "Original docking dialogue decoded from language archive")
	game.pilot.global_position = controller.ports[0].entry
	game.pilot.global_basis = Basis.from_euler(Vector3(0.5, 0.7, 1.0))
	game.pilot.velocity = Vector3(0, 0, controller.maximum_docking_speed())
	check(controller.request_docking(), "Exact permission speed accepts tilted approach")
	advance(controller, Docking.Stage.ALIGN)
	var upright: Basis = Docking.approach_basis(game.pilot.global_basis, game.pilot.global_position, controller.current.entry)
	advance(controller, Docking.Stage.OPEN)
	check(game.pilot.global_basis.is_equal_approx(upright), "Autopilot levels pitch and roll and faces the docking position after settling")
	game._reset_submarine()
	game.pilot.global_position = controller.ports[0].entry + Vector3(1.5, 0.0, 0.0)
	game.pilot.velocity = Vector3(0.8, 0.0, 0.0)
	game.pilot.rotation.y = PI * 0.75
	check(controller.request_docking() and controller.stage == Docking.Stage.SETTLE, "Moving approach settles before alignment")
	var old_velocity: Vector3 = game.pilot.velocity
	controller._physics_process(1.0 / 60.0)
	check((game.pilot.velocity - old_velocity).length() <= 4.0 / 60.0 + 0.0001, "Approach does not instantly erase momentum")
	advance(controller, Docking.Stage.ALIGN)
	var turn_position: Vector3 = game.pilot.global_position
	var stationary_turn := true
	var turning_pods := false
	var peak_turn_speed := 0.0
	var peak_turn_acceleration := 0.0
	var old_turn_rate: float = game.pilot.movement.yaw_velocity
	for frame in range(2000):
		if controller.stage != Docking.Stage.ALIGN: break
		controller._physics_process(1.0 / 60.0)
		stationary_turn = stationary_turn and game.pilot.global_position.distance_to(turn_position) < 0.00001 and game.pilot.velocity.length() < 0.00001
		turning_pods = turning_pods or game.pilot.movement.left_power * game.pilot.movement.right_power < 0.0
		peak_turn_speed = maxf(peak_turn_speed, absf(game.pilot.movement.yaw_velocity))
		peak_turn_acceleration = maxf(peak_turn_acceleration, absf(game.pilot.movement.yaw_velocity - old_turn_rate) * 60.0)
		old_turn_rate = game.pilot.movement.yaw_velocity
	check(stationary_turn and controller.stage == Docking.Stage.APPROACH, "Submarine completes its turn without translating")
	check(turning_pods, "Opposing side propellers animate the turn on the spot")
	var to_port: Vector3 = controller.current.entry - game.pilot.global_position
	var horizontal_to_port := Vector3(to_port.x, 0, to_port.z).normalized()
	check((-game.pilot.global_basis.z).dot(horizontal_to_port) > 0.9999, "Nose faces the docking position before forward travel begins")
	var max_speed := 0.0
	var max_acceleration := 0.0
	var max_horizontal_speed := 0.0
	var max_turn_speed := peak_turn_speed
	var max_turn_acceleration := peak_turn_acceleration
	var previous_turn: float = game.pilot.movement.yaw_velocity
	var previous_velocity: Vector3 = game.pilot.velocity
	var forward_only := true
	var approach_heading: Basis = game.pilot.global_basis
	for frame in range(10000):
		if controller.stage == Docking.Stage.DOCKED: break
		controller._physics_process(1.0 / 60.0)
		if controller.stage == Docking.Stage.APPROACH and game.pilot.velocity.length() > 0.001:
			var horizontal := Vector3(game.pilot.velocity.x, 0, game.pilot.velocity.z).normalized()
			forward_only = forward_only and horizontal.dot(-game.pilot.global_basis.z) > 0.9999
		max_speed = maxf(max_speed, game.pilot.velocity.length())
		max_horizontal_speed = maxf(max_horizontal_speed, Vector2(game.pilot.velocity.x, game.pilot.velocity.z).length())
		max_turn_speed = maxf(max_turn_speed, absf(game.pilot.movement.yaw_velocity))
		max_turn_acceleration = maxf(max_turn_acceleration, absf(game.pilot.movement.yaw_velocity - previous_turn) * 60.0)
		previous_turn = game.pilot.movement.yaw_velocity
		max_acceleration = maxf(max_acceleration, (game.pilot.velocity - previous_velocity).length() * 60.0)
		previous_velocity = game.pilot.velocity
	check(controller.stage == Docking.Stage.DOCKED, "Speed-limited transit completes")
	check(forward_only, "Approach velocity points forward along the nose, with no sideways sliding")
	check(game.pilot.global_basis.is_equal_approx(approach_heading), "Submarine preserves approach heading after reaching the port")
	check(max_speed <= float(game.pilot.movement.settings.vertical_speed) + 0.001, "Docking never exceeds vertical top speed")
	check(max_acceleration <= float(game.pilot.movement.settings.side_thrust) * 2.0 / float(game.pilot.movement.settings.mass) + 0.001, "Docking never exceeds available vertical thrust acceleration")
	check(max_horizontal_speed <= float(game.pilot.movement.settings.forward_speed) + 0.001, "Alignment respects horizontal top speed")
	check(max_turn_speed <= deg_to_rad(float(game.pilot.movement.settings.turn_speed)) + 0.001, "Docking respects maximum turn rate")
	check(max_turn_acceleration <= deg_to_rad(float(game.pilot.movement.settings.turn_acceleration)) + 0.001, "Docking respects turning acceleration")
	var normal_descent_duration: float = controller.travel_profile.duration
	game._reset_submarine()
	game.pilot.movement.settings.vertical_speed = 0.5
	game.pilot.movement.settings.side_thrust *= 0.1
	game.pilot.global_position = controller.ports[0].entry
	game.pilot.velocity = Vector3.ZERO
	check(controller.request_docking(), "Docking accepts slower movement settings")
	advance(controller, Docking.Stage.DESCEND)
	check(float(controller.travel_profile.duration) > normal_descent_duration * 2.0, "Reduced speed and thrust lengthen docking transit instead of forcing its duration")
	game._reset_submarine()
	game.pilot.global_position = controller.ports[0].entry
	game.pilot.global_basis = Basis(Vector3.UP, 2.3)
	game.pilot.movement.settings.turn_acceleration = 0.0
	game.pilot.movement.settings.turn_speed = 0.0
	check(controller.request_docking(), "Upright ship can dock at any heading even with turning disabled")
	advance(controller, Docking.Stage.OPEN)
	check(game.pilot.global_basis.is_equal_approx(Basis(Vector3.UP, 2.3)), "Docking with turning disabled preserves heading")
	game._reset_submarine()
	game.pilot.global_position = controller.ports[0].entry + Vector3.BACK * 1.5
	game.pilot.global_basis = Basis.IDENTITY
	game.pilot.velocity = Vector3.RIGHT * 0.8
	check(controller.request_docking(), "Aligned moving approach can begin settling with turning disabled")
	for frame in range(1000):
		if controller.stage == Docking.Stage.IDLE: break
		controller._physics_process(0.1)
	check(controller.stage == Docking.Stage.IDLE and game.pilot.active and game.pilot.global_position.distance_to(controller.ports[0].entry) > 1.0, "Changed bearing during settling cancels safely instead of sliding sideways when turning is disabled")
	game.queue_free()
	await create_timer(0.25).timeout
	print("Docking verification: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
