extends MultiMeshInstance3D

const DEFAULTS := {"enabled": true, "count": 600.0, "size": 0.025, "drift": 0.06, "radius": 12.0, "visibility": 0.45}
var settings: Dictionary = DEFAULTS.duplicate()
var camera: Camera3D
var active := false
var drift_distance := 0.0
var rng := RandomNumberGenerator.new()
var material := ShaderMaterial.new()

func _init() -> void:
	preload("res://natural_light.gd").ensure_globals()
	name = "WaterParticles"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rng.seed = 74329
	material.shader = preload("res://water_particles.gdshader")
	material_override = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = QuadMesh.new()

func configure(values: Dictionary) -> void:
	var previous_count := int(settings.count)
	var previous_radius := float(settings.radius)
	settings.merge(values, true)
	settings.count = clampf(float(settings.count), 0.0, 4000.0)
	settings.size = clampf(float(settings.size), 0.005, 0.08)
	settings.drift = clampf(float(settings.drift), 0.0, 0.3)
	settings.radius = clampf(float(settings.radius), 3.0, 30.0)
	settings.visibility = clampf(float(settings.visibility), 0.0, 1.0)
	multimesh.mesh.size = Vector2.ONE * float(settings.size)
	material.set_shader_parameter("cloud_radius", settings.radius)
	material.set_shader_parameter("visibility", settings.visibility)
	visible = bool(settings.enabled) and active
	if multimesh.instance_count == 0 or previous_count != int(settings.count): _rebuild()
	if previous_radius != float(settings.radius): _update_bounds()

func _rebuild() -> void:
	# A periodic cube supplies a uniform spherical cloud after shader clipping.
	# Compensate for the cube's unused corners to retain the requested density.
	multimesh.instance_count = ceili(float(settings.count) * 6.0 / PI)
	for index in range(multimesh.instance_count):
		var phase := Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))
		var size := rng.randf_range(0.65,1.35)
		multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size),phase))
		multimesh.set_instance_custom_data(index,Color(rng.randf_range(0.4,1.0),rng.randf(),rng.randf(),rng.randf()))
	_update_bounds()

func _update_bounds() -> void:
	var extent := Vector3.ONE * (float(settings.radius) + 1.0)
	custom_aabb = AABB(-extent,extent * 2.0)

func _process(delta: float) -> void:
	visible = active and bool(settings.enabled)
	if not visible or not is_instance_valid(camera): return
	# Only two uniforms and one cloud transform change, independent of count.
	# Our own clock respects pause and keeps drift changes continuous.
	drift_distance += maxf(delta,0.0) * float(settings.drift)
	global_position = camera.global_position
	material.set_shader_parameter("cloud_center",global_position)
	material.set_shader_parameter("drift_distance",drift_distance)
