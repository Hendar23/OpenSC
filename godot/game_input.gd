extends RefCounted
## Input routing, pilot control gating, and pointer mode.

var game: Node3D

func _init(context: Node3D) -> void:
	game = context
	Input.joy_connection_changed.connect(_joy_connection_changed)

const Bindings = preload("res://input_bindings.gd")
const Docking = preload("res://docking_controller.gd")

func _input(event: InputEvent) -> void:
	var camera = game.game_camera
	if Bindings.pressed(event, "cockpit_freelook_toggle") and not Bindings.pressed(event, "camera_toggle") and camera.can_freelook():
		var active_device: int = camera.stick_freelook_device
		var device := _freelook_controller(event, active_device)
		if device >= 0 and (active_device < 0 or active_device == device):
			camera.set_stick_freelook(-1 if active_device == device else device)
			game.get_viewport().set_input_as_handled(); return
	if event is InputEventJoypadMotion:
		if event.device == camera.stick_freelook_device and event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
			game.get_viewport().set_input_as_handled(); return
		if event.axis == JOY_AXIS_RIGHT_X and camera.stick_freelook_device < 0 and not Bindings.capture_active \
				and camera.can_freelook() and not Bindings.pressed(event, "camera_toggle"):
			camera.set_horizontal_look(event.device, event.axis_value)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and camera.can_freelook():
			camera.mouse_freelook = true
			_update_mouse_pointer()
			game.get_viewport().set_input_as_handled(); return
		if not event.pressed and camera.mouse_freelook:
			camera.mouse_freelook = false
			_update_mouse_pointer()
			game.get_viewport().set_input_as_handled(); return
	if event is InputEventMouseMotion and camera.mouse_freelook and camera.can_freelook():
		camera.look(event.screen_relative)
		game.get_viewport().set_input_as_handled(); return
	if game.loading_save or game.world_loading:
		game.get_viewport().set_input_as_handled(); return
	if game.get_tree().paused and game.front_end.menu_layer.visible: return
	if game._rov_prompt_active():
		if Bindings.pressed(event,"dock_accept") or Bindings.pressed(event,"menu_accept"):
			game.equipment.support_tools.rover.answer_docking(true); game.get_viewport().set_input_as_handled(); return
		if Bindings.pressed(event,"dock_decline") or Bindings.pressed(event,"menu_cancel"):
			game.equipment.support_tools.rover.answer_docking(false); game.get_viewport().set_input_as_handled(); return
	if game._delivery_prompt_active():
		if Bindings.pressed(event,"dock_accept") or Bindings.pressed(event,"menu_accept"):
			game._answer_delivery(true); game.get_viewport().set_input_as_handled(); return
		if Bindings.pressed(event,"dock_decline") or Bindings.pressed(event,"menu_cancel"):
			game._answer_delivery(false); game.get_viewport().set_input_as_handled(); return
	if Bindings.pressed(event,"map_toggle") and game.pilot_mode and not game.world_loading and not game.get_tree().paused and not game.developer_ui_visible and game.docking.stage != Docking.Stage.DOCKED:
		game._set_map_open(not game.map_open)
		game.get_viewport().set_input_as_handled()
	elif game.map_open and Bindings.pressed(event,"menu_cancel"):
		game._set_map_open(false)
		game.get_viewport().set_input_as_handled()
	elif game.developer_enabled and Bindings.pressed(event,"developer_toggle"):
		game._set_map_open(false)
		game._toggle_developer_ui()
		game.get_viewport().set_input_as_handled()

func _freelook_controller(event: InputEvent, active: int) -> int:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion: return event.device
	if active >= 0: return active
	var controllers := Input.get_connected_joypads()
	return controllers[0] if not controllers.is_empty() else -1

