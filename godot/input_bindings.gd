extends Node

# Two editable slots per action; button chords are evaluated before plain buttons.
const KEYS := {
	"map_toggle":KEY_M,"camera_toggle":KEY_V,
	"menu_accept":KEY_ENTER,"menu_cancel":KEY_ESCAPE,"menu_up":KEY_UP,"menu_down":KEY_DOWN,"menu_left":KEY_LEFT,"menu_right":KEY_RIGHT,
	"main_menu":KEY_ESCAPE,"weapon_previous":KEY_PAGEUP,"weapon_next":KEY_PAGEDOWN,"fps_toggle":KEY_F11,"screenshot":KEY_F12,
	"dock_accept":KEY_Y,"dock_decline":KEY_N,"equipment_previous":KEY_BRACKETLEFT,
	"equipment_next":KEY_BRACKETRIGHT,"equipment_toggle":KEY_L,"weapon_fire":KEY_SPACE,
	"hud_1":KEY_1,"hud_2":KEY_2,"hud_3":KEY_3,"hud_4":KEY_4,"hud_5":KEY_5,
	"thrust_forward":KEY_W,"thrust_reverse":KEY_S,"thrust_up":KEY_E,"thrust_down":KEY_Q,
	"turn_left":KEY_A,"turn_right":KEY_D,"pitch_up":KEY_UP,"pitch_down":KEY_DOWN
}
const EDITOR_KEYS := {"editor_frame":KEY_F,"editor_fast":KEY_SHIFT,"editor_undo":KEY_Z,"editor_redo":KEY_Y,"editor_save":KEY_S}
const BUTTONS := {
	"camera_toggle":JOY_BUTTON_Y,"dock_accept":JOY_BUTTON_A,"dock_decline":JOY_BUTTON_B,
	"menu_accept":JOY_BUTTON_A,"menu_cancel":JOY_BUTTON_B,"menu_up":JOY_BUTTON_DPAD_UP,"menu_down":JOY_BUTTON_DPAD_DOWN,"menu_left":JOY_BUTTON_DPAD_LEFT,"menu_right":JOY_BUTTON_DPAD_RIGHT,
	"equipment_toggle":JOY_BUTTON_B,"equipment_previous":JOY_BUTTON_DPAD_LEFT,
	"equipment_next":JOY_BUTTON_DPAD_RIGHT,"weapon_previous":JOY_BUTTON_DPAD_UP,
	"weapon_next":JOY_BUTTON_DPAD_DOWN,"weapon_fire":JOY_BUTTON_X,"main_menu":JOY_BUTTON_START
}
const CONFIG_PATH := "user://controls.cfg"
const AXES := {"thrust_forward":[JOY_AXIS_TRIGGER_RIGHT,1],"thrust_reverse":[JOY_AXIS_TRIGGER_LEFT,1],"thrust_up":[JOY_AXIS_RIGHT_Y,-1],"thrust_down":[JOY_AXIS_RIGHT_Y,1],"turn_left":[JOY_AXIS_LEFT_X,-1],"turn_right":[JOY_AXIS_LEFT_X,1],"pitch_up":[JOY_AXIS_LEFT_Y,1],"pitch_down":[JOY_AXIS_LEFT_Y,-1]}
static var bindings := {}
static var installed := false
static var capture_active := false
static var held_buttons := {}
static var previous_axes := {}
static var axis_event_id := 0
static var axis_edges := {}

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	install()
func _input(event: InputEvent) -> void: track_event(event)
static func track_event(event: InputEvent) -> void:
	if event is InputEventJoypadButton: held_buttons["%d:%d" % [event.device,event.button_index]] = event.pressed
	elif event is InputEventJoypadMotion: observe_axis(event)

static func observe_axis(event: InputEventJoypadMotion) -> void:
	if axis_event_id == event.get_instance_id(): return
	axis_event_id = event.get_instance_id()
	var id := "%d:%d" % [event.device,event.axis]
	var previous: float = previous_axes.get(id,0.0)
	axis_edges = {1:event.axis_value > 0.5 and previous <= 0.5,-1:event.axis_value < -0.5 and previous >= -0.5}
	previous_axes[id] = event.axis_value

