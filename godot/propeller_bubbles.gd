extends Node3D

# World-space particles leave a wake behind the moving hull. One draw call,
# bounded storage, and no collision or changes to the propulsion simulation.
const MAX_BUBBLES := 4096
static var bubble_limit := 200
static var emitters: Array[WeakRef] = []
static var birth_serial := 0
static var bursts: Array[WeakRef] = []
var capacity := MAX_BUBBLES
const DRIFT_DAMPING := 12.0
var particles: Array[Dictionary] = []
var credits := {}
var random := RandomNumberGenerator.new()
var instances: MultiMesh
var material: StandardMaterial3D
var render_buffer := PackedFloat32Array()
var surface_height := INF
var replay_serial := 0

func _ready() -> void:
	emitters.append(weakref(self))
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
	instances.instance_count = capacity
	instances.visible_instance_count = 0
	var renderer := MultiMeshInstance3D.new()
	renderer.multimesh = instances
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(renderer)

func configure(texture: Texture2D) -> void:
	material.albedo_texture = texture
	var model := preload("res://bubble_visual.gd").replacement()
	if model != null: instances.mesh = model
	else:
		var quad := QuadMesh.new(); quad.size = Vector2.ONE; quad.material = material
		instances.mesh = quad

func clear() -> void:
	particles.clear()
	credits.clear()
	if instances != null: instances.visible_instance_count = 0

