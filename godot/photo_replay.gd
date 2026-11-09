extends Node3D
## Thirty-second visual/audio recording. Playback never runs gameplay controllers.
const Visual = preload("res://replay_visual.gd")
const Wake = preload("res://replay_wake.gd")
const INTERVAL := 0.05
const DURATION := 30.0
var game: Node
var tracks := {}
var wakes := {}
var pending := {}
var archive_id := -1
var timeline := 0.0
var tick := -1
var clock := 0.0
var started := false
var death_captured := false
var enabled := true
var playing := false
var speed := 1.0
var cursor := 0.0
var oldest := 0.0
var frozen: Array[Dictionary] = []
var hidden_sources := {}
var playback: Node3D
var last_capture_usec := 0
var last_visual_usec := 0
var last_wake_usec := 0
var last_audio_usec := 0
var capture_total_usec := 0
var capture_count := 0
var shader_times := PackedFloat64Array()
var sample_times := PackedFloat64Array()
var ambient_positions := PackedVector3Array()
var audio: Node

func setup(context: Node) -> void:
	game = context; name = "PhotoReplay"; process_mode = Node.PROCESS_MODE_ALWAYS; process_priority = 1000
	audio = preload("res://replay_audio.gd").new(); add_child(audio); audio.setup()
	shader_times.resize(Visual.CAPACITY)
	sample_times.resize(Visual.CAPACITY)
	ambient_positions.resize(Visual.CAPACITY)
	get_tree().node_added.connect(_added)
	get_tree().node_removed.connect(_removed)
	game.events.session_started.connect(func(_loaded: bool) -> void: clear())

func set_enabled(value: bool) -> void:
	if enabled == value: return
	enabled = value
	if not enabled: clear()

func _process(delta: float) -> void:
	if playback != null or not enabled: return
	if game.world_loading or not game.has_started_game or not game.pilot_mode or not is_instance_valid(game.pilot):
		if started: clear()
		return
	if game.pilot.dead:
		# Retain the final voyage instead of overwriting it with time spent at
		# Game Over. Include the destruction visuals once before freezing it.
		if started and not death_captured:
			capture(clock); clock = 0; death_captured = true
		audio.set_recording(false)
		return
	if game.docking.stage != game.Docking.Stage.IDLE:
		if started: clear()
		return
	if get_tree().paused:
		audio.set_recording(false); return
	audio.set_recording(true)
	if not started:
		_start_recording()
	clock += delta
	if clock < INTERVAL:
		_register_pending(); return
	# Never manufacture multiple identical frames after a hitch.
	var elapsed := clock; clock = 0
	capture(elapsed)

func _start_recording() -> void:
	started = true
	# Every existing actor needs the first sample. Discovering the world in
	# time slices leaves holes that photo entry cannot reconstruct afterwards.
	_scan(game)
	capture(0)

func _added(node: Node) -> void:
	if started and enabled and playback == null and (node is VisualInstance3D or node is Light3D): pending[node.get_instance_id()] = weakref(node)

func _removed(node: Node) -> void:
	var id := node.get_instance_id()
	pending.erase(id)
	if not tracks.has(id): return
	# Ambient fish are pooled and re-enter with the same instance IDs. Their
	# earlier voyage must not interpolate into the next fish's spawn position.
	var track: RefCounted = tracks[id]
	track.detached = true
	tracks.erase(id); tracks[archive_id] = track; archive_id -= 1

func _scan(node: Node, defer_registration: bool = false) -> void:
	if node == self or node is CanvasLayer or node is SubViewport or node is Camera3D: return
	if node is VisualInstance3D or node is Light3D:
		if defer_registration: pending[node.get_instance_id()] = weakref(node)
		else: _register(node)
	for child in node.get_children(): _scan(child,defer_registration)

func _register_pending() -> void:
	for id in pending.keys():
		var node: Node = pending[id].get_ref(); pending.erase(id)
		if node != null: _register(node)

func _dynamic(node: Node) -> bool:
	var ancestor: Node = node
	var dynamic := false
	while ancestor != null and ancestor != game:
		if ancestor is CanvasLayer or ancestor is SubViewport or ancestor == self or ancestor == game.photo_mode: return false
		if ancestor != game.world_root and (ancestor.get_script() != null or ancestor.has_meta("city_id") or ancestor.get_node_or_null("Trader") != null or ancestor.get_node_or_null("GunTurret") != null): dynamic = true
		ancestor = ancestor.get_parent()
	return dynamic

func _register(node: Node3D) -> void:
	if not node.is_inside_tree() or node.get_script() == preload("res://water_particles.gd") or not _dynamic(node): return
	var id := node.get_instance_id()
	# Constructors and streamed shoals can be incomplete when node_added fires.
	# Keep them waiting until ready, rather than losing them until photo entry.
	var ancestor: Node = node
	while ancestor != null and ancestor != game:
		if ancestor.get_meta("wildlife_preparing",false):
			pending[id] = weakref(node); return
		ancestor = ancestor.get_parent()
	if node is MultiMeshInstance3D:
		if node.get_parent().get_script() == preload("res://propeller_bubbles.gd") and not wakes.has(id):
			var wake := Wake.new(); wake.setup(node.get_parent(),timeline); wakes[id] = wake
		if node.get_parent().get_script() == preload("res://propeller_bubbles.gd"): return
	if not (node is MeshInstance3D or node is Sprite3D or node is OmniLight3D or node is SpotLight3D or node is CPUParticles3D or node is MultiMeshInstance3D) or tracks.has(id): return
	if node is MeshInstance3D and node.mesh == null:
		pending[id] = weakref(node); return
	var track := Visual.new(); track.setup(node,timeline)
	tracks[id] = track

