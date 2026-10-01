extends SceneTree
const Pilot = preload("res://submarine_controller.gd")
const Paths = preload("res://asset_paths.gd")
const Mods = preload("res://mod_registry.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Mods.initialize(false)
	var pilot := Pilot.new()
	pilot.remember_settings = false
	root.add_child(pilot)
	pilot.visual = Node3D.new()
	pilot.add_child(pilot.visual)
	pilot.set_process(false)
	pilot.submarine_audio.setup(pilot, Paths.find_game_folder())
	var record := AudioEffectRecord.new()
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "SoundPreview")
	AudioServer.add_bus_effect(bus, record)
	for player in pilot.submarine_audio.players.values(): player.bus = "SoundPreview"
	# Record the actual mixed loops without playing the test through speakers.
	AudioServer.set_bus_mute(bus, true)
	record.set_recording_active(true)
	for frame in range(390):
		var time := frame / 60.0
		var main := clampf(time / 2.0, 0.0, 1.0) if time < 2.0 else maxf(0.0, 1.0 - (time - 2.0) / 0.7)
		var side := clampf((time - 3.0) / 2.0, 0.0, 1.0) if time < 5.0 else maxf(0.0, 1.0 - (time - 5.0) / 0.7)
		pilot.propeller_speeds = Vector3(main, side, side)
		pilot.pod_rotation_power = 1.0 if time >= 5.8 and time < 6.3 else 0.0
		pilot.movement.main_power = main if time < 2.0 else 0.0
		pilot.velocity = Vector3.FORWARD * (main + side) * 3.0
		pilot.submarine_audio.update(1.0 / 60.0)
		await physics_frame
	record.set_recording_active(false)
	var stream := record.get_recording()
	var error := stream.save_to_wav(ProjectSettings.globalize_path("res://tests/submarine-sound-preview.wav"))
	pilot.free()
	await create_timer(0.25).timeout
	print("Submarine audio preview: ", stream.get_length(), " seconds, saved ", error == OK)
	quit(0 if error == OK else 1)
