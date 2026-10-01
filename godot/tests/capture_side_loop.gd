extends SceneTree
const Audio = preload("res://submarine_audio.gd")
const Paths = preload("res://asset_paths.gd")
const Mods = preload("res://mod_registry.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Mods.initialize(false)
	var role := "main_propeller" if "--main" in OS.get_cmdline_user_args() else "side_pods"
	var source: AudioStreamWAV = Audio.load_sound(Paths.find_game_folder(), role)
	var record := AudioEffectRecord.new()
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "SideCapture")
	AudioServer.add_bus_effect(bus, record)
	AudioServer.set_bus_mute(bus, true)
	var player := AudioStreamPlayer.new()
	root.add_child(player)
	player.bus = "SideCapture"
	player.volume_db = -10.0
	player.pitch_scale = 0.96
	for blend in [0.0, 19.0]:
		player.stream = Audio.guarded_loop(Audio.seamless_loop(source, blend))
		record.set_recording_active(true)
		player.play()
		await create_timer(4.0).timeout
		player.stop()
		record.set_recording_active(false)
		record.get_recording().save_to_wav(ProjectSettings.globalize_path("res://tests/%s-loop-fixed-%d.wav" % [role, int(blend)]))
	player.free()
	await create_timer(0.25).timeout
	print(role, " loop captures saved")
	quit()