static func defaults() -> Dictionary:
	var result := {}
	for action in KEYS:
		var key := {"kind":"key","code":KEYS[action],"physical":action in AXES,"ctrl":false,"alt":false,"shift":false,"meta":false}
		var second: Variant = null
		if BUTTONS.has(action): second = {"kind":"button","button":BUTTONS[action],"modifier":-1}
		elif AXES.has(action): second = {"kind":"axis","axis":AXES[action][0],"sign":AXES[action][1]}
		result[action] = [key,second]
	result.map_toggle[1] = {"kind":"button","button":JOY_BUTTON_Y,"modifier":JOY_BUTTON_LEFT_SHOULDER}
	return result
static func install() -> void:
	if installed: return
	installed = true; bindings = defaults(); load_settings(); apply_all()
static func install_editor() -> void:
	install()
	for action in EDITOR_KEYS:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event := InputEventKey.new(); event.keycode = EDITOR_KEYS[action]
		event.ctrl_pressed = action in ["editor_undo","editor_redo","editor_save"]
		InputMap.action_add_event(action,event)
static func valid(value: Variant) -> bool:
	if value == null: return true
	if not value is Dictionary: return false
	match value.get("kind",""):
		"key": return value.get("code") is int and value.code > 0 and value.code != KEY_F1 and value.get("physical") is bool and value.get("ctrl") is bool and value.get("alt") is bool and value.get("shift") is bool and value.get("meta") is bool
		"button": return value.get("button") is int and value.button >= 0 and value.button < JOY_BUTTON_MAX and value.get("modifier") is int and value.modifier >= -1 and value.modifier < JOY_BUTTON_MAX and value.modifier != value.button
		"axis": return value.get("axis") is int and value.axis >= 0 and value.axis < JOY_AXIS_MAX and value.get("sign") in [-1,1]
		"mouse": return value.get("button") is int and value.button >= 1 and value.button <= MOUSE_BUTTON_XBUTTON2
	return false
