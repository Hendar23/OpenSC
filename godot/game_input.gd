extends RefCounted
## Input routing, pilot control gating, and pointer mode.

var game: Node3D

func _init(context: Node3D) -> void:
	game = context

const Bindings = preload("res://input_bindings.gd")
const Docking = preload("res://docking_controller.gd")

func _input(event: InputEvent) -> void:
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
		if Bindings.pressed(event,"camera_toggle"):
			game._set_camera_mode(not game.first_person)
			game.get_viewport().set_input_as_handled()
			return
	if not game.developer_ui_visible and game.cockpit_hud != null:
		for index in range(5):
			if Bindings.pressed(event,"hud_%d" % (index + 1)):
				game.cockpit_hud.toggle(index)
				game.hud_enabled[index] = game.cockpit_hud.enabled[index]
				game._save_preferences()
				game.get_viewport().set_input_as_handled()
				return
	if not game.developer_ui_visible and game.equipment != null and game.docking.stage != Docking.Stage.DOCKED:
		if Bindings.pressed(event,"weapon_previous") and game.weapons != null: game.weapons.cycle(-1)
		elif Bindings.pressed(event,"weapon_next") and game.weapons != null: game.weapons.cycle(1)
		if Bindings.pressed(event,"equipment_previous"): game.equipment.cycle(-1)
		elif Bindings.pressed(event,"equipment_next"): game.equipment.cycle(1)
		elif Bindings.pressed(event,"equipment_toggle") and game.docking.stage == Docking.Stage.IDLE:
			if not Bindings.pressed(event,"dock_decline") or game.docking.nearby.is_empty(): game.equipment.toggle_selected()
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
	if game.pilot == null or game.get_tree().paused: return
	var pointer := game.get_viewport().get_mouse_position()
	var over_ui: bool = game.developer_ui_visible and game.controls.get_global_rect().has_point(pointer)
	if game.developer_ui_visible and game.tuning_panel.visible:
		over_ui = over_ui or game.tuning_panel.get_global_rect().has_point(pointer)
	if game.developer_ui_visible and game.sound_panel != null and game.sound_panel.visible:
		over_ui = over_ui or game.sound_panel.get_global_rect().has_point(pointer)
	game.pilot.controls_enabled = game.pilot_mode and not game.pilot.dead and not game.map_open and not game.world_loading and not game.loading_save and not game.developer_ui_visible and not over_ui and not game.folder_dialog.visible and not game.export_all_dialog.visible and not game.mod_panel.visible and not game.tuning_panel.export_dialog.visible and (game.sound_panel == null or not game.sound_panel.export_dialog.visible) and (game.docking == null or game.docking.stage == Docking.Stage.IDLE)
	game.pilot.remote_controlled = game.equipment != null and game.equipment.support_tools != null and is_instance_valid(game.equipment.support_tools.rover) and game.equipment.support_tools.rover.deployed

func _desired_mouse_mode() -> int:
	var menus: bool = game.map_open or game.developer_ui_visible or (game.folder_dialog != null and game.folder_dialog.visible) or (game.mod_panel != null and game.mod_panel.visible)
	menus = menus or (game.front_end != null and game.front_end.menu_layer.visible)
	menus = menus or (game.dock_interface != null and game.dock_interface.visible)
	menus = menus or (game.export_all_dialog != null and game.export_all_dialog.visible)
	menus = menus or (game.tuning_panel != null and game.tuning_panel.export_dialog.visible) or (game.sound_panel != null and game.sound_panel.export_dialog.visible)
	var docked: bool = game.docking != null and game.docking.stage == Docking.Stage.DOCKED
	return Input.MOUSE_MODE_HIDDEN if game.pilot_mode and not game.world_loading and not game.loading_save and not menus and not docked else Input.MOUSE_MODE_VISIBLE

func _update_mouse_pointer() -> void:
	var mode: int = game._desired_mouse_mode()
	if Input.mouse_mode != mode: Input.mouse_mode = mode
