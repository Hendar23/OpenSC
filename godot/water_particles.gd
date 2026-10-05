extends MultiMeshInstance3D

const DEFAULTS := {"enabled": true, "count": 600.0, "size": 0.025, "drift": 0.06, "radius": 12.0, "visibility": 0.45}
var settings: Dictionary = DEFAULTS.duplicate()
var camera: Camera3D
var active := false
var positions: Array[Vector3] = []
var flows: Array[Vector3] = []
var sizes: Array[float] = []
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
	if positions.size() != int(settings.count) or previous_count != int(settings.count): _rebuild()

func _rebuild() -> void:
	positions.clear(); flows.clear(); sizes.clear()
	multimesh.instance_count = int(settings.count)
	var center := camera.global_position if camera != null and camera.is_inside_tree() else Vector3.ZERO
	for i in range(multimesh.instance_count):
		positions.append(center + _offset())
		flows.append(Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.1, 0.4), rng.randf_range(-0.7, 0.7)))
		sizes.append(rng.randf_range(0.65, 1.35))
		multimesh.set_instance_custom_data(i, Color(rng.randf_range(0.4, 1.0), 0, 0, 0))
		_draw(i)

func _offset() -> Vector3:
	var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
	return direction * pow(rng.randf(), 1.0 / 3.0) * float(settings.radius)

func _draw(index: int) -> void:
	multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sizes[index]), positions[index]))

func _process(delta: float) -> void:
	visible = active and bool(settings.enabled)
	if not visible or camera == null: return
	var center := camera.global_position
	var radius := float(settings.radius)
	for i in range(positions.size()):
		positions[i] += flows[i] * float(settings.drift) * delta
		if positions[i].distance_squared_to(center) > radius * radius: positions[i] = center + _offset()
		_draw(i)
	# Avoid frustum culling against the initial cloud after travelling the map.
	custom_aabb = AABB(center - Vector3.ONE * (radius + 1.0), Vector3.ONE * (radius + 1.0) * 2.0)
