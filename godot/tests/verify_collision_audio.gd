extends SceneTree
const Pilot = preload("res://submarine_controller.gd")
const Paths = preload("res://asset_paths.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
var events: Array[Dictionary] = []
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(description)
func _run() -> void:
	Mods.initialize(false)
	var pilot := Pilot.new()
	pilot.remember_settings = false
	pilot.active = true
	pilot.controls_enabled = false
	root.add_child(pilot)
	pilot.visual = Node3D.new()
	pilot.add_child(pilot.visual)
	pilot.set_process(false)
	pilot.submarine_audio.setup(pilot, Paths.find_game_folder())
	var audio: Node = pilot.submarine_audio
	audio.effect_played.connect(func(role: String, pitch: float) -> void: events.append({"role": role, "pitch": pitch}))
	for role in audio.ONE_SHOTS:
		var stream: AudioStreamWAV = audio.effect_players[role].stream
		check(stream != null and stream.mix_rate == 11025 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s is a one-shot at the original sample rate" % role)
	check(not audio.impact(0.1) and events.is_empty(), "Tiny contacts do not trigger hull sounds")
	audio.tuning.settings.impact_creak_chance = 1.0
	check(audio.impact(3.0) and events.size() == 1, "A meaningful impact plays exactly one hit immediately")
	var quiet: float = audio.effect_players[events.back().role].volume_db
	check(not audio.impact(3.0) and events.size() == 1, "Cooldown prevents collision chatter")
	check(audio.pending_creaks.size() == 1 and audio.pending_creaks[0].remaining > 0.5, "Creak is scheduled after the hit finishes")
	audio.update(0.1)
	check(events.size() == 1, "Creak is not played on the impact frame")
	audio.update(4.0)
	check(events.size() == 2 and events.back().role == "impact_creaking", "Delayed creak plays after the hit")
	audio.tuning.settings.impact_creak_chance = 0.2
	audio.random.seed = 8172
	var hits := {"impact_hit1": 0, "impact_hit3": 0}
	var creaks := 0
	var varied := {}
	var bounded := true
	for impact in range(1000):
		audio.update(4.0)
		audio.impact(4.6)
		var event: Dictionary = events.back()
		hits[event.role] += 1
		varied[event.pitch] = true
		bounded = bounded and event.pitch >= 0.95 and event.pitch <= 1.05
		creaks += audio.pending_creaks.size()
	check(hits.impact_hit1 > 400 and hits.impact_hit3 > 400, "Both HIT1 and HIT3 are randomly selected")
	check(creaks > 150 and creaks < 250, "Creaks occur approximately one in five times")
	check(bounded and varied.size() > 900, "Hit pitch varies within the configured ±5% range")
	check(audio.effect_players[events.back().role].volume_db > quiet, "Harder impacts are louder")
	audio.tuning.settings.impact_creak_chance = 1.0
	audio.update(4.0)
	audio.impact(3.0)
	pilot.reset_at(Vector3.ZERO)
	check(audio.pending_creaks.is_empty() and audio.effect_players.values().all(func(p: AudioStreamPlayer) -> bool: return not p.playing), "Reset cancels hits and scheduled creaking")
	audio.impact(3.0)
	pilot.visual.hide()
	audio.update(0.1)
	check(audio.pending_creaks.is_empty() and not audio.impact(3.0), "Hidden docked hull cannot play delayed or new impacts")
	pilot.visual.show()
	audio.tuning.settings.impact_creak_chance = 0.0
	events.clear()
	# Real physics integration: hit a wall and remain pressed against it.
	var wall := StaticBody3D.new()
	wall.position = Vector3(2.0, 0.0, 0.0)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 10, 10)
	collision.shape = box
	wall.add_child(collision)
	root.add_child(wall)
	pilot.reset_at(Vector3.ZERO)
	pilot.velocity = Vector3.RIGHT * 4.0
	for frame in range(90):
		audio.update(1.0 / 60.0)
		await physics_frame
	check(events.size() == 1 and pilot.position.x <= wall.position.x - box.size.x / 2.0 - pilot.COLLIDER_RADIUS + 0.02, "Real wall collision plays one impact and blocks the hull")
	var hits_before := events.size()
	for frame in range(60):
		pilot.velocity = Vector3.RIGHT * 0.1
		audio.update(1.0 / 60.0)
		await physics_frame
	check(events.size() == hits_before, "Remaining in contact does not repeatedly play hits")
	var floor_collision := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(10, 1, 10)
	floor_collision.shape = floor_box
	floor_collision.position = Vector3(-2, -pilot.COLLIDER_RADIUS - 0.5, 0)
	wall.add_child(floor_collision)
	pilot.reset_at(Vector3.ZERO)
	events.clear()
	for frame in range(10):
		audio.update(1.0 / 60.0)
		await physics_frame
	pilot.velocity = Vector3.RIGHT * 4.0
	for frame in range(90):
		audio.update(1.0 / 60.0)
		await physics_frame
	check(events.size() == 1, "Floor contact does not suppress a wall impact on another face of the same terrain body")
	pilot.surface_height = 1.5
	pilot.reset_at(Vector3.ZERO)
	pilot.velocity = Vector3.UP * 3.0
	events.clear()
	for frame in range(60):
		audio.update(1.0 / 60.0)
		await physics_frame
	check(events.size() == 1 and pilot.position.y <= 1.5 - pilot.COLLIDER_RADIUS, "Water surface impact also plays a single hit while blocking ascent")
	# Mod replacements are decoded through the same one-shot path.
	var fixture := "res://tests/collision-audio-mod"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(4410)
	wave.data = samples
	wave.save_to_wav(ProjectSettings.globalize_path(fixture.path_join("hit.wav")))
	var manifest := FileAccess.open(fixture.path_join("mod.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema_version": 1, "id": "collision.audio.test", "assets": {"audio.submarine.impact_hit1": "hit.wav"}}))
	manifest.close()
	Mods.initialize(false, "res://tests")
	Mods.apply(["collision.audio.test"], Mods.order, false)
	audio.setup(pilot, Paths.find_game_folder())
	check(audio.effect_players.impact_hit1.stream.mix_rate == 22050 and audio.effect_players.impact_hit1.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Modern WAV collision replacement remains a one-shot")
	Mods.apply([], Mods.order, false)
	audio.setup(pilot, Paths.find_game_folder())
	check(audio.effect_players.impact_hit1.stream.get_meta("asset_source").ends_with("HIT1.RAW"), "Disabling collision replacement restores original sound")
	for path in ["hit.wav", "mod.json"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture.path_join(path)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	Mods.initialize(false)
	pilot.free()
	wall.free()
	await create_timer(0.25).timeout
	print("Collision audio verification: %d checks, %d failures; random creaks %d/1000" % [checks, failures, creaks])
	quit(1 if failures else 0)