func capture(delta: float) -> void:
	var began := Time.get_ticks_usec()
	timeline += maxf(0,delta); tick += 1
	# Samples have timestamps because frame rate need not divide twenty Hz.
	shader_times[tick%Visual.CAPACITY] = fmod(Time.get_ticks_msec()/1000.0,3600.0)
	sample_times[tick%Visual.CAPACITY] = timeline
	if is_instance_valid(game.pilot):
		ambient_positions[tick%Visual.CAPACITY] = game.pilot.get_global_transform_interpolated().origin
	oldest = maxf(0,timeline-DURATION)
	if audio != null: audio.capture(timeline,oldest)
	last_audio_usec = Time.get_ticks_usec()-began
	# Reclaim expired histories before retrying waiting visuals in this capture.
	for id in tracks.keys():
		var track: RefCounted = tracks[id]
		if track.last_seen < oldest and (track.detached or track.source.get_ref() == null):
			track.dispose(); tracks.erase(id)
	for id in wakes.keys():
		var wake: RefCounted = wakes[id]
		if wake.last_seen < oldest and wake.source.get_ref() == null:
			wake.dispose(); wakes.erase(id)
	_register_pending()
	var appearances := {}
	var visual_began := Time.get_ticks_usec()
	for id in tracks.keys():
		var track: RefCounted = tracks[id]
		track.record(tick,timeline,appearances)
	last_visual_usec = Time.get_ticks_usec()-visual_began
	var wake_began := Time.get_ticks_usec()
	for id in wakes.keys():
		var wake: RefCounted = wakes[id]; wake.record(timeline,oldest)
	last_wake_usec = Time.get_ticks_usec()-wake_began
	last_capture_usec = Time.get_ticks_usec()-began; capture_total_usec += last_capture_usec; capture_count += 1

func begin() -> bool:
	if not enabled or tick < 0: return false
	# Finish discovery on entry so no newly spawned visual remains frozen live.
	_scan(game)
	# Capture the exact present once before hiding it, with no simulation step.
	capture(clock); clock = 0
	audio.set_recording(false)
	playback = Node3D.new(); playback.name = "ReplayVisuals"; add_child(playback)
	frozen.clear(); hidden_sources.clear()
	for track in tracks.values():
		if not track.detached: _hide_source(track.source.get_ref())
	for wake in wakes.values():
		var node: Node = wake.source.get_ref()
		if node != null:
			for child in node.get_children():
				if child is MultiMeshInstance3D: _hide_source(child)
	cursor = timeline; playing = false; speed = 1.0
	seek(cursor)
	return true

func _hide_source(node: Node3D) -> void:
	if node == null or hidden_sources.has(node.get_instance_id()): return
	hidden_sources[node.get_instance_id()] = true
	frozen.append({"node":weakref(node),"visible":node.visible}); node.hide()

func end() -> void:
	if audio != null: audio.stop()
	if playback == null: return
	for entry in frozen:
		var node: Node3D = entry.node.get_ref()
		if node != null: node.visible = entry.visible
	frozen.clear(); hidden_sources.clear()
	for track in tracks.values():
		track.proxy = null
	for wake in wakes.values():
		wake.proxy = null
	# Newly reconstructed wreck meshes may still have pending renderer updates.
	# Hide immediately, then release the proxy subtree at the normal frame end.
	playback.hide(); playback.queue_free(); playback = null; playing = false
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
	var ambient := ambient_positions[low%Visual.CAPACITY].lerp(ambient_positions[mini(low+1,tick)%Visual.CAPACITY],fraction)
	game.natural_light.set_ambient_source(ambient)

func _time(index: int) -> float:
	return sample_times[index%Visual.CAPACITY]

func advance(delta: float, scrub: float = 0.0) -> void:
	if playback == null: return
	if scrub != 0: playing = false; seek(cursor+scrub*delta*5.0)
	elif playing:
		seek(cursor+delta*speed,true)
		if cursor >= timeline: playing = false
	else:
		for wake in wakes.values(): wake.show_at(playback,cursor,game.photo_mode.view)
	audio.update(cursor,playing and is_equal_approx(speed,1.0))

func toggle_play() -> void:
	if playback == null: return
	if cursor >= timeline: seek(oldest)
	playing = not playing
	audio.update(cursor,playing and is_equal_approx(speed,1.0))

func clear() -> void:
	death_captured = false
	end()
	if audio != null: audio.clear()
	for track in tracks.values(): track.dispose()
	for wake in wakes.values(): wake.dispose()
	tracks.clear(); wakes.clear(); pending.clear(); archive_id = -1
	timeline = 0; tick = -1; clock = 0; oldest = 0; started = false
	sample_times.fill(0); shader_times.fill(0)
	capture_total_usec = 0; capture_count = 0; last_capture_usec = 0
	last_visual_usec = 0; last_wake_usec = 0; last_audio_usec = 0

func _exit_tree() -> void:
	clear()
