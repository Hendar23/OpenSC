extends AudioStreamPlayer
## Short original radio burst for messages without their own voice sample.
signal notification_played
const SECONDS := 0.25
const RATE := 11025
var tuning: RefCounted
var playback_allowed := Callable()

func setup(folder: String, feed: Control, sound_tuning: RefCounted, allowed: Callable = Callable()) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	playback_allowed = allowed
	tuning = sound_tuning; stop(); stream = load_notification(folder)
	if not feed.message_presented.is_connected(message_presented): feed.message_presented.connect(message_presented)
	if not feed.cleared.is_connected(stop): feed.cleared.connect(stop)

static func load_notification(folder: String) -> AudioStreamWAV:
	var path := folder.path_join("WAVES/ENGLISH/AA2.RAW")
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return null
	var bytes := file.get_buffer(mini(int(round(RATE*SECONDS)),file.get_length()))
	if bytes.is_empty(): return null
	var clip := preload("res://legacy_audio.gd").raw_stream(bytes,RATE,0,false)
	clip.set_meta("asset_source",path)
	return clip

func _process(_delta: float) -> void:
	if playing and playback_allowed.is_valid() and not playback_allowed.call(): stop()

func message_presented(message: Dictionary) -> void:
	if playback_allowed.is_valid() and not playback_allowed.call():
		stop(); return
	if stream == null or str(message.get("text","")).is_empty(): return
	if message.get("voice") != null or message.get("voice_played",false): return
	var master := float(tuning.settings.master_volume) if tuning != null else 0.0
	if master <= -60.0: return
	volume_db = master+preload("res://docking_radio.gd").SPEECH_VOLUME_DB
	play(); notification_played.emit()
