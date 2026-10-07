extends RefCounted
const Mods = preload("res://mod_registry.gd")
const DEFAULTS := {
	"master_volume": 0.0, "low_shield_volume": 0.0, "volume_response": 0.18, "pitch_response": 0.2, "loop_blend_ms": 15.0,
	"main_propeller_volume": -10.0, "main_propeller_pitch_min": 0.45, "main_propeller_pitch_max": 1.35, "main_propeller_speed_pitch": 0.65,
	"side_pods_volume": -15.0, "side_pods_pitch_min": 0.45, "side_pods_pitch_max": 1.0, "side_pods_speed_pitch": 0.25,
	"pod_rotation_volume": -27.0, "pod_rotation_pitch_min": 1.0, "pod_rotation_pitch_max": 1.0, "pod_rotation_speed_pitch": 0.0,
	"impact_volume": -10.0, "creaking_volume": -16.0, "impact_pitch_variation": 0.05,
	"impact_creak_chance": 0.2, "impact_min_speed": 0.5, "impact_cooldown": 0.35, "impact_rumble_strength": 0.65,
	"docking_volume": -18.0, "dock_doors_volume": -12.0, "dock_shut_volume": -10.0
}
var settings: Dictionary = DEFAULTS.duplicate()
var defaults: Dictionary = DEFAULTS.duplicate()
var persistence_path := "user://submarine_sound.cfg"
var defaults_hash := ""

func load_settings(remember: bool = true, path: String = "", source: String = "res://submarine_audio.cfg") -> void:
	defaults = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(source) == OK: _apply(config, defaults)
	defaults_hash = JSON.stringify(defaults).sha256_text()
	persistence_path = path
	if path.is_empty():
		var ids := Mods.active_ids()
		persistence_path = "user://submarine_sound.cfg" if ids.is_empty() else "user://sound-mod-%s.cfg" % JSON.stringify(ids).sha256_text().substr(0, 16)
	settings = defaults.duplicate()
	if remember and config.load(persistence_path) == OK and config.get_value("defaults", "source_hash", "") == defaults_hash:
		_apply(config, settings)

static func _apply(config: ConfigFile, values: Dictionary) -> void:
	for key in DEFAULTS:
		var value: Variant = config.get_value("sound", key, values[key])
		if not (value is int or value is float) or not is_finite(float(value)): continue
		if key.ends_with("volume"): values[key] = clampf(float(value), -60.0, 6.0)
		elif key == "impact_pitch_variation": values[key] = clampf(float(value), 0.0, 0.25)
		elif key == "impact_creak_chance": values[key] = clampf(float(value), 0.0, 1.0)
		elif key == "impact_rumble_strength": values[key] = clampf(float(value), 0.0, 1.0)
		elif key == "impact_min_speed": values[key] = clampf(float(value), 0.0, 5.0)
		elif key == "impact_cooldown": values[key] = clampf(float(value), 0.05, 2.0)
		elif key == "loop_blend_ms": values[key] = clampf(float(value), 0.0, 50.0)
		elif key.ends_with("response"): values[key] = clampf(float(value), 0.01, 2.0)
		else: values[key] = clampf(float(value), 0.0 if key.ends_with("speed_pitch") else 0.25, 4.0)

func save_settings(path: String = "") -> Error:
	var config := ConfigFile.new()
	for key in settings: config.set_value("sound", key, settings[key])
	config.set_value("defaults", "source_hash", defaults_hash)
	return config.save(persistence_path if path.is_empty() else path)
