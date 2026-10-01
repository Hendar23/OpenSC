extends Node
signal effect_played(role: String, pitch: float)
signal impact_accepted(speed: float)

const Mods = preload("res://mod_registry.gd")
const AudioLoop = preload("res://audio_loop.gd")
const LegacyAudio = preload("res://legacy_audio.gd")
const Tuning = preload("res://sound_tuning.gd")
const SAMPLES := {"main_propeller": "PROP3", "side_pods": "PROP4", "pod_rotation": "PROP1"}
const ONE_SHOTS := {"impact_hit1": "HIT1", "impact_hit3": "HIT3", "impact_creaking": "CREAKING"}
var effect_players := {}
var pending_creaks: Array[Dictionary] = []
var impact_cooldown := 0.0
var random := RandomNumberGenerator.new()
var players := {}
var levels := Vector3.ZERO
var pilot: RigidBody3D
var tuning := Tuning.new()
var solo_role := ""
var preview := false
var preview_load := 0.75
var source_streams := {}
var applied_blend := -1.0

func setup(body: RigidBody3D, folder: String) -> void:
	pilot = body
	for child in get_children(): child.free()
	players.clear()
	effect_players.clear()
	pending_creaks.clear()
	impact_cooldown = 0.0
	random.randomize()
	levels = Vector3.ZERO
	solo_role = ""
	preview = false
	tuning.load_settings(body.remember_settings)
	source_streams.clear()
	for role in SAMPLES:
		var player := AudioStreamPlayer.new()
		player.name = role
		player.stream = load_sound(folder, role)
		source_streams[role] = player.stream
		player.volume_db = -80.0
		add_child(player)
		players[role] = player
	rebuild_loops()
	for role in ONE_SHOTS:
		var player := AudioStreamPlayer.new()
		player.name = role
		player.stream = AudioLoop.prepare(load_sound(folder, role), false)
		player.max_polyphony = 3
		add_child(player)
		effect_players[role] = player

func rebuild_loops() -> void:
	applied_blend = float(tuning.settings.loop_blend_ms)
	for role in players:
		var source: AudioStream = source_streams[role]
		players[role].stream = AudioLoop.prepare(source, true, applied_blend)

# Compatibility entry points; all PCM loop preparation lives in one helper.
static func guarded_loop(source: AudioStreamWAV) -> AudioStreamWAV:
	return AudioLoop.guarded_loop(source)

static func seamless_loop(source: AudioStreamWAV, milliseconds: float) -> AudioStreamWAV:
	return AudioLoop.seamless_loop(source, milliseconds)

static func load_sound(folder: String, role: String) -> AudioStream:
	for replacement in Mods.candidates("audio.submarine." + role):
		var stream := _read_stream(replacement.path)
		if stream != null:
			stream.set_meta("asset_mod", replacement.name)
			return stream
		Mods.note("%s: could not load submarine audio %s; using the next replacement or original." % [replacement.name, role])
	var sample: String = SAMPLES.get(role, ONE_SHOTS.get(role, ""))
	return _read_stream(folder.path_join("WAVES/" + sample + ".RAW")) if not sample.is_empty() else null

static func _read_stream(path: String) -> AudioStream:
	var stream := LegacyAudio.load_file(path)
	if stream == null: return null
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	else: stream.loop = true
	stream.set_meta("asset_source", path)
	return stream

func silence() -> void:
	levels = Vector3.ZERO
	pending_creaks.clear()
	impact_cooldown = 0.0
	for player in players.values(): player.stop(); player.volume_db = -80.0
	for player in effect_players.values(): player.stop()