func emit_from(index: int, origin: Vector3, exhaust: Vector3, power: float, rate: float, delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(origin) > pow(camera.far + 8.0,2):
		credits[index] = 0.0; return
	if absf(power) < 0.025 or rate <= 0.0:
		credits[index] = 0.0
		return
	credits[index] = minf(float(credits.get(index,0.0)) + rate * absf(power) * delta, 8.0)
	while credits[index] >= 1.0:
		credits[index] -= 1.0
		if particles.size() >= capacity or bubble_limit == 0: continue
		if bubble_limit > 0:
			while total_bubbles() >= bubble_limit: _discard_oldest()
		birth_serial += 1
		var jitter := Vector3(random.randf_range(-0.04, 0.04), random.randf_range(-0.04, 0.04), random.randf_range(-0.04, 0.04))
		replay_serial += 1
		particles.append({"budget_birth":birth_serial,"replay_id":replay_serial,"position": origin + jitter, "drift": exhaust * signf(power) * random.randf_range(0.06, 0.14),
			"rise": random.randf_range(0.8, 1.2), "age": 0.0, "size": random.randf_range(0.045, 0.10)})

func _physics_process(delta: float) -> void:
	advance(delta,false)

func _process(_delta: float) -> void:
	_update_instances()

func advance(delta: float, upload: bool = true) -> void:
	var decay := exp(-DRIFT_DAMPING * delta)
	var drift_step := (1.0-decay)/DRIFT_DAMPING
	var count := 0
	# Compact survivors without repeatedly shifting the rest of a crowded wake.
	for particle in particles:
		var age: float = float(particle.age)+delta
		var drift: Vector3 = particle.drift
		var point: Vector3 = particle.position+drift*drift_step+Vector3.UP*float(particle.rise)*delta
		if point.y >= surface_height or age >= float(particle.get("lifetime",120.0)): continue
		particle.age = age; particle.position = point; particle.drift = drift*decay
		particles[count] = particle; count += 1
	particles.resize(count)
	if upload: _update_instances()

func _update_instances() -> void:
	# Physics may catch up several ticks in one frame. Only its final transforms
	# are displayed; upload them once per rendered frame, keeping every tick of
	# simulation and all bubble/replay data intact.
	if particles.is_empty():
		instances.visible_instance_count = 0; return
	var camera := get_viewport().get_camera_3d()
	var camera_point := camera.global_position if camera != null else Vector3.ZERO
	var has_surface := is_finite(surface_height)
	if render_buffer.size() != instances.instance_count*16:
		render_buffer.resize(instances.instance_count*16)
		render_buffer.fill(0.0)
	for index in particles.size():
		var particle := particles[index]
		var point: Vector3 = particle.position
		var age: float = particle.age
		var size: float = particle.size
		var lifetime: float = particle.get("lifetime",120.0)
		size = lerpf(size,particle.end_size,minf(1.0,age/lifetime)) if particle.has("end_size") else size*(1.0+minf(age/6.0,1.0)*0.45)
		var opacity: float = particle.get("opacity",0.7)
		if camera != null: opacity *= smoothstep(0.25,1.25,camera_point.distance_to(point))
		if has_surface: opacity *= smoothstep(0.0,0.2,surface_height-point.y)
		if particle.has("lifetime"): opacity *= smoothstep(0.0,0.5,lifetime-age)
		var offset := index*16
		render_buffer[offset] = size; render_buffer[offset+3] = point.x
		render_buffer[offset+5] = size; render_buffer[offset+7] = point.y
		render_buffer[offset+10] = size; render_buffer[offset+11] = point.z
		render_buffer[offset+12] = 0.82; render_buffer[offset+13] = 0.94
		render_buffer[offset+14] = 1.0; render_buffer[offset+15] = opacity
	instances.buffer = render_buffer
	instances.visible_instance_count = particles.size()

static func total_bubbles() -> int:
	var total := 0
	for reference in emitters:
		var emitter: Node3D = reference.get_ref()
		if emitter != null: total += emitter.particles.size()
	for reference in bursts:
		var burst: Node3D = reference.get_ref()
		if burst != null: total += int(burst.get_meta("bubble_budget",0))
	return total

static func _discard_oldest() -> void:
	var oldest: Node3D
	var serial := 9223372036854775807
	for reference in emitters:
		var emitter: Node3D = reference.get_ref()
		if emitter == null or emitter.particles.is_empty(): continue
		var first: int = emitter.particles[0].get("budget_birth",0)
		if first < serial: oldest = emitter; serial = first
	if oldest != null:
		oldest.particles.remove_at(0)
		oldest.instances.visible_instance_count = mini(oldest.instances.visible_instance_count,oldest.particles.size())
	else:
		for reference in bursts:
			var burst: CPUParticles3D = reference.get_ref()
			if burst == null or int(burst.get_meta("bubble_budget",0)) == 0: continue
			var remaining := int(burst.get_meta("bubble_budget"))-1
			burst.set_meta("bubble_budget",remaining)
			if remaining == 0: burst.hide(); burst.emitting = false
			else: burst.amount = remaining
			break

static func set_limit(value: int) -> void:
	bubble_limit = maxi(-1,value)
	emitters = emitters.filter(func(reference: WeakRef) -> bool: return reference.get_ref() != null)
	if bubble_limit >= 0:
		while total_bubbles() > bubble_limit: _discard_oldest()
		for reference in emitters: reference.get_ref()._update_instances()

func _exit_tree() -> void:
	emitters = emitters.filter(func(reference: WeakRef) -> bool: return reference.get_ref() != null and reference.get_ref() != self)

static func reserve_burst(burst: CPUParticles3D) -> void:
	bursts = bursts.filter(func(reference: WeakRef) -> bool: return reference.get_ref() != null and reference.get_ref() != burst)
	burst.set_meta("bubble_budget",0)
	var count := burst.amount if bubble_limit < 0 else mini(burst.amount,bubble_limit)
	if count == 0:
		burst.hide(); burst.emitting = false; return
	if bubble_limit > 0:
		while total_bubbles()+count > bubble_limit: _discard_oldest()
	burst.show(); burst.amount = count; burst.set_meta("bubble_budget",count)
	bursts.append(weakref(burst)); birth_serial += 1
	var token := birth_serial; burst.set_meta("bubble_budget_token",token)
	var reference: WeakRef = weakref(burst)
	burst.get_tree().create_timer(burst.lifetime,false).timeout.connect(func() -> void:
		var live: Node3D = reference.get_ref()
		if live != null and live.get_meta("bubble_budget_token",0) == token: live.set_meta("bubble_budget",0)
	)
