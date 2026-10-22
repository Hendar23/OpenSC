extends Node3D
## Bounded visual/audio recording. Playback never runs gameplay controllers.
const Visual = preload("res://replay_visual.gd")
const Wake = preload("res://replay_wake.gd")
const INTERVAL := 0.05
const DURATION := 30.0
const MAX_TRACKS := 2048
const MAX_BYTES := 96*1024*1024
var game: Node
var tracks := {}
var wakes := {}
var pending := {}
var timeline := 0.0
var tick := -1
var clock := 0.0
var started := false
var bytes := 0
var enabled := true
var playing := false
var speed := 1.0
var cursor := 0.0
var oldest := 0.0
var frozen: Array[Dictionary] = []
var hidden_sources := {}
var playback: Node3D
var last_capture_usec := 0
var capture_total_usec := 0
var capture_count := 0
var shader_times := PackedFloat64Array()
var sample_times := PackedFloat64Array()
var audio: Node

func setup(context: Node) -> void:
	game = context; name = "PhotoReplay"; process_mode = Node.PROCESS_MODE_ALWAYS; process_priority = 1000
	audio = preload("res://replay_audio.gd").new(); add_child(audio); audio.setup()
	shader_times.resize(Visual.CAPACITY)
	sample_times.resize(Visual.CAPACITY)
	get_tree().node_added.connect(_added)
	game.events.session_started.connect(func(_loaded: bool) -> void: clear())

func set_enabled(value: bool) -> void:
	if enabled == value: return
	enabled = value
	if not enabled: clear()

func _process(delta: float) -> void:
	if playback != null or not enabled: return
	if game.world_loading or not game.has_started_game or not game.pilot_mode or not is_instance_valid(game.pilot) or game.pilot.dead:
		if started: clear()
		return
	if game.docking.stage != game.Docking.Stage.IDLE:
		if started: clear()
		return
	if get_tree().paused:
		audio.set_recording(false); return
	audio.set_recording(true)
	if not started:
		started = true; _scan(game)
	clock += delta
	if clock < INTERVAL: return
	# Never manufacture multiple identical frames after a hitch.
	var elapsed := clock; clock = 0
	capture(elapsed)

func _added(node: Node) -> void:
	if started and enabled and playback == null and (node is VisualInstance3D or node is Light3D): pending[node.get_instance_id()] = weakref(node)

func _scan(node: Node) -> void:
	if node == self or node is CanvasLayer or node is SubViewport or node is Camera3D: return
	if node is VisualInstance3D or node is Light3D: _register(node)
	for child in node.get_children(): _scan(child)

func _dynamic(node: Node) -> bool:
	var ancestor: Node = node
	while ancestor != null and ancestor != game:
		if ancestor is CanvasLayer or ancestor is SubViewport or ancestor == self or ancestor == game.photo_mode: return false
		if ancestor != game.world_root and (ancestor.get_script() != null or ancestor.has_meta("city_id") or ancestor.get_node_or_null("Trader") != null or ancestor.get_node_or_null("GunTurret") != null): return true
		ancestor = ancestor.get_parent()
	return false

func _register(node: Node3D) -> void:
	if not node.is_inside_tree() or not _dynamic(node): return
	var id := node.get_instance_id()
	if node is MultiMeshInstance3D:
		if node.get_parent().get_script() == preload("res://propeller_bubbles.gd") and not wakes.has(id):
			var wake := Wake.new(); wake.setup(node.get_parent(),timeline); wakes[id] = wake
		if node.get_script() != preload("res://water_particles.gd"): return
	if not (node is MeshInstance3D or node is Sprite3D or node is OmniLight3D or node is SpotLight3D or node is CPUParticles3D or node is MultiMeshInstance3D) or tracks.has(id) or tracks.size() >= MAX_TRACKS: return
	if node is MeshInstance3D and node.mesh == null: return
	var track := Visual.new(); track.setup(node,timeline)
	if bytes+track.data.size()*4 > MAX_BYTES: track.dispose(); return
	bytes += track.data.size()*4; tracks[id] = track

func capture(delta: float) -> void:
	var began := Time.get_ticks_usec()
	timeline += maxf(0,delta); tick += 1
	# Samples have timestamps because frame rate need not divide twenty Hz.
	shader_times[tick%Visual.CAPACITY] = fmod(Time.get_ticks_msec()/1000.0,3600.0)
	sample_times[tick%Visual.CAPACITY] = timeline
	oldest = maxf(0,timeline-DURATION)
	if audio != null: audio.capture(timeline,oldest)
	for entry in pending.values():
		var node: Node = entry.get_ref()
		if node != null: _register(node)
	pending.clear()
	for id in tracks.keys():
		var track: RefCounted = tracks[id]
		if track.last_seen < oldest and track.source.get_ref() == null:
			bytes -= track.data.size()*4; track.dispose(); tracks.erase(id); continue
		track.record(tick,timeline)
	for id in wakes.keys():
		var wake: RefCounted = wakes[id]; wake.record(timeline,oldest)
		if wake.last_seen < oldest and wake.source.get_ref() == null: wake.dispose(); wakes.erase(id)
	last_capture_usec = Time.get_ticks_usec()-began; capture_total_usec += last_capture_usec; capture_count += 1

