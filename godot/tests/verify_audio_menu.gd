extends SceneTree
const FrontEnd = preload("res://front_end.gd")
const Effects = preload("res://effects_audio.gd")
const Bindings = preload("res://input_bindings.gd")
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("_run")
func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func press(menu: Node,action: String) -> void:
	var event := InputEventAction.new(); event.action = action; event.pressed = true
	menu._input(event)

func _run() -> void:
	Bindings.install()
	var game := Node.new(); root.add_child(game)
	var early := AudioStreamPlayer.new(); game.add_child(early)
	var front := FrontEnd.new(); front.remember_preferences = false; game.add_child(front)
	await process_frame
	check(early.bus == &"Effects","Existing sounds join the global effects mix")
	for player in [AudioStreamPlayer.new(),AudioStreamPlayer2D.new(),AudioStreamPlayer3D.new()]:
		game.add_child(player)
		check(player.bus == &"Effects","New sounds join the global effects mix")
	AudioServer.add_bus(); var music_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(music_index,"Music")
	var music := AudioStreamPlayer.new(); music.bus = &"Music"; game.add_child(music)
	check(music.bus == &"Music","Music remains separate")
	front.show_menu(false); front._activate_button("options"); front._activate_button("audio")
	var menu: CanvasLayer = front.audio_menu
	check(menu.visible and menu.slider.has_focus(),"Audio page opens focused on effects volume")
	check(front.menu_layer.visible and front.menu_picture.visible and not front.buttons.audio.visible,"Audio keeps the main menu backdrop and title without overlapping options")
	check(menu.get_child(0).color.a == 0.0,"Audio does not cover the live sea background")
	check(menu.caption.get_theme_font_size("font_size") == front.buttons.audio.get_theme_font_size("font_size") and menu.back.size == front.buttons.audio.size,"Audio matches main menu font and button size")
	paused = true; press(menu,"menu_left")
	check(menu.slider.value == 99,"Controller/keyboard adjusts audio while paused")
	menu.slider.value = 50
	var index := AudioServer.get_bus_index("Effects")
	check(is_equal_approx(AudioServer.get_bus_volume_db(index),linear_to_db(0.5)),"Slider scales the final sound mix")
	check(early.volume_db == 0,"Individual sound gain stays unchanged")
	check(AudioServer.get_bus_volume_db(music_index) == 0,"Global effects slider leaves music unchanged")
	check(not menu.slider.scrollable,"Mouse wheel cannot adjust this slider")
	menu.slider.value = 200
	check(menu.slider.value == 200 and is_equal_approx(AudioServer.get_bus_volume_db(index),linear_to_db(2.0)),"200 percent doubles the baseline effects gain")
	menu.slider.value = 0
	check(AudioServer.is_bus_mute(index),"Zero volume mutes every effects sound")
	press(menu,"menu_down"); check(menu.back.has_focus(),"Controller can focus Back")
	press(menu,"menu_accept")
	check(not menu.visible and front.buttons.audio.has_focus(),"Back restores focus to Audio option")
	paused = false
	var path := "res://tests/audio_preferences_test.cfg"
	var config := ConfigFile.new(); config.set_value("controls","untouched",42); config.save(path)
	front.effects_audio.settings_path = path; front.effects_audio.remember_preferences = true
	check(front.effects_audio.set_volume(175) == OK,"Boosted volume automatically saves")
	config.load(path)
	check(config.get_value("controls","untouched") == 42,"Saving audio preserves other preferences")
	check(config.get_value("audio","effects_volume") == 175.0,"Preference records the player volume")
	var restored := Effects.new(); restored.settings_path = path; front.add_child(restored)
	check(restored.volume == 175.0,"Boosted effects volume is restored on next launch")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if OS.get_environment("OPENSC_CAPTURE_AUDIO") == "1":
		front._activate_button("audio")
		await process_frame; await process_frame
		root.get_texture().get_image().save_png("res://tests/audio-menu.png")
	game.free(); AudioServer.remove_bus(music_index)
	print("Audio menu: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
