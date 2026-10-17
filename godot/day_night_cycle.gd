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

func sun_direction() -> Vector3:
	# +X is east: sunrise at 06:00, overhead at noon, west at 18:00.
	var angle := (hour - 6.0) / 24.0 * TAU
	return Vector3(cos(angle),sin(angle),0.0)

func apply(environment: Environment, sun: DirectionalLight3D, surface: ShaderMaterial = null) -> void:
	var day := daylight()
	var night_tint := Color(0.006, 0.02, 0.055) * (night_brightness / 0.18)
	night_tint.a = 1.0
	var water := night_tint.lerp(Color(0.005, 0.48, 0.56), day)
	environment.background_color = preload("res://natural_light.gd").background_colour(water)
	environment.fog_light_color = water
	# Neutral nearby illumination preserves the original texture colours. Water
	# tint comes from distance fog, rather than colouring every object's lighting.
	environment.ambient_light_color = Color(0.75, 0.8, 0.88).lerp(Color(0.9, 0.95, 1.0), day)
	# The night control describes visible brightness. RenderingDevice shades in
	# linear space; using the display value as energy lifted even minimum night
	# lighting substantially. Keep the established daytime energy unchanged.
	var night_energy := night_brightness
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		night_energy = Color(night_brightness,night_brightness,night_brightness).srgb_to_linear().r
	environment.ambient_light_energy = lerpf(night_energy, 0.32, day)
	var direction := sun_direction()
	sun.basis = Basis.looking_at(-direction,Vector3.FORWARD)
	var elevation := maxf(0.0,direction.y)
	sun.light_color = Color(1.0,0.7,0.43).lerp(Color(0.97,0.99,1.0),smoothstep(0.0,0.5,elevation))
	sun.light_energy = 1.2 * smoothstep(0.0,0.18,elevation)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 0.6
	if surface != null:
		surface.set_shader_parameter("daylight", day)
		surface.set_shader_parameter("night_brightness", night_brightness)

func settings() -> Dictionary:
	return {"cycle_enabled": enabled, "time_of_day": hour, "cycle_minutes": cycle_minutes, "night_brightness": night_brightness}
