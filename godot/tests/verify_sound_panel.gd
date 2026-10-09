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
	check(panel.sliders.has("explosion_volume") and panel.sliders.has("low_shield_volume"), "Explosion and shield warning sound controls are available")
	check(panel.sliders.has("dock_menu_volume") and not panel.sliders.dock_menu_volume.scrollable,"Dock menu volume is adjustable without mouse-wheel changes")
	panel.sliders.dock_menu_volume.value = -18
	panel.sliders.master_volume.value = -3
	game.dock_interface.open("home"); game.dock_interface._play_menu_sound("commodity_trade")
	check(game.dock_interface.sound_players.commodity_trade.volume_db == -21,"Dock transaction gain combines with the master volume live")
	panel.sliders.dock_menu_volume.value = -60; game.dock_interface._play_menu_sound("commodity_trade")
	check(game.dock_interface.sound_players.commodity_trade.volume_db == -80,"Dock menu slider can mute its sounds")
	panel.sliders.dock_menu_volume.value = -18; panel.sliders.master_volume.value = -60
	game.dock_interface._play_menu_sound("commodity_trade")
	check(game.dock_interface.sound_players.commodity_trade.volume_db == -80,"Master mute also mutes dock menu audio")
	panel.sliders.master_volume.value = 0; game.dock_interface.dismiss()
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
	check(restored.settings.dock_menu_volume == -18,"Dock menu volume exports and reloads")
	check(is_equal_approx(restored.settings.impact_rumble_strength, 0.4), "Controller rumble strength exports and loads as a default")
	var burst := preload("res://mine_explosion.gd").new(); game.world_root.add_child(burst)
	burst.setup([],1.0,game.submarine_explosion_sound)
	panel.sliders.master_volume.value = -3; panel.sliders.explosion_volume.value = -20
	burst._process(0.0)
	check(burst.audio.volume_db == -23,"Explosion volume combines with master volume")
	panel.sliders.explosion_volume.value = -60; burst._process(0.0)
	check(burst.audio.volume_db == -80,"Explosion slider supports muting")
	check(not panel.find_children("*","Button",true,false).any(func(b: Button) -> bool: return b.text == "Save" and not panel.export_dialog.is_ancestor_of(b)) and not game.tuning_panel.find_children("*","Button",true,false).any(func(b: Button) -> bool: return b.text == "Save settings" and not game.tuning_panel.export_dialog.is_ancestor_of(b)),"Manual Save buttons are removed")
	game.defaults_directory = "res://tests/autosave-defaults"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(game.defaults_directory))
	game.remember_preferences = true
	game.tuning_panel.sliders.main_forward.value = 670
	panel.sliders.explosion_volume.value = -17
	game.equipment_controls.som_radius.value = 0.32
	panel.sliders.dock_menu_volume.value = -24
	await process_frame
	game.remember_preferences = false
	var shipped_view := ConfigFile.new(); shipped_view.load(game.defaults_directory.path_join("view_defaults.cfg"))
	var shipped_sound := ConfigFile.new(); shipped_sound.load(game.defaults_directory.path_join("submarine_audio.cfg"))
	var shipped_movement := ConfigFile.new(); shipped_movement.load(game.defaults_directory.path_join("submarine_tuning.cfg"))
	check(shipped_movement.get_value("movement","main_forward") == 670 and shipped_sound.get_value("sound","explosion_volume") == -17 and is_equal_approx(shipped_view.get_value("view","som_radius"),0.32),"Changes automatically update the single current settings set")
	var loaded := Tuning.new(); loaded.load_settings(false,"",game.defaults_directory.path_join("submarine_audio.cfg"))
	check(loaded.settings.explosion_volume == -17,"A fresh settings instance reads the same current values")
	check(loaded.settings.dock_menu_volume == -24,"Dock menu volume saves automatically and survives reload")
	check(shipped_sound.get_value("settings","unified",false) and shipped_movement.get_value("settings","unified",false),"Autosaving retains the completed legacy migration marker")
	var stale_path := game.defaults_directory.path_join("stale-movement.cfg")
	var stale := ConfigFile.new(); stale.set_value("movement","main_forward",50); stale.save(stale_path)
	shipped_movement.erase_section("settings"); shipped_movement.save(game.defaults_directory.path_join("submarine_tuning.cfg"))
	preload("res://current_settings.gd").migrate_legacy(stale_path,stale_path,game.defaults_directory)
	shipped_movement.load(game.defaults_directory.path_join("submarine_tuning.cfg"))
	check(shipped_movement.get_value("movement","main_forward") == 670 and shipped_movement.get_value("settings","unified",false),"An earlier autosave without its marker cannot reimport stale legacy settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stale_path))
	var blocked_path := ProjectSettings.globalize_path(game.defaults_directory.path_join("submarine_tuning.cfg"))
	DirAccess.remove_absolute(blocked_path); DirAccess.make_dir_absolute(blocked_path)
	game.remember_preferences = true; game._save_all_preferences()
	check(game.status_label.text.contains("submarine_tuning.cfg") and game.settings_save_pending,"An autosave failure identifies the file and schedules a retry")
	DirAccess.remove_absolute(blocked_path)
	await create_timer(0.4).timeout
	check(FileAccess.file_exists(blocked_path) and game.settings_save_error.is_empty() and not game.settings_save_pending,"Autosave recovers from a temporary write failure and clears its warning")
	game.remember_preferences = false
	for file in ["view_defaults.cfg","submarine_audio.cfg","submarine_tuning.cfg"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(game.defaults_directory.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.defaults_directory))
	burst.queue_free()
	check(not panel.find_children("*","Button",true,false).any(func(b: Button) -> bool: return b.text == "Reset defaults") and not game.tuning_panel.find_children("*","Button",true,false).any(func(b: Button) -> bool: return b.text == "Reset defaults"), "Neither developer panel offers a defaults reset")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game.queue_free()
	await create_timer(0.25).timeout
	print("Sound panel verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
