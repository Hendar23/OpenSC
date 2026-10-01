extends SceneTree
const Game = preload("res://game.gd")
const Tuning = preload("res://sound_tuning.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(description)
func _run() -> void:
	Mods.initialize(false)
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete and game.sound_panel != null, "Game creates the sound tuning panel")
	var panel: PanelContainer = game.sound_panel
	var audio: Node = game.pilot.submarine_audio
	game._toggle_sound_tuning()
	check(game.canvas.visible and panel.visible and not game.tuning_panel.visible, "Sound shortcut reveals developer UI without overlapping movement tuning")
	check(panel.sliders.size() == 26, "All 26 independent sound controls are available")
	panel.sliders.main_propeller_volume.value = -18
	panel.sliders.main_propeller_pitch_max.value = 2.5
	check(audio.tuning.settings.main_propeller_volume == -18 and audio.tuning.settings.main_propeller_pitch_max == 2.5, "Sliders update the live mix")
	panel.sliders.impact_pitch_variation.value = 0.08
	panel.sliders.impact_creak_chance.value = 0.3
	check(is_equal_approx(audio.tuning.settings.impact_pitch_variation, 0.08) and is_equal_approx(audio.tuning.settings.impact_creak_chance, 0.3), "Collision controls update the live randomization settings")
	panel.sliders.dock_doors_volume.value = -22.0
	panel.sliders.impact_rumble_strength.value = 0.4
	game.docking.audio._process(0.0)
	check(game.docking.audio.players.doors.volume_db == -22.0, "Docking gain slider updates its live audio player")
	panel.preview_button.button_pressed = true
	game.pilot.propeller_speeds = Vector3.ZERO
	audio.update(0.5)
	check(audio.preview and audio.players.main_propeller.playing, "Stationary preview plays independently of propulsion input")
	game._toggle_tuning()
	check(not audio.preview and not panel.visible, "Switching panels stops the audio preview")
	game._toggle_sound_tuning()
	panel.preview_button.button_pressed = true
	game._toggle_developer_ui()
	check(not audio.preview and not game.canvas.visible, "Hiding developer UI also stops the preview")
	var path := "res://tests/sound-settings-test.cfg"
	check(audio.tuning.save_settings(path) == OK, "Sound mix exports to a CFG file")
	var restored := Tuning.new()
	restored.load_settings(false, path, path)
	check(restored.settings.main_propeller_volume == -18 and restored.settings.main_propeller_pitch_max == 2.5, "Exported sound settings load as defaults")
	check(is_equal_approx(restored.settings.impact_pitch_variation, 0.08) and is_equal_approx(restored.settings.impact_creak_chance, 0.3), "Collision settings export and load as defaults alongside the mix")
	check(restored.settings.dock_doors_volume == -22.0, "Docking gain exports and loads as a default")
	check(is_equal_approx(restored.settings.impact_rumble_strength, 0.4), "Controller rumble strength exports and loads as a default")
	panel._reset()
	check(audio.tuning.settings == audio.tuning.defaults, "Reset restores sound defaults independently of movement")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.queue_free()
	await create_timer(0.25).timeout
	print("Sound panel verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
