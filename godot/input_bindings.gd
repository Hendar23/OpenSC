extends Node

# Defaults live here; consumers use action names. Existing InputMap bindings
# are retained, so a future controls screen can replace them without changing
# gameplay, menus, or HUD code.
const KEYS := {
	"map_toggle":KEY_M,"developer_toggle":KEY_F1,"camera_toggle":KEY_V,
	"menu_accept":KEY_ENTER,"menu_cancel":KEY_ESCAPE,"menu_up":KEY_UP,"menu_down":KEY_DOWN,"menu_left":KEY_LEFT,"menu_right":KEY_RIGHT,
	"fps_toggle":KEY_F11,"screenshot":KEY_F12,"sub_reset":KEY_R,
	"dock_accept":KEY_Y,"dock_decline":KEY_N,"equipment_previous":KEY_BRACKETLEFT,
	"equipment_next":KEY_BRACKETRIGHT,"equipment_toggle":KEY_L,"weapon_fire":KEY_SPACE,
	"hud_1":KEY_1,"hud_2":KEY_2,"hud_3":KEY_3,"hud_4":KEY_4,"hud_5":KEY_5,
	"thrust_forward":KEY_W,"thrust_reverse":KEY_S,"thrust_up":KEY_E,"thrust_down":KEY_Q,
	"editor_frame":KEY_F,"editor_fast":KEY_SHIFT,
	"turn_left":KEY_A,"turn_right":KEY_D,"pitch_up":KEY_UP,"pitch_down":KEY_DOWN
}
const BUTTONS := {
	"camera_toggle":JOY_BUTTON_Y,"dock_accept":JOY_BUTTON_A,"dock_decline":JOY_BUTTON_B,
	"menu_accept":JOY_BUTTON_A,"menu_cancel":JOY_BUTTON_B,"menu_up":JOY_BUTTON_DPAD_UP,"menu_down":JOY_BUTTON_DPAD_DOWN,"menu_left":JOY_BUTTON_DPAD_LEFT,"menu_right":JOY_BUTTON_DPAD_RIGHT,
	"equipment_toggle":JOY_BUTTON_B,"equipment_previous":JOY_BUTTON_DPAD_LEFT,
	"equipment_next":JOY_BUTTON_DPAD_RIGHT,"weapon_previous":JOY_BUTTON_DPAD_UP,
	"weapon_next":JOY_BUTTON_DPAD_DOWN,"weapon_fire":JOY_BUTTON_X,"main_menu":JOY_BUTTON_START
}
func _enter_tree() -> void:
	install_editor()
static func install() -> void:
	for action in KEYS:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		if action.begins_with("thrust_") or action.begins_with("turn_") or action.begins_with("pitch_"):
			event.physical_keycode = KEYS[action]
		else: event.keycode = KEYS[action]
		InputMap.action_add_event(action,event)
		if BUTTONS.has(action):
			var button := InputEventJoypadButton.new(); button.button_index = BUTTONS[action]; button.device = -1
			InputMap.action_add_event(action,button)
	for action in BUTTONS:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var button := InputEventJoypadButton.new(); button.button_index = BUTTONS[action]; button.device = -1
		InputMap.action_add_event(action,button)

static func install_editor() -> void:
	install()
	for entry in [["editor_undo",KEY_Z],["editor_redo",KEY_Y],["editor_save",KEY_S]]:
		if InputMap.has_action(entry[0]): continue
		InputMap.add_action(entry[0])
		var event := InputEventKey.new(); event.keycode = entry[1]; event.ctrl_pressed = true
		InputMap.action_add_event(entry[0],event)
