extends Node3D

# World-space particles leave a wake behind the moving hull. One draw call,
# bounded storage, and no collision or changes to the propulsion simulation.
const MAX_BUBBLES := 4096
const DRIFT_DAMPING := 12.0
var particles: Array[Dictionary] = []
var credits := Vector3.ZERO
var random := RandomNumberGenerator.new()
var instances: MultiMesh
var material: StandardMaterial3D
var surface_height := INF

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	global_transform = Transform3D.IDENTITY
	random.randomize()
	material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	instances = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = quad
	instances.instance_count = MAX_BUBBLES
	instances.visible_instance_count = 0
	var renderer := MultiMeshInstance3D.new()
	renderer.multimesh = instances
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(renderer)

func configure(texture: Texture2D) -> void:
	material.albedo_texture = texture

func clear() -> void:
	particles.clear()
	credits = Vector3.ZERO
	if instances != null: instances.visible_instance_count = 0

func emit_from(index: int, origin: Vector3, exhaust: Vector3, power: float, rate: float, delta: float) -> void:
	if absf(power) < 0.025 or rate <= 0.0:
		credits[index] = 0.0
		return
	credits[index] = minf(credits[index] + rate * absf(power) * delta, 8.0)
	while credits[index] >= 1.0:
		credits[index] -= 1.0
		if particles.size() >= MAX_BUBBLES: continue
		var jitter := Vector3(random.randf_range(-0.04, 0.04), random.randf_range(-0.04, 0.04), random.randf_range(-0.04, 0.04))
		particles.append({"position": origin + jitter, "drift": exhaust * signf(power) * random.randf_range(0.06, 0.14),
			"rise": random.randf_range(0.8, 1.2), "age": 0.0, "size": random.randf_range(0.045, 0.10)})

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var particle := particles[i]
		particle.age += delta
		var decay := exp(-DRIFT_DAMPING * delta)
		particle.position += particle.drift * ((1.0 - decay) / DRIFT_DAMPING) + Vector3.UP * particle.rise * delta
		particle.drift *= decay
		# In the game bubbles survive until the water surface, even after thrust
		# is released. A timeout only protects previews without a water boundary.
		if particle.position.y >= surface_height or (not is_finite(surface_height) and particle.age >= 120.0):
			particles.remove_at(i)
	var camera := get_viewport().get_camera_3d()
	for i in particles.size():
		var particle := particles[i]
		var size: float = particle.size * (1.0 + minf(particle.age / 6.0, 1.0) * 0.45)
		instances.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), particle.position))
		# Close camera zoom can pass through the wake; fade nearby sprites before
		# they fill the screen or obscure the hull.
		var camera_fade := smoothstep(0.25, 1.25, camera.global_position.distance_to(particle.position)) if camera != null else 1.0
		var surface_fade := smoothstep(0.0, 0.2, surface_height - particle.position.y) if is_finite(surface_height) else 1.0
		instances.set_instance_color(i, Color(0.82, 0.94, 1.0, 0.7 * camera_fade * surface_fade))
	instances.visible_instance_count = particles.size()
