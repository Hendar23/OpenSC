extends Node
signal door_finished

const Mods = preload("res://mod_registry.gd")
const LegacyAudio = preload("res://legacy_audio.gd")
const AudioLoop = preload("res://audio_loop.gd")
const SAMPLES := {"sequence": "DOCKING", "doors": "DOCK", "door_stop": "DOCKSHUT"}
const GAINS := {"sequence": "docking_volume", "doors": "dock_doors_volume", "door_stop": "dock_shut_volume"}
var players := {}
var sources := {}
var tuning: RefCounted
var submarine_audio: Node
var sequence_active := false
var doors_active := false
var applied_blend := -1.0

func setup(sound: Node, folder: String) -> void:
	submarine_audio = sound
	tuning = sound.tuning
	for child in get_children(): child.free()
	players.clear()
	sources.clear()
	sequence_active = false
	doors_active = false
	for role in SAMPLES:
		var player := AudioStreamPlayer.new()
		player.name = role
		player.volume_db = -80.0
		add_child(player)
		players[role] = player
		sources[role] = load_sound(folder, role)
	rebuild_loops()
	_update_gains()

static func load_sound(folder: String, role: String) -> AudioStream:
	for replacement in Mods.candidates("audio.docking." + role):
		var stream := LegacyAudio.load_file(replacement.path)
		if stream != null:
			stream.set_meta("asset_mod", replacement.name)
			return stream
		Mods.note("%s: could not load docking audio %s; using the next replacement or original." % [replacement.name, role])
	return LegacyAudio.load_file(folder.path_join("WAVES/" + str(SAMPLES[role]) + ".RAW"))

func rebuild_loops() -> void:
	applied_blend = float(tuning.settings.loop_blend_ms)
	for role in players:
		if role != "sequence" and players[role].stream != null: continue
		players[role].stream = AudioLoop.prepare(sources[role], role == "sequence", applied_blend if role == "sequence" else 0.0)
	_update_loops()

func set_phase(active: bool, moving_doors: bool, finished: bool = false) -> void:
	var started_doors := moving_doors and not doors_active
	sequence_active = active
	doors_active = moving_doors
	_update_gains()
	_update_loops()
	var doors: AudioStreamPlayer = players.get("doors")
	if doors != null and doors.stream != null:
		if started_doors: doors.play()
		elif not moving_doors: doors.stop()
	if finished:
		var player: AudioStreamPlayer = players.get("door_stop")
		if player != null and player.stream != null: player.play()
		door_finished.emit()

func _update_loops() -> void:
	for role in ["sequence"]:
		var player: AudioStreamPlayer = players.get(role)
		if player == null or player.stream == null: continue
		var active := sequence_active if role == "sequence" else doors_active
		if active and not player.playing: player.play()
		elif not active: player.stop()

func _update_gains() -> void:
	if tuning == null: return
	for role in players:
		var gain := float(tuning.settings[GAINS[role]])
		var solo: bool = is_instance_valid(submarine_audio) and not submarine_audio.solo_role.is_empty()
		players[role].volume_db = -80.0 if gain <= -60.0 or float(tuning.settings.master_volume) <= -60.0 or solo else gain + float(tuning.settings.master_volume)

func _process(_delta: float) -> void:
	if tuning == null: return
	if applied_blend != float(tuning.settings.loop_blend_ms): rebuild_loops()
	_update_gains()

func stop() -> void:
	sequence_active = false
	doors_active = false
	for player in players.values(): player.stop()
