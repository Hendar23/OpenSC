extends RefCounted
## Applies world fog, daylight, and the water surface material.

var game: Node3D

func _init(context: Node3D) -> void:
	game = context

const World = preload("res://world_loader.gd")

func _update_water_environment() -> void:
	game.camera.far = game.fog_visibility if game.fog_button.button_pressed else 4000.0
	if game.menu_backdrop != null: game.menu_backdrop.view.far = game.camera.far
	if game.cockpit_hud != null and game.cockpit_hud.bottom_camera != null: game.cockpit_hud.bottom_camera.far = game.camera.far
	if game.wildlife != null: game.wildlife.visibility_range = game.fog_visibility if game.fog_button.button_pressed else game.camera.far
	game.water_environment.fog_enabled = game.fog_button.button_pressed
	game.water_environment.fog_mode = Environment.FOG_MODE_DEPTH
	game.water_environment.fog_density = 1.0
	if game.fog_start_slider != null:
		game.fog_start_slider.max_value = game.fog_visibility - 0.5
		game.water_environment.fog_depth_begin = game.fog_start_slider.value
		game.water_environment.fog_depth_curve = game.fog_curve_slider.value
		game.fog_start_label.text = "Fade start distance: %.1f units" % game.fog_start_slider.value
		game.fog_curve_label.text = "Fog build-up curve: %.1f" % game.fog_curve_slider.value
	game.water_environment.fog_depth_end = game.fog_visibility
	game.water_environment.fog_sun_scatter = 0.0
	game.fog_label.text = "Absolute view distance: %.1f units" % game.fog_visibility
	game._update_daylight()

func _update_daylight() -> void:
	var lighting_cycle: RefCounted = game.menu_backdrop.daylight if game.menu_backdrop != null and game.menu_backdrop.active else game.day_night
	lighting_cycle.apply(game.water_environment, game.sun, game.surface_material)
	if game.front_end != null and game.front_end.player_graphics != null: game.front_end.player_graphics.apply_sun(game.sun)
	game.get_tree().call_group("building_searchlights", "set_daylight", lighting_cycle.daylight())
	# Materials already own distance fog. Engine sky fog would recolour the
	# sheltered background blue even after its cave exposure was applied.
	game.water_environment.fog_sky_affect = 0.0
	if game.fog_slider != null:
		game.natural_light.lighting(game.water_environment,game.fog_visibility,game.fog_start_slider.value,game.fog_curve_slider.value)
	var lighting_camera: Camera3D = game.menu_backdrop.view if game.menu_backdrop != null and game.menu_backdrop.active else game.camera
	if is_instance_valid(lighting_camera) and game.natural_light.image != null:
		var exposure: float = game.natural_light.visibility(lighting_camera.global_position,true)
		# Empty space behind cave geometry must match sheltered water, while
		# the actual surface keeps its daylight material through cave exits.
		var cave_ambient := minf(float(game.natural_light.settings.cave_ambient),game.water_environment.ambient_light_energy)
		game.water_environment.background_color = game.natural_light.background_colour(game.water_environment.fog_light_color * exposure + Color(0.75,0.8,0.88) * cave_ambient * (1.0 - exposure))
	game.water_visuals.lighting(float(game.world_root.get_meta("surface_height")) if is_instance_valid(game.world_root) and game.world_root.has_meta("surface_height") else 0.0,lighting_cycle.sun_direction())
	if game.fog_slider != null: game.water_visuals.fog(game.fog_visibility if game.fog_button.button_pressed else 1000000.0,game.fog_start_slider.value,game.fog_curve_slider.value)
	if game.clock_label != null:
		var minutes := int(game.day_night.hour * 60.0) % 1440
		game.clock_label.text = "World time: %02d:%02d" % [minutes / 60, minutes % 60]
		game.daylight_controls.time_of_day.set_value_no_signal(game.day_night.hour)

func _add_water_surface() -> void:
	var bounds: AABB = game.world_root.get_meta("bounds")
	var surface := MeshInstance3D.new()
	surface.name = "WaterSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(bounds.size.x + 40.0, bounds.size.z + 40.0)
	plane.subdivide_width = clampi(ceili(plane.size.x / 2.0),32,256)
	plane.subdivide_depth = clampi(ceili(plane.size.y / 2.0),32,256)
	surface.mesh = plane
	# Sunlight passes through the water; the visual surface must not shadow
	# the entire underwater world like an opaque roof.
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.position = Vector3(bounds.get_center().x, float(game.world_root.get_meta("surface_height")), bounds.get_center().z)
	var material := ShaderMaterial.new()
	material.shader = preload("res://water_surface.gdshader")
	game.surface_material = material
	game.water_visuals.surface = material
	game.water_visuals.configure({})
	surface.extra_cull_margin = 0.2
	game._update_daylight()
	surface.material_override = material
	game.world_root.add_child(surface)
