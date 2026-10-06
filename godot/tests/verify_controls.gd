extends SceneTree
const Bindings = preload("res://input_bindings.gd")
const Menu = preload("res://controls_menu.gd")
const PilotInput = preload("res://pilot_input.gd")
var checks := 0
var failures := 0
const FIXTURE := "res://tests/controls-test.cfg"
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func key(code: int, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = pressed; return event
func button(code: int, pressed: bool = true, device: int = 77) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new(); event.button_index = code; event.pressed = pressed; event.device = device; return event
func run() -> void:
	Bindings.install()
	var original := Bindings.bindings.duplicate(true)
	Bindings.reset_defaults()
	check(not Bindings.bindings.has("developer_toggle") and not Bindings.bindings.has("sub_reset") and not Bindings.bindings.keys().any(func(action: String) -> bool: return action.begins_with("editor_")),"Player bindings exclude developer, reset and editor commands")
	check(Bindings.pressed(key(KEY_F1),"developer_toggle") and not Bindings.pressed(key(KEY_F2),"developer_toggle"),"Developer shortcut is fixed to F1")
	check(not Bindings.set_binding("map_toggle",0,{"kind":"key","code":KEY_F1,"physical":false,"ctrl":false,"alt":false,"shift":false,"meta":false}),"F1 cannot be reassigned to a player command")
	Input.action_press("thrust_forward")
	Bindings.set_binding("thrust_forward",0,{"kind":"key","code":KEY_Z,"physical":true,"ctrl":false,"alt":false,"shift":false,"meta":false})
	check(PilotInput.read().is_zero_approx(),"Changing a held binding cannot leave movement stuck")
	Bindings.reset_defaults()
	for action in Bindings.bindings:
		check(Bindings.bindings[action].size() == 2,"Two slots: " + action)
		for value in Bindings.bindings[action]: check(Bindings.valid(value),"Valid default: " + action)
	check(Bindings.pressed(key(KEY_M),"map_toggle"),"Keyboard M opens map")
	var y := button(JOY_BUTTON_Y)
	check(Bindings.pressed(y,"camera_toggle") and not Bindings.pressed(y,"map_toggle"),"Y alone switches camera")
	Bindings.track_event(button(JOY_BUTTON_LEFT_SHOULDER))
	check(Bindings.pressed(y,"map_toggle") and not Bindings.pressed(y,"camera_toggle"),"Left shoulder + Y opens map and suppresses camera toggle")
	check(not Bindings.pressed(button(JOY_BUTTON_Y,true,1),"map_toggle"),"Combo requires buttons on the same controller")
	check(not Bindings.pressed(button(JOY_BUTTON_Y,false),"map_toggle"),"Releasing a combo does not toggle map")
	Bindings.track_event(button(JOY_BUTTON_LEFT_SHOULDER,false))
	check(Bindings.pressed(y,"camera_toggle"),"Releasing shoulder restores Y camera action")
	var second: Dictionary = Bindings.bindings.map_toggle[1].duplicate()
	Bindings.set_binding("map_toggle",0,{"kind":"key","code":KEY_J,"physical":false,"ctrl":false,"alt":false,"shift":false,"meta":false})
	check(not Bindings.pressed(key(KEY_M),"map_toggle") and Bindings.pressed(key(KEY_J),"map_toggle"),"Rebinding replaces the old key")
	check(Bindings.bindings.map_toggle[1] == second,"Rebinding preserves second slot")
	var menu := Menu.new(); menu.settings_path = FIXTURE; root.add_child(menu)
	menu.open_menu()
	check(menu.binding_buttons.size() == Bindings.bindings.size(),"Controls UI covers every action")
	for column in range(4):
		menu.navigation_rows[0][column].grab_focus()
		menu._input(key(KEY_DOWN))
		check(root.gui_get_focus_owner() == menu.navigation_rows[1][column],"Down keeps column %d" % column)
		menu._input(key(KEY_UP))
		check(root.gui_get_focus_owner() == menu.navigation_rows[0][column],"Up keeps column %d" % column)
	menu.navigation_rows[0][0].grab_focus()
	for column in range(1,4):
		menu._input(button(JOY_BUTTON_DPAD_RIGHT))
		check(root.gui_get_focus_owner() == menu.navigation_rows[0][column],"Right moves through slots and clear buttons")
	menu._input(button(JOY_BUTTON_DPAD_LEFT))
	check(root.gui_get_focus_owner() == menu.navigation_rows[0][2],"Left moves back to the previous slot")
	menu.begin_capture("weapon_fire",0)
	menu.capture_event(key(KEY_F1))
	check(Bindings.capture_active and menu.status.text.contains("reserved"),"Binding capture keeps F1 reserved and waits for another control")
	check(Bindings.capture_active and not Bindings.pressed(key(KEY_F11),"fps_toggle") and PilotInput.read() == Vector4.ZERO,"Binding capture suppresses gameplay and screenshot/FPS commands")
	var control := key(KEY_CTRL); control.ctrl_pressed = true; menu.capture_event(control)
	var chord_key := key(KEY_K); chord_key.ctrl_pressed = true; menu.capture_event(chord_key)
	check(not Bindings.capture_active and Bindings.pressed(chord_key,"weapon_fire") and not Bindings.pressed(key(KEY_K),"weapon_fire"),"Keyboard modifiers are captured and required")
	menu.begin_capture("map_toggle",1)
	menu.capture_event(button(JOY_BUTTON_RIGHT_SHOULDER)); menu.capture_event(button(JOY_BUTTON_X))
	check(Bindings.bindings.map_toggle[1].modifier == JOY_BUTTON_RIGHT_SHOULDER and Bindings.bindings.map_toggle[1].button == JOY_BUTTON_X,"Controller chord capture stores held and trigger buttons")
	menu.begin_capture("weapon_fire",1)
	menu.capture_event(button(JOY_BUTTON_A)); menu.capture_event(button(JOY_BUTTON_A,false))
	check(Bindings.bindings.weapon_fire[1].modifier == -1 and Bindings.bindings.weapon_fire[1].button == JOY_BUTTON_A,"Controller single button captures on release")
	menu.begin_capture("thrust_forward",1)
	var axis := InputEventJoypadMotion.new(); axis.axis = JOY_AXIS_RIGHT_X; axis.axis_value = 0.9; menu.capture_event(axis)
	check(Bindings.bindings.thrust_forward[1].axis == JOY_AXIS_RIGHT_X and Bindings.bindings.thrust_forward[1].sign == 1,"Stick axis direction can be rebound")
	menu.begin_capture("weapon_fire",0)
	var mouse := InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = true; menu.capture_event(mouse)
	check(Bindings.pressed(mouse,"weapon_fire"),"Mouse fire binding works")
	var before: Array = Bindings.bindings.weapon_fire.duplicate(true)
	menu.begin_capture("weapon_fire",0); menu.cancel_capture()
	check(Bindings.bindings.weapon_fire == before and not Bindings.capture_active,"Cancel leaves binding unchanged")
	check(Bindings.set_binding("weapon_fire",1,null),"Binding can be cleared")
	var expected := Bindings.bindings.duplicate(true)
	check(Bindings.save_settings(FIXTURE) == OK,"Settings save")
	Bindings.reset_defaults(); Bindings.load_settings(FIXTURE); Bindings.apply_all()
	check(Bindings.bindings == expected,"Settings reload preserves keys, mouse, axes, chords and empty slots")
	check(not Bindings.set_binding("weapon_fire",0,{"kind":"axis","axis":100,"sign":1}),"Invalid axis rejected")
	Bindings.reset_defaults()
	Input.action_press("thrust_forward",0.8)
	check(is_equal_approx(PilotInput.read().x,0.8),"Piloting reads action strength")
	Input.action_release("thrust_forward")
	var forward := InputEventKey.new(); forward.physical_keycode = KEY_W; forward.pressed = true; Input.parse_input_event(forward)
	var trigger := InputEventJoypadMotion.new(); trigger.axis = JOY_AXIS_TRIGGER_LEFT; trigger.axis_value = 0.8; Input.parse_input_event(trigger)
	for frame in range(2): await process_frame
	check(PilotInput.read().x > 0.0 and PilotInput.read().x < 1.0,"Keyboard and controller movement slots both contribute")
	var forward_release := forward.duplicate() as InputEventKey; forward_release.pressed = false; Input.parse_input_event(forward_release)
	for frame in range(2): await process_frame
	check(PilotInput.read().x < -0.7,"Releasing keyboard leaves controller thrust active")
	var trigger_release := trigger.duplicate() as InputEventJoypadMotion; trigger_release.axis_value = 0.0; Input.parse_input_event(trigger_release)
	for frame in range(2): await process_frame
	menu.refresh()
	var clear_button := menu.binding_buttons.thrust_forward[1].get_parent().get_child(4) as Button
	clear_button.pressed.emit()
	check(Bindings.bindings.thrust_forward[1] == null and Bindings.bindings.thrust_forward[0] != null,"UI clear button changes only the selected slot")
	Bindings.reset_defaults()
	var positive := InputEventJoypadMotion.new(); positive.axis = JOY_AXIS_LEFT_X; positive.axis_value = 0.8
	check(Bindings.pressed(positive,"turn_right"),"Analog direction crosses action threshold")
	var repeat := positive.duplicate() as InputEventJoypadMotion
	check(not Bindings.pressed(repeat,"turn_right"),"Held axis does not repeat toggle commands")
	menu.refresh(); menu.cancel_capture(); menu.scroll.scroll_vertical = 0
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280,800)
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/controls-menu-preview.png")
	menu.close_menu(); menu.queue_free()
	Bindings.bindings = original; Bindings.apply_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
	print("Controls: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
