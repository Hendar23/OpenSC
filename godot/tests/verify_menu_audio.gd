extends SceneTree
const FrontEnd = preload("res://front_end.gd")
const Paths = preload("res://asset_paths.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
var sounds: Array[String] = []
var exited := false
func _initialize() -> void: call_deferred("_run")
func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func _run() -> void:
	Mods.initialize(false)
	var menu := FrontEnd.new(); root.add_child(menu)
	var folder := Paths.find_game_folder()
	menu.load_art(folder)
	menu.menu_sound_played.connect(func(role: String) -> void: sounds.append(role))
	menu.new_game_requested.connect(menu.hide_menu)
	menu.exit_requested.connect(func() -> void: exited = true)
	await process_frame
	for role in menu.MENU_SOUNDS:
		var stream: AudioStreamWAV = menu.sound_players[role].stream
		check(stream != null and stream.mix_rate == 11025 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and stream.get_meta("asset_source").ends_with(menu.MENU_SOUNDS[role] + ".RAW"),"Menu sound %s uses the requested original one-shot" % role)
	menu.show_menu(false)
	check(sounds.is_empty(),"Opening the menu does not invent a hover sound")
	for route in [
		["new_game",JOY_BUTTON_DPAD_DOWN,"load"], ["load",JOY_BUTTON_DPAD_DOWN,"continue"],
		["continue",JOY_BUTTON_DPAD_DOWN,"website"], ["website",JOY_BUTTON_DPAD_DOWN,"exit"],
		["exit",JOY_BUTTON_DPAD_UP,"website"], ["website",JOY_BUTTON_DPAD_UP,"continue"],
		["continue",JOY_BUTTON_DPAD_UP,"load"], ["load",JOY_BUTTON_DPAD_UP,"new_game"],
		["new_game",JOY_BUTTON_DPAD_RIGHT,"controls"], ["controls",JOY_BUTTON_DPAD_LEFT,"new_game"],
		["load",JOY_BUTTON_DPAD_RIGHT,"audio"], ["audio",JOY_BUTTON_DPAD_LEFT,"load"],
		["continue",JOY_BUTTON_DPAD_RIGHT,"graphics"], ["graphics",JOY_BUTTON_DPAD_LEFT,"continue"],
		["controls",JOY_BUTTON_DPAD_DOWN,"audio"], ["audio",JOY_BUTTON_DPAD_DOWN,"graphics"],
		["graphics",JOY_BUTTON_DPAD_UP,"audio"], ["audio",JOY_BUTTON_DPAD_UP,"controls"],
		["new_game",JOY_BUTTON_DPAD_UP,"new_game"], ["exit",JOY_BUTTON_DPAD_DOWN,"exit"]
	]:
		menu.buttons[route[0]].grab_focus()
		var direction := InputEventJoypadButton.new(); direction.pressed = true; direction.button_index = route[1]
		menu._input(direction)
		check(root.gui_get_focus_owner() == menu.buttons[route[2]],"D-pad follows %s → %s" % [route[0],route[2]])
	menu.buttons.load.grab_focus()
	menu.buttons.load.pressed.emit()
	check(menu.menu_layer.visible,"Selecting an unimplemented menu entry keeps the menu open")
	menu.buttons.new_game.grab_focus(); sounds.clear()
	menu.buttons.exit.grab_focus()
	check(sounds == ["off","over"],"Controller focus change plays OFFBUTT then OVERBUTT")
	menu.buttons.exit.mouse_entered.emit()
	check(sounds.size() == 2,"Overlapping hover and focus do not double-play OVERBUTT")
	menu.buttons.exit.mouse_exited.emit()
	check(sounds.back() == "off" and sounds.size() == 3,"Moving the mouse off a button plays OFFBUTT")
	menu.buttons.new_game.mouse_entered.emit()
	check(sounds.back() == "over","Mouse hover plays OVERBUTT")
	menu.buttons.new_game.grab_focus()
	sounds.clear()
	paused = true
	var accept := InputEventJoypadButton.new(); accept.pressed = true; accept.button_index = JOY_BUTTON_A
	Input.parse_input_event(accept); await process_frame
	check(sounds == ["activate"] and not menu.menu_layer.visible,"Controller A plays ACTIVATE once, without an extra off sound on closing")
	var stream: AudioStream = menu.sound_players.activate.stream
	menu.load_art(folder)
	check(menu.sound_players.activate.stream == stream and menu.sound_players.activate.playing,"Reloading for New Game preserves its activation sound")
	menu.show_menu(false); menu.buttons.exit.grab_focus(); sounds.clear()
	menu.buttons.exit.pressed.emit()
	check(sounds == ["activate"] and not exited,"Exit starts ACTIVATE before quitting")
	for frame in range(240):
		if exited: break
		await process_frame
	check(exited,"Exit waits for ACTIVATE to finish even while the game is paused")
	paused = false; menu.queue_free(); await process_frame
	print("Menu audio: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
