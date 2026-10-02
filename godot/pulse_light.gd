extends OmniLight3D

const Assets = preload("res://clump_loader.gd")
var peak_energy := 1.0
var light_mode := "flashing"
var pulse_period := 2.4
var pulse_minimum := 0.2
var flash_on_time := 0.5
var flash_off_time := 1.0
var flare_size := 4.0
var elapsed := 0.0
var phase := 0.0
var flare: MeshInstance3D
var material: StandardMaterial3D

func configure(folder: String, settings: Dictionary) -> void:
	peak_energy = clampf(float(settings.get("energy", 1.0)), 0.0, 16.0)
	omni_range = clampf(float(settings.get("range", 5.0)), 0.1, 1000.0)
	light_mode = mode_from(settings)
	pulse_period = clampf(float(settings.get("pulse_period", 2.4)), 0.1, 60.0)
	pulse_minimum = clampf(float(settings.get("pulse_minimum", 0.2)), 0.0, 1.0)
	flash_on_time = clampf(float(settings.get("flash_on_time", 0.5)), 0.05, 60.0)
	flash_off_time = clampf(float(settings.get("flash_off_time", 1.0)), 0.05, 60.0)
	flare_size = clampf(float(settings.get("flare_size", 4.0)), 0.1, 100.0)
	# Position gives neighbouring beacons different, reproducible pulse phases.
	phase = fposmod(position.dot(Vector3(0.73, 0.37, 0.19)), TAU)
	# Editor undo/duplicate clones the child node but initially shares resources.
	flare = get_node_or_null("Flare") as MeshInstance3D
	if flare == null:
		flare = MeshInstance3D.new(); flare.name = "Flare"
		flare.mesh = QuadMesh.new()
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Keep depth testing and water fog: terrain and closed doors hide the flare.
		material.albedo_texture = _flare_texture(folder)
		flare.material_override = material; add_child(flare)
	else:
		flare.mesh = flare.mesh.duplicate()
		material = flare.material_override.duplicate() as StandardMaterial3D
		flare.material_override = material
	flare.mesh.size = Vector2.ONE * flare_size
	update_pulse()

static func _flare_texture(folder: String) -> Texture2D:
	var source := Assets._load_texture(folder, "FLARE", "", {})
	if source == null or source.has_meta("asset_mod"): return source
	# The original BMP encodes brightness over opaque black. Additive blending
	# hides black until fog tints it; convert brightness to real transparency.
	# Unpremultiply the colour so the soft glow retains its original strength.
	var pixels := source.get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	for y in range(pixels.get_height()):
		for x in range(pixels.get_width()):
			var color := pixels.get_pixel(x, y)
			var brightness := maxf(color.r, maxf(color.g, color.b))
			pixels.set_pixel(x, y, Color(color.r / brightness, color.g / brightness, color.b / brightness, color.a * brightness) if brightness > 0.0 else Color.TRANSPARENT)
	return ImageTexture.create_from_image(pixels)

static func mode_from(settings: Dictionary) -> String:
	if settings.has("light_mode"): return str(settings.light_mode)
	# Preserve explicitly saved pulse/steady choices from earlier map versions.
	if settings.has("pulse_enabled"): return "pulsing" if settings.pulse_enabled else "steady"
	return "flashing"

func settings() -> Dictionary:
	return {"energy": peak_energy, "range": omni_range, "light_mode": light_mode,
		"pulse_period": pulse_period, "pulse_minimum": pulse_minimum, "flare_size": flare_size,
		"flash_on_time": flash_on_time, "flash_off_time": flash_off_time}

func _process(delta: float) -> void:
	elapsed = fposmod(elapsed + delta, flash_on_time + flash_off_time if light_mode == "flashing" else pulse_period)
	update_pulse()

func update_pulse() -> void:
	var brightness := 1.0
	if light_mode == "pulsing":
		brightness = lerpf(pulse_minimum, 1.0, (sin(elapsed * TAU / pulse_period + phase) + 1.0) * 0.5)
	elif light_mode == "flashing":
		var cycle := flash_on_time + flash_off_time
		brightness = 1.0 if fposmod(elapsed + phase / TAU * cycle, cycle) < flash_on_time else 0.0
	light_energy = peak_energy * brightness
	if flare != null: flare.visible = brightness > 0.0 and peak_energy > 0.0
	if material != null:
		material.albedo_color = Color(0.8, 0.95, 1.0, clampf(peak_energy, 0.0, 1.0) * brightness)