func begin() -> bool:
	if not enabled or tick < 0: return false
	# Capture the exact present once before hiding it, with no simulation step.
	capture(clock); clock = 0
	audio.set_recording(false)
	playback = Node3D.new(); playback.name = "ReplayVisuals"; add_child(playback)
	frozen.clear(); hidden_sources.clear()
	for track in tracks.values(): _hide_source(track.source.get_ref())
	for wake in wakes.values():
		var node: Node = wake.source.get_ref()
		if node != null:
			for child in node.get_children():
				if child is MultiMeshInstance3D: _hide_source(child)
	_hide_overflow(game)
	cursor = timeline; playing = false; speed = 1.0
	seek(cursor)
	return true

func _hide_source(node: Node3D) -> void:
	if node == null or hidden_sources.has(node.get_instance_id()): return
	hidden_sources[node.get_instance_id()] = true
	frozen.append({"node":weakref(node),"visible":node.visible}); node.hide()

func _hide_overflow(node: Node) -> void:
	if node == game.photo_mode or node is CanvasLayer or node is SubViewport or node is Camera3D: return
	# A saturated budget must omit excess visuals instead of showing future
	# live objects inside the past. This walk occurs only when entering photo.
	if node is Node3D and (node is MeshInstance3D or node is Sprite3D or node is CPUParticles3D or node is OmniLight3D or node is SpotLight3D) and _dynamic(node): _hide_source(node)
	for child in node.get_children(): _hide_overflow(child)

func end() -> void:
	if audio != null: audio.stop()
	if playback == null: return
	for entry in frozen:
		var node: Node3D = entry.node.get_ref()
		if node != null: node.visible = entry.visible
	frozen.clear(); hidden_sources.clear()
	for track in tracks.values():
		if track.proxy != null: track.proxy.free(); track.proxy = null
	for wake in wakes.values():
		if wake.proxy != null: wake.proxy.free(); wake.proxy = null
	playback.free(); playback = null; playing = false
	RenderingServer.global_shader_parameter_set("osc_replay_active",false)

func seek(time: float, continuous: bool = false) -> void:
	if playback == null: return
	if not continuous: audio.stop()
	var first := maxi(0,tick-Visual.CAPACITY+1)
	while first < tick and _time(first) < oldest: first += 1
	cursor = clampf(time,_time(first),timeline)
	var low := first; var high := tick
	while low < high:
		var middle := (low+high+1)/2
		if _time(middle) <= cursor+0.000001: low = middle
		else: high = middle-1
	var fraction := clampf((cursor-_time(low))/maxf(0.000001,_time(mini(low+1,tick))-_time(low)),0,1)
	for track in tracks.values(): track.show_at(playback,low,fraction,cursor)
	for wake in wakes.values(): wake.show_at(playback,cursor,game.photo_mode.view)
	var shader_start := shader_times[low%Visual.CAPACITY]
	var shader_end := shader_times[mini(low+1,tick)%Visual.CAPACITY]
	if shader_end < shader_start-1800.0: shader_end += 3600.0
	RenderingServer.global_shader_parameter_set("osc_replay_time",fmod(lerpf(shader_start,shader_end,fraction),3600.0))
	RenderingServer.global_shader_parameter_set("osc_replay_active",true)

func _time(index: int) -> float:
	return sample_times[index%Visual.CAPACITY]

func advance(delta: float, scrub: float = 0.0) -> void:
	if playback == null: return
	if scrub != 0: playing = false; seek(cursor+scrub*delta*5.0)
	elif playing:
		seek(cursor+delta*speed,true)
		if cursor >= timeline: playing = false
	else:
		for track in tracks.values():
			if track.kind == "multi": track.refresh_view(game.photo_mode.view)
		for wake in wakes.values(): wake.show_at(playback,cursor,game.photo_mode.view)
	audio.update(cursor,playing and is_equal_approx(speed,1.0))

func toggle_play() -> void:
	if playback == null: return
	if cursor >= timeline: seek(oldest)
	playing = not playing
	audio.update(cursor,playing and is_equal_approx(speed,1.0))

func clear() -> void:
	end()
	if audio != null: audio.clear()
	for track in tracks.values(): track.dispose()
	for wake in wakes.values(): wake.dispose()
	tracks.clear(); wakes.clear(); pending.clear()
	timeline = 0; tick = -1; clock = 0; oldest = 0; bytes = 0; started = false
	sample_times.fill(0); shader_times.fill(0)
	capture_total_usec = 0; capture_count = 0; last_capture_usec = 0

func _exit_tree() -> void:
	clear()
