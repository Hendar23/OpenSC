extends CanvasLayer
## Double-size, modal playback. Conversion only runs in prepare(), at startup.
const Library = preload("res://fmv_library.gd")
const Bindings = preload("res://input_bindings.gd")
const DISPLAY_SCALE := 2.0
signal completed(id: String)
signal idle
var game: Node
var active := false
var current := ""
var movies := {}
var warnings: Array[String] = []
var conversions := 0
var worker: Thread
var shade: ColorRect
var queue: Array[Dictionary] = []
var was_paused := false
var mouse_mode := Input.MOUSE_MODE_VISIBLE
var effects_muted := false
var focus: WeakRef
var finishing := false
var terminal_playback := false
var prepared_folder := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS; layer = 200
	shade = ColorRect.new(); shade.color = Color.BLACK; shade.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(shade)
	get_viewport().size_changed.connect(_layout)
	hide(); _layout()

func setup(context: Node) -> void:
	game = context
	game.events.fmv_requested.connect(request)
	game.events.city_docked.connect(_docked)

func _docked(_city: int) -> void:
	if game.loading_save or not game.has_started_game or game.docking.current.is_empty(): return
	request("dock",0,int(game.docking.current.get("race",0)))

func prepare(folder: String, progress: Callable = Callable(), decoder: String = "") -> void:
	if prepared_folder == folder: return
	for entry in movies.values(): entry.player.free()
	movies.clear(); warnings.clear(); conversions = 0
	if decoder.is_empty(): decoder = Library.decoder_path()
	for id in Library.FILES:
		var source := Library.source_path(folder,id)
		if not FileAccess.file_exists(source): warnings.append("Missing FMV: "+source); continue
		var info := Library.smacker_info(source)
		if info.is_empty() or int(info.frames) <= 1: warnings.append("Incomplete FMV: "+source); continue
		if progress.is_valid(): progress.call("Preparing FMV: "+id)
		await get_tree().process_frame
		var output := Library.cache_path(source)
		if not Library.Cache._valid(output):
			if decoder.is_empty(): warnings.append("FMV conversion requires FFmpeg: "+id); continue
			worker = Thread.new()
			var error := worker.start(Library.convert.bind(decoder,source,output))
			if error != OK: worker = null; warnings.append("Could not start FMV conversion: "+id); continue
			while worker.is_alive(): await get_tree().process_frame
			var result: Dictionary = worker.wait_to_finish(); worker = null
			if not result.ok: warnings.append("FMV conversion failed: "+id+" "+str(result.get("error",""))); continue
			conversions += 1
		var video := VideoStreamPlayer.new(); video.name = id; video.expand = true
		video.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		video.size = Vector2(info.width,info.height)*DISPLAY_SCALE; video.bus = &"Master"; video.volume = 0.0
		shade.add_child(video)
		var stream := VideoStreamTheora.new(); stream.file = ProjectSettings.globalize_path(output)
		video.stream = stream; video.finished.connect(_finished.bind(id))
		movies[id] = {"player":video,"size":video.size,"path":output}
		# Open the decoder and prime the first frame behind the loading screen.
		video.play(); await get_tree().process_frame; video.paused = true; video.hide()
	prepared_folder = folder
	_layout()
	if not warnings.is_empty(): push_warning("FMVs: "+"; ".join(warnings))

func request(cue: String, city: int = 0, race: int = 0) -> bool:
	var id := Library.movie(cue,city,race)
	if game != null and not game.front_end.gameplay_menu.fmvs_enabled: return false
	if not movies.has(id): return false
	queue.append({"id":id,"terminal":Library.terminal(cue)})
	if not active:
		was_paused = get_tree().paused; mouse_mode = Input.mouse_mode
		focus = weakref(get_viewport().gui_get_focus_owner())
		var bus := AudioServer.get_bus_index("Effects")
		if bus >= 0:
			effects_muted = AudioServer.is_bus_mute(bus); AudioServer.set_bus_mute(bus,true)
		active = true; get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		show(); _next()
	return true

func _next() -> void:
	var item: Dictionary = queue.pop_front(); current = item.id
	terminal_playback = terminal_playback or bool(item.terminal)
	var video: VideoStreamPlayer = movies[current].player
	# Honour the player's effects volume, without allowing paused gameplay or
	# radio audio to leak into the film's soundtrack.
	var bus := AudioServer.get_bus_index("Effects")
	video.volume = db_to_linear(AudioServer.get_bus_volume_db(bus)) if bus >= 0 and not effects_muted else 0.0 if bus >= 0 else 1.0
	# Restart from frame zero after the silent startup warmup.
	video.play(); video.show(); video.paused = false
	_layout()

func _input(event: InputEvent) -> void:
	if not active: return
	Bindings.track_event(event)
	get_viewport().set_input_as_handled()
	if Bindings.pressed(event,"dock_accept") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)):
		# Consume the skip press for the entire frame, including the city/menu UI.
		if not finishing: finishing = true; _finish_current.call_deferred()

func _finished(id: String) -> void:
	if active and current == id and not finishing:
		finishing = true; _finish_current.call_deferred()

func _finish_current() -> void:
	if not active: return
	var id := current
	var video: VideoStreamPlayer = movies[id].player
	video.hide(); video.volume = 0.0; video.stop()
	# Re-prime for later visits to the same dock, while the modal cover remains.
	video.play(); await get_tree().process_frame; video.paused = true
	completed.emit(id); finishing = false
	if not queue.is_empty(): _next(); return
	var bus := AudioServer.get_bus_index("Effects")
	if bus >= 0: AudioServer.set_bus_mute(bus,effects_muted)
	current = ""; active = false; hide()
	get_tree().paused = was_paused; Input.mouse_mode = mouse_mode
	if focus != null and is_instance_valid(focus.get_ref()): focus.get_ref().grab_focus()
	if terminal_playback and game != null: game._show_main_menu()
	terminal_playback = false; idle.emit()

func _layout() -> void:
	if shade == null: return
	# Counter canvas_items stretch so 512x320 means physical screen pixels,
	# including on high-resolution/ultrawide displays.
	var stretch := get_viewport().get_stretch_transform().get_scale()
	scale = Vector2.ONE / stretch
	shade.size = get_viewport().get_visible_rect().size * stretch
	for entry in movies.values(): entry.player.position = (shade.size-entry.size)*0.5

func _exit_tree() -> void:
	if worker != null: worker.wait_to_finish(); worker = null
	if active:
		var bus := AudioServer.get_bus_index("Effects")
		if bus >= 0: AudioServer.set_bus_mute(bus,effects_muted)
		get_tree().paused = was_paused; Input.mouse_mode = mouse_mode
