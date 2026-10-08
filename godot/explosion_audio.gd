extends RefCounted
static func apply(audio: AudioStreamPlayer3D, base_gain: float = 0.0, setting: String = "explosion_volume") -> void:
	if audio == null: return
	var master := 0.0
	var gain: float = preload("res://sound_tuning.gd").DEFAULTS.get(setting,-10.0)
	var source := audio.get_tree().get_first_node_in_group("submarine_sound")
	if source != null:
		master = float(source.tuning.settings.master_volume)
		gain = float(source.tuning.settings.get(setting,-10.0))
	audio.volume_db = -80.0 if master <= -60.0 or gain <= -60.0 else master + gain + base_gain
