extends RefCounted

const DEFAULTS := {"cycle_enabled": true, "time_of_day": 12.0, "cycle_minutes": 20.0, "night_brightness": 0.18}
var enabled := true
var hour := 12.0
var cycle_minutes := 20.0
var night_brightness := 0.18

func step(delta: float) -> void:
	if enabled: hour = fposmod(hour + maxf(delta, 0.0) * 24.0 / (cycle_minutes * 60.0), 24.0)

func daylight() -> float:
	return smoothstep(-0.18, 0.3, cos((hour - 12.0) / 24.0 * TAU))

func apply(environment: Environment, sun: DirectionalLight3D, surface: ShaderMaterial = null) -> void:
	var day := daylight()
	var night_tint := Color(0.006, 0.02, 0.055) * (night_brightness / 0.18)
	night_tint.a = 1.0
	var water := night_tint.lerp(Color(0.005, 0.48, 0.56), day)
	environment.background_color = water
	environment.fog_light_color = water
	# Neutral nearby illumination preserves the original texture colours. Water
	# tint comes from distance fog, rather than colouring every object's lighting.
	environment.ambient_light_color = Color(0.75, 0.8, 0.88).lerp(Color(0.9, 0.95, 1.0), day)
	environment.ambient_light_energy = lerpf(night_brightness, 0.7, day)
	sun.light_color = Color(0.7, 0.76, 0.9).lerp(Color(0.97, 0.99, 1.0), day)
	sun.light_energy = lerpf(night_brightness * 0.35, 1.0, day)
	if surface != null:
		surface.set_shader_parameter("daylight", day)
		surface.set_shader_parameter("night_brightness", night_brightness)

func settings() -> Dictionary:
	return {"cycle_enabled": enabled, "time_of_day": hour, "cycle_minutes": cycle_minutes, "night_brightness": night_brightness}