func _unhandled_input(event: InputEvent) -> void:
	if game.get_tree().paused or not game.pilot_mode or game.world_loading or game.loading_save or game.map_open or (game.dock_interface != null and game.dock_interface.visible): return
	if game.pilot.dead: return
	if not game.developer_ui_visible and game.docking.stage == Docking.Stage.IDLE:
		if Bindings.pressed(event,"rear_camera_toggle") and game.cockpit_hud != null:
			game.cockpit_hud.set_rear_camera_enabled(not game.cockpit_hud.rear_camera_enabled)
			game.get_viewport().set_input_as_handled(); return
		if Bindings.pressed(event,"bottom_camera_toggle") and game.cockpit_hud != null:
			game.cockpit_hud.set_bottom_camera_enabled(not game.cockpit_hud.bottom_camera_enabled)
			game.get_viewport().set_input_as_handled(); return
	if not game.developer_ui_visible and game.docking.stage != Docking.Stage.DOCKED and Bindings.pressed(event,"camera_toggle"):
		game._set_camera_mode(not game.first_person)
		game.get_viewport().set_input_as_handled()
		return
	if not game.developer_ui_visible and game.cockpit_hud != null:
		for index in range(5):
			if Bindings.pressed(event,"hud_%d" % (index + 1)):
				game.cockpit_hud.toggle(index)
				game.game_settings.save_player_preferences(index)
				game.get_viewport().set_input_as_handled()
				return
	if not game.developer_ui_visible and game.equipment != null and game.docking.stage != Docking.Stage.DOCKED:
		if Bindings.pressed(event,"weapon_previous") and game.weapons != null: game.weapons.cycle(-1)
		elif Bindings.pressed(event,"weapon_next") and game.weapons != null: game.weapons.cycle(1)
		if Bindings.pressed(event,"equipment_previous"): game.equipment.cycle(-1)
		elif Bindings.pressed(event,"equipment_next"): game.equipment.cycle(1)
		elif Bindings.pressed(event,"equipment_toggle"):
			var in_transit: bool = game.docking.stage != Docking.Stage.IDLE
			var selected_id: String = game.equipment.current().get("id", "")
			var can_toggle: bool
			if in_transit:
				can_toggle = selected_id in ["deep_sea_lights", "night_vision"] or game.docking.is_undocking()
			else:
				can_toggle = not Bindings.pressed(event,"dock_decline") or game.docking.nearby.is_empty()
			if can_toggle:
				# An input event can arrive before the physics tick updates launch permissions.
				_update_pilot_controls()
				game.equipment.toggle_selected()
	if Bindings.pressed(event,"dock_accept"):
		game._request_docking()
		game.get_viewport().set_input_as_handled()
	elif Bindings.pressed(event,"dock_decline"):
		game.docking.decline_docking()
		game.get_viewport().set_input_as_handled()
	elif Bindings.pressed(event,"menu_cancel") and game.developer_ui_visible: game._toggle_developer_ui()
	elif event is InputEventMouseButton and event.pressed:
		if game.developer_ui_visible and game.developer_menu.get_global_rect().has_point(game.get_viewport().get_mouse_position()): return
		var distance := float(game.pilot.movement.settings.camera_distance)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: game.tuning_panel.set_camera_distance(distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: game.tuning_panel.set_camera_distance(distance * 1.1)

func _physics_process(_delta: float) -> void:
	_update_pilot_controls()

func _update_pilot_controls() -> void:
	if game.pilot == null or game.get_tree().paused: return
	var pointer := game.get_viewport().get_mouse_position()
	var over_ui: bool = game.developer_ui_visible and game.controls.get_global_rect().has_point(pointer)
	if game.developer_ui_visible and game.tuning_panel.visible:
		over_ui = over_ui or game.tuning_panel.get_global_rect().has_point(pointer)
	if game.developer_ui_visible and game.sound_panel != null and game.sound_panel.visible:
		over_ui = over_ui or game.sound_panel.get_global_rect().has_point(pointer)
	var tools_ready: bool = game.pilot_mode and not game.pilot.dead and not game.map_open and not game.world_loading and not game.loading_save and not game.developer_ui_visible and not over_ui and not game.folder_dialog.visible and not game.export_all_dialog.visible and not game.mod_panel.visible and not game.tuning_panel.export_dialog.visible and (game.sound_panel == null or not game.sound_panel.export_dialog.visible)
	game.pilot.controls_enabled = tools_ready and (game.docking == null or game.docking.stage == Docking.Stage.IDLE)
	game.pilot.set_meta("launch_tools",tools_ready and game.docking != null and game.docking.is_undocking())
	game.pilot.remote_controlled = game.equipment != null and game.equipment.support_tools != null and is_instance_valid(game.equipment.support_tools.rover) and game.equipment.support_tools.rover.deployed

func _joy_connection_changed(device: int, connected: bool) -> void:
	if not connected and game.game_camera.stick_freelook_device == device:
		game.game_camera.set_stick_freelook(-1)
	if not connected and game.game_camera.horizontal_look_device == device:
		game.game_camera.set_horizontal_look(device, 0.0)

func _desired_mouse_mode() -> int:
	if game.game_camera.mouse_freelook and game.game_camera.can_freelook(): return Input.MOUSE_MODE_CAPTURED
	var menus: bool = game.map_open or game.developer_ui_visible or (game.folder_dialog != null and game.folder_dialog.visible) or (game.mod_panel != null and game.mod_panel.visible)
	menus = menus or (game.front_end != null and game.front_end.menu_layer.visible)
	menus = menus or (game.dock_interface != null and game.dock_interface.visible)
	menus = menus or (game.export_all_dialog != null and game.export_all_dialog.visible)
	menus = menus or (game.tuning_panel != null and game.tuning_panel.export_dialog.visible) or (game.sound_panel != null and game.sound_panel.export_dialog.visible)
	var docked: bool = game.docking != null and game.docking.stage == Docking.Stage.DOCKED
	return Input.MOUSE_MODE_HIDDEN if game.pilot_mode and not game.world_loading and not game.loading_save and not menus and not docked else Input.MOUSE_MODE_VISIBLE

func _update_mouse_pointer() -> void:
	if game.game_camera.freelook and not game.game_camera.can_freelook(): game.game_camera.cancel_freelook()
	var mode: int = game._desired_mouse_mode()
	if Input.mouse_mode != mode: Input.mouse_mode = mode