func impact(speed: float) -> bool:
	if not is_instance_valid(pilot) or not pilot.active or not is_instance_valid(pilot.visual) or not pilot.visual.is_visible_in_tree(): return false
	if speed < float(tuning.settings.impact_min_speed) or impact_cooldown > 0.0: return false
	var role := "impact_hit1" if random.randi_range(0, 1) == 0 else "impact_hit3"
	var player: AudioStreamPlayer = effect_players.get(role)
	impact_cooldown = float(tuning.settings.impact_cooldown)
	impact_accepted.emit(speed)
	# Small pitch variation changes timbre and duration without making the hull cartoonish.
	var variation := float(tuning.settings.impact_pitch_variation)
	var pitch := random.randf_range(1.0 - variation, 1.0 + variation)
	var level := lerpf(0.3, 1.0, clampf(speed / maxf(0.1, float(pilot.movement.settings.forward_speed)), 0.0, 1.0))
	_play_effect(role, pitch, level)
	if player != null and player.stream != null and random.randf() < float(tuning.settings.impact_creak_chance):
		pending_creaks.append({"remaining": player.stream.get_length() / pitch + random.randf_range(0.15, 0.5), "pitch": random.randf_range(1.0 - variation, 1.0 + variation), "level": level})
	return true

func _play_effect(role: String, pitch: float, level: float) -> void:
	var player: AudioStreamPlayer = effect_players.get(role)
	if player == null or player.stream == null: return
	var gain := float(tuning.settings.creaking_volume if role == "impact_creaking" else tuning.settings.impact_volume)
	player.pitch_scale = pitch
	player.set_meta("effect_level", level)
	player.volume_db = -80.0 if gain <= -60.0 or float(tuning.settings.master_volume) <= -60.0 or not solo_role.is_empty() else float(tuning.settings.master_volume) + gain + linear_to_db(level)
	player.play()
	effect_played.emit(role, pitch)

func _update_effects(delta: float) -> void:
	impact_cooldown = maxf(0.0, impact_cooldown - delta)
	for index in range(pending_creaks.size() - 1, -1, -1):
		pending_creaks[index].remaining -= delta
		if pending_creaks[index].remaining <= 0.0:
			var creak: Dictionary = pending_creaks[index]
			pending_creaks.remove_at(index)
			_play_effect("impact_creaking", creak.pitch, creak.level)
	# Master gain / solo changes should also affect a one-shot already playing.
	for role in effect_players:
		var player: AudioStreamPlayer = effect_players[role]
		var gain := float(tuning.settings.creaking_volume if role == "impact_creaking" else tuning.settings.impact_volume)
		player.volume_db = -80.0 if gain <= -60.0 or float(tuning.settings.master_volume) <= -60.0 or not solo_role.is_empty() else float(tuning.settings.master_volume) + gain + linear_to_db(float(player.get_meta("effect_level", 1.0)))

func update(delta: float) -> void:
	if not is_instance_valid(pilot) or not is_instance_valid(pilot.visual):
		silence()
		return
	if not pilot.visual.is_visible_in_tree():
		silence()
		return
	_update_effects(delta)
	var speeds: Vector3 = pilot.propeller_speeds.abs()
	var targets := Vector3(speeds.x, maxf(speeds.y, speeds.z), pilot.pod_rotation_power)
	var settings: Dictionary = tuning.settings
	levels = levels.lerp(Vector3.ONE * preview_load if preview else targets, 1.0 - exp(-delta / float(settings.volume_response)))
	var speed := clampf(pilot.velocity.length() / maxf(0.1, float(pilot.movement.settings.forward_speed)), 0.0, 1.0)
	if preview: speed = preview_load
	var roles := ["main_propeller", "side_pods", "pod_rotation"]
	for i in range(3):
		var player: AudioStreamPlayer = players.get(roles[i])
		if player == null or player.stream == null: continue
		var level: float = levels[i]
		if level < 0.01:
			player.stop()
			player.volume_db = -80.0
			continue
		# Keep sample phase continuous; never restart the loop for pitch changes.
		if not player.playing: player.play()
		var role: String = roles[i]
		var desired_pitch := lerpf(float(settings[role + "_pitch_min"]), float(settings[role + "_pitch_max"]), level) + speed * float(settings[role + "_speed_pitch"])
		player.pitch_scale = clampf(lerpf(player.pitch_scale, desired_pitch, 1.0 - exp(-delta / float(settings.pitch_response))), 0.25, 4.0)
		player.volume_db = -80.0 if (not solo_role.is_empty() and solo_role != role) or float(settings[role + "_volume"]) <= -60.0 or float(settings.master_volume) <= -60.0 else float(settings.master_volume) + float(settings[role + "_volume"]) + linear_to_db(level * (0.8 + speed * 0.2))
