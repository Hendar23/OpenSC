extends RefCounted
static func apply(audio: AudioStreamPlayer3D, base_gain: float = 0.0, setting: String = "explosion_volume") -> void:
	if audio == null: return
	if setting == "explosion_volume":
		# The default ten-unit scale leaves blasts loud across most nearby
		# combat. Use a smaller scale and bounded gain for a clearer falloff.
		audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		audio.unit_size = 2.0; audio.max_db = 0.0; audio.max_distance = 60.0
	var master := 0.0
	var gain: float = preload("res://sound_tuning.gd").DEFAULTS.get(setting,-10.0)
	var source := audio.get_tree().get_first_node_in_group("submarine_sound")
	if source != null:
		master = float(source.tuning.settings.master_volume)
		gain = float(source.tuning.settings.get(setting,-10.0))
	audio.volume_db = -80.0 if master <= -60.0 or gain <= -60.0 else master + gain + base_gain