static func load_settings(path: String = CONFIG_PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	for action in bindings:
		var slots: Variant = config.get_value("bindings",action,null)
		if slots is Array and slots.size() == 2 and valid(slots[0]) and valid(slots[1]): bindings[action] = slots.duplicate(true)
static func save_settings(path: String = CONFIG_PATH) -> Error:
	var config := ConfigFile.new()
	for action in bindings: config.set_value("bindings",action,bindings[action])
	return config.save(path)
static func set_binding(action: String, slot: int, value: Variant) -> bool:
	install()
	if not bindings.has(action) or slot not in [0,1] or not valid(value): return false
	bindings[action][slot] = value.duplicate() if value is Dictionary else null
	apply_all(); return true
static func reset_defaults() -> void: bindings = defaults(); apply_all()
static func to_event(value: Dictionary) -> InputEvent:
	match value.kind:
		"key":
			var event := InputEventKey.new()
			if value.physical: event.physical_keycode = value.code
			else: event.keycode = value.code
			event.ctrl_pressed = value.ctrl; event.alt_pressed = value.alt; event.shift_pressed = value.shift; event.meta_pressed = value.meta
			return event
		"button":
			if value.modifier >= 0: return null
			var event := InputEventJoypadButton.new(); event.button_index = value.button; event.device = -1; return event
		"axis":
			var event := InputEventJoypadMotion.new(); event.axis = value.axis; event.axis_value = value.sign; event.device = -1; return event
		"mouse":
			var event := InputEventMouseButton.new(); event.button_index = value.button; return event
	return null
static func apply_all() -> void:
	for action in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_set_deadzone(action,0.05 if action in ["thrust_forward","thrust_reverse"] else 0.15)
		InputMap.action_erase_events(action)
		Input.action_release(action)
		for value in bindings[action]:
			if value == null: continue
			var event := to_event(value)
			if event != null: InputMap.action_add_event(action,event)
	for suffix in ["accept","cancel","up","down","left","right"]:
		var ui: String = "ui_" + suffix
		if not InputMap.has_action(ui): InputMap.add_action(ui)
		InputMap.action_erase_events(ui)
		Input.action_release(ui)
		for value in bindings["menu_" + suffix]:
			if value == null: continue
			var event := to_event(value)
			if event != null: InputMap.action_add_event(ui,event)
static func button_held(device: int, button: int) -> bool:
	if device in Input.get_connected_joypads(): return Input.is_joy_button_pressed(device,button)
	return bool(held_buttons.get("%d:%d" % [device,button],false)) or Input.is_joy_button_pressed(device,button)
static func claimed_by_chord(event: InputEvent) -> bool:
	if not event is InputEventJoypadButton: return false
	for slots in bindings.values():
		for value in slots:
			if value != null and value.kind == "button" and value.modifier >= 0 and value.button == event.button_index and button_held(event.device,value.modifier): return true
	return false
static func pressed(event: InputEvent, action: String) -> bool:
	if capture_active or event.is_echo(): return false
	if action == "developer_toggle": return event is InputEventKey and event.pressed and (event.keycode == KEY_F1 or event.physical_keycode == KEY_F1)
	if event is InputEventAction: return event.action == action and event.pressed
	if not bindings.has(action): return event.is_action_pressed(action)
	var claimed := claimed_by_chord(event)
	for value in bindings[action]:
		if value == null: continue
		if value.kind == "button" and value.modifier >= 0:
			if event is InputEventJoypadButton and event.pressed and event.button_index == value.button and button_held(event.device,value.modifier): return true
	if claimed: return false
	if event is InputEventJoypadMotion:
		observe_axis(event)
		if not event.is_action_pressed(action,true): return false
		return bool(axis_edges.get(1 if event.axis_value > 0 else -1,false))
	return event.is_action_pressed(action,true)
static func strength(action: String) -> float:
	if capture_active: return 0.0
	var value := Input.get_action_strength(action)
	for binding in bindings.get(action,[]):
		if binding == null or binding.kind != "button": continue
		for device in Input.get_connected_joypads():
			if binding.modifier >= 0:
				if button_held(device,binding.modifier) and button_held(device,binding.button): value = 1.0
			else:
				var event := InputEventJoypadButton.new(); event.device = device; event.button_index = binding.button
				if button_held(device,binding.button) and claimed_by_chord(event):
					value = 0.0
					# A claimed controller button must not suppress a held keyboard/mouse slot.
					for other in bindings.get(action,[]):
						if other == null: continue
						if other.kind == "key" and (Input.is_physical_key_pressed(other.code) if other.physical else Input.is_key_pressed(other.code)):
							if (not other.ctrl or Input.is_key_pressed(KEY_CTRL)) and (not other.alt or Input.is_key_pressed(KEY_ALT)) and (not other.shift or Input.is_key_pressed(KEY_SHIFT)) and (not other.meta or Input.is_key_pressed(KEY_META)): value = 1.0
						elif other.kind == "mouse" and Input.is_mouse_button_pressed(other.button): value = 1.0
						elif other.kind == "axis":
							var deadzone := InputMap.action_get_deadzone(action)
							value = maxf(value,clampf((Input.get_joy_axis(device,other.axis) * other.sign - deadzone) / (1.0 - deadzone),0.0,1.0))
	return value
static func describe(value: Variant) -> String:
	if value == null: return "Unbound"
	if value.kind == "button": return button_name(value.modifier) + " + " + button_name(value.button) if value.modifier >= 0 else button_name(value.button)
	if value.kind == "axis":
		var names := ["Left stick X","Left stick Y","Right stick X","Right stick Y","Left trigger","Right trigger"]
		return str(names[value.axis] if value.axis < names.size() else "Axis %d" % value.axis) + (" +" if value.sign > 0 else " -")
	return to_event(value).as_text()
static func button_name(button: int) -> String:
	var names := {JOY_BUTTON_A:"A / Cross",JOY_BUTTON_B:"B / Circle",JOY_BUTTON_X:"X / Square",JOY_BUTTON_Y:"Y / Triangle",JOY_BUTTON_LEFT_SHOULDER:"Left shoulder",JOY_BUTTON_RIGHT_SHOULDER:"Right shoulder",JOY_BUTTON_START:"Start / Options",JOY_BUTTON_BACK:"Back / Select",JOY_BUTTON_DPAD_UP:"D-pad up",JOY_BUTTON_DPAD_DOWN:"D-pad down",JOY_BUTTON_DPAD_LEFT:"D-pad left",JOY_BUTTON_DPAD_RIGHT:"D-pad right"}
	return str(names.get(button,"Controller button %d" % button))
