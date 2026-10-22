extends Node3D
## Free camera and visual replay: gameplay stays paused until exit.
const Bindings = preload("res://input_bindings.gd")
var game: Node
var active := false
var view: Camera3D
var source: Camera3D
var saved: Array[Dictionary] = []
var mouse_mode := Input.MOUSE_MODE_HIDDEN
var device := -1
var yaw := 0.0
var pitch := 0.0
var replay: Node3D

func setup(context: Node) -> void:
	game = context; name = "PhotoMode"; process_mode = Node.PROCESS_MODE_ALWAYS
	view = Camera3D.new(); view.name = "PhotoCamera"; add_child(view)
	replay = preload("res://photo_replay.gd").new(); add_child(replay); replay.setup(game)
	replay.set_enabled(game.front_end.gameplay_menu.replay_enabled)
	game.front_end.gameplay_menu.replay_changed.connect(replay.set_enabled)

func can_enter() -> bool:
	return game != null and game.has_started_game and game.pilot_mode and not game.world_loading and not get_tree().paused and not Bindings.capture_active and is_instance_valid(game.pilot) and not game.pilot.dead and game.pilot.active and not game.map_open and not game.developer_ui_visible and game.docking != null and game.docking.stage == game.Docking.Stage.IDLE and game._desired_mouse_mode() == Input.MOUSE_MODE_HIDDEN

func enter(controller: int = -1) -> bool:
	if active or not can_enter(): return false
	source = get_viewport().get_camera_3d()
	if source == null: return false
	view.global_transform = source.global_transform
	view.fov = source.fov; view.near = source.near; view.far = source.far
	view.keep_aspect = source.keep_aspect; view.environment = source.environment; view.attributes = source.attributes
	# Include the player's hull/ROV, but never camera-local canopy geometry.
	view.cull_mask = (source.cull_mask | game.SUB_RENDER_LAYER | preload("res://remote_vehicle.gd").RENDER_LAYER) & ~preload("res://first_person_cockpit.gd").RENDER_LAYER
	var angles := view.global_basis.get_euler(); yaw = angles.y; pitch = clampf(angles.x,-PI*0.495,PI*0.495)
	device = controller; mouse_mode = Input.mouse_mode; saved.clear()
	active = true
	_suspend(game)
	view.make_current(); get_tree().paused = true
	replay.begin()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return true

func _suspend(node: Node) -> void:
	if node == self: return
	# Ordinary gameplay already pauses with the tree. Menus, radio and other
	# ALWAYS controllers must also stop instead of ageing hidden UI/messages.
	var runs_paused := node.process_mode in [Node.PROCESS_MODE_ALWAYS,Node.PROCESS_MODE_WHEN_PAUSED]
	if node is CanvasLayer or runs_paused:
		var entry := {"node":weakref(node),"mode":node.process_mode}
		if node is CanvasLayer: entry["visible"] = node.visible; node.hide()
		saved.append(entry)
		if runs_paused: node.process_mode = Node.PROCESS_MODE_PAUSABLE
	for child in node.get_children(): _suspend(child)

func leave() -> void:
	if not active: return
	replay.end()
	active = false; view.clear_current()
	if is_instance_valid(source): source.make_current()
	for entry in saved:
		var node: Node = entry.node.get_ref()
		if node == null: continue
		node.process_mode = entry.mode
		if node is CanvasLayer: node.visible = entry.visible
	saved.clear(); get_tree().paused = false; Input.mouse_mode = mouse_mode
	if is_instance_valid(game.first_person_cockpit): game.first_person_cockpit.refresh()

func _input(event: InputEvent) -> void:
	if not active:
		if Bindings.pressed(event,"photo_mode") and enter(event.device if event is InputEventJoypadButton else -1): get_viewport().set_input_as_handled()
		return
	if Bindings.pressed(event,"photo_mode") or Bindings.pressed(event,"main_menu") or Bindings.pressed(event,"menu_cancel"):
		leave()
	elif Bindings.pressed(event,"screenshot") or (event is InputEventJoypadButton and Bindings.pressed(event,"menu_accept")):
		game.capture_overlay.save_screenshot(false)
	elif event is InputEventMouseMotion:
		look(Vector2(event.relative.x,event.relative.y)*0.0025)
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_DPAD_UP: replay.toggle_play()
		elif event.button_index == JOY_BUTTON_DPAD_DOWN: replay.speed = 0.25 if replay.speed == 1.0 else 1.0
		elif event.button_index in [JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT]: replay.seek(replay.cursor+(-0.5 if event.button_index == JOY_BUTTON_DPAD_LEFT else 0.5)); replay.playing = false
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE: replay.toggle_play()
		elif event.keycode == KEY_DOWN: replay.speed = 0.25 if replay.speed == 1.0 else 1.0
	if event is InputEventJoypadButton or event is InputEventJoypadMotion: device = event.device
	get_viewport().set_input_as_handled()

func look(amount: Vector2) -> void:
	yaw -= amount.x; pitch = clampf(pitch-amount.y,-PI*0.495,PI*0.495)
	view.global_basis = Basis.from_euler(Vector3(pitch,yaw,0))

func _keyboard(action: String) -> float:
	for binding in Bindings.bindings.get(action,[]):
		if binding == null or binding.kind != "key": continue
		if (Input.is_physical_key_pressed(binding.code) if binding.physical else Input.is_key_pressed(binding.code)): return 1.0
	return 0.0

func _axis(axis: int) -> float:
	if device not in Input.get_connected_joypads(): return 0.0
	var value := Input.get_joy_axis(device,axis)
	return signf(value)*maxf(0,absf(value)-0.15)/0.85

func _process(delta: float) -> void:
	if not active: return
	if device < 0 and not Input.get_connected_joypads().is_empty(): device = Input.get_connected_joypads()[0]
	var scrub := float(Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_LEFT))
	if device >= 0:
		scrub += float(Input.is_joy_button_pressed(device,JOY_BUTTON_DPAD_RIGHT))-float(Input.is_joy_button_pressed(device,JOY_BUTTON_DPAD_LEFT))
	look(Vector2(_axis(JOY_AXIS_RIGHT_X),_axis(JOY_AXIS_RIGHT_Y))*1.8*delta)
	var direction := Vector3(_keyboard("turn_right")-_keyboard("turn_left")+_axis(JOY_AXIS_LEFT_X),0,_keyboard("thrust_reverse")-_keyboard("thrust_forward")+_axis(JOY_AXIS_LEFT_Y))
	var rise := _keyboard("thrust_up")-_keyboard("thrust_down")+maxf(0,_axis(JOY_AXIS_TRIGGER_RIGHT))-maxf(0,_axis(JOY_AXIS_TRIGGER_LEFT))
	var fast := Input.is_physical_key_pressed(KEY_SHIFT) or (device >= 0 and Input.is_joy_button_pressed(device,JOY_BUTTON_RIGHT_SHOULDER))
	var slow := Input.is_physical_key_pressed(KEY_CTRL) or (device >= 0 and Input.is_joy_button_pressed(device,JOY_BUTTON_LEFT_SHOULDER))
	move(direction,rise,delta,0.25 if slow else 4.0 if fast else 1.0)
	replay.advance(delta,clampf(scrub,-1,1))

func move(direction: Vector3, rise: float, delta: float, speed_scale: float = 1.0) -> void:
	var motion := view.global_basis*direction+Vector3.UP*rise
	view.global_position += motion.limit_length(1.0)*3.0*speed_scale*delta

func _exit_tree() -> void:
	if active:
		leave(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
