extends Node3D

const DEFAULTS := {"sweep_speed":15.0, "sweep_angle":45.0, "beam_length":2.4336, "beam_width":0.9, "beam_brightness":0.55, "beam_softness":0.65, "day_brightness":0.2}
var tuning := DEFAULTS.duplicate()
var sweep_speed := 15.0
var angle := 0.0
var direction := 1.0
var daylight := 1.0
var pivot: Node3D
var volume: MeshInstance3D
var material: ShaderMaterial

func _ready() -> void:
	add_to_group("building_searchlights")

func setup(_template: Node3D) -> void:
	configure("", {})

func configure(_folder: String, values: Dictionary) -> void:
	for key in DEFAULTS: tuning[key] = float(values.get(key, DEFAULTS[key]))
	sweep_speed = tuning.sweep_speed
	angle = clampf(angle, -tuning.sweep_angle, tuning.sweep_angle)
	pivot = get_node_or_null("Sweep") as Node3D
	if pivot == null:
		pivot = Node3D.new(); pivot.name = "Sweep"; add_child(pivot)
	# Duplicate/undo can carry child nodes with shared resources. Always give
	# this instance its own volume mesh and shader parameters.
	for child in pivot.get_children(): child.free()
	volume = MeshInstance3D.new(); volume.name = "SoftBeam"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tuning.beam_width, tuning.beam_width, tuning.beam_length)
	volume.mesh = mesh; volume.position.z = tuning.beam_length * 0.5
	volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = ShaderMaterial.new(); material.shader = preload("res://searchlight.gdshader")
	volume.material_override = material; pivot.add_child(volume)
	for key in ["beam_length", "beam_brightness", "beam_softness"]: material.set_shader_parameter(key, tuning[key])
	material.set_shader_parameter("beam_radius", tuning.beam_width * 0.5)
	set_daylight(daylight)
	pivot.rotation_degrees.y = angle

func settings() -> Dictionary:
	var result := tuning.duplicate()
	result.light_type = "searchlight"
	return result

func set_daylight(value: float) -> void:
	daylight = clampf(value, 0.0, 1.0)
	if material != null: material.set_shader_parameter("brightness_factor", lerpf(1.0, tuning.day_brightness, daylight))

func _process(delta: float) -> void:
	if pivot == null: return
	var limit: float = tuning.sweep_angle
	if limit <= 0.0:
		angle = 0.0; pivot.rotation.y = 0.0; return
	# Fold travel so a long frame cannot overshoot either end of the sweep.
	var travel := fposmod(angle + limit if direction > 0 else 3.0 * limit - angle, 4.0 * limit)
	travel = fposmod(travel + maxf(sweep_speed, 0.0) * delta, 4.0 * limit)
	if travel < 2.0 * limit:
		angle = travel - limit; direction = 1.0
	else:
		angle = 3.0 * limit - travel; direction = -1.0
	pivot.rotation_degrees.y = angle
